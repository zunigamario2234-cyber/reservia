-- La vista pública de disponibilidad pasa a exponer la DURACIÓN de cada reserva,
-- y deja de exponer las canceladas.
--
-- POR QUÉ
-- El cálculo de slots comparaba la hora EXACTA: un corte de 60 minutos a las
-- 11:30 marcaba ocupado solo el slot 11:30, y las 12:00 y 12:30 seguían
-- ofreciéndose. Un segundo cliente podía reservar encima de una cita en curso.
-- Confirmado en producción con un caso real.
--
-- Para calcular el solapamiento, el navegador necesita saber cuánto dura cada
-- reserva YA EXISTENTE, y esta vista no lo exponía: solo id, barberia_id, fecha,
-- hora, barbero_nombre y procesado. Ese era el bloqueador — el resto del arreglo
-- vive en reservar.html y club.html, pero sin este dato no se puede hacer.
--
-- POR QUÉ LA DURACIÓN RESUELTA Y NO LA COLUMNA `servicio`
-- Exponer `servicio` habría sido más simple, pero le contaría a cualquier
-- visitante anónimo qué servicio se hizo cada cliente a cada hora. La duración
-- sola no identifica a nadie y es lo único que el cálculo necesita. Además deja
-- el match en un solo lugar, en vez de duplicarlo en las dos páginas.
--
-- EL MATCH ES FEO PORQUE `reservas.servicio` ES TEXTO LIBRE, NO UNA FK
-- (deuda conocida). En producción conviven los dos formatos: el flujo público
-- guarda el NOMBRE del servicio (reservar.html manda p_servicio con
-- SEL.servicio.nombre) y app.html resuelve por ID primero y por nombre después
-- (resolveServicioInfo). Por eso se aceptan los dos, con la misma precedencia
-- que usa app.html: primero id, después nombre normalizado.
--
-- Va como SUBCONSULTA con limit 1, no como join: nada impide que un negocio
-- tenga dos servicios con el mismo nombre, y con join eso duplicaría la fila de
-- la reserva.
--
-- FALLBACK DE 30 MINUTOS cuando el servicio no se encuentra (renombrado,
-- borrado, o escrito distinto). Es el mismo criterio que ya usa app.html en
-- resolveServicioInfo, así que el dueño ve lo mismo en su calendario que el
-- cliente en la grilla. Subestima una reserva larga huérfana; la alternativa
-- (asumir el servicio más largo del negocio) escondía horarios realmente libres.
--
-- POR QUÉ AHORA SE DESCARTAN LAS CANCELADAS
-- La vista no exponía `estado`, y una reserva cancelada queda con
-- procesado=false, así que seguía bloqueando su hora para siempre. Se descartan
-- acá y no en el navegador para no exponer el estado de cada cita a un
-- visitante anónimo. 'No asistió' va por la misma puerta: esa silla quedó libre.
--
-- `coalesce(estado,'')` hace que un estado nulo SÍ ocupe: ante la duda, bloquear.
-- Bloquear de más molesta; liberar de más produce dos clientes a la misma hora.
--
-- SE MANTIENE LA COLUMNA `procesado` aunque el frontend nuevo deje de filtrarla.
-- Es lo que permite desplegar esta migración ANTES que el frontend: el
-- reservar.html que hoy está en producción sigue haciendo .eq('procesado',false)
-- y no se rompe. Ver el orden de despliegue más abajo.
--
-- ⚠ ORDEN DE DESPLIEGUE: ESTA MIGRACIÓN VA PRIMERO, EL FRONTEND DESPUÉS.
-- Es al revés que migration_hora_pasada.sql. Esta migración es retrocompatible
-- (agrega una columna al final y devuelve menos filas), así que el sitio en
-- producción sigue funcionando —de hecho mejora, porque las canceladas dejan de
-- bloquear—. Al revés se rompe: el frontend nuevo le pide duracion_min a una
-- vista que todavía no la tiene, y la grilla de horarios queda vacía.
--
-- SIN begin;/commit;: es una sola sentencia, ya es atómica. La regla del README
-- aplica a las migraciones que definen funciones (el cuerpo entre $function$
-- rompe el troceo del editor); acá no hay dollar-quoting, pero se mantiene el
-- mismo formato por consistencia.

create or replace view public.reservas_disponibilidad as
  select
    r.id,
    r.barberia_id,
    r.fecha,
    r.hora,
    r.barbero_nombre,
    r.procesado,
    coalesce((
      select s.duracion_min
      from servicios s
      where s.barberia_id = r.barberia_id
        and (s.id::text = r.servicio
             or lower(btrim(s.nombre)) = lower(btrim(r.servicio)))
      order by (s.id::text = r.servicio) desc
      limit 1
    ), 30) as duracion_min
  from reservas r
  where coalesce(r.estado, '') not in ('Cancelada', 'No asistió');

grant select on public.reservas_disponibilidad to anon, authenticated;


-- =============================================================================
-- PASO 1 — VERIFICAR QUE LA VISTA CAMBIÓ
-- Tiene que aparecer duracion_min en la lista de columnas.
--
-- select column_name, data_type
-- from information_schema.columns
-- where table_schema = 'public' and table_name = 'reservas_disponibilidad'
-- order by ordinal_position;
--
-- =============================================================================
-- PASO 2 — VERIFICAR QUE LA DURACIÓN SE RESUELVE DE VERDAD
-- Si sale todo en 30, el match no está funcionando y el arreglo no sirve:
-- las reservas largas seguirían sin bloquear los slots siguientes.
--
-- select d.fecha, d.hora, d.barbero_nombre, d.duracion_min, r.servicio
-- from reservas_disponibilidad d
-- join reservas r on r.id = d.id
-- order by d.fecha desc, d.hora
-- limit 30;
--
-- =============================================================================
-- PASO 3 — CUÁNTAS CAEN AL FALLBACK DE 30
-- Si `sin_match` es alto, conviene revisar esos nombres antes de confiar en el
-- cálculo: son reservas que van a bloquear menos tiempo del que realmente ocupan.
--
-- select b.nombre as negocio,
--        count(*) filter (where s.id is null) as sin_match,
--        count(*) as total,
--        string_agg(distinct r.servicio, ' | ') filter (where s.id is null)
--          as servicios_no_encontrados
-- from reservas r
-- join barberias b on b.id = r.barberia_id
-- left join lateral (
--   select s.id from servicios s
--   where s.barberia_id = r.barberia_id
--     and (s.id::text = r.servicio or lower(btrim(s.nombre)) = lower(btrim(r.servicio)))
--   order by (s.id::text = r.servicio) desc
--   limit 1
-- ) s on true
-- where coalesce(r.estado,'') not in ('Cancelada','No asistió')
-- group by b.nombre
-- order by sin_match desc;
--
-- =============================================================================
-- PASO 4 — VERIFICAR QUE LAS CANCELADAS DESAPARECIERON
-- Tiene que devolver 0 filas.
--
-- select count(*) as canceladas_visibles
-- from reservas_disponibilidad d
-- join reservas r on r.id = d.id
-- where r.estado in ('Cancelada','No asistió');
--
-- =============================================================================
-- PASO 5 — VERIFICAR QUE UN VISITANTE ANÓNIMO NO VE DATOS DEL CLIENTE
-- La vista no tiene que exponer nombre, whatsapp, email ni notas.
-- No puede aparecer ninguna de esas columnas.
--
-- select column_name
-- from information_schema.columns
-- where table_schema = 'public' and table_name = 'reservas_disponibilidad'
--   and column_name in ('nombre_cliente','whatsapp_cliente','email_cliente','notas');
