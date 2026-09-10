-- Intervalo de horarios configurable por negocio.
--
-- POR QUÉ
-- Hoy la grilla de reservas arranca cada 30 minutos y ese número está escrito a
-- mano en el código (`PASO_MIN` en reservar.html, `R_PASO_MIN` en club.html).
-- Un negocio cuyos servicios duran 45 o 60 minutos ve la mitad de los botones
-- muertos: se ofrecen las 10:30 y las 11:30 y ninguna de las dos cabe. Peor,
-- el cliente elige la primera hora libre que ve, y al negocio le queda la
-- agenda picada en huecos de 15 minutos que no se venden.
--
-- QUÉ ES Y QUÉ NO ES
-- Esto define CADA CUÁNTO PUEDE EMPEZAR una cita, no cuánto dura ni cuánto
-- cierra. La duración sigue viniendo del servicio y el cierre de
-- horario_negocio: el cálculo de si una cita CABE (cabeEnLaJornada) no cambia.
--
-- ALCANCE: SOLO LAS PÁGINAS PÚBLICAS
-- reservar.html y club.html. La agenda del dueño en app.html sigue pintando
-- bloques de 30 minutos (AG_SLOT_MIN): tiene su propio cálculo de posiciones en
-- píxeles y arrastrarlo no aporta nada, porque el dueño carga la hora a mano
-- con un campo de tipo `time` y nunca estuvo limitado a la grilla.
--
-- QUÉ PASA CON LAS RESERVAS YA TOMADAS SI EL DUEÑO CAMBIA EL INTERVALO
-- Nada se rompe, y conviene saber por qué. Si había una cita a las 10:30 y el
-- negocio pasa a bloques de 60, las 10:30 dejan de ofrecerse pero la cita sigue
-- ahí y sigue bloqueando: el choque se calcula por rangos reales
-- ([inicio, inicio+duración)), no comparando la hora contra la grilla. Lo único
-- que cambia es qué horas nuevas se ofrecen de ahí en adelante.
--
-- ═══════════════════════════════════════════════════════════════
-- POR QUÉ UN CHECK Y NO TEXTO LIBRE
-- Un intervalo de 7 minutos, o de 0, no es una preferencia rara: es una grilla
-- rota o un bucle infinito en `for(m=ini; m<fin; m+=PASO)`. El CHECK deja la
-- lista de valores permitidos en un solo lugar, y agregar uno nuevo (20, 90)
-- después es una línea.
--
-- La lista TIENE QUE COINCIDIR con las opciones del <select> de Config en
-- app.html. test-intervalo-horarios.html compara las dos y falla si se separan:
-- si divergen, el dueño elige una opción y la base se la rechaza con un error
-- de constraint que no le dice nada.
--
-- Esta migración NO define funciones, así que puede ir envuelta en
-- begin;/commit; sin el problema del dollar-quoting del SQL Editor.
-- ═══════════════════════════════════════════════════════════════

begin;

-- PASO 1: la columna.
-- `not null default 30` deja a todos los negocios existentes exactamente como
-- están hoy: 30 minutos es el valor que ya corría hardcodeado. Nadie ve un
-- cambio hasta que lo toque en Config.
alter table barberias
  add column if not exists intervalo_min smallint not null default 30;

-- PASO 2: red por si la columna ya existía de antes sin el default.
-- Con el `add column` de arriba esto no toca ninguna fila; queda porque un
-- `add column if not exists` que encuentra la columna ya creada NO le aplica
-- el not null ni el default, y ahí un null haría pasar el CHECK igual
-- (null no viola un check) y reventaría recién en el JavaScript.
update barberias set intervalo_min = 30 where intervalo_min is null;

-- PASO 3: los valores permitidos.
-- El drop previo hace la migración repetible: correrla dos veces no falla.
alter table barberias
  drop constraint if exists barberias_intervalo_min_valido;

alter table barberias
  add constraint barberias_intervalo_min_valido
  check (intervalo_min in (30, 45, 60));

commit;


-- ═══════════════════════════════════════════════════════════════
-- VERIFICACIÓN (correr DESPUÉS, cada paso por separado)
-- ═══════════════════════════════════════════════════════════════

-- PASO 1 — La columna existe, es not null y su default es 30.
-- Esperado: 1 fila → intervalo_min | smallint | NO | 30
--
-- select column_name, data_type, is_nullable, column_default
-- from information_schema.columns
-- where table_name = 'barberias' and column_name = 'intervalo_min';


-- PASO 2 — Ningún negocio quedó sin intervalo, y todos en 30.
-- Esperado: 1 fila → total = <cantidad de negocios>, en_30 = el mismo número,
-- nulos = 0. Si en_30 no coincide con total, alguien ya lo cambió (imposible
-- todavía: el panel aún no lo guarda).
--
-- select count(*) as total,
--        count(*) filter (where intervalo_min = 30) as en_30,
--        count(*) filter (where intervalo_min is null) as nulos
-- from barberias;


-- PASO 3 — El CHECK está puesto y dice lo que tiene que decir.
-- Esperado: 1 fila con la definición → CHECK ((intervalo_min = ANY (ARRAY[30, 45, 60])))
--
-- select conname, pg_get_constraintdef(oid) as definicion
-- from pg_constraint
-- where conrelid = 'barberias'::regclass
--   and conname = 'barberias_intervalo_min_valido';


-- PASO 4 — El CHECK RECHAZA de verdad un valor inválido.
-- Un constraint que nunca rechaza nada no prueba nada. Esto tiene que FALLAR
-- con: new row for relation "barberias" violates check constraint
-- "barberias_intervalo_min_valido".
-- Va envuelto en begin;/rollback; — no deja rastro ni siquiera si pasara.
--
-- begin;
--   update barberias set intervalo_min = 7
--   where id = (select id from barberias order by created_at limit 1);
-- rollback;


-- PASO 5 — Los tres valores permitidos SÍ entran.
-- Esperado: los tres updates pasan sin error. Igual que el anterior, envuelto
-- en begin;/rollback;: la base queda como estaba.
--
-- begin;
--   update barberias set intervalo_min = 45
--   where id = (select id from barberias order by created_at limit 1);
--   update barberias set intervalo_min = 60
--   where id = (select id from barberias order by created_at limit 1);
--   update barberias set intervalo_min = 30
--   where id = (select id from barberias order by created_at limit 1);
--   select intervalo_min from barberias order by created_at limit 1;
-- rollback;


-- PASO 6 — EL QUE DE VERDAD IMPORTA: quién puede LEER y ESCRIBIR la columna.
-- Los permisos de PostgREST pueden estar dados por tabla o columna por
-- columna. Si estuvieran SOLO por columna, la columna nueva no los tendría:
-- una columna recién creada nace con attacl = NULL, sin ningún permiso propio.
-- Y pasarían las dos cosas peores posibles, las dos en silencio:
--   · reservar.html leería intervalo_min = undefined y volvería a 30 sin avisar
--   · el panel guardaría Config y el intervalo no cambiaría nunca
--
-- ⚠ CÓMO SE LEE ESTA VISTA, QUE NO ES OBVIO:
-- information_schema.column_privileges devuelve una fila por columna SIEMPRE,
-- incluso cuando el permiso se otorgó a nivel de TABLA — la vista es la unión
-- de dos ramas, y una de ellas expande el ACL de la tabla sobre todas sus
-- columnas. Muchas filas NO significa "hay permisos por columna". Este archivo
-- decía lo contrario en su primera versión y era falso.
--
-- Esperado: que `intervalo_min` aparezca con los MISMOS privilegios que el
-- resto de las columnas (SELECT/INSERT/UPDATE/REFERENCES para anon y
-- authenticated). Eso solo puede venir del permiso de TABLA, porque nadie
-- otorgó nada sobre una columna creada hace un minuto — y es exactamente lo
-- que hace falta.
--
-- Si `intervalo_min` NO aparece, o aparece con menos privilegios que las demás,
-- hay permisos por columna y hay que agregar la nueva a mano: para ahí y
-- avísame antes de que yo toque el código.
--
-- select grantee, privilege_type, column_name
-- from information_schema.column_privileges
-- where table_schema = 'public'
--   and table_name = 'barberias'
--   and grantee in ('anon', 'authenticated')
-- order by grantee, privilege_type, column_name;


-- PASO 6b — Confirmación del mecanismo (opcional: no bloquea el despliegue).
-- Esta sí distingue, porque mira attacl directo en vez de la vista expandida.
-- Esperado: CERO filas — no existe ningún permiso por columna en la tabla y
-- todo viene del ACL de la tabla.
--
-- select a.attname, a.attacl
-- from pg_attribute a
-- where a.attrelid = 'public.barberias'::regclass
--   and a.attnum > 0
--   and not a.attisdropped
--   and a.attacl is not null;


-- PASO 7 — Confirmación de que anon puede leer la columna nueva.
-- Complemento del anterior: mira el permiso a nivel TABLA. Esperado: al menos
-- una fila con grantee = 'anon' y privilege_type = 'SELECT'. Si no aparece,
-- la página pública de reservas no puede leer barberias — y entonces tampoco
-- podría leer el nombre del negocio, así que si hoy funciona, esto sale bien.
--
-- select grantee, privilege_type
-- from information_schema.role_table_grants
-- where table_schema = 'public'
--   and table_name = 'barberias'
--   and grantee in ('anon', 'authenticated')
-- order by grantee, privilege_type;
