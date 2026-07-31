-- Las reservas públicas dejan de aceptar a un profesional dado de baja.
--
-- POR QUÉ
-- Desde e191046 el dueño puede dar de baja a un profesional, y las tres
-- lecturas respetan la columna: reservar.html y club.html no lo traen
-- (.eq('activo',true)) y mi-agenda.html no lo deja entrar. Pero las dos RPC
-- públicas nunca la miraron: buscan la ficha SOLO por nombre normalizado, así
-- que un profesional dado de baja sigue siendo reservable llamando la RPC
-- directo. La anon key es pública por diseño, y esto es el mismo agujero que
-- ya se cerró con 'Por asignar' y con la hora pasada: lo que el navegador
-- esconde no está validado hasta que lo valida la base.
--
-- El caso real no es un atacante, es una pestaña vieja: el cliente cargó la
-- página cuando el profesional estaba activo, el dueño lo dio de baja, y el
-- cliente reserva media hora después con la grilla que ya tenía en pantalla.
-- Ahí no hay nada malicioso y la reserva entra igual.
--
-- POR QUÉ `activo = true` Y NO `coalesce(activo, true)`
-- barberos.activo es `boolean DEFAULT true` SIN not null, así que puede haber
-- filas en null. Tratar null como activo parece lo prudente, pero sería un
-- criterio NUEVO: los tres lugares que ya leen la columna tratan null como
-- INACTIVO. reservar.html y club.html usan .eq('activo',true), que en
-- PostgREST excluye null; app.html pinta el checkbox con `b.activo?'checked'`,
-- que deja null sin marcar. Usar coalesce acá haría que la base aceptara a
-- alguien que la página pública no ofrece y que el panel muestra como dado de
-- baja. Un solo criterio, y es este.
--
-- Antes de aplicar conviene mirar el PASO 0: si hay filas en null, esos
-- profesionales YA están invisibles en la página pública, así que esta
-- migración no les cambia nada — pero es mejor saberlo que suponerlo.
--
-- DE REGALO ARREGLA EL DESEMPATE POR NOMBRE
-- La búsqueda termina en `limit 1` sin orden. Con dos fichas del mismo nombre
-- —una activa y una dada de baja— podía quedarse con la dada de baja y
-- escribir ESE nombre en la reserva. Al filtrar por activo, el limit 1 ya solo
-- puede elegir entre fichas válidas.
--
-- QUÉ NO HACE ESTA MIGRACIÓN
-- No valida que el profesional realice el servicio elegido. reservar.html sí
-- lo filtra (por barbero_servicios.activo), así que es el mismo tipo de
-- agujero que este, pero es una validación distinta y va en su propia
-- migración: acá se agrega una condición a una consulta que ya existe, eso
-- necesitaría cruzar otra tabla y decidir qué pasa con las reservas cuyo
-- servicio viene en null.
--
-- Tampoco toca mi_agenda_crear_reserva ni la creación manual de app.html. Es
-- la misma regla de migration_hora_pasada.sql: las puertas públicas validan,
-- las internas no. Un profesional dado de baja hoy puede seguir teniendo que
-- registrar una atención de la semana pasada.
--
-- El mensaje de la excepción es el que ya existía para "no encontré la ficha",
-- y sirve igual para este caso: desde el lado del cliente, un profesional dado
-- de baja y uno que no existe son lo mismo. Se muestra tal cual en el cartel
-- de error de reservar.html, por eso está escrito para una persona.
--
-- ⚠ SIN begin;/commit; A PROPÓSITO — NO LOS AGREGUES
-- Este archivo define FUNCIONES. El SQL Editor de Supabase trocea el script
-- por `;` y los puntos y coma de adentro del cuerpo $function$ rompen el
-- troceo: devuelve éxito y deja el cuerpo viejo, sin dar ningún error. Ya pasó
-- con migration_profesional_obligatorio.sql. Ver la verificación del final.

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
  -- `activo = true` es el mismo criterio que usan reservar.html y club.html;
  -- excluye los null a propósito (ver el encabezado).
  select nombre into v_barbero_nombre
  from barberos
  where barberia_id = p_barberia_id
    and lower(btrim(nombre)) = lower(btrim(p_barbero_nombre))
    and activo = true
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

  -- Mismo filtro por activo que crear_reserva_publica.
  select nombre into v_barbero_nombre
  from barberos
  where barberia_id = p_barberia_id
    and lower(btrim(nombre)) = lower(btrim(p_barbero_nombre))
    and activo = true
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
-- PASO 0 — ANTES DE APLICAR: ¿hay fichas en null?
-- Solo para saber contra qué se está aplicando. No bloquea nada: las fichas en
-- null ya están invisibles en la página pública. Si aparece alguna que creías
-- activa, resuélvela con el toggle de app.html ANTES de seguir.
--
-- select barberia_id,
--        count(*)                                as total,
--        count(*) filter (where activo is true)  as activos,
--        count(*) filter (where activo is false) as dados_de_baja,
--        count(*) filter (where activo is null)  as en_null
-- from barberos
-- group by barberia_id
-- order by en_null desc, total desc;
--
-- =============================================================================
-- PASO 1 — VERIFICAR QUE EL CUERPO CAMBIÓ DE VERDAD
-- Esto va PRIMERO de las pruebas. Si el editor no aplicó nada (la trampa del
-- troceo), el PASO 2 insertaría una reserva de verdad en vez de fallar.
-- Las dos filas tienen que decir true en las dos columnas.
--
-- select proname,
--        prosrc like '%activo = true%'        as tiene_la_validacion_nueva,
--        prosrc like '%America/Santiago%'     as conserva_la_de_hora_pasada
-- from pg_proc
-- where proname in ('crear_reserva_publica','crear_reserva_publica_club');
--
-- =============================================================================
-- PASO 2 — PROBAR EL RECHAZO (con rollback obligatorio)
-- Da de baja un profesional de prueba, intenta reservarlo, y revierte todo.
-- El update va DENTRO de la transacción a propósito: así el profesional vuelve
-- a quedar activo solo con el rollback, aunque la prueba falle a la mitad.
--
-- begin;
--   update barberos set activo = false
--   where barberia_id = '<id-de-tu-barberia>'::uuid
--     and nombre = '<nombre-de-un-profesional>';
--
--   select public.crear_reserva_publica(
--     '<id-de-tu-barberia>'::uuid, 'Prueba dado de baja', '+56900000000',
--     current_date + 1, '10:00'::time, null, null, null,
--     '<nombre-de-un-profesional>', null
--   );
-- rollback;
--
-- Tiene que fallar con P0001 'El profesional elegido ya no está disponible...'.
-- Ojo: la fecha va en FUTURO. Con fecha pasada fallaría por la validación de
-- hora y parecería que esta anda, sin haberla ejercitado nunca.
--
-- =============================================================================
-- PASO 3 — PROBAR QUE UN PROFESIONAL ACTIVO SIGUE PASANDO
-- Sin esto, una validación demasiado estricta rompe las reservas reales y no
-- se nota hasta que un cliente no puede reservar. Es el paso que atrapa el
-- error de haber excluido los null sin querer.
--
-- begin;
-- select public.crear_reserva_publica(
--   '<id-de-tu-barberia>'::uuid, 'Prueba activo', '+56900000000',
--   current_date + 1, '10:00'::time, null, null, null,
--   '<nombre-de-un-profesional-activo>', null
-- );
-- rollback;
--
-- Tiene que devolver un uuid.
--
-- =============================================================================
-- PASO 4 — LO MISMO PARA LA PUERTA DEL CLUB
-- Es la RPC que más fácil se olvida, porque el flujo de Club VIP se prueba
-- menos que el público.
--
-- begin;
--   update barberos set activo = false
--   where barberia_id = '<id-de-tu-barberia>'::uuid
--     and nombre = '<nombre-de-un-profesional>';
--
--   select public.crear_reserva_publica_club(
--     '<id-de-tu-barberia>'::uuid, '<id-de-un-cliente>'::uuid,
--     current_date + 1, '10:00'::time, null,
--     '<nombre-de-un-profesional>', null
--   );
-- rollback;
--
-- Tiene que fallar con P0001 'El profesional elegido ya no está disponible...'.
