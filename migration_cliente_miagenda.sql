-- PUNTO 3 — Alta de clientes desde Mi Agenda: correo, cumpleaños, y el
-- match del WhatsApp normalizado SOLO por este camino.
--
-- Lo que ya funcionaba y no se toca: el profesional ya podía escribir un
-- nombre y un WhatsApp nuevos al agendar, y la ficha se creaba sola. No
-- dependía del dueño.
--
-- Lo que se arregla acá:
--   1. El modal no pedía correo ni cumpleaños. Ahora los pide (opcionales) y
--      viajan a la reserva y de ahí a la ficha.
--   2. La ficha quedaba con canal = 'Reserva Web' aunque la cargó un
--      profesional en el mostrador.
--   3. fecha_registro salía de la FECHA DE LA RESERVA, no de hoy: agendar
--      para el mes que viene daba de alta un cliente "registrado" el mes que
--      viene. Ahora es hoy, anclado a hora de Chile.
--   4. El match para reconocer una ficha existente era `whatsapp = ...`,
--      texto exacto, y en la base conviven cuatro formatos del mismo número
--      ('+56 9 8754 2136', '+56987542136', '56987542136', '987542136'). El
--      mismo cliente tipeado distinto abría una ficha nueva.
--
-- ═══════════════════════════════════════════════════════════════
-- ⚠ POR QUÉ SE CREA UNA FUNCIÓN NUEVA EN VEZ DE ARREGLAR
--    buscar_o_crear_cliente_club — LEER ANTES DE TOCAR ESTO
--
-- El arreglo obvio sería normalizar el match dentro de
-- buscar_o_crear_cliente_club, que es la que llamaba Mi Agenda. NO se hace,
-- y no es por comodidad.
--
-- Esa función es la puerta de más volumen del sistema: corre en CADA reserva
-- del link público y del Club VIP. migration_backfill_email_ficha.sql ya
-- había dejado escrito, a propósito, que su criterio no se mueve sin decisión
-- explícita: cambiarlo hace que empiece a encontrar fichas que hoy no
-- encuentra, lo que mueve a qué ficha se le suman las visitas y corre
-- reportes históricos. Eso es "la deuda del WhatsApp" y es un proyecto propio.
--
-- Decisión explícita del 2026-09-16: se normaliza SOLO el camino de Mi
-- Agenda. El link público y el Club VIP siguen con match exacto, intactos.
-- Por eso hay una función nueva y buscar_o_crear_cliente_club no aparece en
-- este archivo ni siquiera para reemplazarla por sí misma.
--
-- Consecuencia aceptada a sabiendas: durante un tiempo dos caminos del mismo
-- producto reconocen fichas con criterios distintos. Una reserva del link
-- público puede crear una ficha que Mi Agenda habría reconocido. Es el precio
-- de no mover las rutas de volumen, y es reversible: el día que se salde la
-- deuda, esta función y la otra convergen.
-- ═══════════════════════════════════════════════════════════════
--
-- Ejecutar UNA VEZ, completo, en el SQL Editor de Supabase.


-- ═══════════════════════════════════════════════════════════════
-- (0) ANTES DE APLICAR — no escribe nada, correr suelto.
--
-- El repo puede estar atrasado respecto de la base. Comparar el cuerpo real
-- de mi_agenda_crear_reserva con el que este archivo reemplaza; si no
-- coincide con el de migration_mi_agenda.sql, parar y avisar.
--
--   select pg_get_functiondef(p.oid)
--   from pg_proc p join pg_namespace n on n.oid = p.pronamespace
--   where n.nspname = 'public' and p.proname = 'mi_agenda_crear_reserva';
--
-- Y confirmar que la columna generada que usa el match nuevo existe:
--
--   select table_name, column_name, generation_expression
--   from information_schema.columns
--   where table_schema = 'public' and column_name = 'whatsapp_norm';
--
--   Esperado: al menos `clientes`, con
--   right(regexp_replace(coalesce(whatsapp,''), '\D', '', 'g'), 9)
-- ═══════════════════════════════════════════════════════════════


-- ═══════════════════════════════════════════════════════════════
-- (1) mi_agenda_crear_reserva — ahora acepta correo y cumpleaños.
--
-- Los dos parámetros nuevos van AL FINAL y con default null: así una llamada
-- vieja de 6 argumentos sigue siendo válida mientras se despliega el HTML.
--
-- ⚠ CAMBIA LA FIRMA, así que el drop de la versión de 6 argumentos es
-- obligatorio. Sin él quedan las DOS conviviendo —Postgres las trata como
-- funciones distintas— y PostgREST elige por los argumentos que le manden:
-- el día que alguien llame sin correo, entra por la vieja y el dato se pierde
-- en silencio.
-- ═══════════════════════════════════════════════════════════════

drop function if exists mi_agenda_crear_reserva(text,text,date,time,text,text);

create or replace function mi_agenda_crear_reserva(
  p_nombre_cliente     text,
  p_whatsapp_cliente   text,
  p_fecha              date,
  p_hora               time,
  p_servicio           text default null,
  p_notas              text default null,
  p_email_cliente      text default null,
  p_cumpleanos_cliente date default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $function$
declare
  v_barbero_id uuid := auth_barbero_id();
  v_nombre     text;
  v_barberia   uuid := auth_barberia_id();
  v_id         uuid;
begin
  if v_barbero_id is null then
    raise exception 'No autorizado';
  end if;

  -- El nombre del profesional se resuelve acá adentro, no llega por
  -- parámetro: es lo que impide agendar a nombre de otro.
  select b.nombre into v_nombre from barberos b where b.id = v_barbero_id;

  insert into reservas (
    barberia_id, nombre_cliente, whatsapp_cliente, email_cliente,
    cumpleanos_cliente, fecha, hora,
    servicio, barbero_nombre, estado, procesado, notas, fuente
  ) values (
    v_barberia, p_nombre_cliente, p_whatsapp_cliente, p_email_cliente,
    p_cumpleanos_cliente, p_fecha, p_hora,
    p_servicio, v_nombre, 'Confirmada', false, p_notas, 'Mi Agenda'
  ) returning id into v_id;

  return v_id;
end;
$function$;

revoke all on function mi_agenda_crear_reserva(text,text,date,time,text,text,text,date) from public;
revoke all on function mi_agenda_crear_reserva(text,text,date,time,text,text,text,date) from anon;
grant execute on function mi_agenda_crear_reserva(text,text,date,time,text,text,text,date) to authenticated;


-- ═══════════════════════════════════════════════════════════════
-- (2) mi_agenda_resolver_cliente — la ficha, con match normalizado.
--
-- Reemplaza a buscar_o_crear_cliente_club SOLO para el camino de Mi Agenda.
-- Devuelve además si la ficha se creó o se reutilizó, para que la pantalla
-- pueda decirlo: hoy la llamada va en un try/catch que solo hace console.log
-- y el profesional no se entera de nada.
-- ═══════════════════════════════════════════════════════════════

create or replace function mi_agenda_resolver_cliente(p_reserva_id uuid)
returns table (cliente_id uuid, creado boolean)
language plpgsql
security definer
set search_path = public
as $function$
declare
  v_barbero_id uuid := auth_barbero_id();
  v_barberia   uuid := auth_barberia_id();
  v_reserva    reservas%rowtype;
  v_norm       text;
  v_cliente_id uuid;
  v_creado     boolean := false;
begin
  if v_barbero_id is null then
    raise exception 'No autorizado';
  end if;

  -- El barberia_id NO llega por parámetro, sale de la sesión. Es la
  -- diferencia con buscar_o_crear_cliente_club, que lo recibe del cliente y
  -- solo comprueba que la reserva le pertenezca: acá no hay forma de apuntar
  -- a la reserva de otro negocio.
  select * into v_reserva
  from reservas r
  where r.id = p_reserva_id and r.barberia_id = v_barberia;

  if not found then
    raise exception 'Reserva no encontrada para este negocio';
  end if;

  -- ⚠ SE LEE LA COLUMNA GENERADA, NO SE RECALCULA LA FÓRMULA.
  -- `reservas.whatsapp_norm` y `clientes.whatsapp_norm` son las dos columnas
  -- generadas, con la MISMA transformación (los últimos 9 dígitos, sin los
  -- no-dígitos) aplicada cada una a su columna de teléfono. Los dos lados de
  -- la comparación de abajo salen entonces de la misma definición.
  --
  -- Escribir acá `right(regexp_replace(...), 9)` a mano funcionaría hoy y
  -- sería una TERCERA copia de esa fórmula, mantenida en otro lugar: el día
  -- que alguien cambie la definición de las columnas generadas, esta se
  -- quedaría atrás y el match dejaría de encontrar fichas — creando
  -- duplicados en silencio, que es justo lo que esta migración viene a
  -- arreglar. El bug se vería como "volvió el problema", no como "hay dos
  -- fórmulas distintas".
  v_norm := v_reserva.whatsapp_norm;

  -- ⚠ La guarda del largo no es decorativa. Una ficha vieja sin teléfono
  -- tiene whatsapp_norm = '': sin este if, un cliente sin WhatsApp matearía
  -- contra ella y el profesional terminaría agendando sobre la ficha
  -- equivocada. Con 9 exigidos, '' nunca puede coincidir.
  --
  -- La columna generada nunca es null (el coalesce de su propia definición
  -- deja '' cuando no hay teléfono), así que length() acá siempre responde.
  if length(v_norm) = 9 then
    select c.id into v_cliente_id
    from clientes c
    where c.barberia_id = v_barberia
      and c.whatsapp_norm = v_norm
    limit 1;
  end if;

  if v_cliente_id is not null then
    -- Ficha existente: se RELLENAN los huecos, nunca se pisa lo que ya hay.
    -- El dato viejo puede haberlo corregido el dueño a mano.
    update clientes c
       set email = email_para_ficha(v_reserva.email_cliente)
     where c.id = v_cliente_id
       and c.barberia_id = v_barberia
       and coalesce(btrim(c.email), '') = ''
       and email_para_ficha(v_reserva.email_cliente) is not null;

    update clientes c
       set cumpleanos = v_reserva.cumpleanos_cliente
     where c.id = v_cliente_id
       and c.barberia_id = v_barberia
       and c.cumpleanos is null
       and v_reserva.cumpleanos_cliente is not null;

    return query select v_cliente_id, false;
    return;
  end if;

  -- Ficha nueva.
  --   · canal 'Mi Agenda' y no 'Reserva Web': la cargó un profesional en el
  --     mostrador, y el canal se usa para saber de dónde viene la gente.
  --   · fecha_registro es HOY en hora de Chile, no la fecha de la reserva:
  --     agendar para dentro de un mes no da de alta un cliente en el futuro.
  --     `current_date` a secas es UTC y en Chile adelanta el día desde las
  --     21:00 — el mismo error que hubo que corregir en
  --     registrar_cobro_conjunto.
  --   · el correo pasa por email_para_ficha, que descarta lo que no sea un
  --     correo; así un "no tiene" tipeado en el campo no queda como email.
  insert into clientes (
    barberia_id, nombre, whatsapp, email, cumpleanos, canal, fecha_registro
  ) values (
    v_barberia,
    v_reserva.nombre_cliente,
    v_reserva.whatsapp_cliente,
    email_para_ficha(v_reserva.email_cliente),
    v_reserva.cumpleanos_cliente,
    'Mi Agenda',
    (now() at time zone 'America/Santiago')::date
  )
  returning id into v_cliente_id;

  v_creado := true;
  return query select v_cliente_id, v_creado;
end;
$function$;

revoke all on function mi_agenda_resolver_cliente(uuid) from public;
revoke all on function mi_agenda_resolver_cliente(uuid) from anon;
grant execute on function mi_agenda_resolver_cliente(uuid) to authenticated;


-- ═══════════════════════════════════════════════════════════════
-- (3) VERIFICACIÓN
--
-- ⚠ EL BLOQUE (c) ESCRIBE. Va entre begin; y rollback; y hay que correrlo
--   SELECCIONÁNDOLO ENTERO, con un solo Run. El SQL Editor de Supabase NO
--   mantiene sesión entre ejecuciones: en partes, el begin de una no envuelve
--   a los inserts de la siguiente, caen en autocommit y el rollback no
--   revierte nada — quedan fichas de prueba en producción.
--
--   a) Quedó UNA sola mi_agenda_crear_reserva, la de 8 argumentos:
--
--      select p.proname, pg_get_function_arguments(p.oid) as args
--      from pg_proc p join pg_namespace n on n.oid = p.pronamespace
--      where n.nspname = 'public' and p.proname = 'mi_agenda_crear_reserva';
--
--      Esperado: UNA fila, con p_email_cliente y p_cumpleanos_cliente.
--      Si aparecen dos, el drop no corrió y hay que borrar la de 6 a mano.
--
--   b) La función nueva está bien blindada, y anon afuera de las dos:
--
--      select p.proname, p.prosecdef as definer, p.proconfig as search_path,
--             has_function_privilege('anon', p.oid, 'execute') as anon,
--             has_function_privilege('authenticated', p.oid, 'execute') as auth
--      from pg_proc p join pg_namespace n on n.oid = p.pronamespace
--      where n.nspname = 'public'
--        and p.proname in ('mi_agenda_resolver_cliente','mi_agenda_crear_reserva');
--
--      Esperado: las dos con definer t, search_path {search_path=public},
--                anon f, auth t
--
--   c) EL CHECK QUE IMPORTA: el mismo número en otro formato reconoce la
--      ficha en vez de duplicarla.
--
--      Comprueba su PRECONDICIÓN antes de afirmar nada: si la ficha de prueba
--      no se insertó, el select de abajo daría 0 igual y el paso "pasaría"
--      por el motivo equivocado.
--
--      Reemplazar <BARBERIA_ID>.
--
--      ⚠ La precondición va DENTRO del mismo select que los casos, no en un
--      select aparte. El SQL Editor de Supabase muestra el resultado del
--      ÚLTIMO select nada más: separados, la precondición no se vería y
--      quedaría sin comprobar justamente lo que le da sentido al resto.
--
--      begin;
--
--      insert into clientes (barberia_id, nombre, whatsapp, canal, fecha_registro)
--      values ('<BARBERIA_ID>', 'ZZ Prueba Norm', '+56 9 8754 2136',
--              'Prueba', current_date);
--
--      select f.formato,
--             (select count(*) from clientes c
--               where c.barberia_id = '<BARBERIA_ID>'
--                 and c.nombre = 'ZZ Prueba Norm'
--             ) as precondicion_esperado_1,
--             (select count(*) from clientes c
--               where c.barberia_id = '<BARBERIA_ID>'
--                 and c.whatsapp_norm = right(regexp_replace(f.formato,'\D','','g'), 9)
--             ) as encuentra_normalizado,
--             (select count(*) from clientes c
--               where c.barberia_id = '<BARBERIA_ID>'
--                 and c.whatsapp = f.formato
--             ) as encuentra_exacto
--      from (values ('+56987542136'), ('56987542136'), ('987542136')) as f(formato);
--
--      -- Esperado, TRES filas, y es el PAR de las dos últimas columnas lo que
--      -- prueba el arreglo:
--      --   precondicion_esperado_1 = 1 en las tres  ← si da 0, todo lo demás
--      --                                              miente y hay que parar
--      --   encuentra_normalizado   = 1 en las tres  ← el criterio nuevo
--      --   encuentra_exacto        = 0 en las tres  ← el viejo, que duplicaba
--
--      rollback;
--
--   d) Las otras dos puertas quedaron INTACTAS con match exacto — esto es lo
--      que confirma que la decisión se respetó:
--
--      select p.proname,
--             p.prosrc like '%whatsapp = v_reserva.whatsapp_cliente%' as sigue_exacto,
--             p.prosrc like '%whatsapp_norm%'                         as se_contamino
--      from pg_proc p join pg_namespace n on n.oid = p.pronamespace
--      where n.nspname = 'public' and p.proname = 'buscar_o_crear_cliente_club';
--
--      Esperado: sigue_exacto t, se_contamino f
-- ═══════════════════════════════════════════════════════════════
