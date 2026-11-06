-- =============================================================================
-- GIFT CARDS
--
-- El negocio vende una tarjeta (física o digital) por UN servicio. La
-- plataforma solo genera y valida el CÓDIGO: el dueño lo anota en la tarjeta
-- y, cuando la persona viene, se canjea al cobrar.
--
-- Contabilidad: la venta de la tarjeta NO se registra como ingreso (el dinero
-- entró fuera de la plataforma y registrarlo dos veces inflaría los reportes).
-- El ingreso se cuenta el día del canje: la visita queda con el valor del
-- servicio y método de pago 'Gift card', así la comisión del profesional se
-- calcula como cualquier otra atención.
--
-- Canje atómico: registrar_cobro_conjunto y mi_agenda_procesar_pago reciben
-- el código opcional y lo marcan Canjeada en la MISMA transacción que crea la
-- visita (select ... for update), así un código no se puede usar dos veces
-- aunque se manden dos cobros a la vez.
-- =============================================================================

create table if not exists public.gift_cards (
  id            uuid primary key default gen_random_uuid(),
  barberia_id   uuid not null references public.barberias(id) on delete cascade,
  codigo        text not null,
  servicio      text not null,
  valor         numeric not null default 0 check (valor >= 0),
  estado        text not null default 'Activa' check (estado in ('Activa','Canjeada','Anulada')),
  para_nombre   text,
  de_nombre     text,
  notas         text,
  vence         date,
  created_at    timestamptz not null default now(),
  canjeada_at   timestamptz,
  cobro_id      uuid,
  unique (barberia_id, codigo)
);

alter table public.gift_cards enable row level security;

drop policy if exists gift_cards_own on public.gift_cards;
create policy gift_cards_own on public.gift_cards
  for all
  using (barberia_id = auth_barberia_id() and auth_rol() = 'dueno')
  with check (barberia_id = auth_barberia_id() and auth_rol() = 'dueno');

-- Código legible: GC-XXXX-XXXX sin 0/O/1/I para que no se confunda al dictarlo.
create or replace function public.gift_card_codigo_nuevo()
returns text
language plpgsql
volatile
set search_path to 'public'
as $$
declare
  v_alfabeto constant text := 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'; -- 32 caracteres
  v_bytes bytea := decode(replace(gen_random_uuid()::text || gen_random_uuid()::text, '-', ''), 'hex');
  v_out text := '';
  i int;
begin
  for i in 0..7 loop
    v_out := v_out || substr(v_alfabeto, (get_byte(v_bytes, i) % 32) + 1, 1);
    if i = 3 then v_out := v_out || '-'; end if;
  end loop;
  return 'GC-' || v_out;
end;
$$;

create or replace function public.crear_gift_card(
  p_servicio text,
  p_para_nombre text default null,
  p_de_nombre text default null,
  p_notas text default null,
  p_vence date default null
) returns public.gift_cards
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  v_barberia uuid := auth_barberia_id();
  v_precio numeric;
  v_fila public.gift_cards;
  v_intento int := 0;
begin
  if v_barberia is null or auth_rol() <> 'dueno' then
    raise exception 'No autorizado';
  end if;
  if coalesce(btrim(p_servicio), '') = '' then
    raise exception 'Falta elegir el servicio';
  end if;
  select precio into v_precio from servicios
    where barberia_id = v_barberia and nombre = p_servicio limit 1;
  if not found then
    raise exception 'El servicio "%" no existe en este negocio', p_servicio;
  end if;

  loop
    v_intento := v_intento + 1;
    begin
      insert into gift_cards (barberia_id, codigo, servicio, valor, para_nombre, de_nombre, notas, vence)
      values (v_barberia, gift_card_codigo_nuevo(), p_servicio, coalesce(v_precio, 0),
              nullif(btrim(coalesce(p_para_nombre, '')), ''),
              nullif(btrim(coalesce(p_de_nombre, '')), ''),
              nullif(btrim(coalesce(p_notas, '')), ''),
              p_vence)
      returning * into v_fila;
      return v_fila;
    exception when unique_violation then
      if v_intento >= 8 then raise exception 'No se pudo generar un código único, intenta de nuevo'; end if;
    end;
  end loop;
end;
$$;

-- Valida y marca una gift card como canjeada. Devuelve el servicio que cubre.
-- Se llama SOLO desde las dos RPC de cobro (misma transacción).
create or replace function public.gift_card_canjear_interno(
  p_barberia uuid,
  p_codigo text,
  p_cobro_id uuid
) returns text
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  v_gc public.gift_cards;
  v_hoy date := (now() at time zone 'America/Santiago')::date;
begin
  select * into v_gc from gift_cards
    where barberia_id = p_barberia and codigo = upper(btrim(p_codigo))
    for update;
  if not found then
    raise exception 'Gift card % no existe en este negocio', p_codigo;
  end if;
  if v_gc.estado = 'Canjeada' then
    raise exception 'La gift card % ya fue canjeada', v_gc.codigo;
  end if;
  if v_gc.estado = 'Anulada' then
    raise exception 'La gift card % está anulada', v_gc.codigo;
  end if;
  if v_gc.vence is not null and v_gc.vence < v_hoy then
    raise exception 'La gift card % venció el %', v_gc.codigo, v_gc.vence;
  end if;
  update gift_cards
     set estado = 'Canjeada', canjeada_at = now(), cobro_id = p_cobro_id
   where id = v_gc.id;
  return v_gc.servicio;
end;
$$;
revoke all on function public.gift_card_canjear_interno(uuid, text, uuid) from public, anon, authenticated;

-- ── registrar_cobro_conjunto con código opcional ────────────────────────────
-- Se reemplaza la firma vieja (3 argumentos) por una con 4 y default null, así
-- los llamados existentes siguen funcionando sin cambios.
drop function if exists public.registrar_cobro_conjunto(jsonb, text, numeric);

create or replace function public.registrar_cobro_conjunto(
  p_lineas jsonb,
  p_metodo_pago text,
  p_total_declarado numeric,
  p_gift_codigo text default null
) returns uuid
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
  if v_barberia is null or auth_rol() <> 'dueno' then
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
      precio_lista, descuento_pct, descuento_monto, propina, propina_pct
    ) values (
      v_barberia, v_cliente_id, coalesce(v_reserva.barbero_nombre, ''),
      coalesce(v_reserva.servicio, ''), v_valor, v_reserva.fecha, v_reserva.hora,
      'Reserva', 'Atendida', v_comision_monto, v_metodo, v_cobro_id,
      nullif((v_linea->>'precio_lista')::numeric, 0),
      (v_linea->>'descuento_pct')::numeric,
      (v_linea->>'descuento_monto')::numeric,
      v_propina,
      (v_linea->>'propina_pct')::numeric
    );

    update reservas set procesado = true, estado = 'Atendida' where id = v_reserva.id;
  end loop;

  -- Una gift card cubre un servicio: si el cobro no incluye ese servicio, no
  -- se canjea (se deshace todo, incluida la marca de Canjeada).
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
      precio_unitario, descuento_monto, valor, comision_monto, fecha
    ) values (
      v_cobro_id, v_barberia, v_producto_id, v_barbero_nombre, v_cantidad,
      v_precio_unitario, round(coalesce((v_linea->>'descuento_monto')::numeric, 0)),
      v_valor, v_comision_monto, v_fecha
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

-- ── mi_agenda_procesar_pago con código opcional ─────────────────────────────
drop function if exists public.mi_agenda_procesar_pago(uuid, text);

create or replace function public.mi_agenda_procesar_pago(
  p_reserva_id uuid,
  p_metodo_pago text,
  p_gift_codigo text default null
) returns uuid
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
    fuente, estado, comision_monto, metodo_pago
  ) values (
    v_barberia, v_cliente_id, v_nombre, v_reserva.servicio, v_precio, v_reserva.fecha, v_reserva.hora,
    'Reserva', 'Atendida', v_comision_monto, v_metodo
  ) returning id into v_visita_id;

  update reservas set procesado = true, estado = 'Atendida' where id = p_reserva_id;

  return v_visita_id;
end;
$function$;

-- ── mi_agenda_citas: devuelve también el origen de la reserva ───────────────
drop function if exists public.mi_agenda_citas(date);

create or replace function public.mi_agenda_citas(p_fecha date)
returns table(id uuid, tipo text, fecha date, hora time without time zone, servicio text, estado text,
              procesado boolean, nombre_cliente text, whatsapp_cliente text, valor numeric,
              comision_monto numeric, notas text, cliente_notas text, fuente text)
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_barbero_id uuid := auth_barbero_id();
  v_nombre text;
  v_barberia uuid := auth_barberia_id();
begin
  if v_barbero_id is null then
    return;
  end if;
  select nombre into v_nombre from barberos where barberos.id = v_barbero_id;

  return query
  select r.id, 'reserva'::text, r.fecha, r.hora, r.servicio, r.estado, r.procesado,
         r.nombre_cliente, r.whatsapp_cliente, null::numeric, null::numeric, r.notas,
         (select case when count(*) = 1 then min(c.notas) end
            from clientes c
           where c.barberia_id = r.barberia_id
             and coalesce(r.whatsapp_norm, '') <> ''
             and c.whatsapp_norm = r.whatsapp_norm
             and lower(split_part(btrim(c.nombre), ' ', 1))
                 = lower(split_part(btrim(r.nombre_cliente), ' ', 1))
             and coalesce(btrim(c.notas), '') <> ''),
         r.fuente
  from reservas r
  where r.barberia_id = v_barberia and r.barbero_nombre = v_nombre
    and r.fecha = p_fecha and r.oculto_profesional = false
    and r.procesado = false
  union all
  select v.id, 'visita'::text, v.fecha, v.hora, v.servicio, v.estado, true,
         c.nombre, c.whatsapp, v.valor, v.comision_monto, v.notas,
         c.notas, null::text
  from visitas v
  left join clientes c on c.id = v.cliente_id
  where v.barberia_id = v_barberia and v.barbero_nombre = v_nombre
    and v.fecha = p_fecha and v.oculto_profesional = false
  order by 4;
end;
$function$;
