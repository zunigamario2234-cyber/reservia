-- "Próximas reservas" en el link personal del Club VIP.
--
-- POR QUÉ
-- El cliente agenda y no tiene dónde volver a consultarlo: no le llega correo
-- de confirmación, y club.html hoy solo le muestra su nivel, sus beneficios y
-- la pestaña de reservar. Este es el dato que más le sirve y el único que no
-- puede ver.
--
-- ALCANCE: SOLO LO QUE VIENE, NUNCA EL HISTORIAL
-- El link del club es `club.html?id=<barberia>&cliente=<cliente>`: dos uuid en
-- la URL y ningún token, así que el link ES la credencial y se comparte por
-- WhatsApp, donde queda en el chat para siempre. Una cita FUTURA ya la conoce
-- quien coordinó esa reserva — no es información nueva. El historial pasado
-- con fechas y montos sí lo sería, y por eso queda afuera.
--
-- ⚠ SI ALGÚN DÍA SE AGREGA historial pasado, montos, o cualquier dato más
-- sensible a este link, hay que revisar el token primero. El patrón existe y
-- funciona: es el de club_tokens (migration_club_alta_directa.sql).
--
-- ═══════════════════════════════════════════════════════════════
-- EL PROBLEMA REAL NO ERA LA CONSULTA, ERA EL MATCH
-- `reservas` NO tiene cliente_id: se vincula por whatsapp_cliente, que es
-- texto libre. En la base conviven cuatro formatos del mismo número
-- ('+56 9 8754 2136', '+56987542136', '56987542136', '987542136') y las
-- puertas de alta usan criterios distintos — deudas #14 y #16. Con un match
-- exacto, a un cliente podrían no aparecerle SUS PROPIAS reservas, y eso se
-- vería como un bug de esta pantalla cuando es el de siempre.
--
-- La solución ya existía a medias: clientes.whatsapp_norm, la columna generada
-- que el Club QR usa desde agosto. Acá se agrega la simétrica en reservas y se
-- matchea norm contra norm. Es aditiva: se calcula sola en cada insert y
-- update, y hoy no la lee nadie más.
--
-- Esto NO cierra la deuda #16 —los criterios contradictorios siguen en los
-- flujos de alta— pero le da a esta pantalla un match robusto sin tocarlos.
--
-- ⚠ A DIFERENCIA de las columnas nuevas de `visitas`, una columna GENERADA
-- STORED reescribe la tabla al agregarse: no es metadata-only. Con el volumen
-- actual es instantáneo, pero conviene saberlo.
--
-- ═══════════════════════════════════════════════════════════════
-- ⚠ CÓMO SE CORRE
-- Define una función con dollar-quoting, así que va SIN begin;/commit; — esa
-- combinación el SQL Editor de Supabase la falla en silencio devolviendo
-- éxito. Correr completo, de una, y verificar con los pasos del final.


-- ═══════════════════════════════════════════════════════════════
-- (1) El WhatsApp normalizado de las reservas
-- Misma fórmula EXACTA que clientes.whatsapp_norm: los últimos 9 dígitos.
-- Si las dos fórmulas se separaran, el match dejaría de funcionar en silencio.
-- ═══════════════════════════════════════════════════════════════

alter table public.reservas
  add column if not exists whatsapp_norm text
  generated always as (right(regexp_replace(coalesce(whatsapp_cliente,''), '\D', '', 'g'), 9)) stored;

comment on column public.reservas.whatsapp_norm is
  'Últimos 9 dígitos del whatsapp_cliente, generada. Gemela de clientes.whatsapp_norm: las dos fórmulas tienen que ser idénticas o el match del club se rompe sin avisar.';

-- El índice NO es único, igual que el de clientes: un mismo teléfono tiene
-- varias reservas, que es lo normal.
create index if not exists idx_reservas_barberia_whatsapp_norm
  on public.reservas (barberia_id, whatsapp_norm);


-- ═══════════════════════════════════════════════════════════════
-- (2) La RPC pública
-- Mismo molde que get_club_vip_historial_publico: security definer,
-- search_path fijo, y los DOS ids como scoping — nunca uno solo.
-- No usa auth_barberia_id(): el club se abre sin sesión, la identidad son los
-- parámetros. Por eso se puede probar con SQL directo sin simular ningún JWT.
-- ═══════════════════════════════════════════════════════════════

create or replace function get_proximas_reservas_publico(p_barberia_id uuid, p_cliente_id uuid)
returns table (
  fecha date,
  hora time,
  servicio text,
  profesional text
)
language sql
security definer
set search_path = public
as $$
  select r.fecha, r.hora, r.servicio, r.barbero_nombre
  from reservas r
  join clientes c
    on c.id = p_cliente_id
   and c.barberia_id = p_barberia_id
   -- LA LÍNEA MÁS IMPORTANTE DE LA FUNCIÓN. Una ficha vieja SIN whatsapp tiene
   -- whatsapp_norm = '', que matchearía contra todas las reservas que tampoco
   -- lo tienen, de cualquier persona. Sin esto, un cliente sin teléfono vería
   -- las citas de desconocidos.
   and c.whatsapp_norm <> ''
   -- TELÉFONOS COMPARTIDOS ENTRE PERSONAS DISTINTAS.
   -- Como `reservas` no tiene cliente_id y se empareja por teléfono, dos fichas
   -- con nombres distintos y el mismo número se ven las reservas entre sí. En
   -- la base real hay dos casos (verificado 2026-09-08) de personas DISTINTAS
   -- compartiendo número. Ahí falla el razonamiento con el que se aceptó un
   -- link sin token —"la cita ya la conoce quien la coordinó"—, porque el que
   -- la ve NO es quien la coordinó.
   --
   -- Ante la duda no se muestra nada: esas personas no ven sus reservas, que es
   -- una molestia, en vez de ver las de otro, que es una filtración.
   --
   -- Compara el PRIMER nombre y no el completo, a propósito. Dos fichas de la
   -- MISMA persona escrita distinto —el nombre solo en una y nombre+apellido en
   -- la otra— son la mayoría de los casos de número repetido, y tienen que
   -- seguir viendo lo suyo. Dos personas distintas con el mismo número no. Con
   -- el nombre completo, todos los duplicados benignos quedarían bloqueados de
   -- más.
   --
   -- El arreglo de fondo es reservas.cliente_id, que elimina la adivinanza por
   -- teléfono. Es otra tarea: columna, backfill y poblarla en las tres puertas
   -- de alta.
   and not exists (
     select 1 from clientes c2
     where c2.barberia_id = c.barberia_id
       and c2.whatsapp_norm = c.whatsapp_norm
       and c2.id <> c.id
       and lower(split_part(trim(c2.nombre), ' ', 1)) <> lower(split_part(trim(c.nombre), ' ', 1))
   )
  where r.barberia_id = p_barberia_id
    and r.whatsapp_norm = c.whatsapp_norm
    and r.procesado = false
    and coalesce(r.estado,'') <> 'Cancelada'
    -- El servidor corre en UTC, que va ADELANTE de Chile: a las 21:00 hora
    -- chilena ya son las 01:00 UTC del día siguiente, así que current_date
    -- daría mañana y escondería la cita de esa misma noche. Es el mismo bug de
    -- las noches que ya se arregló del lado del navegador.
    --
    -- Se compara contra el DÍA y no contra fecha+hora a propósito: una cita de
    -- hoy sigue visible todo el día, aunque su hora ya haya pasado. Al que
    -- llega tarde le sirve verla; hacerla desaparecer a la hora exacta sería
    -- peor.
    and r.fecha >= (now() at time zone 'America/Santiago')::date
  order by r.fecha, r.hora;
$$;

-- Devuelve SOLO lo mínimo para saber cuándo hay que venir: ni whatsapp, ni
-- notas, ni ids, ni montos. Todo lo que no se devuelve es algo que no se puede
-- filtrar con el link.
revoke all on function get_proximas_reservas_publico(uuid, uuid) from public;
grant execute on function get_proximas_reservas_publico(uuid, uuid) to anon, authenticated;


-- =============================================================================
-- PASO 1 — LA COLUMNA Y EL ÍNDICE
--
-- select column_name, data_type, is_generated, generation_expression
-- from information_schema.columns
-- where table_schema='public' and table_name='reservas' and column_name='whatsapp_norm';
--
-- select indexname from pg_indexes
-- where schemaname='public' and indexname='idx_reservas_barberia_whatsapp_norm';
--
-- is_generated tiene que decir ALWAYS. Si dice NEVER, la columna se creó como
-- normal y NO se va a actualizar sola: hay que dropearla y rehacerla.
--
-- =============================================================================
-- PASO 2 — QUE LAS DOS FÓRMULAS SEAN IDÉNTICAS
-- Si se separan, el match se rompe sin ningún error. Esto las compara.
--
-- select table_name, generation_expression
-- from information_schema.columns
-- where table_schema='public' and column_name='whatsapp_norm'
-- order by table_name;
--
-- Las dos filas (clientes y reservas) tienen que traer la MISMA expresión,
-- salvo por el nombre de la columna de origen (whatsapp vs whatsapp_cliente).
--
-- =============================================================================
-- PASO 3 — QUE LA NORMALIZACIÓN FUNCIONE SOBRE LOS DATOS REALES
-- Los cuatro formatos tienen que colapsar al mismo valor.
--
-- select whatsapp_cliente, whatsapp_norm
-- from reservas
-- where whatsapp_cliente is not null
-- order by whatsapp_norm
-- limit 20;
--
-- Todos los whatsapp_norm tienen que ser 9 dígitos sin símbolos. Y esto
-- muestra cuántas reservas van a poder emparejarse:
--
-- select count(*) filter (where whatsapp_norm <> '')  as con_telefono,
--        count(*) filter (where whatsapp_norm = '')   as sin_telefono
-- from reservas where procesado = false;
--
-- =============================================================================
-- PASO 4 — CUÁNTAS RESERVAS GANA CADA CLIENTE CON EL MATCH NUEVO
-- Compara el match exacto contra el normalizado. Si la segunda columna es
-- mayor, son reservas que con el criterio viejo el cliente NO habría visto.
--
-- select c.nombre, c.whatsapp,
--        count(*) filter (where r.whatsapp_cliente = c.whatsapp) as match_exacto,
--        count(*)                                                as match_normalizado
-- from clientes c
-- join reservas r
--   on r.barberia_id = c.barberia_id
--  and r.whatsapp_norm = c.whatsapp_norm
-- where c.whatsapp_norm <> '' and r.procesado = false
-- group by c.nombre, c.whatsapp
-- having count(*) > 0
-- order by match_normalizado desc;
--
-- =============================================================================
-- PASO 5 — LA FUNCIÓN, CON UN CLIENTE REAL
-- No hace falta simular JWT: la identidad son los parámetros.
--
-- select * from get_proximas_reservas_publico('<barberia_id>', '<cliente_id>');
--
-- Tiene que traer solo fechas de hoy en adelante, sin canceladas y sin
-- procesadas, ordenadas por fecha y hora.
--
-- =============================================================================
-- PASO 6 — QUE EL SCOPING MUERDA
-- Un cliente de OTRO negocio, o un uuid inventado, tienen que devolver CERO
-- filas. Nunca un error, nunca datos de otro.
--
-- select count(*) as debe_ser_cero
-- from get_proximas_reservas_publico('<barberia_id>', '00000000-0000-0000-0000-000000000000');
--
-- select count(*) as debe_ser_cero
-- from get_proximas_reservas_publico('00000000-0000-0000-0000-000000000000', '<cliente_id>');
--
-- =============================================================================
-- PASO 8 — TELÉFONOS COMPARTIDOS ENTRE PERSONAS DISTINTAS
-- El caso que motivó el `not exists`. Primero, quiénes son:
--
-- select c1.nombre as veria, c2.nombre as reservas_de, c1.whatsapp_norm
-- from clientes c1
-- join clientes c2
--   on c2.barberia_id = c1.barberia_id
--  and c2.whatsapp_norm = c1.whatsapp_norm
--  and c2.id <> c1.id
-- where c1.whatsapp_norm <> ''
--   and lower(split_part(trim(c1.nombre),' ',1)) <> lower(split_part(trim(c2.nombre),' ',1));
--
-- En la base del 2026-09-08 esto devuelve DOS pares de personas distintas
-- compartiendo número. Y ahora, que NINGUNO de ellos vea nada:
--
-- select c.nombre,
--        (select count(*) from get_proximas_reservas_publico(c.barberia_id, c.id)) as ve
-- from clientes c
-- where c.whatsapp_norm <> ''
--   and exists (
--     select 1 from clientes c2
--     where c2.barberia_id = c.barberia_id and c2.whatsapp_norm = c.whatsapp_norm
--       and c2.id <> c.id
--       and lower(split_part(trim(c2.nombre),' ',1)) <> lower(split_part(trim(c.nombre),' ',1))
--   );
--
-- `ve` tiene que ser 0 en TODAS las filas.
--
-- Y el control opuesto, que es igual de importante: los duplicados BENIGNOS
-- (misma persona, ficha repetida) tienen que seguir viendo lo suyo. Sin esto,
-- un filtro demasiado ancho se ve igual que uno correcto.
--
-- Los números salen de la consulta de arriba invertida: los que comparten
-- teléfono Y comparten el primer nombre. Se buscan en el momento en vez de
-- dejarlos escritos acá — este archivo es público y son datos de contacto de
-- personas reales.
--
-- select c.nombre,
--        (select count(*) from get_proximas_reservas_publico(c.barberia_id, c.id)) as ve
-- from clientes c
-- where c.whatsapp_norm <> ''
--   and exists (
--     select 1 from clientes c2
--     where c2.barberia_id = c.barberia_id and c2.whatsapp_norm = c.whatsapp_norm
--       and c2.id <> c.id
--       and lower(split_part(trim(c2.nombre),' ',1)) = lower(split_part(trim(c.nombre),' ',1))
--   )
-- order by c.nombre;
--
-- Son fichas duplicadas de la MISMA persona —el nombre solo en una y
-- nombre+apellido en la otra— así que NO tienen que quedar bloqueadas: si
-- tienen reservas futuras, las siguen viendo.
--
-- =============================================================================
-- PASO 7 — EL AGUJERO DE LAS FICHAS SIN TELÉFONO (el más importante)
-- Un cliente sin whatsapp NO puede ver las reservas de nadie. Si este paso
-- devuelve filas, la línea `c.whatsapp_norm <> ''` no está haciendo efecto y
-- hay una filtración de datos entre clientes.
--
-- select c.id, c.nombre,
--        (select count(*) from get_proximas_reservas_publico(c.barberia_id, c.id)) as reservas_visibles
-- from clientes c
-- where c.whatsapp_norm = ''
-- limit 10;
--
-- reservas_visibles tiene que ser 0 en TODAS las filas. Si no hay clientes sin
-- teléfono, la consulta no devuelve nada y ese caso no se puede probar hoy —
-- anotarlo y volver a correrlo cuando aparezca alguno.
