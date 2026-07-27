-- Verificación previa al proyecto "correos al profesional".
-- SOLO LECTURA: ningún insert/update/delete/alter. Se puede correr en
-- producción sin riesgo. SQL Editor de Supabase, consulta por consulta.

-- ═══════════════════════════════════════════════════════════════
-- (1) ¿Qué columnas tiene realmente "barberos"?
-- Confirma que "email" existe (app.html ya la escribe) y si hay
-- alguna otra columna de contacto que no esté a la vista en el código.
-- ═══════════════════════════════════════════════════════════════
select column_name, data_type, is_nullable
from information_schema.columns
where table_schema = 'public' and table_name = 'barberos'
order by ordinal_position;

-- ═══════════════════════════════════════════════════════════════
-- (2) ¿Cuántos profesionales tienen email cargado?
-- Es LA pregunta que decide si el proyecto es viable hoy o si primero
-- hay que hacer que el dueño complete los correos de su equipo.
-- ═══════════════════════════════════════════════════════════════
select
  count(*)                                                              as total,
  count(*) filter (where activo)                                        as activos,
  count(*) filter (where activo and coalesce(email, '') <> '')          as activos_con_email,
  count(*) filter (where activo and auth_user_id is not null)           as activos_con_cuenta_mi_agenda,
  count(*) filter (where activo and coalesce(email, '') <> ''
                     and auth_user_id is null)                          as activos_con_email_sin_cuenta
from barberos;

-- ═══════════════════════════════════════════════════════════════
-- (3) Desglose por negocio: sirve para saber si el faltante de correos
-- está concentrado en cuentas de prueba o repartido en negocios reales.
-- ═══════════════════════════════════════════════════════════════
select
  b.nombre                                                     as negocio,
  count(ba.*) filter (where ba.activo)                         as profesionales_activos,
  count(ba.*) filter (where ba.activo
                        and coalesce(ba.email, '') <> '')      as con_email
from barberias b
left join barberos ba on ba.barberia_id = b.id
group by b.id, b.nombre
order by profesionales_activos desc;

-- ═══════════════════════════════════════════════════════════════
-- (4) Riesgo del vínculo por TEXTO: reservas.barbero_nombre no es una FK.
-- Para mandarle correo al profesional hay que resolver nombre -> fila de
-- barberos por match exacto. Esto mide cuántas reservas NO resolverían.
-- 'Por asignar' es el default que pone crear_reserva_publica() cuando el
-- cliente no elige profesional: se cuenta aparte porque no es un error,
-- es "no hay a quién avisarle".
-- ═══════════════════════════════════════════════════════════════
select
  count(*)                                                     as reservas_ultimos_90d,
  count(*) filter (where r.barbero_nombre = 'Por asignar')     as sin_profesional_elegido,
  count(*) filter (where r.barbero_nombre <> 'Por asignar'
                     and not exists (
                       select 1 from barberos ba
                       where ba.barberia_id = r.barberia_id
                         and ba.nombre = r.barbero_nombre))    as nombre_que_no_matchea,
  count(*) filter (where exists (
                       select 1 from barberos ba
                       where ba.barberia_id = r.barberia_id
                         and ba.nombre = r.barbero_nombre
                         and coalesce(ba.email, '') <> ''))    as matchea_y_tiene_email
from reservas r
where r.fecha >= current_date - 90;

-- ═══════════════════════════════════════════════════════════════
-- (5) ¿El flujo de cancelación se usa de verdad, o es teórico?
-- Decide si el correo "te cancelaron una cita" resuelve un problema real.
-- ═══════════════════════════════════════════════════════════════
select estado, count(*) as cantidad
from reservas
where fecha >= current_date - 90
group by estado
order by cantidad desc;
