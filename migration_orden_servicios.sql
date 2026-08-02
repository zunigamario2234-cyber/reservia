-- Orden manual de servicios: el dueño decide en qué orden aparecen sus
-- servicios en las páginas de reserva, en vez de que manden el precio o el
-- alfabeto.
--
-- QUÉ HAY HOY. Tres vistas ordenan por precio ascendente (reservar.html,
-- club.html, mi-agenda.html) y app.html ordena alfabético — o sea el dueño ve
-- sus servicios en un orden distinto al que ven sus clientes. Con esta columna
-- las cuatro pasan a usar el mismo criterio.
--
-- POR QUÉ EL BACKFILL NO ES OPCIONAL. Si la columna naciera en null o en 0, el
-- día que se aplique cambiaría solo el orden de las páginas públicas, sin que
-- el dueño haya tocado nada. Se rellena con el orden que YA se ve hoy (precio
-- ascendente), así aplicar esto no cambia nada visible hasta que él mueva algo.
--
-- ORDEN DE APLICACIÓN — IMPORTA. Esta migración va ANTES de desplegar el
-- código que ordena por esta columna. Al revés, las páginas públicas pedirían
-- una columna que no existe, PostgREST devolvería 400 y la lista de servicios
-- quedaría vacía: un cliente entrando a reservar vería "No hay servicios
-- disponibles" y el negocio perdería reservas reales mientras dure.
--
-- Se deja NULLABLE a propósito, sin default: app.html escribe max+1 al crear un
-- servicio, y las lecturas ordenan con nulls al final más el precio como
-- desempate. Así una fila que se cuele en null se va al final en vez de
-- desordenar la lista entera.
--
-- Ejecutar UNA VEZ en el SQL Editor de Supabase. No define funciones, así que
-- acá begin;/commit; sí es seguro — y conviene, porque son dos sentencias que
-- tienen que quedar juntas: la columna sin su backfill es justamente el estado
-- que se quiere evitar.

begin;

alter table servicios add column if not exists orden integer;

-- El "where orden is null" hace esto repetible: si se corre de nuevo, no
-- renumera lo que el dueño ya haya acomodado a mano.
with r as (
  select id,
         row_number() over (partition by barberia_id order by precio, nombre) as n
  from servicios
  where orden is null
)
update servicios s
set orden = r.n
from r
where r.id = s.id;

commit;

-- =============================================================================
-- VERIFICACIÓN — correr DESPUÉS, por separado.
-- =============================================================================
--
-- PASO 1 — La columna existe y no quedó ninguna fila sin orden.
-- sin_orden tiene que ser 0.
--
-- select count(*) as total,
--        count(orden) as con_orden,
--        count(*) - count(orden) as sin_orden
-- from servicios;
--
-- PASO 2 — Dentro de cada negocio el orden es único y arranca en 1.
-- No tiene que devolver ninguna fila.
--
-- select barberia_id, orden, count(*)
-- from servicios
-- group by barberia_id, orden
-- having count(*) > 1;
--
-- PASO 3 — El orden nuevo coincide con el que se ve hoy (precio ascendente).
-- Mirar que la columna "orden" suba junto con el precio dentro de cada negocio.
--
-- select b.nombre as negocio, s.orden, s.nombre, s.precio
-- from servicios s
-- join barberias b on b.id = s.barberia_id
-- order by b.nombre, s.orden;
