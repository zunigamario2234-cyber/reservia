-- Limpieza de datos de prueba de producción — 2026-09-11.
--
-- NO ES UNA MIGRACIÓN. No cambia el esquema ni define funciones: borra filas
-- concretas, una sola vez. Se guarda en el repo porque dentro de seis meses la
-- pregunta va a ser "¿qué pasó con las tres visitas de $15.000 de julio?", y
-- este archivo es la respuesta.
--
-- QUÉ SE BORRA Y POR QUÉ
-- Cinco fichas de `clientes` que son del entorno de prueba del dueño, mezcladas
-- con clientes reales en la misma base. Confirmado por él: nada de esto se
-- declaró, ningún aliado real está involucrado, y ningún profesional real
-- cobró comisión de verdad por estas ventas.
--
--   150cc10d-…  ficha de prueba A   Sintonia Salon
--   4d34a83b-…  ficha de prueba B   Sintonia Salon  (la del código de alianza)
--   2e8afe08-…  ficha de prueba C   Sintonia Salon
--   0bdcb8e6-…  ficha de prueba D   Sintonia Salon
--   21acbbbf-…  ficha de prueba E   zbarber
--
-- ⚠ POR QUÉ VAN POR ID Y NO POR NOMBRE — esto casi sale mal.
-- El primer filtro buscaba por NOMBRE, con una lista de nombres de pila. Y
-- arrastró a una ficha REAL de Essentials Studio (28c9379b-…), el negocio de
-- verdad: su nombre de pila coincidía con el de una ficha de prueba de otro
-- negocio. Se detectó porque la consulta de inventario mostraba
-- `barberia_id` y el nombre del negocio. Un delete por nombre habría borrado
-- una ficha real y sus reservas sin que nadie se enterara.
--
-- Los nombres de persona no son identificadores. Acá van ids literales, y el
-- PASO 0 los muestra con su negocio antes de tocar nada.
--
-- ⚠ CINCO TABLAS, CUATRO COMPORTAMIENTOS DISTINTOS al borrar una ficha:
--   · alianza_canjes  → sin cláusula (NO ACTION): BLOQUEA vía alianza_codigos
--   · alianza_codigos → sin cláusula (NO ACTION): BLOQUEA el borrado
--   · visitas         → ON DELETE SET NULL: la visita SOBREVIVE, huérfana,
--                       con su plata intacta sumando en ventas e IVA
--   · vip_historial   → ON DELETE CASCADE: se borra en silencio (acá son 0)
--   · reservas        → SIN FK, se vinculan por WhatsApp en texto: quedan
--                       huérfanas y nadie avisa
--
-- De ahí el orden, y de ahí que `visitas` y `reservas` se borren EXPLÍCITAMENTE:
-- si solo se borraran las fichas, los $45.000 de julio seguirían contando.
--
-- Esto no define funciones, así que puede ir envuelto en begin;/commit;.


-- ═══════════════════════════════════════════════════════════════
-- PASO 0 — INVENTARIO. Correr SOLO esto primero y comparar los números.
--
-- Esperado, exactamente:
--   canjes 2 · codigos 1 · visitas 3 · reservas 12 · vip_historial 0
--
-- Si alguno difiere, PARAR: el borrado alcanzaría algo que no vimos.
-- ═══════════════════════════════════════════════════════════════

-- select
--   (select count(*) from alianza_canjes cj
--      where cj.codigo_id in (select id from alianza_codigos
--                             where cliente_id in (
--                               '150cc10d-b5e2-4212-a4ab-0eac40278a04',
--                               '4d34a83b-454c-44d2-9b46-5eb0d94232c2',
--                               '2e8afe08-641f-4373-996d-7fbcf5e322b8',
--                               '0bdcb8e6-9d38-4635-ac24-cfe59d7b52f1',
--                               '21acbbbf-b566-413f-ba1f-cc111caa85ec'))) as canjes,
--   (select count(*) from alianza_codigos
--      where cliente_id in (
--        '150cc10d-b5e2-4212-a4ab-0eac40278a04','4d34a83b-454c-44d2-9b46-5eb0d94232c2',
--        '2e8afe08-641f-4373-996d-7fbcf5e322b8','0bdcb8e6-9d38-4635-ac24-cfe59d7b52f1',
--        '21acbbbf-b566-413f-ba1f-cc111caa85ec')) as codigos,
--   (select count(*) from visitas
--      where cliente_id in (
--        '150cc10d-b5e2-4212-a4ab-0eac40278a04','4d34a83b-454c-44d2-9b46-5eb0d94232c2',
--        '2e8afe08-641f-4373-996d-7fbcf5e322b8','0bdcb8e6-9d38-4635-ac24-cfe59d7b52f1',
--        '21acbbbf-b566-413f-ba1f-cc111caa85ec')) as visitas,
--   (select count(*) from vip_historial
--      where cliente_id in (
--        '150cc10d-b5e2-4212-a4ab-0eac40278a04','4d34a83b-454c-44d2-9b46-5eb0d94232c2',
--        '2e8afe08-641f-4373-996d-7fbcf5e322b8','0bdcb8e6-9d38-4635-ac24-cfe59d7b52f1',
--        '21acbbbf-b566-413f-ba1f-cc111caa85ec')) as vip_historial,
--   (select count(*) from reservas r where exists (
--      select 1 from clientes c
--      where c.id in (
--        '150cc10d-b5e2-4212-a4ab-0eac40278a04','4d34a83b-454c-44d2-9b46-5eb0d94232c2',
--        '2e8afe08-641f-4373-996d-7fbcf5e322b8','0bdcb8e6-9d38-4635-ac24-cfe59d7b52f1',
--        '21acbbbf-b566-413f-ba1f-cc111caa85ec')
--        and coalesce(c.whatsapp_norm,'') <> ''
--        and c.barberia_id = r.barberia_id
--        and c.whatsapp_norm = r.whatsapp_norm)) as reservas;


-- ═══════════════════════════════════════════════════════════════
-- PASO 0b — LA FOTO DE ESSENTIALS STUDIO, el negocio REAL.
--
-- Anota estos tres números antes de borrar. Después del borrado tienen que ser
-- IDÉNTICOS. Es la comprobación de que la limpieza no cruzó de negocio — que es
-- exactamente el error que el filtro por nombre estuvo a punto de cometer.
-- ═══════════════════════════════════════════════════════════════

-- select
--   (select count(*) from clientes where barberia_id = '1f97f706-4fcc-4965-a49c-9d29c2b94bbe') as fichas,
--   (select count(*) from visitas  where barberia_id = '1f97f706-4fcc-4965-a49c-9d29c2b94bbe') as visitas,
--   (select count(*) from reservas where barberia_id = '1f97f706-4fcc-4965-a49c-9d29c2b94bbe') as reservas;


-- ═══════════════════════════════════════════════════════════════
-- EL BORRADO. Correr después de confirmar los números del PASO 0.
--
-- El orden NO es negociable:
--   · los canjes antes que el código, y el código antes que las fichas, porque
--     los dos bloquean con NO ACTION;
--   · las RESERVAS antes que las fichas, porque se identifican cruzando contra
--     `clientes` por whatsapp_norm — borrada la ficha, ya no hay con qué
--     encontrarlas y quedarían huérfanas para siempre.
-- ═══════════════════════════════════════════════════════════════

begin;

-- (1) Los dos canjes del código del aliado ficticio.
delete from alianza_canjes
where codigo_id in (
  select id from alianza_codigos
  where cliente_id in (
    '150cc10d-b5e2-4212-a4ab-0eac40278a04',
    '4d34a83b-454c-44d2-9b46-5eb0d94232c2',
    '2e8afe08-641f-4373-996d-7fbcf5e322b8',
    '0bdcb8e6-9d38-4635-ac24-cfe59d7b52f1',
    '21acbbbf-b566-413f-ba1f-cc111caa85ec'));

-- (2) El código de alianza. Bloqueaba el borrado de la ficha de prueba B.
delete from alianza_codigos
where cliente_id in (
  '150cc10d-b5e2-4212-a4ab-0eac40278a04',
  '4d34a83b-454c-44d2-9b46-5eb0d94232c2',
  '2e8afe08-641f-4373-996d-7fbcf5e322b8',
  '0bdcb8e6-9d38-4635-ac24-cfe59d7b52f1',
  '21acbbbf-b566-413f-ba1f-cc111caa85ec');

-- (3) Las tres visitas de $15.000 de julio, con sus $7.500 de comisión cada
-- una. ESTE es el paso que corrige los números: con ON DELETE SET NULL, borrar
-- solo las fichas las habría dejado huérfanas y sumando igual.
delete from visitas
where cliente_id in (
  '150cc10d-b5e2-4212-a4ab-0eac40278a04',
  '4d34a83b-454c-44d2-9b46-5eb0d94232c2',
  '2e8afe08-641f-4373-996d-7fbcf5e322b8',
  '0bdcb8e6-9d38-4635-ac24-cfe59d7b52f1',
  '21acbbbf-b566-413f-ba1f-cc111caa85ec');

-- (4) Las 12 reservas. ANTES que las fichas: sin ellas no hay forma de
-- encontrarlas, porque `reservas` no tiene cliente_id.
--
-- ⚠ El `coalesce(c.whatsapp_norm,'') <> ''` no es decorativo. Sin esa guarda,
-- una ficha sin teléfono tendría whatsapp_norm = '' y matchearía contra TODAS
-- las reservas sin teléfono de ese negocio. Las cinco tienen número, así que
-- hoy no cambia nada — pero es la diferencia entre borrar 12 filas y borrar
-- muchas más, y no se ve hasta que pasa.
--
-- El `c.barberia_id = r.barberia_id` tampoco: dos de estas fichas de prueba,
-- una en cada negocio, comparten el mismo número de teléfono. Sin el scoping por
-- negocio, borrar uno se llevaría las reservas del otro.
delete from reservas r
where exists (
  select 1 from clientes c
  where c.id in (
      '150cc10d-b5e2-4212-a4ab-0eac40278a04',
      '4d34a83b-454c-44d2-9b46-5eb0d94232c2',
      '2e8afe08-641f-4373-996d-7fbcf5e322b8',
      '0bdcb8e6-9d38-4635-ac24-cfe59d7b52f1',
      '21acbbbf-b566-413f-ba1f-cc111caa85ec')
    and coalesce(c.whatsapp_norm,'') <> ''
    and c.barberia_id = r.barberia_id
    and c.whatsapp_norm = r.whatsapp_norm);

-- (5) Las cinco fichas. `vip_historial` se va sola por su ON DELETE CASCADE
-- (acá son 0 filas, pero conviene saber que ese camino existe).
delete from clientes
where id in (
  '150cc10d-b5e2-4212-a4ab-0eac40278a04',
  '4d34a83b-454c-44d2-9b46-5eb0d94232c2',
  '2e8afe08-641f-4373-996d-7fbcf5e322b8',
  '0bdcb8e6-9d38-4635-ac24-cfe59d7b52f1',
  '21acbbbf-b566-413f-ba1f-cc111caa85ec');

commit;


-- ═══════════════════════════════════════════════════════════════
-- VERIFICACIÓN (correr DESPUÉS, cada paso por separado)
-- ═══════════════════════════════════════════════════════════════

-- PASO 6 — No queda nada de las cinco fichas.
-- Esperado: los cinco contadores en 0. Es el PASO 0 otra vez, palabra por
-- palabra: si alguno no dio 0, quedó algo sin borrar.
-- (Volver a correr el PASO 0 tal cual.)


-- PASO 7 — LA QUE IMPORTA: Essentials Studio intacto.
-- Esperado: los tres números IDÉNTICOS a los del PASO 0b.
-- Si alguno bajó, la limpieza cruzó de negocio y hay que restaurar.
-- (Volver a correr el PASO 0b tal cual.)


-- PASO 8 — Julio quedó corregido.
-- Esperado: ninguna fila con esas tres visitas de $15.000 a nombre de "mario"
-- en Sintonia Salon. El total de julio de ese negocio baja $45.000 y las
-- comisiones $22.500.
--
-- select fecha, servicio, valor, comision_monto, barbero_nombre
-- from visitas
-- where barberia_id = '5d883a97-0f2b-4381-849d-97800444a7b8'
--   and fecha between '2026-07-01' and '2026-07-31'
-- order by fecha;


-- PASO 9 — No quedaron visitas huérfanas de este borrado.
-- `visitas.cliente_id` es ON DELETE SET NULL, así que si alguna visita de las
-- cinco fichas se hubiera escapado del paso (3), ahora estaría con cliente_id
-- nulo en vez de borrada — invisible en "Por cliente" y sumando igual.
--
-- Esperado: cero filas en julio. Las de otros meses, si las hay, son
-- anteriores a esta limpieza y no salen de acá.
--
-- select fecha, servicio, valor, barbero_nombre
-- from visitas
-- where barberia_id = '5d883a97-0f2b-4381-849d-97800444a7b8'
--   and cliente_id is null
-- order by fecha;
