-- Recuperar los correos que los clientes YA escribieron y nunca llegaron a su
-- ficha.
--
-- POR QUÉ
-- reservar.html hace el correo OBLIGATORIO y lo guarda en
-- reservas.email_cliente. Pero las tres RPCs que crean la ficha del cliente
-- (buscar_o_crear_cliente_club, registrar_cobro_conjunto,
-- mi_agenda_procesar_pago) insertan sin esa columna. Resultado: el dato está
-- en la base desde el primer día y la ficha figura sin correo.
--
-- Esto NO arregla la causa — eso va en la migración de las tres funciones, que
-- tiene que correr también. Esto rescata lo ya perdido.
--
-- ⚠ ORDEN: da igual cuál corra primero. Son independientes: una mira hacia
-- atrás y la otra hacia adelante. Pero las DOS tienen que correr, o se arregla
-- la mitad del problema.
--
-- ═══════════════════════════════════════════════════════════════
-- LAS TRES TRAMPAS DEL CRUCE
--
-- 1. EL FORMATO DEL TELÉFONO. Las RPCs matchean con
--    `c.whatsapp = r.whatsapp_cliente`, texto exacto, y en la base conviven
--    cuatro formatos del mismo número ('+56 9 8754 2136', '+56987542136',
--    '56987542136', '987542136'). Un match exacto acá dejaría afuera
--    justamente a los clientes cuya ficha se creó con otro formato.
--    Este backfill usa whatsapp_norm, la columna generada que ya existe en las
--    DOS tablas. Matchea más, y es el criterio correcto para mirar el pasado.
--
--    ⚠ A propósito, esto es MÁS generoso que lo que hacen las RPCs en vivo. No
--    se están cambiando ellas: cambiarles el criterio haría que empiecen a
--    encontrar fichas que hoy no encuentran, lo que mueve a qué ficha se le
--    suman las visitas y corre reportes históricos. Eso es la deuda del
--    WhatsApp y es un proyecto propio.
--
-- 2. TELÉFONOS COMPARTIDOS ENTRE PERSONAS DISTINTAS. Una pareja, un papá con
--    su hijo. Sin guardia, el correo de uno termina en la ficha del otro — y
--    eso no es un dato mal puesto, es mandarle a una persona los correos de
--    otra. Se compara el PRIMER nombre, mismo criterio que
--    get_proximas_reservas_publico: el nombre completo bloquearía también a
--    todas las fichas duplicadas de la MISMA persona ("Felipe Guerra" /
--    "Felipe"), que son la mayoría de los casos de teléfono repetido.
--
-- 3. VARIOS CORREOS PARA EL MISMO TELÉFONO. La persona cambió de correo, o se
--    equivocó una vez. Se toma el MÁS RECIENTE no vacío, por fecha y hora de
--    la reserva.
--
-- 4. CORREOS DE PRUEBA DE OTRAS CUENTAS. Detectado en el ensayo del 2026-09-10:
--    'sintoniasalon@gmail.com' aparecía en las reservas de "leandro martinez",
--    "luis vera" y "pruba 2" — datos de prueba del dueño desde otras cuentas
--    suyas, no el correo de esas personas. Se excluye LA DIRECCIÓN, no los tres
--    clientes: así una cuarta reserva con ese mismo correo, hoy o mañana, queda
--    afuera sola.
--
--    La lista está en un `<> all (array[...])` repetido en cada paso. Agregar
--    otra dirección es un elemento más, pero HAY QUE AGREGARLA EN TODOS LOS
--    PASOS o el ensayo deja de mostrar lo que el update va a hacer. El PASO 8
--    de verificación existe justamente para cazar esa divergencia.
--
--    NO se usa la regla general que parece obvia —"un correo en varias fichas
--    distintas es sospechoso"—: en el mismo ensayo apareció Bruno Otarola con
--    el correo de su mamá, que agendó por él. Es correcto y tiene que entrar.
--    Un correo compartido entre familiares es normal; esa heurística lo
--    rompería.
--
-- Y sobre todo: SOLO fichas con el correo vacío. Nunca se pisa uno cargado.
-- Es la misma regla que decidirEmailFicha() en app.html, que existe desde el
-- cruce del panel: rellenar un campo vacío es aditivo y no pierde nada;
-- pisarlo sí, y el correo de la ficha normalmente lo escribió el propio
-- cliente, no un tercero transcribiendo por teléfono.
--
-- Esta migración NO define funciones, así que puede ir envuelta en
-- begin;/commit; sin el problema del dollar-quoting del SQL Editor.
-- ═══════════════════════════════════════════════════════════════


-- ═══════════════════════════════════════════════════════════════
-- PASO 1 — EL ENSAYO. Correr ESTO PRIMERO, solo, y mirar el resultado.
--
-- No escribe nada. Muestra exactamente qué fichas se tocarían y con qué
-- correo. Es más valioso que cualquier verificación posterior: acá se puede
-- decidir NO correr el update si algo se ve raro.
--
-- Mirar sobre todo: que el nombre de la ficha y el de la reserva sean la
-- misma persona, y que los correos tengan pinta de correos.
-- ═══════════════════════════════════════════════════════════════

-- with fichas_sin_correo as (
--   select c.id, c.barberia_id, c.nombre, c.whatsapp, c.whatsapp_norm,
--          lower(split_part(btrim(c.nombre), ' ', 1)) as primer_nombre
--   from clientes c
--   where coalesce(btrim(c.email), '') = ''
--     and coalesce(c.whatsapp_norm, '') <> ''
-- ),
-- candidatos as (
--   select f.id as cliente_id, f.nombre as ficha_nombre, f.whatsapp,
--          btrim(r.email_cliente) as email, r.nombre_cliente, r.fecha,
--          row_number() over (
--            partition by f.id order by r.fecha desc, r.hora desc
--          ) as rn
--   from fichas_sin_correo f
--   join reservas r
--     on r.barberia_id = f.barberia_id
--    and r.whatsapp_norm = f.whatsapp_norm
--    and coalesce(btrim(r.email_cliente), '') <> ''
--    and position('@' in btrim(r.email_cliente)) > 1
--    and lower(btrim(r.email_cliente)) <> all (array['sintoniasalon@gmail.com'])
--    and lower(split_part(btrim(r.nombre_cliente), ' ', 1)) = f.primer_nombre
-- )
-- select ficha_nombre, nombre_cliente, whatsapp, email, fecha as ultima_reserva
-- from candidatos
-- where rn = 1
-- order by ficha_nombre;


-- ═══════════════════════════════════════════════════════════════
-- PASO 2 — EL TAMAÑO. Los tres números que dicen si valió la pena.
--
-- Esperado: `se_rellenan` tiene que coincidir con la cantidad de filas del
-- PASO 1. Si `sin_correo` es mucho mayor que `se_rellenan`, la diferencia son
-- clientes que nunca dieron correo (altas por QR, cargas manuales) — esos van
-- a necesitar el canal de WhatsApp, no hay correo que rescatar.
-- ═══════════════════════════════════════════════════════════════

-- select
--   (select count(*) from clientes) as fichas,
--   (select count(*) from clientes
--      where coalesce(btrim(email),'') = '') as sin_correo,
--   (select count(*) from (
--      select f.id
--      from clientes f
--      join reservas r
--        on r.barberia_id = f.barberia_id
--       and r.whatsapp_norm = f.whatsapp_norm
--       and coalesce(btrim(r.email_cliente),'') <> ''
--       and position('@' in btrim(r.email_cliente)) > 1
--       and lower(btrim(r.email_cliente))
--           <> all (array['sintoniasalon@gmail.com'])
--       and lower(split_part(btrim(r.nombre_cliente),' ',1))
--           = lower(split_part(btrim(f.nombre),' ',1))
--      where coalesce(btrim(f.email),'') = ''
--        and coalesce(f.whatsapp_norm,'') <> ''
--      group by f.id
--    ) x) as se_rellenan;


-- ═══════════════════════════════════════════════════════════════
-- PASO 3 — LOS QUE QUEDAN AFUERA POR TELÉFONO COMPARTIDO.
--
-- Acá aparecen las fichas que TIENEN una reserva con correo y el mismo
-- teléfono, pero con OTRO primer nombre. Se saltan a propósito.
--
-- Esperado: pocas filas, y al mirarlas tiene que quedar claro que son personas
-- distintas. Si aparece la misma persona escrita distinto ("Jose" / "José"),
-- dime y lo vemos: puede valer un ajuste del criterio antes de correr nada.
-- ═══════════════════════════════════════════════════════════════

-- select distinct f.nombre as ficha_nombre, r.nombre_cliente as nombre_reserva,
--        f.whatsapp
-- from clientes f
-- join reservas r
--   on r.barberia_id = f.barberia_id
--  and r.whatsapp_norm = f.whatsapp_norm
--  and coalesce(btrim(r.email_cliente),'') <> ''
-- where coalesce(btrim(f.email),'') = ''
--   and coalesce(f.whatsapp_norm,'') <> ''
--   and lower(split_part(btrim(r.nombre_cliente),' ',1))
--       <> lower(split_part(btrim(f.nombre),' ',1))
-- order by f.nombre;


-- ═══════════════════════════════════════════════════════════════
-- PASO 4 — EL UPDATE. Correr SOLO después de mirar los pasos 1 a 3.
-- ═══════════════════════════════════════════════════════════════

begin;

with fichas_sin_correo as (
  select c.id, c.barberia_id, c.whatsapp_norm,
         lower(split_part(btrim(c.nombre), ' ', 1)) as primer_nombre
  from clientes c
  where coalesce(btrim(c.email), '') = ''
    and coalesce(c.whatsapp_norm, '') <> ''
),
candidatos as (
  select f.id as cliente_id,
         btrim(r.email_cliente) as email,
         row_number() over (
           partition by f.id order by r.fecha desc, r.hora desc
         ) as rn
  from fichas_sin_correo f
  join reservas r
    on r.barberia_id = f.barberia_id
   and r.whatsapp_norm = f.whatsapp_norm
   and coalesce(btrim(r.email_cliente), '') <> ''
   -- Filtro mínimo de basura: sin arroba, o con la arroba al principio, no es
   -- un correo. reservar.html solo valida includes('@'), así que algo así
   -- puede haber entrado.
   and position('@' in btrim(r.email_cliente)) > 1
   -- Correos de prueba de otras cuentas del dueño. Ver la trampa 4 arriba.
   -- Esta línea TIENE que ser idéntica a la de los pasos 1 y 2, o el ensayo
   -- deja de predecir lo que pasa acá. El PASO 8 lo verifica después.
   and lower(btrim(r.email_cliente)) <> all (array['sintoniasalon@gmail.com'])
   -- Teléfono compartido entre personas distintas. Ver la trampa 2 arriba.
   -- OJO: esto NO bloquea el correo de un familiar que agenda por otro. En el
   -- ensayo apareció Bruno Otarola con el correo de su mamá, que reservó a su
   -- nombre: el nombre de la reserva es el de Bruno, así que pasa el filtro y
   -- entra. Está bien que entre — es el correo por el que se le llega.
   and lower(split_part(btrim(r.nombre_cliente), ' ', 1)) = f.primer_nombre
)
update clientes c
   set email = k.email
  from candidatos k
 where c.id = k.cliente_id
   and k.rn = 1
   -- La regla que duele si se rompe, repetida acá y no solo en la CTE: es la
   -- que hace el update seguro por sí mismo, sin depender de lo que se leyó
   -- unos milisegundos antes.
   and coalesce(btrim(c.email), '') = '';

commit;


-- ═══════════════════════════════════════════════════════════════
-- VERIFICACIÓN (correr DESPUÉS, cada paso por separado)
-- ═══════════════════════════════════════════════════════════════

-- PASO 5 — Cuántas fichas quedaron con correo.
-- Esperado: `con_correo` subió exactamente en el `se_rellenan` del PASO 2.
--
-- select count(*) as fichas,
--        count(*) filter (where coalesce(btrim(email),'') <> '') as con_correo,
--        count(*) filter (where coalesce(btrim(email),'') = '') as sin_correo
-- from clientes;


-- PASO 6 — El ensayo del PASO 1 tiene que devolver CERO filas ahora.
-- Si sigue devolviendo filas, algo no se escribió y hay que mirarlo antes de
-- seguir. Volver a correr el PASO 1 tal cual.


-- PASO 7 — INVENTARIO de fichas con más de un correo dando vueltas.
--
-- ⚠ ESTE PASO NO ES UNA ALARMA, y su primera versión decía que sí. Marca las
-- fichas cuyo correo difiere de ALGUNA de sus reservas, que es lo normal en
-- cuanto alguien cambia de correo entre una cita y otra. El 2026-09-11
-- devolvió filas esperables — Luis Silva entre ellas, porque su ficha quedó
-- con el correo de una reserva y otra suya tiene el que excluimos. Nosotros lo
-- pusimos ahí a propósito.
--
-- Sirve para mirar la lista, no para contar filas. La alarma de verdad es el
-- PASO 7b.
--
-- select c.nombre, c.email as email_ficha,
--        string_agg(distinct btrim(r.email_cliente), ' | ') as emails_en_reservas
-- from clientes c
-- join reservas r
--   on r.barberia_id = c.barberia_id
--  and r.whatsapp_norm = c.whatsapp_norm
--  and coalesce(btrim(r.email_cliente),'') <> ''
-- where coalesce(btrim(c.email),'') <> ''
--   and lower(btrim(c.email)) <> lower(btrim(r.email_cliente))
-- group by c.id, c.nombre, c.email
-- order by c.nombre;


-- PASO 7b — LA ALARMA DE VERDAD: un correo que no salió de ninguna reserva.
--
-- La diferencia con el 7 es el `having bool_and(...)`: exige que el correo de
-- la ficha difiera de TODAS sus reservas, no de alguna. Eso es un correo que
-- el backfill no pudo haber escrito, porque solo sabe copiar de una reserva
-- que matchee.
--
-- Esperado: CERO filas.
-- Si devuelve alguna, es un correo cargado por otra vía —a mano, importación—
-- y hay que mirarlo antes de darle uso: es una ficha a la que la encuesta le
-- llegaría a una dirección que esa persona nunca dio.
--
-- select c.nombre, c.email as email_ficha,
--        string_agg(distinct btrim(r.email_cliente), ' | ') as emails_en_sus_reservas
-- from clientes c
-- join reservas r
--   on r.barberia_id = c.barberia_id
--  and r.whatsapp_norm = c.whatsapp_norm
--  and coalesce(btrim(r.email_cliente),'') <> ''
-- where coalesce(btrim(c.email),'') <> ''
-- group by c.id, c.nombre, c.email
-- having bool_and(lower(btrim(c.email)) <> lower(btrim(r.email_cliente)))
-- order by c.nombre;


-- PASO 8 — QUE NINGÚN CORREO EXCLUIDO SE HAYA COLADO.
--
-- La lista de exclusión está repetida en tres consultas de este archivo. Si
-- alguna se editó y otra no, el ensayo habría mostrado una cosa y el update
-- habría hecho otra — en silencio. Esto lo caza.
--
-- ⚠ LEER ESTO ANTES DE ALARMARSE. La primera versión de este paso buscaba
-- CUALQUIER ficha con el correo excluido y decía "esperado: cero filas". Está
-- mal, y el 2026-09-11 costó un rato largo: devolvió 3 fichas (Ian Zuñiga,
-- marcelo, Luis Silva) que YA tenían ese correo de una carga manual anterior.
-- El backfill no las había tocado. La consulta confundía "el update escribió
-- algo indebido" con "este correo existe en la base por cualquier motivo".
--
-- Ahora mira solo lo que el update PUDO haber escrito: una ficha cuyo correo
-- venga de una reserva suya que estaba excluida. Si el backfill hubiera
-- fallado, esa combinación existiría; si el correo es previo, no.
--
-- Esperado: CERO filas. Y si devuelve alguna, ANTES de limpiar nada correr el
-- PASO 7, porque entonces el problema no serían esas fichas sino todos los
-- correos mal copiados que no se pueden encontrar buscando una dirección
-- puntual.
--
-- select c.id, c.nombre, c.email
-- from clientes c
-- where lower(btrim(c.email)) = any (array['sintoniasalon@gmail.com'])
--   and exists (
--     select 1 from reservas r
--     where r.barberia_id = c.barberia_id
--       and r.whatsapp_norm = c.whatsapp_norm
--       and lower(btrim(r.email_cliente)) = lower(btrim(c.email))
--       and lower(split_part(btrim(r.nombre_cliente),' ',1))
--           = lower(split_part(btrim(c.nombre),' ',1))
--   );


-- PASO 8b — INVENTARIO, no alarma. Las fichas que tienen un correo excluido
-- por el motivo que sea, incluidas las previas a esta migración.
--
-- No hay un número esperado: es una lista para mirar y decidir. El 2026-09-11
-- eran tres, todas de cargas manuales de prueba entre negocios del dueño, y se
-- vaciaron a mano después de comprobar que el backfill no las había escrito.
--
-- select id, nombre, email
-- from clientes
-- where lower(btrim(email)) = any (array['sintoniasalon@gmail.com']);


-- PASO 9 — QUE LOS TRES DE PRUEBA SIGAN SIN CORREO.
-- Complemento del anterior, mirando desde el otro lado: por nombre en vez de
-- por dirección. Esperado: las tres filas, las tres con email vacío o nulo.
-- Si alguna quedó con correo, mira CUÁL es antes de borrarlo — podría ser uno
-- legítimo que ya tenía de antes y que este backfill no tocó.
--
-- select nombre, coalesce(nullif(btrim(email),''), '(vacío)') as email
-- from clientes
-- where lower(btrim(nombre)) in ('leandro martinez', 'luis vera', 'pruba 2')
-- order by nombre;
