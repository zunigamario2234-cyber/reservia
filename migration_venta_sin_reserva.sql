-- Arregla la fecha de un cobro SIN reservas, antes de habilitar la venta
-- suelta de productos en la UI.
--
-- POR QUÉ AHORA
-- La rama `v_fecha is null` de registrar_cobro_conjunto() NUNCA se ejecutó:
-- todos los cobros hechos hasta hoy —y los siete pasos con que se verificó
-- migration_cobro_productos.sql— incluyeron al menos una reserva, que fijaba
-- la fecha. Es código que existe desde f418dc9 y no corrió ni una vez.
--
-- La venta de producto sin reserva es justo lo que la despierta, así que se
-- corrige ANTES de darle una entrada en la pantalla. Hay que tratarla como
-- código nuevo y no como algo ya validado.
--
-- QUÉ CAMBIA — EXACTAMENTE UNA LÍNEA
--   antes:  v_fecha := current_date;
--   ahora:  v_fecha := (now() at time zone 'America/Santiago')::date;
--
-- current_date es la fecha del SERVIDOR, que corre en UTC. A las 21:00 hora
-- chilena ya son las 01:00 UTC del día siguiente: una venta nocturna se
-- registraba con fecha de mañana, y una del día 30 caía en el mes siguiente,
-- descuadrando el IVA de los dos meses. Es el mismo bug de las noches que ya
-- se corrigió en el navegador (ahoraEnChile) y en la RPC del club.
--
-- ESTA ES AHORA LA DEFINICIÓN VIGENTE de registrar_cobro_conjunto(). El resto
-- del cuerpo es IDÉNTICO al de migration_cobro_productos.sql: se generó
-- extrayéndolo de ese archivo, no transcribiéndolo, para que no haya
-- divergencias por un error de copia.
--
-- ⚠ CÓMO SE CORRE
-- Define una función con dollar-quoting, así que va SIN begin;/commit; — esa
-- combinación el SQL Editor de Supabase la falla en silencio devolviendo
-- éxito. Correr completo, de una, y verificar con los pasos del final.


create or replace function registrar_cobro_conjunto(
  p_lineas jsonb,
  p_metodo_pago text,
  p_total_declarado numeric
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
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
      insert into clientes (barberia_id, nombre, whatsapp, cumpleanos, canal, fecha_registro)
      values (v_barberia, v_reserva.nombre_cliente, v_reserva.whatsapp_cliente,
              v_reserva.cumpleanos_cliente, 'Reserva Web', v_reserva.fecha)
      returning id into v_cliente_id;
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
$$;


revoke all on function registrar_cobro_conjunto(jsonb,text,numeric) from public;
grant execute on function registrar_cobro_conjunto(jsonb,text,numeric) to authenticated;


-- =============================================================================
-- PASO 1 — QUE EL CUERPO HAYA CAMBIADO DE VERDAD
-- El SQL Editor puede devolver éxito sin aplicar nada.
--
-- select proname,
--        pg_get_functiondef(oid) like '%America/Santiago%'      as usa_hora_de_chile,
--        pg_get_functiondef(oid) like '%v_fecha := current_date%' as quedo_el_viejo
-- from pg_proc where proname = 'registrar_cobro_conjunto';
--
-- usa_hora_de_chile = true y quedo_el_viejo = FALSE. Y tiene que haber UNA
-- sola fila: si aparecen dos, se creó una sobrecarga en vez de reemplazar.
--
-- =============================================================================
-- PASO 2 — QUE UNA VENTA SIN RESERVA GUARDE LA FECHA DE HOY (con rollback)
-- Esta es la rama que nunca había corrido. Reemplazar el producto y el
-- profesional por unos reales.
--
-- begin;
--   select set_config('request.jwt.claims',
--                     json_build_object('sub','<auth_user_id-del-dueño>')::text, true);
--
--   select registrar_cobro_conjunto(
--     '[{"tipo":"producto","producto_id":"<id-producto>","cantidad":1,
--        "precio_unitario":1000,"valor":1000,"barbero_nombre":"<profesional>"}]'::jsonb,
--     'Efectivo', 1000);
--
--   select cp.fecha                                     as fecha_guardada,
--          (now() at time zone 'America/Santiago')::date as hoy_en_chile,
--          current_date                                  as hoy_del_servidor,
--          cp.fecha = (now() at time zone 'America/Santiago')::date as coincide
--   from cobro_productos cp
--   order by cp.created_at desc limit 1;
-- rollback;
--
-- `coincide` tiene que ser true.
--
-- ⚠ DE DÍA ESTE PASO NO PRUEBA NADA. hoy_en_chile y hoy_del_servidor dan lo
-- MISMO mientras UTC no haya cambiado de día, así que pasa igual con el bug
-- puesto. Para que distinga algo hay que correrlo DESPUÉS DE LAS 21:00 hora de
-- Chile: ahí las dos columnas difieren y se ve cuál usó la función. Si se
-- corre de día, anotarlo como NO VERIFICADO en vez de darlo por bueno.
--
-- =============================================================================
-- PASO 3 — QUE LOS COBROS CON RESERVA SIGAN IGUAL
-- La fecha de un cobro CON reservas sale de la reserva, no de esta rama: no
-- debería cambiar nada. Con una reserva real sin cobrar:
--
-- begin;
--   select set_config('request.jwt.claims',
--                     json_build_object('sub','<auth_user_id-del-dueño>')::text, true);
--   select registrar_cobro_conjunto(
--     '[{"tipo":"reserva","reserva_id":"<id-reserva>","valor":10000,"propina":0}]'::jsonb,
--     'Efectivo', 10000);
--   select v.fecha as fecha_visita,
--          (select fecha from reservas where id = '<id-reserva>') as fecha_reserva,
--          v.fecha = (select fecha from reservas where id = '<id-reserva>') as coincide,
--          (now() at time zone 'America/Santiago')::date as hoy_chile
--   from visitas v
--   order by v.created_at desc
--   limit 1;
-- rollback;
--
-- UNA sola fila, la recién creada, y coincide = true.
--
-- ⚠ LA PRIMERA VERSIÓN DE ESTE PASO ESTABA MAL ESCRITA y devolvía 59 filas de
-- ruido: hacía `join reservas r on r.id = '<id>'`, que no relaciona la visita
-- con la reserva sino que multiplica por una fila fija, y el
-- `where v.cobro_id is not null` traía TODO el histórico. Todas esas filas
-- comparaban visitas ajenas contra la fecha de una reserva que no era la suya.
-- Es el mismo error que el PASO 6 de migration_cobro_productos.sql ya había
-- tenido: no acotar a la transacción. Acá se resuelve con
-- `order by created_at desc limit 1`, que dentro de la transacción es
-- exactamente la visita recién creada.
--
-- ⚠ Y CON UNA RESERVA DE HOY ESTE PASO NO DISTINGUE NADA: la fecha de la
-- reserva y la de hoy coinciden, así que pasaría igual aunque la función
-- usara la rama equivocada. Para que pruebe algo, usar una reserva de una
-- fecha DISTINTA de hoy — ahí `fecha_visita` tiene que seguir a
-- `fecha_reserva` y no a `hoy_chile`.
