-- Que el correo del cliente llegue a su ficha, en las tres puertas que hoy lo
-- tiran.
--
-- POR QUÉ
-- reservar.html hace el correo OBLIGATORIO y lo guarda en
-- reservas.email_cliente. Pero las tres RPCs que resuelven la ficha del cliente
-- insertan sin esa columna:
--
--   · buscar_o_crear_cliente_club  — tras reservar en el link público y el club
--   · mi_agenda_procesar_pago      — el cobro del profesional
--   · registrar_cobro_conjunto     — el cobro del panel
--
-- El mismo insert de seis columnas está copiado en ocho migraciones y en
-- ninguna aparece email. Resultado: el cliente escribe su correo, queda en la
-- reserva, y su ficha figura vacía.
--
-- ⚠ Y HAY UNA SEGUNDA MITAD, menos obvia que la primera: las tres solo
-- insertan `if v_cliente_id is null`. Si la ficha YA existe sin correo, no la
-- tocan nunca. Un cliente puede reservar diez veces escribiendo su correo cada
-- vez y su ficha sigue vacía para siempre. Arreglar solo el insert dejaría
-- afuera justo a los clientes de siempre, que son los que más importan.
-- Por eso cada función lleva DOS cambios, no uno.
--
-- Esto NO recupera lo ya perdido — eso es migration_backfill_email_ficha.sql,
-- que mira hacia atrás. Las DOS tienen que correr; el orden entre ellas da
-- igual, son independientes.
--
-- ═══════════════════════════════════════════════════════════════
-- LA REGLA, Y POR QUÉ VA EN EL `WHERE` Y NO EN UN `IF`
--
-- Rellenar solo si la ficha está vacía. NUNCA sobrescribir: el correo que ya
-- está normalmente lo escribió el propio cliente en el link público, y uno
-- dictado por teléfono y mal tipeado lo borraría en silencio. Rellenar un
-- campo vacío es aditivo y no pierde nada; pisarlo sí.
--
-- Es la misma regla que decidirEmailFicha() en app.html, que ya existe para la
-- reserva manual del panel.
--
-- La condición va en el WHERE del update, no en un `if` previo. Con un `if`
-- sería leer-y-después-escribir, y entre esas dos cosas otra transacción puede
-- haber cargado el correo: lo pisaríamos justo en el caso que la regla
-- pretende proteger. En el WHERE, la comprobación y la escritura son el mismo
-- statement.
--
-- ⚠ Esta migración DEFINE FUNCIONES, así que va SIN begin;/commit; — con
-- dollar-quoting adentro, el SQL Editor de Supabase falla en silencio
-- devolviendo éxito. Correr cada bloque por separado.
-- ═══════════════════════════════════════════════════════════════


-- ═══════════════════════════════════════════════════════════════
-- (1) QUÉ CUENTA COMO CORREO USABLE — una sola definición
--
-- Sin esto, la misma condición quedaría copiada en las tres funciones más el
-- backfill. Este repo ya arrastra reglas en su cuarta y quinta copia, y cuando
-- se separan nadie se entera: cada copia sigue funcionando, solo que distinto.
--
-- Devuelve el correo limpio, o NULL si no sirve. `position('@') > 1` descarta
-- lo obvio —vacío, sin arroba, o empezando con arroba— sin pretender validar
-- de verdad: reservar.html solo pide includes('@'), así que algo así ya pudo
-- entrar. Es el mismo filtro que usa el backfill.
--
-- No es security definer y no toca ninguna tabla, así que no entra en la deuda
-- de search_path de las funciones que sí sostienen el aislamiento multi-tenant.
-- ═══════════════════════════════════════════════════════════════

create or replace function email_para_ficha(p_email text)
returns text
language sql
immutable
as $$
  select case when position('@' in coalesce(btrim(p_email), '')) > 1
              then btrim(p_email) end;
$$;

-- PostgREST publica como endpoint toda función del esquema public. Esta no
-- tiene nada que ofrecer a nadie de afuera —es texto puro, no lee datos— así
-- que no se publica.
--
-- ⚠ HACEN FALTA LAS DOS LÍNEAS, y la segunda no es redundante. Supabase trae
-- default privileges en el esquema public que otorgan EXECUTE sobre toda
-- función nueva a anon, authenticated y service_role. Eso es un grant
-- EXPLÍCITO A CADA ROL, no heredado de PUBLIC: quitarle el permiso a PUBLIC
-- deja el de anon intacto, y con que quede uno la función sigue publicada.
--
-- Verificado el 2026-09-11: con solo el revoke a public,
-- has_function_privilege('anon', ...) seguía dando true. Para confirmarlo en
-- otra base, mirar `proacl` en pg_proc — un `anon=X/postgres` es el grant
-- explícito, y un `=X/postgres` sin nombre delante es PUBLIC.
--
-- Ninguno de los dos revokes rompe las tres RPCs: son security definer y
-- corren como su dueño, que conserva el execute.
revoke execute on function email_para_ficha(text) from public;
revoke execute on function email_para_ficha(text) from anon, authenticated;


-- ═══════════════════════════════════════════════════════════════
-- (2) buscar_o_crear_cliente_club
--
-- La puerta de más volumen: corre cada vez que alguien reserva por el link
-- público o desde su Club VIP.
--
-- Generada editando el texto REAL aplicado en la base (pg_get_functiondef), no
-- el del repo — que para estas funciones puede estar atrasado. El diff contra
-- el original es de exactamente dos bloques, los dos de correo.
-- ═══════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.buscar_o_crear_cliente_club(p_barberia_id uuid, p_reserva_id uuid)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_cliente_id uuid;
  v_reserva reservas%rowtype;
begin
  select * into v_reserva
  from reservas
  where id = p_reserva_id and barberia_id = p_barberia_id;
  if not found then
    raise exception 'Reserva no encontrada para este negocio';
  end if;
  select id into v_cliente_id
  from clientes
  where barberia_id = p_barberia_id and whatsapp = v_reserva.whatsapp_cliente
  limit 1;
  if v_cliente_id is not null then
    update clientes
       set email = email_para_ficha(v_reserva.email_cliente)
     where id = v_cliente_id
       and barberia_id = p_barberia_id
       and coalesce(btrim(email), '') = ''
       and email_para_ficha(v_reserva.email_cliente) is not null;
    return v_cliente_id;
  end if;
  insert into clientes (barberia_id, nombre, whatsapp, email, cumpleanos, canal, fecha_registro)
  values (
    p_barberia_id, v_reserva.nombre_cliente, v_reserva.whatsapp_cliente,
    email_para_ficha(v_reserva.email_cliente),
    v_reserva.cumpleanos_cliente, 'Reserva Web', v_reserva.fecha
  )
  returning id into v_cliente_id;
  return v_cliente_id;
end;
$function$;


-- ═══════════════════════════════════════════════════════════════
-- (3) mi_agenda_procesar_pago
--
-- El cobro del profesional. Acá la estructura era distinta —un
-- `if v_cliente_id is null then insert ... end if;`— así que el relleno va en
-- un `else`, no antes del return. El efecto es el mismo.
--
-- Todo el resto de la función queda EXACTAMENTE como estaba: el permiso
-- puede_procesar_pagos, el cálculo de comisión con modo_comision/iva_pct, el
-- insert en visitas y el update de la reserva. El diff son solo los dos
-- bloques de correo.
--
-- ⚠ NOTA APARTE, NO SE TOCA ACÁ: el mensaje de error de permisos está en
-- voseo ("No tenés permiso... Pedile al dueño"). Se copia tal cual a propósito
-- —cambiarlo acá lo escondería dentro de una migración de correos— y va en el
-- barrido de voseo que ya está decidido como commit propio.
-- ═══════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.mi_agenda_procesar_pago(p_reserva_id uuid, p_metodo_pago text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
    'Reserva', 'Atendida', v_comision_monto, p_metodo_pago
  ) returning id into v_visita_id;

  update reservas set procesado = true, estado = 'Atendida' where id = p_reserva_id;

  return v_visita_id;
end;
$function$;


-- ═══════════════════════════════════════════════════════════════
-- (4) registrar_cobro_conjunto
--
-- El cobro del panel: N reservas y N productos en una transacción. Es la
-- función más larga de las tres y la que más veces se redefinió (cobro
-- conjunto → productos → venta sin reserva), razón de más para editarla sobre
-- el texto APLICADO y no sobre el del repo.
--
-- El bloque del cliente vive DENTRO del loop de reservas, así que el relleno
-- corre una vez por reserva. Con dos líneas del mismo cliente, la primera
-- escribe el correo y la segunda no hace nada: la condición
-- `coalesce(btrim(email),'') = ''` ya no se cumple. Con reservas de clientes
-- distintos, cada uno recibe el suyo.
--
-- Todo lo demás queda EXACTAMENTE igual: las dos pasadas, la revalidación de
-- procesado, el mismo día, el descuento atómico de stock, la comisión de
-- productos, la fecha anclada a Chile y la red del total declarado. El diff
-- son solo los dos bloques de correo.
-- ═══════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.registrar_cobro_conjunto(p_lineas jsonb, p_metodo_pago text, p_total_declarado numeric)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
  -- Productos
  v_producto_id uuid;
  v_prod_nombre text;
  v_cantidad integer;
  v_precio_unitario numeric;
  v_barbero_nombre text;
  v_hay_reserva boolean := false;
begin
  if v_barberia is null or auth_rol() <> 'dueno' then
    raise exception 'No autorizado';
  end if;
  if p_lineas is null or jsonb_array_length(p_lineas) = 0 then
    raise exception 'El cobro no tiene ninguna línea';
  end if;

  select modo_comision, iva_pct into v_modo_comision, v_iva_pct
    from barberias where id = v_barberia;

  -- ── PASADA 1: las reservas ────────────────────────────────────────────
  -- Van primero para que v_fecha quede resuelta antes de los productos, que
  -- heredan la fecha del cobro. Si se recorriera una sola vez, un producto
  -- listado antes de la reserva se guardaría con fecha nula.
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
    -- Se revalida acá y no solo en la UI: entre que se abrió el modal y se
    -- confirmó, la reserva pudo cobrarse desde Mi Agenda. Aborta TODO.
    if v_reserva.procesado then
      raise exception 'La reserva de % ya fue cobrada', v_reserva.nombre_cliente;
    end if;

    -- Alcance del mismo día, exigido en la base y no solo en el frontend.
    if v_fecha is null then
      v_fecha := v_reserva.fecha;
    elsif v_reserva.fecha <> v_fecha then
      raise exception 'Un cobro conjunto no puede mezclar fechas distintas';
    end if;

    -- Cliente por whatsapp, mismo criterio que mi_agenda_procesar_pago.
    -- Adentro de la transacción, así que dos líneas del mismo cliente no
    -- pueden duplicar la ficha.
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

    -- La comisión va sobre lo COBRADO (ya prorrateado el descuento), nunca
    -- sobre el precio de lista, y la propina queda fuera del reparto.
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
      'Reserva', 'Atendida', v_comision_monto, p_metodo_pago, v_cobro_id,
      nullif((v_linea->>'precio_lista')::numeric, 0),
      (v_linea->>'descuento_pct')::numeric,
      (v_linea->>'descuento_monto')::numeric,
      v_propina,
      (v_linea->>'propina_pct')::numeric
    );

    update reservas set procesado = true, estado = 'Atendida' where id = v_reserva.id;
  end loop;

  -- Un cobro de solo productos es legítimo (alguien entra y compra un shampoo):
  -- ahí no hay reserva que fije la fecha y se usa la de hoy.
  if v_fecha is null then
    -- ⚠ NO current_date: esa es la fecha del SERVIDOR, que corre en UTC y va
    -- ADELANTE de Chile. A las 21:00 hora chilena ya son las 01:00 UTC del
    -- día siguiente, así que una venta nocturna quedaba registrada con fecha
    -- de mañana — y una del día 30 caía en el mes siguiente, descuadrando el
    -- IVA de los dos meses. Mismo bug de las noches que ya se corrigió en el
    -- navegador (ahoraEnChile) y en get_proximas_reservas_publico.
    v_fecha := (now() at time zone 'America/Santiago')::date;
  end if;

  -- ── PASADA 2: los productos ───────────────────────────────────────────
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

    -- El profesional es obligatorio y tiene que existir: de él sale la
    -- comisión, y adjudicarla por omisión es plata de otro mal asignada.
    if v_barbero_nombre is null then
      raise exception 'Falta elegir el profesional que vendió %', v_prod_nombre;
    end if;
    select comision_producto_pct into v_comision_pct from barberos
      where barberia_id = v_barberia and nombre = v_barbero_nombre;
    if not found then
      raise exception 'El profesional % no existe en este negocio', v_barbero_nombre;
    end if;
    v_comision_pct := coalesce(v_comision_pct, 0);

    -- Descuento de stock ATÓMICO. El update relativo (stock = stock - n) hace
    -- que Postgres bloquee la fila, así que dos cobros simultáneos del mismo
    -- producto se serializan en vez de pisarse. El `stock >= v_cantidad` en el
    -- where impide vender lo que no hay, y como no afecta filas se detecta con
    -- `not found`. El patrón viejo del navegador —leer el stock, restar en JS y
    -- escribir el absoluto— perdía unidades sin ningún error visible.
    update inventario set stock = stock - v_cantidad
      where id = v_producto_id and barberia_id = v_barberia and stock >= v_cantidad;
    if not found then
      raise exception 'Stock insuficiente de %', v_prod_nombre;
    end if;

    insert into movimientos_stock (barberia_id, producto_id, tipo, cantidad, motivo, responsable, fecha)
    values (v_barberia, v_producto_id, 'salida', v_cantidad, 'Venta', v_barbero_nombre, v_fecha);

    -- Misma base que los servicios: si el negocio calcula sobre el neto, los
    -- productos siguen el mismo criterio. Lo que cambia es el PORCENTAJE.
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

  -- La red que atrapa un prorrateo mal redondeado en JS antes de que quede
  -- guardado. Sin esto, la caja y la suma de ventas se separan de a pesos y
  -- nadie se entera hasta que no cuadra el IVA.
  if round(p_total_declarado) <> round(v_suma) then
    raise exception 'El total no cuadra con las líneas (% vs %)',
      round(p_total_declarado), round(v_suma);
  end if;

  return v_cobro_id;
end;
$function$;


-- ═══════════════════════════════════════════════════════════════
-- VERIFICACIÓN (correr DESPUÉS, cada paso por separado)
-- ═══════════════════════════════════════════════════════════════

-- PASO 1 — Las tres funciones quedaron redefinidas y siguen siendo security
-- definer con el search_path fijo. Esperado: 3 filas, las tres con
-- security_definer = true y config = {search_path=public}.
--
-- select p.proname, p.prosecdef as security_definer, p.proconfig as config
-- from pg_proc p join pg_namespace n on n.oid = p.pronamespace
-- where n.nspname = 'public'
--   and p.proname in ('buscar_o_crear_cliente_club',
--                     'mi_agenda_procesar_pago',
--                     'registrar_cobro_conjunto')
-- order by p.proname;


-- PASO 2 — Las tres mencionan el correo ahora. Esperado: 3 filas, todas con
-- veces_email >= 2 (el insert y el update).
--
-- select p.proname,
--        (length(pg_get_functiondef(p.oid))
--         - length(replace(pg_get_functiondef(p.oid), 'email_para_ficha', '')))
--        / length('email_para_ficha') as veces_email
-- from pg_proc p join pg_namespace n on n.oid = p.pronamespace
-- where n.nspname = 'public'
--   and p.proname in ('buscar_o_crear_cliente_club',
--                     'mi_agenda_procesar_pago',
--                     'registrar_cobro_conjunto')
-- order by p.proname;


-- PASO 3 — El helper decide bien. Un test que nunca falla no prueba nada, así
-- que se le dan los casos que TIENEN que devolver null.
-- Esperado: 1 fila con todo en true.
--
-- select email_para_ficha('  juan@correo.cl ') = 'juan@correo.cl'  as limpia_espacios,
--        email_para_ficha('@corto')            is null             as rechaza_arroba_inicial,
--        email_para_ficha('sinarroba')         is null             as rechaza_sin_arroba,
--        email_para_ficha('')                  is null             as rechaza_vacio,
--        email_para_ficha('   ')               is null             as rechaza_espacios,
--        email_para_ficha(null)                is null             as rechaza_nulo;


-- PASO 4 — El helper NO quedó publicado como endpoint.
-- Esperado: las dos columnas en false.
--
-- ⚠ La primera versión de este paso preguntaba solo por anon y decía
-- "esperado: false" dando por hecho que el revoke a PUBLIC alcanzaba. El
-- 2026-09-11 dio TRUE y costó una parada en seco: en Supabase, los default
-- privileges le dan EXECUTE a anon y authenticated por separado. Alcanzar a
-- PUBLIC no los toca. Por eso ahora el bloque (1) lleva los dos revokes.
--
-- select has_function_privilege('anon', 'email_para_ficha(text)', 'execute')
--          as lo_puede_llamar_anon,
--        has_function_privilege('authenticated', 'email_para_ficha(text)', 'execute')
--          as lo_puede_llamar_authenticated;


-- PASO 4b — De dónde salía el permiso, si algún día vuelve a aparecer.
-- Muestra la ACL cruda de la función y los default privileges del esquema.
-- En proacl: `anon=X/postgres` es un grant explícito a ese rol;
-- `=X/postgres` (sin nombre delante del =) es PUBLIC.
--
-- select p.proname, p.proacl
-- from pg_proc p join pg_namespace n on n.oid = p.pronamespace
-- where n.nspname = 'public' and p.proname = 'email_para_ficha';
--
-- select defaclrole::regrole as quien_lo_define,
--        defaclnamespace::regnamespace as esquema,
--        defaclacl as privilegios_por_defecto
-- from pg_default_acl
-- where defaclobjtype = 'f';


-- PASO 5 — LA PRUEBA QUE DE VERDAD IMPORTA: que NO se pise un correo cargado.
-- Envuelta en begin;/rollback;, así que no deja rastro.
--
-- Arma una ficha con correo propio y una reserva con OTRO correo, corre la
-- misma sentencia que quedó en las tres funciones, y comprueba que la ficha
-- conservó el suyo. Sin este paso, "nunca sobrescribir" es solo una intención
-- escrita en un comentario.
--
-- begin;
--   insert into clientes (barberia_id, nombre, whatsapp, email)
--   select id, 'ZZ Prueba Correo', '+56 9 0000 0001', 'elsuyo@correo.cl'
--   from barberias order by created_at limit 1;
--
--   -- La misma condición de las tres funciones, con el correo "de la reserva".
--   update clientes
--      set email = email_para_ficha('otro@correo.cl')
--    where nombre = 'ZZ Prueba Correo'
--      and coalesce(btrim(email), '') = ''
--      and email_para_ficha('otro@correo.cl') is not null;
--
--   -- Esperado: 'elsuyo@correo.cl'. Si dice 'otro@correo.cl', la regla no está.
--   select email as debe_seguir_siendo_el_suyo
--   from clientes where nombre = 'ZZ Prueba Correo';
--
--   -- Y el lado positivo: sobre una ficha VACÍA sí tiene que escribir.
--   update clientes set email = null where nombre = 'ZZ Prueba Correo';
--   update clientes
--      set email = email_para_ficha('otro@correo.cl')
--    where nombre = 'ZZ Prueba Correo'
--      and coalesce(btrim(email), '') = ''
--      and email_para_ficha('otro@correo.cl') is not null;
--
--   -- Esperado: 'otro@correo.cl'. Si sigue en null, no rellena nunca.
--   select email as debe_haberse_rellenado
--   from clientes where nombre = 'ZZ Prueba Correo';
-- rollback;
