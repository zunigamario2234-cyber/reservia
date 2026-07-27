-- Housekeeping — borrado real de cuentas de prueba en Supabase.
-- Corre DESPUÉS de haber revisado housekeeping_verificacion_cuentas_prueba.sql
-- (sin nada en la categoría D). Lista de emails confirmada, incluye el que
-- sumaste desde la categoría F (reservia.test.routing.20260722@mailinator.com).
--
-- CÓMO CORRERLO (importante, es una transacción abierta a propósito):
--   1. Pega y corre TODO el bloque de abajo, HASTA la línea que dice
--      "-- ⏸ PARAR ACÁ" inclusive. Va a dejar la transacción abierta,
--      sin confirmar nada todavía.
--   2. Mira el resultado del SELECT final: todas las filas "restantes"
--      tienen que dar 0 y las listas de barberias/emails tienen que estar
--      vacías. Si algo no cuadra, corre `rollback;` y nada se pierde.
--   3. Si está todo en 0, corre `commit;` en la MISMA pestaña del SQL
--      Editor (sin cerrarla ni abrir una nueva — si cambias de pestaña,
--      la transacción se corta sola y hay que empezar de nuevo desde el
--      paso 1, es inofensivo, solo hay que repetirlo).
--
-- Orden de borrado: hijos más profundos primero, barberias justo antes que
-- auth.users (barberias.creado_por referencia auth.users, así que hay que
-- sacar la fila de barberias antes de poder borrar el usuario). perfiles va
-- antes que barberias, no después (perfiles.barberia_id referencia
-- barberias, es hijo, no al revés).

begin;

-- ── Sets objetivo, calculados una sola vez ──
create temp table cleanup_target_uids as
select u.id as uid, u.email
from auth.users u
where u.email in (
  'claude-diag-alianzahuerfana-1784670018@example.com',
  'claude-diag-fotoydesc-1784604959@example.com',
  'claude-diag-nivelesvip-1784608290@example.com',
  'claude-diag-responsive-1784671670@example.com',
  'diag-delres-ui-20260722@example.com',
  'reservia.test.dueno.20260722@mailinator.com',
  'reservia.test.pagos.20260723@mailinator.com',
  'reservia.test.profconpermiso.20260723@mailinator.com',
  'reservia.test.profsinpermiso.20260723@mailinator.com',
  'reservia.test.routing.20260722@mailinator.com'
);

create temp table cleanup_target_barberias as
select distinct b.id as barberia_id
from barberias b
where b.id in (
  select p.barberia_id from perfiles p
  join cleanup_target_uids tu on tu.uid = p.id
  where p.rol = 'dueno'
  union
  select b2.id from barberias b2
  join cleanup_target_uids tu on tu.uid = b2.creado_por
);

-- ── Borrado, hijos primero ──
delete from alianza_canjes where barberia_id in (select barberia_id from cleanup_target_barberias);
delete from alianza_codigos where barberia_id in (select barberia_id from cleanup_target_barberias);
delete from barbero_servicios where barberia_id in (select barberia_id from cleanup_target_barberias);
delete from bloqueos_profesional where barberia_id in (select barberia_id from cleanup_target_barberias);
delete from movimientos_stock where barberia_id in (select barberia_id from cleanup_target_barberias);
delete from vip_historial where barberia_id in (select barberia_id from cleanup_target_barberias);
delete from visitas where barberia_id in (select barberia_id from cleanup_target_barberias);
delete from reservas where barberia_id in (select barberia_id from cleanup_target_barberias);
delete from horario_negocio where barberia_id in (select barberia_id from cleanup_target_barberias);
delete from inventario where barberia_id in (select barberia_id from cleanup_target_barberias);
delete from costos where barberia_id in (select barberia_id from cleanup_target_barberias);
delete from plantillas_mensajes where barberia_id in (select barberia_id from cleanup_target_barberias);
delete from alianzas where barberia_id in (select barberia_id from cleanup_target_barberias);
delete from niveles_vip where barberia_id in (select barberia_id from cleanup_target_barberias);
delete from clientes where barberia_id in (select barberia_id from cleanup_target_barberias);
delete from servicios where barberia_id in (select barberia_id from cleanup_target_barberias);
delete from barberos where barberia_id in (select barberia_id from cleanup_target_barberias);

-- perfiles: por barberia_id (dueño + profesionales de esos negocios) Y por
-- id (por si algún perfil de dueño quedó con barberia_id nulo/inconsistente
-- de un registro a medias — no debería pasar, pero no cuesta nada cubrirlo).
delete from perfiles
where barberia_id in (select barberia_id from cleanup_target_barberias)
   or id in (select uid from cleanup_target_uids);

delete from barberias where id in (select barberia_id from cleanup_target_barberias);

-- auth.users: en el schema de Supabase, auth.identities/sessions/refresh_tokens
-- etc. tienen ON DELETE CASCADE contra auth.users.id, así que esto alcanza.
-- Si esta línea da un error de FK contra alguna tabla de auth.* que no sea
-- de las manejadas por cascade, parar y borrar esos usuarios puntuales desde
-- Authentication → Users en el dashboard en vez de forzarlo acá.
delete from auth.users where id in (select uid from cleanup_target_uids);

-- ── Verificación: todo tiene que dar 0 / vacío ──
select
  (select count(*) from cleanup_target_barberias) as barberias_objetivo,
  (select count(*) from barberias where id in (select barberia_id from cleanup_target_barberias)) as barberias_restantes,
  (select count(*) from perfiles where barberia_id in (select barberia_id from cleanup_target_barberias)) as perfiles_restantes,
  (select count(*) from auth.users where id in (select uid from cleanup_target_uids)) as auth_users_restantes,
  (select count(*) from clientes where barberia_id in (select barberia_id from cleanup_target_barberias)) as clientes_restantes,
  (select count(*) from visitas where barberia_id in (select barberia_id from cleanup_target_barberias)) as visitas_restantes,
  (select count(*) from alianza_codigos where barberia_id in (select barberia_id from cleanup_target_barberias)) as alianza_codigos_restantes;

-- ⏸ PARAR ACÁ — revisa que la fila de arriba dé todo 0 (menos
-- barberias_objetivo, que va a mostrar cuántas barberías se detectaron).
-- Recién ahí, en la MISMA pestaña:
--   commit;
-- o si algo no cuadra:
--   rollback;
