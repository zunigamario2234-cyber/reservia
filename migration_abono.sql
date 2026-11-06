-- =============================================================================
-- ABONO PARA CONFIRMAR LA HORA (transferencia + comprobante, sin pasarela)
--
-- Flujo:
--  1. La barbería activa el abono (abono_config) y elige monto/porcentaje,
--     minutos que se retiene la hora (5 a 120) y si exige comprobante.
--     Cada servicio puede usar el general, otro monto/%, o no pedir abono.
--  2. El cliente reserva por la web: la reserva queda 'Pendiente de abono'
--     (la hora queda retenida) y se le muestran los datos de transferencia.
--  3. El cliente sube el comprobante o avisa que transfirió -> 'Por confirmar'
--     (la hora se mantiene un rato más mientras el negocio revisa).
--  4. Dueño/recepción confirma -> 'Confirmada'. Si el tiempo vence sin abono,
--     la hora se libera sola (la vista de disponibilidad ya la ignora y
--     liberar_abonos_vencidos() ordena el estado).
--  5. Al cobrar, el abono se descuenta: visitas.abono_previo.
--
-- Datos bancarios en tabla privada (barberias es de lectura pública).
-- =============================================================================

-- 1. Configuración (privada) ---------------------------------------------------
create table if not exists public.abono_config (
  barberia_id       uuid primary key references public.barberias(id) on delete cascade,
  activo            boolean not null default false,
  tipo              text not null default 'porcentaje' check (tipo in ('monto','porcentaje')),
  valor             numeric not null default 30 check (valor >= 0),
  retencion_min     integer not null default 30 check (retencion_min between 5 and 120),
  exige_comprobante boolean not null default false,
  club_exento       boolean not null default true,
  banco             text,
  tipo_cuenta       text,
  numero_cuenta     text,
  titular           text,
  rut               text,
  instrucciones     text,
  updated_at        timestamptz not null default now(),
  check (tipo <> 'porcentaje' or valor <= 100)
);
alter table public.abono_config enable row level security;
drop policy if exists abono_config_dueno on public.abono_config;
create policy abono_config_dueno on public.abono_config for all
  using (barberia_id = auth_barberia_id() and auth_rol() = 'dueno')
  with check (barberia_id = auth_barberia_id() and auth_rol() = 'dueno');

-- 2. Servicios: null = usa el general ------------------------------------------
alter table public.servicios add column if not exists abono_tipo  text
  check (abono_tipo in ('ninguno','monto','porcentaje'));
alter table public.servicios add column if not exists abono_valor numeric
  check (abono_valor >= 0);

-- 3. Reservas y visitas --------------------------------------------------------
alter table public.reservas add column if not exists abono_estado text
  check (abono_estado in ('Pendiente','Por confirmar','Confirmado','Vencido','Rechazado'));
alter table public.reservas add column if not exists abono_monto numeric;
alter table public.reservas add column if not exists abono_vence_at timestamptz;
alter table public.reservas add column if not exists abono_token uuid;
alter table public.reservas add column if not exists abono_comprobante text;
alter table public.reservas add column if not exists abono_confirmado_at timestamptz;
alter table public.visitas  add column if not exists abono_previo numeric not null default 0;

-- 4. Disponibilidad: una reserva con abono vencido ya no ocupa la hora ---------
create or replace view public.reservas_disponibilidad as
 select id, barberia_id, fecha, hora, barbero_nombre, procesado,
    coalesce(( select s.duracion_min
           from servicios s
          where s.barberia_id = r.barberia_id
            and (s.id::text = r.servicio or lower(btrim(s.nombre)) = lower(btrim(r.servicio)))
          order by (s.id::text = r.servicio) desc
         limit 1), 30) as duracion_min
   from reservas r
  where coalesce(estado, '') <> all (array['Cancelada','No asistió'])
    and not (r.abono_estado in ('Pendiente','Por confirmar')
             and r.abono_vence_at is not null and r.abono_vence_at < now());

-- 5. Helpers --------------------------------------------------------------------
create or replace function public.liberar_abonos_vencidos()
returns integer language plpgsql security definer set search_path to 'public' as $$
declare n integer;
begin
  update reservas set estado = 'Cancelada', abono_estado = 'Vencido'
   where abono_estado in ('Pendiente','Por confirmar')
     and abono_vence_at < now() and estado = 'Pendiente de abono';
  get diagnostics n = row_count;
  return n;
end $$;

create or replace function public._abono_solapa(
  p_barberia uuid, p_barbero text, p_fecha date, p_hora time, p_dur integer, p_excluir uuid)
returns boolean language sql security definer set search_path to 'public' as $$
  select exists (
    select 1 from reservas_disponibilidad d
     where d.barberia_id = p_barberia
       and lower(btrim(d.barbero_nombre)) = lower(btrim(p_barbero))
       and d.fecha = p_fecha
       and d.id is distinct from p_excluir
       and ((p_fecha + p_hora), (p_fecha + p_hora) + make_interval(mins => greatest(p_dur, 1)))
           overlaps ((d.fecha + d.hora), (d.fecha + d.hora) + make_interval(mins => greatest(d.duracion_min, 1))));
$$;

create or replace function public._abono_duracion(p_barberia uuid, p_servicio text)
returns integer language sql security definer set search_path to 'public' as $$
  select coalesce((select s.duracion_min from servicios s
    where s.barberia_id = p_barberia
      and (s.id::text = p_servicio or lower(btrim(s.nombre)) = lower(btrim(p_servicio)))
    order by (s.id::text = p_servicio) desc limit 1), 30);
$$;

-- Monto de abono que corresponde a un servicio (0 = no pide abono).
create or replace function public.abono_monto_para(p_barberia uuid, p_servicio text)
returns numeric language plpgsql security definer set search_path to 'public' as $$
declare c abono_config%rowtype; s servicios%rowtype; t text; val numeric; v numeric;
begin
  select * into c from abono_config where barberia_id = p_barberia;
  if not found or not c.activo then return 0; end if;
  select * into s from servicios
   where barberia_id = p_barberia
     and (id::text = p_servicio or lower(btrim(nombre)) = lower(btrim(coalesce(p_servicio,''))))
   order by (id::text = p_servicio) desc limit 1;
  if not found then
    return case when c.tipo = 'monto' then round(c.valor) else 0 end;
  end if;
  if coalesce(s.abono_tipo, 'general') = 'ninguno' then return 0; end if;
  if s.abono_tipo is null then t := c.tipo; val := c.valor;
  else t := s.abono_tipo; val := coalesce(s.abono_valor, 0); end if;
  if t = 'porcentaje' then v := round(coalesce(s.precio, 0) * val / 100);
  else v := round(val); end if;
  if coalesce(s.precio, 0) > 0 then v := least(v, s.precio); end if;
  return greatest(v, 0);
end $$;

-- Lo que la web pública puede saber sin ver datos bancarios.
create or replace function public.abono_info_publico(p_barberia_id uuid)
returns jsonb language sql security definer set search_path to 'public' as $$
  select coalesce((select jsonb_build_object(
      'activo', c.activo, 'tipo', c.tipo, 'valor', c.valor,
      'retencion_min', c.retencion_min, 'exige_comprobante', c.exige_comprobante,
      'club_exento', c.club_exento)
    from abono_config c where c.barberia_id = p_barberia_id and c.activo),
    jsonb_build_object('activo', false));
$$;

-- 6. Crear reservas con abono ---------------------------------------------------
create or replace function public._abono_retener(p_reserva_id uuid, p_monto numeric)
returns jsonb language plpgsql security definer set search_path to 'public' as $$
declare c abono_config%rowtype; r reservas%rowtype;
begin
  select * into r from reservas where id = p_reserva_id;
  select * into c from abono_config where barberia_id = r.barberia_id;
  update reservas set
      estado = 'Pendiente de abono', abono_estado = 'Pendiente', abono_monto = p_monto,
      abono_vence_at = now() + make_interval(mins => c.retencion_min),
      abono_token = gen_random_uuid()
    where id = p_reserva_id
    returning * into r;
  return jsonb_build_object('id', r.id, 'requiere_abono', true, 'monto', r.abono_monto,
    'vence_at', r.abono_vence_at, 'token', r.abono_token,
    'retencion_min', c.retencion_min, 'exige_comprobante', c.exige_comprobante);
end $$;

create or replace function public.crear_reserva_publica_abono(
  p_barberia_id uuid, p_nombre_cliente text, p_whatsapp_cliente text, p_fecha date,
  p_hora time, p_email_cliente text default null, p_cumpleanos_cliente date default null,
  p_servicio text default null, p_barbero_nombre text default null, p_notas text default null)
returns jsonb language plpgsql security definer set search_path to 'public' as $$
declare v_id uuid; v_monto numeric;
begin
  perform liberar_abonos_vencidos();
  v_monto := abono_monto_para(p_barberia_id, p_servicio);
  if v_monto > 0 and _abono_solapa(p_barberia_id, p_barbero_nombre, p_fecha, p_hora,
        _abono_duracion(p_barberia_id, p_servicio), null) then
    raise exception 'Esa hora acaba de ser tomada. Elige otra';
  end if;
  v_id := crear_reserva_publica(p_barberia_id, p_nombre_cliente, p_whatsapp_cliente, p_fecha,
    p_hora, p_email_cliente, p_cumpleanos_cliente, p_servicio, p_barbero_nombre, p_notas);
  if v_monto > 0 then return _abono_retener(v_id, v_monto); end if;
  return jsonb_build_object('id', v_id, 'requiere_abono', false);
end $$;

create or replace function public.crear_reserva_club_abono(
  p_barberia_id uuid, p_cliente_id uuid, p_fecha date, p_hora time,
  p_servicio text default null, p_barbero_nombre text default null, p_notas text default null)
returns jsonb language plpgsql security definer set search_path to 'public' as $$
declare v_id uuid; v_monto numeric; v_exento boolean;
begin
  perform liberar_abonos_vencidos();
  select club_exento into v_exento from abono_config where barberia_id = p_barberia_id;
  v_monto := case when coalesce(v_exento, true) then 0
                  else abono_monto_para(p_barberia_id, p_servicio) end;
  if v_monto > 0 and _abono_solapa(p_barberia_id, p_barbero_nombre, p_fecha, p_hora,
        _abono_duracion(p_barberia_id, p_servicio), null) then
    raise exception 'Esa hora acaba de ser tomada. Elige otra';
  end if;
  v_id := crear_reserva_publica_club(p_barberia_id, p_cliente_id, p_fecha, p_hora,
    p_servicio, p_barbero_nombre, p_notas);
  if v_monto > 0 then return _abono_retener(v_id, v_monto); end if;
  return jsonb_build_object('id', v_id, 'requiere_abono', false);
end $$;

-- 7. Lado del cliente: datos de transferencia, comprobante, aviso ----------------
create or replace function public.get_abono_publico(p_reserva_id uuid, p_token uuid)
returns jsonb language plpgsql security definer set search_path to 'public' as $$
declare r reservas%rowtype; c abono_config%rowtype; b barberias%rowtype;
begin
  perform liberar_abonos_vencidos();
  select * into r from reservas where id = p_reserva_id and abono_token = p_token;
  if not found then return null; end if;
  select * into c from abono_config where barberia_id = r.barberia_id;
  select * into b from barberias where id = r.barberia_id;
  return jsonb_build_object(
    'abono_estado', r.abono_estado, 'estado', r.estado, 'monto', r.abono_monto,
    'vence_at', r.abono_vence_at, 'ahora', now(),
    'subio_comprobante', r.abono_comprobante is not null,
    'exige_comprobante', coalesce(c.exige_comprobante, false),
    'banco', c.banco, 'tipo_cuenta', c.tipo_cuenta, 'numero_cuenta', c.numero_cuenta,
    'titular', c.titular, 'rut', c.rut, 'instrucciones', c.instrucciones,
    'negocio', b.nombre, 'barberia_id', r.barberia_id);
end $$;

-- ¿Este archivo puede subirse? Solo el que tiene el token de una reserva abierta.
create or replace function public.abono_puede_subir(p_name text)
returns boolean language plpgsql security definer set search_path to 'public' as $$
declare partes text[];
begin
  partes := string_to_array(p_name, '/');
  if array_length(partes, 1) <> 3 then return false; end if;
  if partes[1] !~ '^[0-9a-f-]{36}$' or partes[2] !~ '^[0-9a-f-]{36}$' then return false; end if;
  return exists (
    select 1 from reservas r
     where r.id = partes[2]::uuid and r.barberia_id = partes[1]::uuid
       and r.abono_token is not null
       and left(partes[3], 36) = r.abono_token::text
       and r.abono_estado in ('Pendiente','Por confirmar','Vencido'));
end $$;

create or replace function public.abono_marcar_transferido(p_reserva_id uuid, p_token uuid, p_path text default null)
returns jsonb language plpgsql security definer set search_path to 'public' as $$
declare r reservas%rowtype; c abono_config%rowtype; v_prev text; v_vence timestamptz;
begin
  perform liberar_abonos_vencidos();
  select * into r from reservas where id = p_reserva_id and abono_token = p_token;
  if not found then raise exception 'Reserva no encontrada'; end if;
  if r.abono_estado = 'Confirmado' then return jsonb_build_object('ok', true, 'ya_confirmado', true); end if;
  if r.abono_estado = 'Rechazado' or r.abono_estado is null then
    raise exception 'Esta reserva fue cancelada. Escríbele al negocio';
  end if;
  select * into c from abono_config where barberia_id = r.barberia_id;
  if p_path is not null and p_path not like r.barberia_id::text || '/' || r.id::text || '/' || r.abono_token::text || '%' then
    raise exception 'Comprobante inválido';
  end if;
  if coalesce(c.exige_comprobante, false) and p_path is null and r.abono_comprobante is null then
    raise exception 'Sube el comprobante de la transferencia';
  end if;
  -- Venció pero el cliente igual transfirió: se revive si la hora sigue libre.
  if r.abono_estado = 'Vencido' then
    if r.abono_vence_at < now() - interval '1 day' then
      raise exception 'Esta reserva venció. Escríbele al negocio con tu comprobante';
    end if;
    if _abono_solapa(r.barberia_id, r.barbero_nombre, r.fecha, r.hora,
         _abono_duracion(r.barberia_id, r.servicio), r.id) then
      raise exception 'Venció el tiempo y esa hora ya la tomó otra persona. Escríbele al negocio con tu comprobante';
    end if;
  end if;
  v_prev := r.abono_estado;
  -- Mientras el negocio revisa, la hora se mantiene al menos 30 min más.
  v_vence := greatest(coalesce(r.abono_vence_at, now()),
                      now() + make_interval(mins => greatest(coalesce(c.retencion_min, 30), 30)));
  update reservas set abono_estado = 'Por confirmar', estado = 'Pendiente de abono',
      abono_comprobante = coalesce(p_path, abono_comprobante), abono_vence_at = v_vence
    where id = r.id;
  if v_prev <> 'Por confirmar' or p_path is not null then
    begin
      perform net.http_post(
        url := 'https://dqoqykngmtxtvbokxbzp.supabase.co/functions/v1/push-reserva',
        headers := '{"Content-Type":"application/json"}'::jsonb,
        body := jsonb_build_object('reserva_id', r.id, 'evento', 'abono'));
    exception when others then null;
    end;
  end if;
  return jsonb_build_object('ok', true, 'vence_at', v_vence);
end $$;

-- 8. Lado del negocio -----------------------------------------------------------
create or replace function public.abono_confirmar(p_reserva_id uuid)
returns jsonb language plpgsql security definer set search_path to 'public' as $$
declare r reservas%rowtype; v_reactivada boolean := false;
begin
  if auth_barberia_id() is null or auth_rol() not in ('dueno','recepcion') then
    raise exception 'No autorizado';
  end if;
  select * into r from reservas where id = p_reserva_id and barberia_id = auth_barberia_id();
  if not found then raise exception 'Reserva no encontrada'; end if;
  if r.abono_estado is null then raise exception 'Esta reserva no tiene abono'; end if;
  if r.abono_estado = 'Confirmado' then raise exception 'El abono ya estaba confirmado'; end if;
  if r.estado = 'Cancelada' then
    if _abono_solapa(r.barberia_id, r.barbero_nombre, r.fecha, r.hora,
         _abono_duracion(r.barberia_id, r.servicio), r.id) then
      raise exception 'Esa hora ya fue tomada por otra reserva';
    end if;
    v_reactivada := true;
  end if;
  update reservas set estado = 'Confirmada', abono_estado = 'Confirmado',
      abono_confirmado_at = now(), abono_vence_at = null
    where id = r.id;
  return jsonb_build_object('ok', true, 'reactivada', v_reactivada);
end $$;

create or replace function public.abono_rechazar(p_reserva_id uuid, p_motivo text default null)
returns jsonb language plpgsql security definer set search_path to 'public' as $$
declare r reservas%rowtype;
begin
  if auth_barberia_id() is null or auth_rol() not in ('dueno','recepcion') then
    raise exception 'No autorizado';
  end if;
  select * into r from reservas where id = p_reserva_id and barberia_id = auth_barberia_id();
  if not found then raise exception 'Reserva no encontrada'; end if;
  if r.abono_estado is null or r.abono_estado = 'Confirmado' then
    raise exception 'Solo se puede rechazar un abono pendiente';
  end if;
  update reservas set estado = 'Cancelada', abono_estado = 'Rechazado',
      notas = nullif(btrim(concat_ws(' · ', notas, nullif(btrim(coalesce(p_motivo,'')), ''))), '')
    where id = r.id;
  return jsonb_build_object('ok', true);
end $$;

-- 9. Storage: bucket privado de comprobantes ------------------------------------
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('comprobantes-abono', 'comprobantes-abono', false, 5242880,
        array['image/jpeg','image/png','image/webp','application/pdf'])
on conflict (id) do update set public = false, file_size_limit = 5242880,
  allowed_mime_types = array['image/jpeg','image/png','image/webp','application/pdf'];

drop policy if exists comprobantes_abono_subir on storage.objects;
create policy comprobantes_abono_subir on storage.objects for insert
  to anon, authenticated
  with check (bucket_id = 'comprobantes-abono' and public.abono_puede_subir(name));

drop policy if exists comprobantes_abono_ver on storage.objects;
create policy comprobantes_abono_ver on storage.objects for select
  to authenticated
  using (bucket_id = 'comprobantes-abono'
         and (storage.foldername(name))[1] = auth_barberia_id()::text
         and auth_rol() in ('dueno','recepcion'));

-- 10. Cobros: el abono pagado queda registrado en la visita ---------------------
create or replace function public.registrar_cobro_conjunto(p_lineas jsonb, p_metodo_pago text, p_total_declarado numeric, p_gift_codigo text default null::text)
 returns uuid
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
declare
  v_barberia uuid := auth_barberia_id();
  v_cobro_id uuid := gen_random_uuid();
  v_linea jsonb;
  v_tipo text;
  v_reserva reservas%rowtype;
  v_cliente_id uuid;
  v_fecha date;
  v_valor numeric;
  v_propina numeric;
  v_suma numeric := 0;
  v_comision_pct numeric;
  v_modo_comision text;
  v_iva_pct numeric;
  v_base numeric;
  v_comision_monto numeric;
  v_producto_id uuid;
  v_prod_nombre text;
  v_cantidad integer;
  v_precio_unitario numeric;
  v_barbero_nombre text;
  v_hay_reserva boolean := false;
  v_gift_servicio text;
  v_gift_cubre boolean := false;
  v_metodo text := p_metodo_pago;
begin
  if v_barberia is null or auth_rol() not in ('dueno', 'recepcion') then
    raise exception 'No autorizado';
  end if;
  if p_lineas is null or jsonb_array_length(p_lineas) = 0 then
    raise exception 'El cobro no tiene ninguna línea';
  end if;

  if coalesce(btrim(p_gift_codigo), '') <> '' then
    v_gift_servicio := gift_card_canjear_interno(v_barberia, p_gift_codigo, v_cobro_id);
    v_metodo := 'Gift card';
  end if;

  select modo_comision, iva_pct into v_modo_comision, v_iva_pct
    from barberias where id = v_barberia;

  for v_linea in select * from jsonb_array_elements(p_lineas) loop
    v_tipo := coalesce(v_linea->>'tipo', 'reserva');
    if v_tipo <> 'reserva' then
      continue;
    end if;
    v_hay_reserva := true;

    select * into v_reserva from reservas
      where id = (v_linea->>'reserva_id')::uuid and barberia_id = v_barberia;
    if not found then
      raise exception 'Reserva no encontrada en este negocio';
    end if;
    if v_reserva.procesado then
      raise exception 'La reserva de % ya fue cobrada', v_reserva.nombre_cliente;
    end if;

    if v_gift_servicio is not null and lower(btrim(v_reserva.servicio)) = lower(btrim(v_gift_servicio)) then
      v_gift_cubre := true;
    end if;

    if v_fecha is null then
      v_fecha := v_reserva.fecha;
    elsif v_reserva.fecha <> v_fecha then
      raise exception 'Un cobro conjunto no puede mezclar fechas distintas';
    end if;

    select c.id into v_cliente_id from clientes c
      where c.barberia_id = v_barberia and c.whatsapp = v_reserva.whatsapp_cliente;
    if v_cliente_id is null then
      insert into clientes (barberia_id, nombre, whatsapp, email, cumpleanos, canal, fecha_registro)
      values (v_barberia, v_reserva.nombre_cliente, v_reserva.whatsapp_cliente,
              email_para_ficha(v_reserva.email_cliente),
              v_reserva.cumpleanos_cliente, 'Reserva Web', v_reserva.fecha)
      returning id into v_cliente_id;
    else
      update clientes
         set email = email_para_ficha(v_reserva.email_cliente)
       where id = v_cliente_id
         and barberia_id = v_barberia
         and coalesce(btrim(email), '') = ''
         and email_para_ficha(v_reserva.email_cliente) is not null;
    end if;

    v_valor   := round(coalesce((v_linea->>'valor')::numeric, 0));
    v_propina := round(coalesce((v_linea->>'propina')::numeric, 0));
    if v_valor < 0 or v_propina < 0 then
      raise exception 'Ni el valor ni la propina pueden ser negativos';
    end if;
    v_suma := v_suma + v_valor + v_propina;

    select comision_pct into v_comision_pct from barberos
      where barberia_id = v_barberia and nombre = v_reserva.barbero_nombre;
    v_comision_pct := coalesce(v_comision_pct, 50);

    if v_modo_comision = 'neto_iva' then
      v_base := v_valor - (v_valor * coalesce(v_iva_pct, 19) / (100 + coalesce(v_iva_pct, 19)));
    else
      v_base := v_valor;
    end if;
    v_comision_monto := round(v_base * v_comision_pct / 100);

    insert into visitas (
      barberia_id, cliente_id, barbero_nombre, servicio, valor, fecha, hora,
      fuente, estado, comision_monto, metodo_pago, cobro_id,
      precio_lista, descuento_pct, descuento_monto, propina, propina_pct,
      abono_previo
    ) values (
      v_barberia, v_cliente_id, coalesce(v_reserva.barbero_nombre, ''),
      coalesce(v_reserva.servicio, ''), v_valor, v_reserva.fecha, v_reserva.hora,
      'Reserva', 'Atendida', v_comision_monto, v_metodo, v_cobro_id,
      nullif((v_linea->>'precio_lista')::numeric, 0),
      (v_linea->>'descuento_pct')::numeric,
      (v_linea->>'descuento_monto')::numeric,
      v_propina,
      (v_linea->>'propina_pct')::numeric,
      case when v_reserva.abono_estado = 'Confirmado'
           then least(coalesce(v_reserva.abono_monto, 0), v_valor) else 0 end
    );

    update reservas set procesado = true, estado = 'Atendida' where id = v_reserva.id;
  end loop;

  if v_gift_servicio is not null and not v_gift_cubre then
    raise exception 'Esta gift card es para "%" y el cobro no incluye ese servicio', v_gift_servicio;
  end if;

  if v_fecha is null then
    v_fecha := (now() at time zone 'America/Santiago')::date;
  end if;

  for v_linea in select * from jsonb_array_elements(p_lineas) loop
    if coalesce(v_linea->>'tipo', 'reserva') <> 'producto' then
      continue;
    end if;

    v_producto_id     := (v_linea->>'producto_id')::uuid;
    v_cantidad        := coalesce((v_linea->>'cantidad')::integer, 0);
    v_precio_unitario := round(coalesce((v_linea->>'precio_unitario')::numeric, 0));
    v_valor           := round(coalesce((v_linea->>'valor')::numeric, 0));
    v_barbero_nombre  := nullif(trim(coalesce(v_linea->>'barbero_nombre', '')), '');

    if v_cantidad <= 0 then
      raise exception 'La cantidad de un producto tiene que ser mayor que cero';
    end if;
    if v_valor < 0 then
      raise exception 'El valor de un producto no puede ser negativo';
    end if;

    select nombre into v_prod_nombre from inventario
      where id = v_producto_id and barberia_id = v_barberia;
    if not found then
      raise exception 'Producto no encontrado en este negocio';
    end if;

    if v_barbero_nombre is null then
      raise exception 'Falta elegir el profesional que vendió %', v_prod_nombre;
    end if;
    select comision_producto_pct into v_comision_pct from barberos
      where barberia_id = v_barberia and nombre = v_barbero_nombre;
    if not found then
      raise exception 'El profesional % no existe en este negocio', v_barbero_nombre;
    end if;
    v_comision_pct := coalesce(v_comision_pct, 0);

    update inventario set stock = stock - v_cantidad
      where id = v_producto_id and barberia_id = v_barberia and stock >= v_cantidad;
    if not found then
      raise exception 'Stock insuficiente de %', v_prod_nombre;
    end if;

    insert into movimientos_stock (barberia_id, producto_id, tipo, cantidad, motivo, responsable, fecha)
    values (v_barberia, v_producto_id, 'salida', v_cantidad, 'Venta', v_barbero_nombre, v_fecha);

    if v_modo_comision = 'neto_iva' then
      v_base := v_valor - (v_valor * coalesce(v_iva_pct, 19) / (100 + coalesce(v_iva_pct, 19)));
    else
      v_base := v_valor;
    end if;
    v_comision_monto := round(v_base * v_comision_pct / 100);

    insert into cobro_productos (
      cobro_id, barberia_id, producto_id, barbero_nombre, cantidad,
      precio_unitario, descuento_monto, valor, comision_monto, fecha, metodo_pago
    ) values (
      v_cobro_id, v_barberia, v_producto_id, v_barbero_nombre, v_cantidad,
      v_precio_unitario, round(coalesce((v_linea->>'descuento_monto')::numeric, 0)),
      v_valor, v_comision_monto, v_fecha, v_metodo
    );

    v_suma := v_suma + v_valor;
  end loop;

  if round(p_total_declarado) <> round(v_suma) then
    raise exception 'El total no cuadra con las líneas (% vs %)',
      round(p_total_declarado), round(v_suma);
  end if;

  return v_cobro_id;
end;
$function$;

create or replace function public.mi_agenda_procesar_pago(p_reserva_id uuid, p_metodo_pago text, p_gift_codigo text default null::text)
 returns uuid
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
declare
  v_barbero_id uuid := auth_barbero_id();
  v_nombre text;
  v_puede boolean;
  v_barberia uuid := auth_barberia_id();
  v_reserva reservas%rowtype;
  v_cliente_id uuid;
  v_precio numeric;
  v_comision_pct numeric;
  v_modo_comision text;
  v_iva_pct numeric;
  v_base numeric;
  v_comision_monto numeric;
  v_visita_id uuid;
  v_metodo text := p_metodo_pago;
  v_gift_servicio text;
begin
  if v_barbero_id is null then
    raise exception 'No autorizado';
  end if;

  select nombre, puede_procesar_pagos, comision_pct
    into v_nombre, v_puede, v_comision_pct
    from barberos where barberos.id = v_barbero_id;

  if not coalesce(v_puede, false) then
    raise exception 'No tenés permiso para procesar pagos. Pedile al dueño que lo active en Config → Equipo.';
  end if;

  select * into v_reserva from reservas
    where id = p_reserva_id and barberia_id = v_barberia and barbero_nombre = v_nombre;
  if not found then
    raise exception 'Reserva no encontrada';
  end if;
  if v_reserva.procesado then
    raise exception 'Esta reserva ya fue procesada';
  end if;

  if coalesce(btrim(p_gift_codigo), '') <> '' then
    v_gift_servicio := gift_card_canjear_interno(v_barberia, p_gift_codigo, null);
    if lower(btrim(coalesce(v_gift_servicio, ''))) is distinct from lower(btrim(coalesce(v_reserva.servicio, ''))) then
      raise exception 'Esta gift card es para "%" y la cita es de "%"', v_gift_servicio, coalesce(v_reserva.servicio, 'sin servicio');
    end if;
    v_metodo := 'Gift card';
  end if;

  select c.id into v_cliente_id from clientes c
    where c.barberia_id = v_barberia and c.whatsapp = v_reserva.whatsapp_cliente;
  if v_cliente_id is null then
    insert into clientes (barberia_id, nombre, whatsapp, email, cumpleanos, canal, fecha_registro)
    values (v_barberia, v_reserva.nombre_cliente, v_reserva.whatsapp_cliente, email_para_ficha(v_reserva.email_cliente), v_reserva.cumpleanos_cliente, 'Reserva Web', v_reserva.fecha)
    returning id into v_cliente_id;
  else
    update clientes
       set email = email_para_ficha(v_reserva.email_cliente)
     where id = v_cliente_id
       and barberia_id = v_barberia
       and coalesce(btrim(email), '') = ''
       and email_para_ficha(v_reserva.email_cliente) is not null;
  end if;

  select precio into v_precio from servicios where barberia_id = v_barberia and nombre = v_reserva.servicio;
  v_precio := coalesce(v_precio, 0);
  v_comision_pct := coalesce(v_comision_pct, 50);

  select modo_comision, iva_pct into v_modo_comision, v_iva_pct from barberias where id = v_barberia;
  if v_modo_comision = 'neto_iva' then
    v_base := v_precio - (v_precio * coalesce(v_iva_pct, 19) / (100 + coalesce(v_iva_pct, 19)));
  else
    v_base := v_precio;
  end if;
  v_comision_monto := round(v_base * v_comision_pct / 100);

  insert into visitas (
    barberia_id, cliente_id, barbero_nombre, servicio, valor, fecha, hora,
    fuente, estado, comision_monto, metodo_pago, abono_previo
  ) values (
    v_barberia, v_cliente_id, v_nombre, v_reserva.servicio, v_precio, v_reserva.fecha, v_reserva.hora,
    'Reserva', 'Atendida', v_comision_monto, v_metodo,
    case when v_reserva.abono_estado = 'Confirmado'
         then least(coalesce(v_reserva.abono_monto, 0), v_precio) else 0 end
  ) returning id into v_visita_id;

  update reservas set procesado = true, estado = 'Atendida' where id = p_reserva_id;

  return v_visita_id;
end;
$function$;

-- 11. Coherencia: si alguien cambia el estado a mano (agenda, edición, Mi Agenda)
-- de una reserva que esperaba abono, el abono queda acorde y la hora no se
-- libera por error. La vista solo ignora holds de reservas que siguen en
-- 'Pendiente de abono'.
create or replace view public.reservas_disponibilidad as
 select id, barberia_id, fecha, hora, barbero_nombre, procesado,
    coalesce(( select s.duracion_min
           from servicios s
          where s.barberia_id = r.barberia_id
            and (s.id::text = r.servicio or lower(btrim(s.nombre)) = lower(btrim(r.servicio)))
          order by (s.id::text = r.servicio) desc
         limit 1), 30) as duracion_min
   from reservas r
  where coalesce(estado, '') <> all (array['Cancelada','No asistió'])
    and not (r.estado = 'Pendiente de abono'
             and r.abono_estado in ('Pendiente','Por confirmar')
             and r.abono_vence_at is not null and r.abono_vence_at < now());

create or replace function public.trg_reserva_abono_coherente()
returns trigger language plpgsql as $$
begin
  if old.estado = 'Pendiente de abono' and new.estado is distinct from 'Pendiente de abono'
     and new.abono_estado in ('Pendiente','Por confirmar') then
    if new.estado in ('Cancelada','No asistió') then
      new.abono_estado := 'Rechazado';
    else
      new.abono_estado := 'Confirmado';
      new.abono_confirmado_at := now();
      new.abono_vence_at := null;
    end if;
  end if;
  return new;
end $$;
drop trigger if exists reservas_abono_coherente on public.reservas;
create trigger reservas_abono_coherente before update on public.reservas
  for each row execute function public.trg_reserva_abono_coherente();

-- 12. Club VIP: todos abonan (sin excepción) -------------------------------------
-- Se decidió que el abono aplica igual a clientes del Club VIP. club_exento queda
-- en la tabla sin uso para no romper nada; esta función ya no lo mira.
update public.abono_config set club_exento = false where club_exento;
create or replace function public.crear_reserva_club_abono(
  p_barberia_id uuid, p_cliente_id uuid, p_fecha date, p_hora time,
  p_servicio text default null, p_barbero_nombre text default null, p_notas text default null)
returns jsonb language plpgsql security definer set search_path to 'public' as $$
declare v_id uuid; v_monto numeric;
begin
  perform liberar_abonos_vencidos();
  v_monto := abono_monto_para(p_barberia_id, p_servicio);
  if v_monto > 0 and _abono_solapa(p_barberia_id, p_barbero_nombre, p_fecha, p_hora,
        _abono_duracion(p_barberia_id, p_servicio), null) then
    raise exception 'Esa hora acaba de ser tomada. Elige otra';
  end if;
  v_id := crear_reserva_publica_club(p_barberia_id, p_cliente_id, p_fecha, p_hora,
    p_servicio, p_barbero_nombre, p_notas);
  if v_monto > 0 then return _abono_retener(v_id, v_monto); end if;
  return jsonb_build_object('id', v_id, 'requiere_abono', false);
end $$;
