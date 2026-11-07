-- =============================================================================
-- FINANCIERO V2 (rama de prueba). TODO ADITIVO: no cambia nada mientras
-- barberias.financiero_v2 = false (valor por defecto). No toca registrar_cobro_conjunto.
-- Regla de redondeo única: pesos enteros, mitad hacia arriba (fin_redondear).
-- La parte del establecimiento se calcula RESTANDO (precio_final - parte_profesional),
-- así las dos partes siempre suman exactamente el precio final.
-- ⚠ SIN begin;/commit; A PROPÓSITO (el SQL Editor trocea por `;` los cuerpos).
-- =============================================================================

-- ── Configuración por negocio y sucursal ────────────────────────────────────
alter table public.barberias add column if not exists financiero_v2 boolean not null default false;
alter table public.barberias add column if not exists modelo_comercial text not null default 'A' check (modelo_comercial in ('A','B','C'));
alter table public.barberias add column if not exists rut text;
alter table public.barberias add column if not exists razon_social text;
alter table public.barberias add column if not exists config_tributaria_validada boolean not null default false;
alter table public.barberias add column if not exists config_validada_por text;
alter table public.barberias add column if not exists config_validada_at timestamptz;
alter table public.barberias add column if not exists modelo_vigente_desde date not null default current_date;
alter table public.sucursales add column if not exists rut text;

create table if not exists public.financiero_modelo_log (
  id uuid primary key default gen_random_uuid(),
  barberia_id uuid not null,
  modelo_anterior text, modelo_nuevo text not null,
  vigente_desde date not null, motivo text not null,
  creado_por uuid default auth.uid(), created_at timestamptz not null default now()
);

-- Cambiar el modelo no es libre: solo hacia adelante, con motivo, y el C exige configuración validada.
create or replace function public.fin_cambiar_modelo(p_modelo text, p_desde date, p_motivo text)
returns void language plpgsql security definer set search_path to 'public' as $$
declare v_b uuid := auth_barberia_id(); v_actual text;
begin
  if v_b is null or auth_rol() <> 'dueno' then raise exception 'No autorizado'; end if;
  if p_modelo not in ('A','B','C') then raise exception 'Modelo no válido'; end if;
  if coalesce(btrim(p_motivo), '') = '' then raise exception 'Falta el motivo del cambio'; end if;
  if p_desde is null or p_desde < (now() at time zone 'America/Santiago')::date then
    raise exception 'El cambio de modelo solo rige desde hoy hacia adelante, no de forma retroactiva';
  end if;
  if p_modelo = 'C' and not (select config_tributaria_validada from barberias where id = v_b) then
    raise exception 'El modelo C requiere configuración tributaria validada antes de activarse';
  end if;
  select modelo_comercial into v_actual from barberias where id = v_b;
  insert into financiero_modelo_log (barberia_id, modelo_anterior, modelo_nuevo, vigente_desde, motivo)
  values (v_b, v_actual, p_modelo, p_desde, btrim(p_motivo));
  update barberias set modelo_comercial = p_modelo, modelo_vigente_desde = p_desde where id = v_b;
end $$;

-- El modelo C no se puede activar directo por UPDATE sin validación.
create or replace function public.trg_fin_modelo_c()
returns trigger language plpgsql as $$
begin
  if new.modelo_comercial = 'C' and not new.config_tributaria_validada then
    raise exception 'El modelo C requiere configuración tributaria validada antes de activarse';
  end if;
  return new;
end $$;
drop trigger if exists fin_modelo_c on public.barberias;
create trigger fin_modelo_c before insert or update of modelo_comercial, config_tributaria_validada on public.barberias
  for each row execute function public.trg_fin_modelo_c();

-- ── Redondeo y motor de distribución (puros) ────────────────────────────────
create or replace function public.fin_redondear(p numeric)
returns numeric language sql immutable as $$ select floor(coalesce(p,0) + 0.5) $$;

-- Parte del profesional sobre el precio FINAL (ya con descuento).
-- base 'bruto': % sobre el precio final. base 'neto': % sobre el neto (sin IVA).
create or replace function public.fin_parte_profesional(p_precio_final numeric, p_pct numeric, p_base text, p_iva_pct numeric)
returns numeric language sql immutable as $$
  select public.fin_redondear(
    case when p_base = 'neto'
         then (p_precio_final - p_precio_final * coalesce(p_iva_pct,19) / (100 + coalesce(p_iva_pct,19)))
         else p_precio_final end
    * coalesce(p_pct,0) / 100)
$$;

-- ── Reglas de distribución versionadas ──────────────────────────────────────
create table if not exists public.reglas_distribucion (
  id uuid primary key default gen_random_uuid(),
  barberia_id uuid not null,
  alcance text not null check (alcance in ('negocio','profesional','servicio','profesional_servicio')),
  barbero_nombre text, servicio_nombre text,
  pct_profesional numeric not null check (pct_profesional between 0 and 100),
  base text not null default 'bruto' check (base in ('bruto','neto')),
  version integer not null default 1,
  vigente_desde date not null default current_date,
  activa boolean not null default true,
  created_at timestamptz not null default now(),
  check ((alcance = 'negocio' and barbero_nombre is null and servicio_nombre is null)
      or (alcance = 'profesional' and barbero_nombre is not null and servicio_nombre is null)
      or (alcance = 'servicio' and barbero_nombre is null and servicio_nombre is not null)
      or (alcance = 'profesional_servicio' and barbero_nombre is not null and servicio_nombre is not null))
);
create index if not exists reglas_dist_busqueda on public.reglas_distribucion (barberia_id, alcance, vigente_desde);

-- Una regla nunca se edita: se crea una versión nueva (la anterior queda como historia).
create or replace function public.trg_fin_regla_inmutable()
returns trigger language plpgsql as $$
begin
  if tg_op = 'UPDATE' and (new.pct_profesional is distinct from old.pct_profesional or new.base is distinct from old.base
     or new.barbero_nombre is distinct from old.barbero_nombre or new.servicio_nombre is distinct from old.servicio_nombre
     or new.vigente_desde is distinct from old.vigente_desde) then
    raise exception 'Una regla no se modifica: crea una versión nueva';
  end if;
  return new;
end $$;
drop trigger if exists fin_regla_inmutable on public.reglas_distribucion;
create trigger fin_regla_inmutable before update on public.reglas_distribucion
  for each row execute function public.trg_fin_regla_inmutable();

create or replace function public.fin_regla_crear(p_alcance text, p_barbero text, p_servicio text, p_pct numeric, p_base text, p_desde date)
returns uuid language plpgsql security definer set search_path to 'public' as $$
declare v_b uuid := auth_barberia_id(); v_ver integer; v_id uuid;
begin
  if v_b is null or auth_rol() <> 'dueno' then raise exception 'No autorizado'; end if;
  select coalesce(max(version),0)+1 into v_ver from reglas_distribucion
   where barberia_id = v_b and alcance = p_alcance and coalesce(barbero_nombre,'') = coalesce(p_barbero,'') and coalesce(servicio_nombre,'') = coalesce(p_servicio,'');
  insert into reglas_distribucion (barberia_id, alcance, barbero_nombre, servicio_nombre, pct_profesional, base, version, vigente_desde)
  values (v_b, p_alcance, p_barbero, p_servicio, p_pct, coalesce(p_base,'bruto'), v_ver, coalesce(p_desde, current_date)) returning id into v_id;
  return v_id;
end $$;

-- Prioridad: profesional+servicio > profesional > servicio > negocio > regla antigua (comisión del profesional).
-- Dentro de cada nivel manda la versión vigente a la fecha del cobro. regla_id NULL = regla antigua (versión 0).
create or replace function public.fin_regla_aplicable(p_barberia uuid, p_barbero text, p_servicio text, p_fecha date)
returns table(regla_id uuid, version integer, pct numeric, base text)
language plpgsql stable security definer set search_path to 'public' as $$
declare r reglas_distribucion%rowtype; b barberias%rowtype; v_pct numeric;
begin
  select * into r from reglas_distribucion x
   where x.barberia_id = p_barberia and x.activa and x.vigente_desde <= p_fecha
     and ((x.alcance='profesional_servicio' and x.barbero_nombre = p_barbero and x.servicio_nombre = p_servicio)
       or (x.alcance='profesional' and x.barbero_nombre = p_barbero)
       or (x.alcance='servicio' and x.servicio_nombre = p_servicio)
       or (x.alcance='negocio'))
   order by case x.alcance when 'profesional_servicio' then 1 when 'profesional' then 2 when 'servicio' then 3 else 4 end,
            x.vigente_desde desc, x.version desc limit 1;
  if found then
    regla_id := r.id; version := r.version; pct := r.pct_profesional; base := r.base; return next; return;
  end if;
  select * into b from barberias where id = p_barberia;
  select comision_pct into v_pct from barberos where barberia_id = p_barberia and nombre = p_barbero order by activo desc limit 1;
  regla_id := null; version := 0; pct := coalesce(v_pct, 50);
  base := case when b.modo_comision = 'neto_iva' then 'neto' else 'bruto' end;
  return next;
end $$;

-- ── Líneas de cobro (una por servicio/producto, congeladas) ─────────────────
create table if not exists public.cobro_lineas (
  id uuid primary key default gen_random_uuid(),
  barberia_id uuid not null, sucursal_id uuid,
  cobro_id uuid, reserva_id uuid,
  visita_id uuid unique, cobro_producto_id uuid unique,
  tipo text not null check (tipo in ('servicio','producto')),
  barbero_nombre text, servicio text,
  precio_original numeric, descuento numeric not null default 0, precio_final numeric not null,
  pct_aplicado numeric, base_calculo text, regla_id uuid, regla_version integer,
  participacion_profesional numeric not null default 0,
  participacion_establecimiento numeric not null default 0,
  propina numeric not null default 0, abono_previo numeric not null default 0,
  modelo text not null default 'A',
  clasificacion_tributaria text not null default 'ingreso_propio' check (clasificacion_tributaria in ('ingreso_propio','tercero')),
  emisor_rut text, receptor_rut text, documento_id uuid,
  metodo_pago text, fecha_cobro date not null,
  estado_conciliacion text not null default 'pendiente' check (estado_conciliacion in ('pendiente','conciliado','sin_caja','anulado')),
  liquidacion_id uuid,
  created_at timestamptz not null default now(),
  check (participacion_profesional + participacion_establecimiento = precio_final)
);
create index if not exists cobro_lineas_periodo on public.cobro_lineas (barberia_id, fecha_cobro);
create index if not exists cobro_lineas_liq on public.cobro_lineas (liquidacion_id);

-- Con financiero_v2 activo, la comisión del servicio sale de la regla aplicable (antes de que
-- visitas_honorarios calcule la retención). Apagado: no hace nada.
create or replace function public.trg_fin_visita_comision()
returns trigger language plpgsql security definer set search_path to 'public' as $$
declare b barberias%rowtype; r record;
begin
  select * into b from barberias where id = new.barberia_id;
  if not found or not b.financiero_v2 then return new; end if;
  select * into r from fin_regla_aplicable(new.barberia_id, new.barbero_nombre, new.servicio, new.fecha);
  if r.regla_id is not null then   -- solo si hay regla nueva; sin regla se respeta el cálculo antiguo
    new.comision_monto := fin_parte_profesional(coalesce(new.valor,0), r.pct, r.base, b.iva_pct);
  end if;
  return new;
end $$;
drop trigger if exists a_fin_visita_comision on public.visitas;
create trigger a_fin_visita_comision before insert on public.visitas
  for each row execute function public.trg_fin_visita_comision();

create or replace function public.fin_clasificar(b barberias, p_tipo text)
returns text language sql immutable as $$
  select case when b.modelo_comercial = 'B' and p_tipo = 'servicio' then 'tercero' else 'ingreso_propio' end
$$;

create or replace function public.trg_fin_linea_visita()
returns trigger language plpgsql security definer set search_path to 'public' as $$
declare b barberias%rowtype; r record; v_final numeric; v_prof numeric; v_rut text; v_tipo_clas text; v_pct numeric;
begin
  select * into b from barberias where id = new.barberia_id;
  if not found or not b.financiero_v2 or coalesce(new.estado,'') = 'Cancelada' then return new; end if;
  v_final := coalesce(new.valor,0);
  select * into r from fin_regla_aplicable(new.barberia_id, new.barbero_nombre, new.servicio, new.fecha);
  v_pct := r.pct;
  v_prof := case when b.modelo_comercial = 'B' then v_final else coalesce(new.comision_monto, fin_parte_profesional(v_final, r.pct, r.base, b.iva_pct)) end;
  if b.modelo_comercial = 'B' then v_pct := 100; end if;
  select coalesce(s.rut, b.rut) into v_rut from sucursales s where s.id = new.sucursal_id;
  v_rut := coalesce(v_rut, b.rut);
  insert into cobro_lineas (barberia_id, sucursal_id, cobro_id, visita_id, tipo, barbero_nombre, servicio,
      precio_original, descuento, precio_final, pct_aplicado, base_calculo, regla_id, regla_version,
      participacion_profesional, participacion_establecimiento, propina, abono_previo, modelo,
      clasificacion_tributaria, emisor_rut, metodo_pago, fecha_cobro, estado_conciliacion)
  values (new.barberia_id, new.sucursal_id, new.cobro_id, new.id, 'servicio', new.barbero_nombre, new.servicio,
      coalesce(new.precio_lista, v_final), coalesce(new.descuento_monto, 0), v_final, v_pct, r.base, r.regla_id, r.version,
      v_prof, v_final - v_prof, coalesce(new.propina,0), coalesce(new.abono_previo,0), b.modelo_comercial,
      fin_clasificar(b,'servicio'), v_rut, new.metodo_pago, new.fecha,
      case when new.metodo_pago = 'Gift card' then 'sin_caja' else 'pendiente' end);
  return new;
end $$;
drop trigger if exists fin_linea on public.visitas;
create trigger fin_linea after insert on public.visitas
  for each row execute function public.trg_fin_linea_visita();

create or replace function public.trg_fin_linea_producto()
returns trigger language plpgsql security definer set search_path to 'public' as $$
declare b barberias%rowtype; v_rut text;
begin
  select * into b from barberias where id = new.barberia_id;
  if not found or not b.financiero_v2 then return new; end if;
  select coalesce(s.rut, b.rut) into v_rut from sucursales s where s.id = new.sucursal_id;
  insert into cobro_lineas (barberia_id, sucursal_id, cobro_id, cobro_producto_id, tipo, barbero_nombre, servicio,
      precio_original, descuento, precio_final, participacion_profesional, participacion_establecimiento,
      modelo, clasificacion_tributaria, emisor_rut, metodo_pago, fecha_cobro, estado_conciliacion, regla_version)
  values (new.barberia_id, new.sucursal_id, new.cobro_id, new.id, 'producto', new.barbero_nombre, null,
      coalesce(new.precio_unitario * new.cantidad, new.valor), coalesce(new.descuento_monto,0), new.valor,
      least(new.comision_monto, new.valor), new.valor - least(new.comision_monto, new.valor),
      b.modelo_comercial, 'ingreso_propio', coalesce(v_rut, b.rut), new.metodo_pago, new.fecha,
      case when new.metodo_pago = 'Gift card' then 'sin_caja' else 'pendiente' end, 0);
  return new;
end $$;
drop trigger if exists fin_linea on public.cobro_productos;
create trigger fin_linea after insert on public.cobro_productos
  for each row execute function public.trg_fin_linea_producto();

-- ── Devoluciones (la línea original no se toca) ─────────────────────────────
create table if not exists public.devoluciones (
  id uuid primary key default gen_random_uuid(),
  barberia_id uuid not null, cobro_linea_id uuid not null references public.cobro_lineas(id),
  monto numeric not null check (monto > 0),
  tipo text not null check (tipo in ('parcial','total')),
  motivo text not null, medio text, fecha date not null default (now() at time zone 'America/Santiago')::date,
  clave text unique, created_at timestamptz not null default now()
);

create or replace function public.fin_devolver(p_linea uuid, p_monto numeric, p_motivo text, p_medio text default null, p_clave text default null)
returns uuid language plpgsql security definer set search_path to 'public' as $$
declare l cobro_lineas%rowtype; v_ya numeric; v_id uuid;
begin
  if auth_barberia_id() is null or auth_rol() not in ('dueno') then raise exception 'No autorizado'; end if;
  select * into l from cobro_lineas where id = p_linea and barberia_id = auth_barberia_id() for update;
  if not found then raise exception 'Línea no encontrada'; end if;
  if p_clave is not null then
    select id into v_id from devoluciones where clave = p_clave;
    if found then return v_id; end if;   -- misma devolución reenviada: no se duplica
  end if;
  if coalesce(btrim(p_motivo),'') = '' then raise exception 'Falta el motivo'; end if;
  select coalesce(sum(monto),0) into v_ya from devoluciones where cobro_linea_id = l.id;
  if p_monto > l.precio_final - v_ya then raise exception 'La devolución supera lo cobrado (queda por devolver %)', l.precio_final - v_ya; end if;
  insert into devoluciones (barberia_id, cobro_linea_id, monto, tipo, motivo, medio, clave)
  values (l.barberia_id, l.id, p_monto, case when p_monto = l.precio_final - v_ya and v_ya = 0 then 'total' else 'parcial' end, p_motivo, p_medio, p_clave)
  returning id into v_id;
  return v_id;
end $$;

-- Líneas con la devolución ya descontada, repartida en proporción a cada parte.
create or replace view public.cobro_lineas_netas with (security_invoker = true) as
select l.*,
       coalesce(d.dev,0) as devuelto,
       l.precio_final - coalesce(d.dev,0) as precio_final_neto,
       case when l.precio_final = 0 then 0 else l.participacion_profesional - public.fin_redondear(coalesce(d.dev,0) * l.participacion_profesional / l.precio_final) end as profesional_neto,
       case when l.precio_final = 0 then 0 else (l.precio_final - coalesce(d.dev,0)) - (l.participacion_profesional - public.fin_redondear(coalesce(d.dev,0) * l.participacion_profesional / l.precio_final)) end as establecimiento_neto
  from public.cobro_lineas l
  left join (select cobro_linea_id, sum(monto) dev from public.devoluciones group by 1) d on d.cobro_linea_id = l.id;

-- ── Documentos tributarios (registro manual; nunca implica emisión ante el SII) ──
create table if not exists public.documentos_tributarios (
  id uuid primary key default gen_random_uuid(),
  barberia_id uuid not null,
  rut_emisor text not null, rut_receptor text,
  tipo text not null check (tipo in ('boleta_honorarios','boleta_ventas','factura','nota_credito','otro')),
  folio text, fecha_emision date,
  monto_neto numeric not null default 0, iva numeric not null default 0,
  honorarios_brutos numeric not null default 0,
  retencion_pct numeric, retencion numeric not null default 0,
  ppm_pct numeric, ppm numeric not null default 0,
  responsable_impuesto text check (responsable_impuesto in ('receptor_retiene','emisor_ppm','sin_retencion')),
  subsidio_negocio numeric not null default 0,
  advertencia text,
  estado text not null default 'pendiente' check (estado in ('pendiente','emitido','fallido','anulado')),
  respaldo_url text, verificado_manual boolean not null default false,
  liquidacion_id uuid, created_at timestamptz not null default now(),
  check (estado <> 'emitido' or (folio is not null and fecha_emision is not null))
);

-- Retención por la fecha del DOCUMENTO. Responsable legal según receptor;
-- el subsidio del negocio se registra aparte y advierte posible renta adicional gravada.
create or replace function public.fin_documento_registrar(
  p_tipo text, p_rut_emisor text, p_rut_receptor text, p_receptor_retiene boolean,
  p_honorarios numeric, p_fecha_emision date, p_folio text default null,
  p_ppm_pct numeric default null, p_subsidio numeric default 0, p_liquidacion uuid default null)
returns uuid language plpgsql security definer set search_path to 'public' as $$
declare v_b uuid := auth_barberia_id(); v_f date; v_t numeric; v_ret numeric := 0; v_ppm numeric := 0; v_resp text; v_adv text; v_id uuid; v_est text;
begin
  if v_b is null or auth_rol() <> 'dueno' then raise exception 'No autorizado'; end if;
  v_f := coalesce(p_fecha_emision, (now() at time zone 'America/Santiago')::date);
  if p_tipo = 'boleta_honorarios' then
    if p_receptor_retiene then
      v_t := tasa_retencion_honorarios(v_f);
      v_ret := fin_redondear(p_honorarios * coalesce(v_t,0) / 100); v_resp := 'receptor_retiene';
    elsif p_ppm_pct is not null then
      v_ppm := fin_redondear(p_honorarios * p_ppm_pct / 100); v_resp := 'emisor_ppm';
    else
      v_resp := 'sin_retencion';
    end if;
  end if;
  if coalesce(p_subsidio,0) > 0 then
    v_adv := 'El negocio financia parte del impuesto del profesional: puede constituir renta adicional gravada. Confírmalo con tu contador.';
  end if;
  v_est := case when p_folio is not null and btrim(p_folio) <> '' then 'emitido' else 'pendiente' end;
  insert into documentos_tributarios (barberia_id, rut_emisor, rut_receptor, tipo, folio, fecha_emision, honorarios_brutos,
      retencion_pct, retencion, ppm_pct, ppm, responsable_impuesto, subsidio_negocio, advertencia, estado, verificado_manual, liquidacion_id)
  values (v_b, p_rut_emisor, p_rut_receptor, p_tipo, nullif(btrim(coalesce(p_folio,'')),''), case when v_est='emitido' then v_f else null end, p_honorarios,
      v_t, v_ret, p_ppm_pct, v_ppm, v_resp, coalesce(p_subsidio,0), v_adv, v_est, v_est = 'emitido', p_liquidacion)
  returning id into v_id;
  return v_id;
end $$;

-- ── Arriendo de sillón (modelo B) ───────────────────────────────────────────
create table if not exists public.arriendos_sillon (
  id uuid primary key default gen_random_uuid(),
  barberia_id uuid not null, barbero_nombre text not null,
  periodo text not null check (periodo ~ '^[0-9]{4}-(0[1-9]|1[0-2])$'),
  monto_neto numeric not null check (monto_neto > 0), iva numeric not null default 0,
  estado text not null default 'pendiente' check (estado in ('pendiente','cobrado','documentado','anulado')),
  documento_id uuid, liquidacion_id uuid, created_at timestamptz not null default now(),
  unique (barberia_id, barbero_nombre, periodo)
);

-- ── Liquidaciones por profesional y período ─────────────────────────────────
create table if not exists public.liquidaciones (
  id uuid primary key default gen_random_uuid(),
  barberia_id uuid not null, barbero_nombre text not null,
  desde date not null, hasta date not null,
  estado text not null default 'emitida' check (estado in ('emitida','pagada_parcial','pagada','anulada')),
  servicios_n integer not null default 0,
  total_cobrado numeric not null default 0,
  honorarios_brutos numeric not null default 0,
  comision_productos numeric not null default 0,
  propinas numeric not null default 0,
  anticipos numeric not null default 0,
  retenciones_aplicadas numeric not null default 0,
  ppm_estimado numeric not null default 0,
  ajustes numeric not null default 0,
  total_a_transferir numeric not null default 0,
  total_transferido numeric not null default 0,
  documentos_pendientes integer not null default 0,
  created_at timestamptz not null default now()
);
create table if not exists public.liquidacion_ajustes (
  id uuid primary key default gen_random_uuid(),
  liquidacion_id uuid not null references public.liquidaciones(id),
  monto numeric not null check (monto <> 0), motivo text not null,
  creado_por uuid default auth.uid(), created_at timestamptz not null default now()
);
create table if not exists public.liquidacion_pagos (
  id uuid primary key default gen_random_uuid(),
  liquidacion_id uuid not null references public.liquidaciones(id),
  monto numeric not null check (monto > 0), medio text, comprobante text,
  clave text unique, fecha date not null default (now() at time zone 'America/Santiago')::date,
  created_at timestamptz not null default now()
);
alter table public.anticipos_profesional add column if not exists liquidacion_id uuid;

-- Las líneas ya liquidadas no entran a otra liquidación (no se paga dos veces).
-- Retención: se descuenta solo la efectivamente aplicada en la visita (retencion_profesional);
-- el PPM propio es solo informativo (ppm_estimado) y NO se resta: así no se descuenta dos veces.
create or replace function public.fin_liquidacion_crear(p_barbero text, p_desde date, p_hasta date, p_ppm_pct numeric default 0)
returns uuid language plpgsql security definer set search_path to 'public' as $$
declare v_b uuid := auth_barberia_id(); v_id uuid := gen_random_uuid();
  v_n int; v_cob numeric; v_hon numeric; v_prod numeric; v_prop numeric; v_ant numeric; v_ret numeric; v_pend int;
begin
  if v_b is null or auth_rol() <> 'dueno' then raise exception 'No autorizado'; end if;
  if p_hasta < p_desde then raise exception 'El período no es válido'; end if;
  select count(*) filter (where tipo='servicio'), coalesce(sum(precio_final_neto),0),
         coalesce(sum(profesional_neto) filter (where tipo='servicio'),0),
         coalesce(sum(profesional_neto) filter (where tipo='producto'),0),
         coalesce(sum(propina),0)
    into v_n, v_cob, v_hon, v_prod, v_prop
    from cobro_lineas_netas where barberia_id = v_b and barbero_nombre = p_barbero
     and fecha_cobro between p_desde and p_hasta and liquidacion_id is null and estado_conciliacion <> 'anulado';
  if v_n = 0 and v_prod = 0 and v_prop = 0 then raise exception 'No hay movimientos sin liquidar en ese período'; end if;
  select coalesce(sum(v.retencion_profesional),0) into v_ret
    from visitas v join cobro_lineas l on l.visita_id = v.id
   where l.barberia_id = v_b and l.barbero_nombre = p_barbero and l.fecha_cobro between p_desde and p_hasta and l.liquidacion_id is null;
  select coalesce(sum(monto),0) into v_ant from anticipos_profesional
   where barberia_id = v_b and barbero_nombre = p_barbero and fecha between p_desde and p_hasta and liquidacion_id is null;
  select count(*) into v_pend from documentos_tributarios d where d.barberia_id = v_b and d.estado in ('pendiente','fallido')
     and d.liquidacion_id is null and d.tipo = 'boleta_honorarios';
  insert into liquidaciones (id, barberia_id, barbero_nombre, desde, hasta, servicios_n, total_cobrado, honorarios_brutos,
      comision_productos, propinas, anticipos, retenciones_aplicadas, ppm_estimado, total_a_transferir, documentos_pendientes)
  values (v_id, v_b, p_barbero, p_desde, p_hasta, v_n, v_cob, v_hon, v_prod, v_prop, v_ant, v_ret,
      fin_redondear(v_hon * coalesce(p_ppm_pct,0) / 100),
      v_hon - v_ret + v_prod + v_prop - v_ant, v_pend);
  update cobro_lineas set liquidacion_id = v_id
   where barberia_id = v_b and barbero_nombre = p_barbero and fecha_cobro between p_desde and p_hasta and liquidacion_id is null and estado_conciliacion <> 'anulado';
  update anticipos_profesional set liquidacion_id = v_id
   where barberia_id = v_b and barbero_nombre = p_barbero and fecha between p_desde and p_hasta and liquidacion_id is null;
  return v_id;
end $$;

create or replace function public.fin_liquidacion_pendiente(p_liq uuid)
returns numeric language sql stable security definer set search_path to 'public' as $$
  select l.total_a_transferir + l.ajustes - coalesce((select sum(monto) from liquidacion_pagos where liquidacion_id = l.id),0)
    from liquidaciones l where l.id = p_liq and l.barberia_id = auth_barberia_id()
$$;

create or replace function public.fin_liquidacion_ajustar(p_liq uuid, p_monto numeric, p_motivo text)
returns void language plpgsql security definer set search_path to 'public' as $$
begin
  if auth_barberia_id() is null or auth_rol() <> 'dueno' then raise exception 'No autorizado'; end if;
  if coalesce(btrim(p_motivo),'') = '' then raise exception 'Falta el motivo del ajuste'; end if;
  if not exists (select 1 from liquidaciones where id = p_liq and barberia_id = auth_barberia_id()) then raise exception 'Liquidación no encontrada'; end if;
  insert into liquidacion_ajustes (liquidacion_id, monto, motivo) values (p_liq, p_monto, p_motivo);
  update liquidaciones set ajustes = ajustes + p_monto where id = p_liq;
  perform fin_liquidacion_estado(p_liq);
end $$;

create or replace function public.fin_liquidacion_estado(p_liq uuid)
returns void language plpgsql security definer set search_path to 'public' as $$
declare v_pend numeric; v_pag numeric;
begin
  select coalesce(sum(monto),0) into v_pag from liquidacion_pagos where liquidacion_id = p_liq;
  select total_a_transferir + ajustes - v_pag into v_pend from liquidaciones where id = p_liq;
  update liquidaciones set total_transferido = v_pag,
     estado = case when estado = 'anulada' then 'anulada' when v_pend <= 0 then 'pagada' when v_pag > 0 then 'pagada_parcial' else 'emitida' end
   where id = p_liq;
end $$;

-- Pago idempotente: reenviar la misma clave no duplica; no se puede pagar más de lo pendiente.
create or replace function public.fin_liquidacion_pagar(p_liq uuid, p_monto numeric, p_medio text, p_comprobante text, p_clave text)
returns uuid language plpgsql security definer set search_path to 'public' as $$
declare v_id uuid; v_pend numeric;
begin
  if auth_barberia_id() is null or auth_rol() <> 'dueno' then raise exception 'No autorizado'; end if;
  perform 1 from liquidaciones where id = p_liq and barberia_id = auth_barberia_id() for update;
  if not found then raise exception 'Liquidación no encontrada'; end if;
  if p_clave is not null then select id into v_id from liquidacion_pagos where clave = p_clave; if found then return v_id; end if; end if;
  v_pend := fin_liquidacion_pendiente(p_liq);
  if p_monto > v_pend then raise exception 'El pago supera lo pendiente (pendiente %)', v_pend; end if;
  insert into liquidacion_pagos (liquidacion_id, monto, medio, comprobante, clave) values (p_liq, p_monto, p_medio, p_comprobante, p_clave) returning id into v_id;
  perform fin_liquidacion_estado(p_liq);
  return v_id;
end $$;

-- Arriendo de sillón: se descuenta de la liquidación como ajuste con trazabilidad.
create or replace function public.fin_arriendo_descontar(p_arriendo uuid, p_liq uuid)
returns void language plpgsql security definer set search_path to 'public' as $$
declare a arriendos_sillon%rowtype; l liquidaciones%rowtype;
begin
  if auth_barberia_id() is null or auth_rol() <> 'dueno' then raise exception 'No autorizado'; end if;
  select * into a from arriendos_sillon where id = p_arriendo and barberia_id = auth_barberia_id() for update;
  select * into l from liquidaciones where id = p_liq and barberia_id = auth_barberia_id();
  if a.id is null or l.id is null then raise exception 'No encontrado'; end if;
  if a.liquidacion_id is not null then raise exception 'Ese arriendo ya fue descontado'; end if;
  if a.barbero_nombre <> l.barbero_nombre then raise exception 'El arriendo es de otro profesional'; end if;
  update arriendos_sillon set liquidacion_id = p_liq, estado = 'cobrado' where id = a.id;
  perform fin_liquidacion_ajustar(p_liq, -(a.monto_neto + a.iva), 'Arriendo de sillón ' || a.periodo);
end $$;

-- ── IVA: solo operaciones propias, con libro de remanente ───────────────────
create table if not exists public.iva_remanente_libro (
  id uuid primary key default gen_random_uuid(),
  barberia_id uuid not null, mes text not null check (mes ~ '^[0-9]{4}-(0[1-9]|1[0-2])$'),
  iva_debito numeric not null default 0, iva_credito numeric not null default 0,
  remanente_anterior numeric not null default 0, reajuste_pct numeric not null default 0,
  remanente_reajustado numeric not null default 0,
  iva_a_pagar numeric not null default 0, remanente_nuevo numeric not null default 0,
  created_at timestamptz not null default now(),
  unique (barberia_id, mes)
);

-- Débito: IVA incluido en el precio final NETO de devoluciones de ingresos propios (por RUT si se indica)
-- + IVA de arriendos de sillón. Crédito: IVA de gastos. El remanente anterior se reajusta con el %
-- que el usuario ingresa (variación de IPC según SII): no se inventa.
create or replace function public.fin_iva_mes(p_mes text, p_reajuste_pct numeric default 0, p_rut text default null)
returns table(iva_debito numeric, iva_credito numeric, remanente_anterior numeric, remanente_reajustado numeric, iva_a_pagar numeric, remanente_nuevo numeric)
language plpgsql stable security definer set search_path to 'public' as $$
declare v_b uuid := auth_barberia_id(); b barberias%rowtype; v_ini date; v_fin date; v_deb numeric; v_cred numeric; v_ant numeric; v_rea numeric; v_net numeric; v_prev text;
begin
  if v_b is null or auth_rol() <> 'dueno' then raise exception 'No autorizado'; end if;
  select * into b from barberias where id = v_b;
  v_ini := (p_mes || '-01')::date; v_fin := (v_ini + interval '1 month - 1 day')::date;
  select coalesce(sum(round(n.precio_final_neto * coalesce(b.iva_pct,19) / (100 + coalesce(b.iva_pct,19)))),0) into v_deb
    from cobro_lineas_netas n where n.barberia_id = v_b and n.clasificacion_tributaria = 'ingreso_propio'
     and n.estado_conciliacion <> 'anulado' and n.fecha_cobro between v_ini and v_fin
     and (p_rut is null or n.emisor_rut = p_rut);
  v_deb := v_deb + coalesce((select sum(a.iva) from arriendos_sillon a where a.barberia_id = v_b and a.periodo = p_mes and a.estado <> 'anulado'),0);
  select coalesce(sum(c.iva),0) into v_cred from costos c where c.barberia_id = v_b and c.fecha between v_ini and v_fin;
  v_prev := to_char(v_ini - interval '1 month', 'YYYY-MM');
  select coalesce((select lb.remanente_nuevo from iva_remanente_libro lb where lb.barberia_id = v_b and lb.mes = v_prev),
                  (select h.remanente from iva_historico h where h.barberia_id = v_b and h.mes = v_prev), 0) into v_ant;
  v_rea := fin_redondear(v_ant * (1 + coalesce(p_reajuste_pct,0) / 100));
  v_net := v_deb - v_cred - v_rea;
  iva_debito := v_deb; iva_credito := v_cred; remanente_anterior := v_ant; remanente_reajustado := v_rea;
  iva_a_pagar := greatest(v_net, 0); remanente_nuevo := greatest(-v_net, 0);
  return next;
end $$;

create or replace function public.fin_iva_cerrar_mes(p_mes text, p_reajuste_pct numeric default 0)
returns void language plpgsql security definer set search_path to 'public' as $$
declare r record;
begin
  select * into r from fin_iva_mes(p_mes, p_reajuste_pct);
  insert into iva_remanente_libro (barberia_id, mes, iva_debito, iva_credito, remanente_anterior, reajuste_pct, remanente_reajustado, iva_a_pagar, remanente_nuevo)
  values (auth_barberia_id(), p_mes, r.iva_debito, r.iva_credito, r.remanente_anterior, p_reajuste_pct, r.remanente_reajustado, r.iva_a_pagar, r.remanente_nuevo)
  on conflict (barberia_id, mes) do update set iva_debito = excluded.iva_debito, iva_credito = excluded.iva_credito,
     remanente_anterior = excluded.remanente_anterior, reajuste_pct = excluded.reajuste_pct,
     remanente_reajustado = excluded.remanente_reajustado, iva_a_pagar = excluded.iva_a_pagar, remanente_nuevo = excluded.remanente_nuevo;
end $$;

-- ── Seguridad: solo el dueño (cada tabla nueva) ─────────────────────────────
do $$ declare t text; begin
  foreach t in array array['financiero_modelo_log','reglas_distribucion','cobro_lineas','devoluciones','documentos_tributarios','arriendos_sillon','liquidaciones','iva_remanente_libro'] loop
    execute format('alter table public.%I enable row level security', t);
    execute format('drop policy if exists %I on public.%I', t||'_dueno', t);
    execute format('create policy %I on public.%I for all using (barberia_id = auth_barberia_id() and auth_rol() = ''dueno'') with check (barberia_id = auth_barberia_id() and auth_rol() = ''dueno'')', t||'_dueno', t);
  end loop;
  execute 'alter table public.liquidacion_ajustes enable row level security';
  execute 'alter table public.liquidacion_pagos enable row level security';
  execute 'drop policy if exists liq_ajustes_dueno on public.liquidacion_ajustes';
  execute 'create policy liq_ajustes_dueno on public.liquidacion_ajustes for all using (exists (select 1 from liquidaciones l where l.id = liquidacion_id and l.barberia_id = auth_barberia_id() and auth_rol() = ''dueno''))';
  execute 'drop policy if exists liq_pagos_dueno on public.liquidacion_pagos';
  execute 'create policy liq_pagos_dueno on public.liquidacion_pagos for all using (exists (select 1 from liquidaciones l where l.id = liquidacion_id and l.barberia_id = auth_barberia_id() and auth_rol() = ''dueno''))';
end $$;

-- ── Abonos: estados nuevos ──────────────────────────────────────────────────
alter table public.reservas drop constraint if exists reservas_abono_estado_check;
alter table public.reservas add constraint reservas_abono_estado_check check (abono_estado is null or abono_estado in
  ('Pendiente','Por confirmar','Confirmado','Vencido','Rechazado','Retenido','Reembolsado','Aplicado','Pendiente regularización'));
