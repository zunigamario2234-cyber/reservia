-- Hace obligatorio el profesional en las dos RPC públicas de reserva.
--
-- POR QUÉ
-- Una reserva sin profesional asignado no le avisa a nadie: el resolver de
-- api/enviar-confirmacion.js descarta 'Por asignar' de entrada, así que ningún
-- profesional se entera, y alguien tiene que acordarse de asignarla a mano
-- antes de la cita. Se eliminó el estado ambiguo en vez de construir avisos
-- para gestionarlo.
--
-- El frontend ya obliga a elegir (commits 168e7c8 y 8deb317), pero eso vive
-- solo en el navegador: la anon key es pública por diseño, así que cualquiera
-- puede llamar la RPC directo y mandar 'Por asignar'. Esto lo cierra en la
-- base, que es donde queda garantizado.
--
-- CORRE DESPUÉS DE QUE EL FRONTEND ESTÉ EN PRODUCCIÓN, no antes: mientras el
-- navegador siga ofreciendo "Cualquier profesional", esto rompe las reservas
-- en vivo.
--
-- LA TERCERA PUERTA NO SE TOCA
-- mi_agenda_crear_reserva no recibe p_barbero_nombre: lo resuelve server-side
-- desde auth_barbero_id(). Ya era imposible crear una reserva sin asignar por
-- ahí.
--
-- POR QUÉ NO SE VALIDA `activo`
-- Sería lo natural —un profesional dado de baja no debería recibir reservas—
-- pero hoy reservar.html y club.html cargan barberos SIN filtrar por activo,
-- así que la grilla pública ofrece gente inactiva. Validarlo acá rechazaría
-- reservas que el propio sitio ofrece. Queda pendiente arreglarlo en el
-- frontend primero; hasta entonces esta función acepta inactivos igual que
-- antes. (Vale la pena saber que una reserva con un profesional inactivo
-- tampoco genera aviso: el resolver de correos los filtra. Es el mismo
-- síntoma que esta migración viene a eliminar, por otra vía.)
--
-- EFECTO EXTRA: NORMALIZA EL NOMBRE GUARDADO
-- En vez de guardar el texto que mandó el navegador, guarda el nombre tal cual
-- está en la ficha del profesional. reservas.barbero_nombre es texto libre y
-- no una FK (deuda conocida), y en producción ya hay reservas con distinta
-- capitalización que la ficha. Esto no arregla la deuda, pero deja de
-- alimentarla.
--
-- Los mensajes de las excepciones llegan al navegador del cliente: reservar.html
-- los muestra tal cual en el cartel de error. Por eso están escritos para que
-- los lea una persona, no para depurar.
--
-- ⚠ SIN begin;/commit; A PROPÓSITO — NO LOS AGREGUES
-- La primera versión de este archivo los traía y el SQL Editor de Supabase NO
-- aplicó nada, sin dar ningún error: devolvió éxito y las funciones quedaron
-- con el cuerpo viejo. Se descubrió porque la prueba de rechazo insertó una
-- reserva en vez de fallar. Sacando las dos líneas funcionó a la primera.
--
-- La diferencia con migration_reservas_insert_own.sql, que sí se aplicó con
-- begin;/commit;, es que este archivo define FUNCIONES: el cuerpo va entre
-- $function$ y lleva `;` adentro. Todo indica que el editor trocea el script
-- por `;` y esos puntos y coma internos rompen el troceo. No está verificado
-- a fondo, pero la regla práctica es clara: en el SQL Editor no hace falta
-- abrir transacción a mano —ya corre en una— y con funciones de por medio
-- hacerlo rompe en silencio, que es la peor forma de romper.

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

-- VERIFICACIÓN (el rollback es obligatorio: si la migración NO quedó aplicada,
-- esto inserta una reserva de verdad en vez de fallar).
--
-- begin;
-- select public.crear_reserva_publica(
--   '<id-de-tu-barberia>'::uuid, 'Prueba', '+56900000000',
--   current_date + 1, '10:00'::time, null, null, null, 'Por asignar', null
-- );
-- rollback;
--
-- Tiene que fallar con P0001 'Tienes que elegir un profesional para reservar'.
-- Aplicada el 2026-07-28: crear_reserva_publica pasó de 519 a 1049 caracteres
-- de cuerpo y crear_reserva_publica_club de 807 a 1339, las dos con la
-- validación presente.
