-- Housekeeping — cuentas de prueba acumuladas en Supabase.
-- SOLO LECTURA. No borra nada, no crea nada permanente (el "with" es una
-- CTE de sesión, se descarta sola al terminar la consulta).
--
-- Ejecutar completo en el SQL Editor de Supabase y revisar el resultado
-- ANTES de pedir el script de DELETE. Cubre lo pedido:
--   1. auth.users.id de los emails listados.
--   2. barberia_id asociados, vía perfiles.rol='dueno' Y vía
--      barberias.creado_por (pueden no coincidir si el registro quedó a
--      medias — un dueño de prueba que nunca llegó a tener fila en
--      perfiles, por ejemplo).
--   3. Conteo de filas por tabla, por cada barberia_id encontrado.
--   4. Detección de otros emails con patrón similar (claude-diag-%,
--      reservia.test.%, diag-%) que no estaban en tu lista.
--   5. Alerta si algún negocio de prueba tiene un perfil vinculado con un
--      email que NO está en la lista — antes de borrar por barberia_id
--      hay que confirmar que no se lleve puesta una cuenta real.

with target_emails(email) as (
  values
    ('claude-diag-alianzahuerfana-1784670018@example.com'),
    ('claude-diag-fotoydesc-1784604959@example.com'),
    ('claude-diag-nivelesvip-1784608290@example.com'),
    ('claude-diag-responsive-1784671670@example.com'),
    ('diag-delres-ui-20260722@example.com'),
    ('reservia.test.dueno.20260722@mailinator.com'),
    ('reservia.test.pagos.20260723@mailinator.com'),
    ('reservia.test.profconpermiso.20260723@mailinator.com'),
    ('reservia.test.profsinpermiso.20260723@mailinator.com')
),
target_uids as (
  select u.id as uid, u.email
  from auth.users u
  join target_emails t on t.email = u.email
),
barberia_origenes as (
  select b.id as barberia_id, 'perfiles.dueno' as origen
  from barberias b
  join perfiles p on p.barberia_id = b.id and p.rol = 'dueno'
  join target_uids tu on tu.uid = p.id
  union
  select b.id as barberia_id, 'barberias.creado_por' as origen
  from barberias b
  join target_uids tu on tu.uid = b.creado_por
),
target_barberias as (
  select bo.barberia_id, b.nombre, string_agg(distinct bo.origen, ', ') as origen
  from barberia_origenes bo
  join barberias b on b.id = bo.barberia_id
  group by bo.barberia_id, b.nombre
)

-- (1) Emails de tu lista que NO existen en auth.users — para que sepas si
-- ya los borraste antes, o si hay un typo en el email.
select 'A) email objetivo NO encontrado' as categoria, t.email as detalle, null::uuid as barberia_id, null::bigint as cantidad
from target_emails t
left join auth.users u on u.email = t.email
where u.id is null

union all

-- (2) Emails de tu lista que SÍ existen — estos son los que se van a borrar
-- de auth.users al final del script de DELETE.
select 'B) email objetivo encontrado', tu.email, null::uuid, null::bigint
from target_uids tu

union all

-- (3) Negocios de prueba detectados y por qué señal (dueño en perfiles,
-- creador en barberias, o ambos).
select 'C) barbería a borrar ('||tb.origen||')', tb.nombre, tb.barberia_id, null::bigint
from target_barberias tb

union all

-- (4) ALERTA: perfiles vinculados a estos negocios cuyo email NO está en tu
-- lista. Si aparece algo acá, PARAR antes de armar el DELETE — puede ser
-- una cuenta real (ej. un profesional invitado con su email personal a un
-- negocio que terminó siendo de prueba).
select 'D) ⚠️ perfil NO listado en este negocio — revisar', u.email, tb.barberia_id, null::bigint
from target_barberias tb
join perfiles p on p.barberia_id = tb.barberia_id
join auth.users u on u.id = p.id
where u.email not in (select email from target_emails)

union all

-- (5) Conteo de filas por tabla, por cada barbería a borrar.
select 'E) perfiles', b.nombre, tb.barberia_id, (select count(*) from perfiles x where x.barberia_id = tb.barberia_id)
from target_barberias tb join barberias b on b.id = tb.barberia_id
union all
select 'E) clientes', b.nombre, tb.barberia_id, (select count(*) from clientes x where x.barberia_id = tb.barberia_id)
from target_barberias tb join barberias b on b.id = tb.barberia_id
union all
select 'E) visitas', b.nombre, tb.barberia_id, (select count(*) from visitas x where x.barberia_id = tb.barberia_id)
from target_barberias tb join barberias b on b.id = tb.barberia_id
union all
select 'E) reservas', b.nombre, tb.barberia_id, (select count(*) from reservas x where x.barberia_id = tb.barberia_id)
from target_barberias tb join barberias b on b.id = tb.barberia_id
union all
select 'E) servicios', b.nombre, tb.barberia_id, (select count(*) from servicios x where x.barberia_id = tb.barberia_id)
from target_barberias tb join barberias b on b.id = tb.barberia_id
union all
select 'E) barberos', b.nombre, tb.barberia_id, (select count(*) from barberos x where x.barberia_id = tb.barberia_id)
from target_barberias tb join barberias b on b.id = tb.barberia_id
union all
select 'E) horario_negocio', b.nombre, tb.barberia_id, (select count(*) from horario_negocio x where x.barberia_id = tb.barberia_id)
from target_barberias tb join barberias b on b.id = tb.barberia_id
union all
select 'E) bloqueos_profesional', b.nombre, tb.barberia_id, (select count(*) from bloqueos_profesional x where x.barberia_id = tb.barberia_id)
from target_barberias tb join barberias b on b.id = tb.barberia_id
union all
select 'E) alianzas', b.nombre, tb.barberia_id, (select count(*) from alianzas x where x.barberia_id = tb.barberia_id)
from target_barberias tb join barberias b on b.id = tb.barberia_id
union all
select 'E) alianza_codigos', b.nombre, tb.barberia_id, (select count(*) from alianza_codigos x where x.barberia_id = tb.barberia_id)
from target_barberias tb join barberias b on b.id = tb.barberia_id
union all
select 'E) alianza_canjes', b.nombre, tb.barberia_id, (select count(*) from alianza_canjes x where x.barberia_id = tb.barberia_id)
from target_barberias tb join barberias b on b.id = tb.barberia_id
union all
select 'E) barbero_servicios', b.nombre, tb.barberia_id, (select count(*) from barbero_servicios x where x.barberia_id = tb.barberia_id)
from target_barberias tb join barberias b on b.id = tb.barberia_id
union all
select 'E) niveles_vip', b.nombre, tb.barberia_id, (select count(*) from niveles_vip x where x.barberia_id = tb.barberia_id)
from target_barberias tb join barberias b on b.id = tb.barberia_id
union all
select 'E) vip_historial', b.nombre, tb.barberia_id, (select count(*) from vip_historial x where x.barberia_id = tb.barberia_id)
from target_barberias tb join barberias b on b.id = tb.barberia_id
union all
select 'E) plantillas_mensajes', b.nombre, tb.barberia_id, (select count(*) from plantillas_mensajes x where x.barberia_id = tb.barberia_id)
from target_barberias tb join barberias b on b.id = tb.barberia_id
union all
select 'E) costos', b.nombre, tb.barberia_id, (select count(*) from costos x where x.barberia_id = tb.barberia_id)
from target_barberias tb join barberias b on b.id = tb.barberia_id
union all
select 'E) inventario', b.nombre, tb.barberia_id, (select count(*) from inventario x where x.barberia_id = tb.barberia_id)
from target_barberias tb join barberias b on b.id = tb.barberia_id
union all
select 'E) movimientos_stock', b.nombre, tb.barberia_id, (select count(*) from movimientos_stock x where x.barberia_id = tb.barberia_id)
from target_barberias tb join barberias b on b.id = tb.barberia_id

union all

-- (6) Otros emails con patrón de prueba que NO estaban en tu lista — por si
-- quedó algo de sesiones más viejas. No se tocan en el DELETE que sigue,
-- son solo para que decidas si hay que sumarlos a una segunda pasada.
select 'F) 🔎 patrón similar, NO listado — revisar aparte', u.email, null::uuid, null::bigint
from auth.users u
where (u.email ilike 'claude-diag-%' or u.email ilike 'reservia.test.%' or u.email ilike 'diag-%')
  and u.email not in (select email from target_emails)

order by 1, 2;
