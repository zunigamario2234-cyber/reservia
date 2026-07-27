-- Diagnóstico: por qué "diego" no matchea con ningún profesional.
-- SOLO LECTURA. Distingue cuatro causas posibles, en orden de qué tan
-- barato es el arreglo:
--   (a) mayúsculas/espacios  -> el profesional existe, el match es muy estricto
--   (b) otro negocio         -> existe pero en otra barbería (no es un error)
--   (c) inactivo             -> existe, activo=false
--   (d) eliminado/renombrado -> no existe en ninguna parte

-- ═══════════════════════════════════════════════════════════════
-- (1) ¿Existe algún "diego" en barberos, en CUALQUIER negocio,
-- ignorando mayúsculas y espacios? Esta sola consulta descarta (d).
-- ═══════════════════════════════════════════════════════════════
select
  ba.id,
  ba.nombre,
  '['|| ba.nombre ||']'                as nombre_con_delimitadores,
  ba.activo,
  coalesce(ba.email, '(sin email)')    as email,
  b.nombre                             as negocio,
  ba.barberia_id
from barberos ba
join barberias b on b.id = ba.barberia_id
where lower(btrim(ba.nombre)) like '%diego%';

-- ═══════════════════════════════════════════════════════════════
-- (2) Las reservas de "diego": en qué negocio están y cómo quedó
-- guardado el texto exacto. Los delimitadores [] hacen visible
-- cualquier espacio al principio o al final.
-- ═══════════════════════════════════════════════════════════════
select
  r.id,
  '['|| r.barbero_nombre ||']'  as barbero_nombre_exacto,
  r.fecha,
  r.estado,
  r.fuente,
  b.nombre                      as negocio,
  r.barberia_id
from reservas r
join barberias b on b.id = r.barberia_id
where lower(btrim(r.barbero_nombre)) like '%diego%'
order by r.fecha desc;

-- ═══════════════════════════════════════════════════════════════
-- (3) LA consulta que decide el diseño del resolver.
-- Para cada reserva que hoy NO matchea de forma exacta, prueba si
-- matchearía relajando mayúsculas y espacios, DENTRO DEL MISMO
-- NEGOCIO (nunca cruzando barberia_id).
-- Si "diego" aparece acá con matches_relajado = 1, la causa es (a)
-- y se arregla en el resolver sin tocar un solo dato.
-- ═══════════════════════════════════════════════════════════════
select
  r.barbero_nombre,
  r.barberia_id,
  count(*) as reservas,
  (select count(*) from barberos ba
    where ba.barberia_id = r.barberia_id
      and lower(btrim(ba.nombre)) = lower(btrim(r.barbero_nombre))
  ) as matches_relajado
from reservas r
where r.barbero_nombre <> 'Por asignar'
  and not exists (
    select 1 from barberos ba
    where ba.barberia_id = r.barberia_id
      and ba.nombre = r.barbero_nombre
  )
group by r.barbero_nombre, r.barberia_id
order by reservas desc;

-- ═══════════════════════════════════════════════════════════════
-- (4) Los dos "mario": confirmar que están en negocios DISTINTOS.
-- Si barberia_id difiere, el scoping por negocio en el resolver no es
-- una precaución teórica: es lo único que evita que el aviso de una
-- reserva le llegue al mario del otro negocio.
-- ═══════════════════════════════════════════════════════════════
select
  ba.id,
  ba.nombre,
  ba.activo,
  coalesce(ba.email, '(sin email)')  as email,
  ba.barberia_id,
  b.nombre                           as negocio
from barberos ba
join barberias b on b.id = ba.barberia_id
where lower(btrim(ba.nombre)) = 'mario'
order by b.nombre;

-- ═══════════════════════════════════════════════════════════════
-- (5) Riesgo general de homónimos: ¿hay algún nombre repetido DENTRO
-- de un mismo negocio (ignorando mayúsculas)? Si esto devuelve filas,
-- el resolver no puede elegir por nombre sin ambigüedad y debe
-- abstenerse de enviar en esos casos.
-- ═══════════════════════════════════════════════════════════════
select
  barberia_id,
  lower(btrim(nombre))  as nombre_normalizado,
  count(*)              as cuantos
from barberos
group by barberia_id, lower(btrim(nombre))
having count(*) > 1;
