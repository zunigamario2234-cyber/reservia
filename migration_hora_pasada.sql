-- Rechaza en la base las reservas públicas para una fecha/hora que ya pasó.
--
-- POR QUÉ
-- La grilla pública nunca comparó contra la hora actual: a las 22:00 del martes
-- seguía ofreciendo las 10:00 de ese mismo martes, y un cliente podía reservar
-- una hora ya pasada. Lo único que miraba el tiempo era el calendario, y solo a
-- nivel de DÍA, así que el día de hoy quedaba entero disponible.
--
-- El frontend ya lo cierra (reservar.html y club.html filtran los slots pasados
-- y exigen 30 minutos de anticipación), pero eso vive en el navegador y depende
-- del reloj del dispositivo del cliente. Dos agujeros que el navegador no puede
-- tapar solo:
--   1. Un celular con la hora mal puesta ve una grilla mal filtrada.
--   2. La anon key es pública por diseño: cualquiera puede llamar la RPC
--      directo con la fecha que quiera, igual que con 'Por asignar'.
-- Por eso la hora la decide el servidor, que es el único reloj confiable.
--
-- POR QUÉ 'America/Santiago' Y NO now() A SECAS
-- now() devuelve timestamptz y la base corre en UTC: comparar contra
-- (p_fecha + p_hora), que es hora de pared chilena, correría el corte 3 o 4
-- horas. `at time zone 'America/Santiago'` lo baja a la hora de pared de Chile,
-- y resuelve solo el cambio de horario — hardcodear -04/-03 se rompe dos veces
-- al año.
--
-- POR QUÉ NO SE APLICA EL BUFFER DE 30 MINUTOS ACÁ
-- El frontend no ofrece nada que empiece dentro de los próximos 30 minutos, y
-- esa es una decisión de negocio que puede cambiar por local. Acá se valida solo
-- la integridad —que la hora no esté en el pasado— para no rechazar a un cliente
-- que eligió un horario válido y se demoró en llenar el formulario. Si el
-- buffer se hiciera configurable por negocio, este es el lugar donde volver a
-- mirarlo.
--
-- LA TERCERA PUERTA NO SE TOCA, Y ES A PROPÓSITO
-- mi_agenda_crear_reserva queda como está. Un profesional SÍ necesita poder
-- registrar una atención que ya ocurrió (un cliente que llegó sin reserva, una
-- cita que se anotó después). Lo mismo vale para la creación manual desde
-- app.html. La regla es: las puertas públicas no aceptan pasado, las internas sí.
--
-- QUÉ NO HACE ESTA MIGRACIÓN
-- No valida `activo` (deuda pendiente, va en su propia migración) ni valida
-- solapamiento por duración del servicio. Esto último es el otro bug abierto:
-- hoy la ocupación se compara por hora exacta, así que un corte de 60 min a las
-- 11:30 no bloquea las 12:00. Se resuelve aparte.
--
-- Los mensajes de las excepciones llegan al navegador del cliente: reservar.html
-- los muestra tal cual en el cartel de error. Por eso están escritos para que
-- los lea una persona, no para depurar.
--
-- ⚠ SIN begin;/commit; A PROPÓSITO — NO LOS AGREGUES
-- Este archivo define FUNCIONES. El SQL Editor de Supabase trocea el script por
-- `;` y los puntos y coma de adentro del cuerpo $function$ rompen el troceo:
-- devuelve éxito y deja el cuerpo viejo, sin dar ningún error. Ya pasó con
-- migration_profesional_obligatorio.sql. Ver la verificación del final.

create or replace function public.crear_reserva_publica(
  p_barberia_id uuid,
  p_nombre_cliente text,
  p_whatsapp_cliente text,
  p_fecha date,
  p_hora time without time zone,
  p_email_cliente text default null::text,
  p_cumpleanos_cliente date default null::date,
  p_servicio text default null::text,
  p_barbero_nombre text default null::text,
  p_notas text default null::text
)
returns uuid
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_id uuid;
  v_barbero_nombre text;
begin
  -- La hora la decide el reloj del servidor, no el del cliente.
  if (p_fecha + p_hora) < (now() at time zone 'America/Santiago') then
    raise exception 'Esa hora ya pasó. Vuelve a cargar la página y elige otra';
  end if;

  if p_barbero_nombre is null
     or btrim(p_barbero_nombre) = ''
     or lower(btrim(p_barbero_nombre)) = 'por asignar' then
    raise exception 'Tienes que elegir un profesional para reservar';
  end if;

  -- Match normalizado, mismo criterio que el resolver de correos: la
  -- capitalización de este sistema no es confiable. Se queda con el nombre de
  -- la ficha, no con el que llegó del navegador.
  select nombre into v_barbero_nombre
  from barberos
  where barberia_id = p_barberia_id
    and lower(btrim(nombre)) = lower(btrim(p_barbero_nombre))
  limit 1;

  if v_barbero_nombre is null then
    raise exception 'El profesional elegido ya no está disponible. Vuelve a cargar la página';
  end if;

  insert into reservas (
    barberia_id, nombre_cliente, whatsapp_cliente, email_cliente,
    cumpleanos_cliente, fecha, hora, servicio, barbero_nombre,
    estado, procesado, notas, fuente
  ) values (
    p_barberia_id, p_nombre_cliente, p_whatsapp_cliente, p_email_cliente,
    p_cumpleanos_cliente, p_fecha, p_hora, p_servicio,
    v_barbero_nombre,
    'Confirmada', false, p_notas, 'Web propia'
  ) returning id into v_id;
  return v_id;
end;
$function$;

create or replace function public.crear_reserva_publica_club(
  p_barberia_id uuid,
  p_cliente_id uuid,
  p_fecha date,
  p_hora time without time zone,
  p_servicio text default null::text,
  p_barbero_nombre text default null::text,
  p_notas text default null::text
)
returns uuid
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_id uuid;
  v_cliente clientes%rowtype;
  v_barbero_nombre text;
begin
  -- Mismo criterio que crear_reserva_publica: la hora la decide el servidor.
  if (p_fecha + p_hora) < (now() at time zone 'America/Santiago') then
    raise exception 'Esa hora ya pasó. Vuelve a cargar la página y elige otra';
  end if;

  select * into v_cliente
  from clientes
  where id = p_cliente_id and barberia_id = p_barberia_id;
  if not found then
    raise exception 'Cliente no encontrado para este negocio';
  end if;

  if p_barbero_nombre is null
     or btrim(p_barbero_nombre) = ''
     or lower(btrim(p_barbero_nombre)) = 'por asignar' then
    raise exception 'Tienes que elegir un profesional para reservar';
  end if;

  select nombre into v_barbero_nombre
  from barberos
  where barberia_id = p_barberia_id
    and lower(btrim(nombre)) = lower(btrim(p_barbero_nombre))
  limit 1;

  if v_barbero_nombre is null then
    raise exception 'El profesional elegido ya no está disponible. Vuelve a cargar la página';
  end if;

  insert into reservas (
    barberia_id, nombre_cliente, whatsapp_cliente, email_cliente,
    cumpleanos_cliente, fecha, hora, servicio, barbero_nombre,
    estado, procesado, notas, fuente
  ) values (
    p_barberia_id,
    trim(v_cliente.nombre || ' ' || coalesce(v_cliente.apellido, '')),
    v_cliente.whatsapp, v_cliente.email, v_cliente.cumpleanos,
    p_fecha, p_hora, p_servicio,
    v_barbero_nombre,
    'Confirmada', false, p_notas, 'Club VIP'
  ) returning id into v_id;
  return v_id;
end;
$function$;


-- =============================================================================
-- PASO 1 — VERIFICAR QUE EL CUERPO CAMBIÓ DE VERDAD
-- Esto va PRIMERO. Si el editor no aplicó nada (la trampa del troceo), la
-- prueba de abajo insertaría una reserva de verdad en vez de fallar.
-- Las dos filas tienen que decir true.
--
-- select proname,
--        length(prosrc) as largo_cuerpo,
--        prosrc like '%America/Santiago%' as tiene_la_validacion
-- from pg_proc
-- where proname in ('crear_reserva_publica','crear_reserva_publica_club');
--
-- =============================================================================
-- PASO 2 — PROBAR EL RECHAZO (con rollback obligatorio)
--
-- begin;
-- select public.crear_reserva_publica(
--   '<id-de-tu-barberia>'::uuid, 'Prueba hora pasada', '+56900000000',
--   current_date - 1, '10:00'::time, null, null, null, '<nombre-de-un-profesional>', null
-- );
-- rollback;
--
-- Tiene que fallar con P0001 'Esa hora ya pasó...'.
--
-- =============================================================================
-- PASO 3 — PROBAR QUE UNA RESERVA VÁLIDA SIGUE PASANDO
-- Sin esto, una validación demasiado estricta rompe las reservas reales y no
-- se nota hasta que un cliente no puede reservar.
--
-- begin;
-- select public.crear_reserva_publica(
--   '<id-de-tu-barberia>'::uuid, 'Prueba hora futura', '+56900000000',
--   current_date + 1, '10:00'::time, null, null, null, '<nombre-de-un-profesional>', null
-- );
-- rollback;
--
-- Tiene que devolver un uuid.
