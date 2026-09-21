-- PUNTO 2 — El profesional puede BORRAR de verdad sus propias reservas.
--
-- Hasta hoy el botón "Eliminar de mi agenda" llamaba a mi_agenda_eliminar_cita,
-- que hace `oculto_profesional = true`: oculta la cita de su vista y el dueño
-- la sigue viendo. El borrado real era solo del dueño (policy
-- reservas_delete_own, con auth_rol() = 'dueno').
--
-- Decisión tomada el 2026-09-16: el profesional puede borrar de verdad, con
-- una restricción — no puede borrar lo ya cobrado.
--
-- ⚠ LO QUE ESTA FUNCIÓN **NO** PUEDE TOCAR, Y POR QUÉ
-- No recibe `p_tipo`. La vieja sí lo recibía ('reserva' | 'visita') porque
-- ocultar una visita es inocuo. Borrar una visita NO lo es: `visitas` es el
-- registro de la venta y de la comisión, y no tiene FK con `reservas` —
-- borrar la reserva no la toca, pero borrar la visita destruiría plata ya
-- cobrada y la comisión de esa persona. Dejar el parámetro afuera es una
-- garantía de la FIRMA: no hay forma de pedirle a esta función que borre una
-- visita, ni siquiera llamándola a mano por PostgREST. Es más fuerte que un
-- `if p_tipo = 'visita' then raise`.
--
-- Las visitas se siguen ocultando con mi_agenda_eliminar_cita, que queda
-- intacta y en uso.
--
-- ⚠ EL FILTRO `procesado = false` NO ES REDUNDANTE aunque la UI ya lo cumpla.
-- mi_agenda_citas() filtra `r.procesado = false` en su select de reservas
-- (migration_fix_duplicado_mi_agenda.sql), así que una cita cobrada ya no se
-- lista como reserva: aparece como visita. O sea que desde la pantalla no se
-- llega a pedir el borrado de una reserva procesada. Pero la RPC es un
-- endpoint HTTP que cualquiera con sesión puede llamar con el id que quiera,
-- y la pantalla no es una defensa. El filtro va en el WHERE.
--
-- La policy reservas_delete_own NO se toca: el camino del dueño queda igual.
--
-- Ejecutar UNA VEZ, completo, en el SQL Editor de Supabase.


-- ═══════════════════════════════════════════════════════════════
-- (0) ANTES DE APLICAR — no escribe nada, correr suelto.
--
-- Acá NO se compara un cuerpo previo como en los otros dos archivos:
-- mi_agenda_borrar_cita no existe todavía. Lo que se comprueba es el ESTADO
-- DE PARTIDA que esta migración da por sentado. Si alguna fila no da lo
-- esperado, parar: significa que la base no está donde el archivo cree.
--
--   select
--     -- 1. La función nueva NO debe existir ya. Si existe, alguien la creó
--     --    antes y este archivo la pisaría sin que sepamos qué hacía.
--     (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
--       where n.nspname='public' and p.proname='mi_agenda_borrar_cita')
--       as borrar_ya_existe_esperado_0,
--
--     -- 2. La de OCULTAR sigue viva: no se toca y queda en uso para las
--     --    visitas, que no se pueden borrar.
--     (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
--       where n.nspname='public' and p.proname='mi_agenda_eliminar_cita')
--       as ocultar_sigue_esperado_1,
--
--     -- 3. El borrado real sigue siendo SOLO del dueño. Este es el estado
--     --    que la migración cambia para el profesional sin tocar al dueño.
--     (select count(*) from pg_policy
--       where polrelid='public.reservas'::regclass and polcmd='d'
--         and pg_get_expr(polqual, polrelid) like '%dueno%')
--       as delete_solo_dueno_esperado_1,
--
--     -- 4. La columna de la que depende el filtro existe.
--     (select count(*) from information_schema.columns
--       where table_schema='public' and table_name='reservas'
--         and column_name='procesado')
--       as columna_procesado_esperado_1;
--
--   Esperado: 0, 1, 1, 1
--
-- Y confirmar que la de ocultar sigue ocultando y no borrando — si alguien
-- ya la había convertido en un delete, este archivo sobraría y habría que
-- revisar qué más cambió:
--
--   select p.prosrc like '%oculto_profesional%' as sigue_ocultando,
--          p.prosrc like '%delete%'             as ya_borraba
--   from pg_proc p join pg_namespace n on n.oid = p.pronamespace
--   where n.nspname='public' and p.proname='mi_agenda_eliminar_cita';
--
--   Esperado: sigue_ocultando t, ya_borraba f
-- ═══════════════════════════════════════════════════════════════


-- ═══════════════════════════════════════════════════════════════
-- (1) La función.
-- ═══════════════════════════════════════════════════════════════

create or replace function mi_agenda_borrar_cita(p_id uuid)
returns boolean
language plpgsql
security definer
set search_path = public
as $function$
declare
  v_barbero_id uuid := auth_barbero_id();
  v_nombre     text;
  v_barberia   uuid := auth_barberia_id();
  v_rows       int;
begin
  -- Sin barbero logueado no hay nada que hacer acá. Mismo mensaje y misma
  -- forma que el resto de las mi_agenda_*.
  if v_barbero_id is null then
    raise exception 'No autorizado';
  end if;

  select b.nombre into v_nombre from barberos b where b.id = v_barbero_id;

  -- Las TRES condiciones de scoping juntas, como en toda la familia
  -- mi_agenda_*: el negocio, el profesional, y que no esté cobrada. Con el
  -- id solo se podría borrar la reserva de otro negocio; con el negocio solo,
  -- la de un compañero.
  delete from reservas r
   where r.id            = p_id
     and r.barberia_id   = v_barberia
     and r.barbero_nombre = v_nombre
     and r.procesado     = false;

  get diagnostics v_rows = row_count;

  -- false cuando no borró: puede ser que no exista, que sea de otro, o que
  -- esté cobrada. Los tres casos devuelven lo mismo a propósito — distinguir
  -- le diría a quien sondee el endpoint cuál de las condiciones falló, y de
  -- paso si un id existe en otro negocio. El front traduce el false a un
  -- aviso genérico.
  return v_rows > 0;
end;
$function$;


-- ═══════════════════════════════════════════════════════════════
-- (2) Permisos.
--
-- Las dos líneas de revoke hacen falta y la segunda NO es redundante: los
-- default privileges de Supabase le dan EXECUTE a anon y authenticated sobre
-- toda función nueva, con un grant explícito a cada rol. El revoke a PUBLIC
-- deja el de anon intacto, y con que quede uno la función sigue publicada
-- como endpoint. Acá importa especialmente: es la única función de borrado
-- real que va a existir fuera del dueño.
-- ═══════════════════════════════════════════════════════════════

revoke all on function mi_agenda_borrar_cita(uuid) from public;
revoke all on function mi_agenda_borrar_cita(uuid) from anon;
grant execute on function mi_agenda_borrar_cita(uuid) to authenticated;


-- ═══════════════════════════════════════════════════════════════
-- (3) VERIFICACIÓN
--
-- ⚠ EL BLOQUE (c) ESCRIBE. Va entre begin; y rollback; y hay que correrlo
--   SELECCIONÁNDOLO ENTERO, con un solo Run. El SQL Editor de Supabase NO
--   mantiene sesión entre ejecuciones: si se corre en partes, el begin de una
--   no envuelve al delete de la siguiente, cae en autocommit y el rollback no
--   revierte nada. Ya pasó dos veces (2026-09-11/12) y dejó filas de prueba
--   en producción.
--
--   a) La función existe, es definer y tiene el search_path fijo:
--
--      select p.proname,
--             pg_get_function_arguments(p.oid) as args,
--             p.prosecdef                      as security_definer,
--             p.proconfig                      as search_path,
--             p.prosrc like '%procesado%'      as bloquea_cobradas
--      from pg_proc p join pg_namespace n on n.oid = p.pronamespace
--      where n.nspname = 'public' and p.proname = 'mi_agenda_borrar_cita';
--
--      Esperado: args "p_id uuid" (UNA sola, sin p_tipo), security_definer t,
--                search_path {search_path=public}, bloquea_cobradas t
--
--   b) anon no quedó con permiso:
--
--      select has_function_privilege('authenticated',
--               'mi_agenda_borrar_cita(uuid)', 'execute') as authenticated,
--             has_function_privilege('anon',
--               'mi_agenda_borrar_cita(uuid)', 'execute') as anon;
--
--      Esperado: authenticated t, anon f
--
--   c) La restricción de verdad: una reserva COBRADA no se borra.
--      Este bloque fabrica el caso, lo prueba y lo revierte.
--
--      Antes de los casos comprueba su PRECONDICIÓN (que las dos filas se
--      insertaron). Un paso que pasa porque no había nada que borrar no
--      prueba nada: el delete daría 0 filas igual si la función estuviera
--      rota.
--
--      Reemplazar <BARBERIA_ID> y <NOMBRE_BARBERO> por los del negocio.
--
--      begin;
--
--      insert into reservas (barberia_id, nombre_cliente, whatsapp_cliente,
--                            fecha, hora, barbero_nombre, estado, procesado, fuente)
--      values ('<BARBERIA_ID>', 'ZZ Prueba Borrado', '+56900000000',
--              current_date, '10:00', '<NOMBRE_BARBERO>', 'Confirmada', false, 'Mi Agenda'),
--             ('<BARBERIA_ID>', 'ZZ Prueba Cobrada', '+56900000000',
--              current_date, '11:00', '<NOMBRE_BARBERO>', 'Atendida',   true,  'Mi Agenda');
--
--      -- PRECONDICIÓN: tienen que ser 2. Si da 0, todo lo de abajo miente.
--      select count(*) as precondicion_esperado_2
--      from reservas where nombre_cliente like 'ZZ Prueba%';
--
--      -- Sin sesión de barbero la función corta en el raise, así que este
--      -- bloque comprueba el WHERE directamente, que es lo que se agregó:
--      delete from reservas r
--       where r.nombre_cliente = 'ZZ Prueba Borrado'
--         and r.barberia_id = '<BARBERIA_ID>'
--         and r.barbero_nombre = '<NOMBRE_BARBERO>'
--         and r.procesado = false;
--      -- Esperado: DELETE 1
--
--      delete from reservas r
--       where r.nombre_cliente = 'ZZ Prueba Cobrada'
--         and r.barberia_id = '<BARBERIA_ID>'
--         and r.barbero_nombre = '<NOMBRE_BARBERO>'
--         and r.procesado = false;
--      -- Esperado: DELETE 0  ← la cobrada sobrevive
--
--      select nombre_cliente, procesado
--      from reservas where nombre_cliente like 'ZZ Prueba%';
--      -- Esperado: queda SOLO 'ZZ Prueba Cobrada'
--
--      rollback;
--
--   d) La policy del dueño quedó intacta:
--
--      select polname, polcmd, pg_get_expr(polqual, polrelid) as using_expr
--      from pg_policy
--      where polrelid = 'public.reservas'::regclass and polcmd = 'd';
--
--      Esperado: reservas_delete_own, con auth_rol() = 'dueno' en el using.
-- ═══════════════════════════════════════════════════════════════
