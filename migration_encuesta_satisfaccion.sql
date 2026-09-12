-- Encuesta de satisfacción post-servicio.
--
-- POR QUÉ
-- Detectar a un cliente insatisfecho ANTES de que vaya a Google, para poder
-- resolverlo en privado. Y al que quedó contento, invitarlo ahí mismo a dejar
-- la reseña.
--
-- Esta migración es SOLO LA CAPA DE DATOS: la tabla, el disparo automático y
-- las dos funciones que la página pública usa. El envío por correo, la lista
-- de WhatsApp y el aviso al dueño son frontend y endpoints, y van aparte.
--
-- ═══════════════════════════════════════════════════════════════
-- DECISIONES DEL DUEÑO, PARA QUE NO SE DISCUTAN DE NUEVO
--
--   · 4-5 estrellas → se le ofrece el link de Google. 1-3 → canal privado.
--   · Se dispara AL COBRAR. Sin cron, sin colas.
--   · Los dos canales: correo si el cliente lo tiene, WhatsApp si no.
--     Medido el 2026-09-11: 88% tiene correo, 12% no.
--   · No anónima — para resolver en privado hay que saber quién es.
--   · Con 1-3 el comentario es OBLIGATORIO: un puntaje bajo sin detalle no
--     sirve para actuar, que es todo el objetivo.
--
-- ═══════════════════════════════════════════════════════════════
-- POR QUÉ UN TRIGGER Y NO ENGANCHARLO EN EL COBRO
--
-- Una visita nace con estado 'Atendida' por DEFAULT, y hay CUATRO caminos que
-- las crean: el cobro del panel (registrar_cobro_conjunto), el del profesional
-- (mi_agenda_procesar_pago), la carga manual y el cambio rápido de estado.
-- Enganchar la encuesta en cada uno son cuatro copias de la misma lógica — el
-- patrón que en este repo ya dejó el cálculo de comisión en su quinta copia.
--
-- El trigger cubre las cuatro sin tocar ninguna.
--
-- ⚠ Y POR ESO MISMO ES PELIGROSO: corre DENTRO de la transacción del cobro. Si
-- falla, el cobro falla. Va con `exception when others` y un `raise warning`:
-- una encuesta que no se crea NO puede voltear una venta. Ese bloque no es
-- decoración defensiva, es la condición para que este diseño sea aceptable.
--
-- Se dispara en INSERT y en UPDATE OF estado. Lo segundo cubre la visita que
-- se cargó como 'No asistió' y después se corrigió a 'Atendida': sin eso, la
-- cuarta puerta quedaba afuera. El `on conflict do nothing` hace que disparar
-- dos veces no duplique nada.
--
-- ═══════════════════════════════════════════════════════════════
-- LA FILA SE CREA AL COBRAR, NO AL ENVIAR
--
-- Es lo que hace que el 12% sin correo no se pierda. Si la fila naciera cuando
-- el correo sale, los clientes sin correo no tendrían fila y no habría de
-- dónde armar la lista de WhatsApp. Así, `enviada_at is null` ES la lista de
-- pendientes, sin importar el canal.
--
-- ═══════════════════════════════════════════════════════════════
-- EL LINK NO LLEVA TOKEN
--
-- `encuesta.html?b=<barberia>&v=<visita>`: dos uuid, igual que el Club VIP, y
-- con el mismo criterio aceptado a sabiendas. Qué expone:
--   · Leer: nombre del negocio, servicio y fecha de ESA visita. Nada de plata,
--     nada de otros clientes.
--   · Escribir: una respuesta, UNA SOLA VEZ. El `respondida_at is null` en el
--     WHERE del update es lo que lo impide, y es atómico — no un chequeo
--     previo que otra petición pueda ganar.
--
-- Esta migración DEFINE FUNCIONES, así que va SIN begin;/commit;. Correr cada
-- bloque por separado.
-- ═══════════════════════════════════════════════════════════════


-- ═══════════════════════════════════════════════════════════════
-- (1) LA TABLA
-- ═══════════════════════════════════════════════════════════════

create table if not exists encuestas (
  id            uuid primary key default gen_random_uuid(),
  barberia_id   uuid not null references barberias(id) on delete cascade,
  -- UNIQUE: una encuesta por visita. Es lo que impide que el trigger duplique
  -- si se dispara dos veces, y lo que ata la respuesta a un servicio concreto.
  visita_id     uuid not null unique references visitas(id) on delete cascade,
  -- SET NULL y no CASCADE: si el dueño borra la ficha del cliente, la
  -- respuesta y su puntaje siguen contando en el promedio del negocio. Lo que
  -- se pierde es a quién contactar, no el dato.
  cliente_id    uuid references clientes(id) on delete set null,
  canal         text,           -- 'email' | 'whatsapp'. null = todavía sin decidir
  enviada_at    timestamptz,    -- null = pendiente de enviar. ES la lista de pendientes.
  puntaje       smallint check (puntaje between 1 and 5),
  comentario    text,
  respondida_at timestamptz,
  avisada_at    timestamptz,    -- cuándo se le avisó al dueño de una respuesta mala
  vista_at      timestamptz,    -- cuándo el dueño la marcó como vista
  created_at    timestamptz not null default now(),

  -- La decisión del comentario obligatorio, en la BASE y no solo en la
  -- pantalla. Si viviera solo en el JavaScript, cualquier llamada directa a la
  -- RPC lo saltearía — y el objetivo entero es poder actuar sobre lo que salió
  -- mal, cosa que un 2 sin texto no permite.
  constraint encuesta_mala_exige_comentario check (
    puntaje is null or puntaje >= 4 or coalesce(btrim(comentario), '') <> ''
  )
);

-- Para el dashboard: cuántas pendientes de responder y cuántas malas sin ver.
create index if not exists idx_encuestas_barberia_estado
  on encuestas (barberia_id, respondida_at, vista_at);


-- ═══════════════════════════════════════════════════════════════
-- (2) RLS — el dueño ve las suyas, nadie más
--
-- Las dos funciones públicas son security definer, así que la política no las
-- afecta: el cliente responde sin poder leer nada de esta tabla.
-- Sin comodines: barberia_id Y rol, igual que clientes_own.
-- ═══════════════════════════════════════════════════════════════

alter table encuestas enable row level security;

drop policy if exists encuestas_own on encuestas;
create policy encuestas_own on encuestas for all
  using      (barberia_id = auth_barberia_id() and auth_rol() = 'dueno')
  with check (barberia_id = auth_barberia_id() and auth_rol() = 'dueno');


-- ═══════════════════════════════════════════════════════════════
-- (3) EL TRIGGER — las cuatro puertas de una vez
-- ═══════════════════════════════════════════════════════════════

create or replace function crear_encuesta_de_visita()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  -- Solo visitas atendidas y con cliente identificable. Sin cliente_id no hay
  -- a quién escribirle, y una venta de solo productos ni siquiera pasa por
  -- acá: no genera visita.
  if new.estado is distinct from 'Atendida' or new.cliente_id is null then
    return new;
  end if;

  -- ⚠ EL BLOQUE QUE HACE ACEPTABLE ESTE DISEÑO.
  -- Esto corre dentro de la transacción del cobro. Sin el exception, cualquier
  -- problema acá —un constraint, un deadlock, lo que sea— aborta el cobro
  -- entero y el cliente queda pagando algo que el sistema no registró.
  -- Una encuesta perdida es un inconveniente; un cobro perdido es plata.
  begin
    insert into encuestas (barberia_id, visita_id, cliente_id)
    values (new.barberia_id, new.id, new.cliente_id)
    on conflict (visita_id) do nothing;
  exception when others then
    raise warning 'No se pudo crear la encuesta de la visita %: %', new.id, sqlerrm;
  end;

  return new;
end;
$$;

-- ⚠ HACEN FALTA LAS DOS LÍNEAS. En Supabase, los default privileges del
-- esquema public le dan EXECUTE a anon y authenticated como grant EXPLÍCITO de
-- cada rol; quitárselo a PUBLIC no los toca. Comprobado dos veces el mismo día
-- (2026-09-11 con email_para_ficha, 2026-09-12 acá): con un solo revoke,
-- has_function_privilege('anon', ...) seguía dando true.
--
-- Acá el riesgo era nulo —una función que devuelve `trigger` no se puede
-- invocar fuera de un trigger, así que el permiso no habilita nada— pero rompe
-- la convención del repo y PUBLIC alcanza a cualquier rol que se cree después.
revoke all on function crear_encuesta_de_visita() from public;
revoke all on function crear_encuesta_de_visita() from anon, authenticated;

drop trigger if exists visitas_crear_encuesta on visitas;
-- INSERT cubre las tres puertas que crean la visita ya atendida.
-- UPDATE OF estado cubre la cuarta: la visita cargada como 'No asistió' que
-- después se corrige. El unique + on conflict hacen que repetir no duplique.
create trigger visitas_crear_encuesta
after insert or update of estado on visitas
for each row execute function crear_encuesta_de_visita();


-- ═══════════════════════════════════════════════════════════════
-- (4) LEER — lo que la página pública necesita para pintarse
--
-- Devuelve lo MÍNIMO: con qué negocio fue, qué servicio y qué día. Ni montos,
-- ni datos del cliente, ni nada de otras visitas. Cada columna que se agregue
-- acá es un dato más expuesto por un link sin token.
-- ═══════════════════════════════════════════════════════════════

create or replace function get_encuesta_publico(p_barberia_id uuid, p_visita_id uuid)
returns table (negocio text, servicio text, fecha date, ya_respondida boolean)
language sql
stable
security definer
set search_path = public
as $$
  select b.nombre, v.servicio, v.fecha, (e.respondida_at is not null)
  from encuestas e
  join visitas   v on v.id = e.visita_id
  join barberias b on b.id = e.barberia_id
  where e.barberia_id = p_barberia_id
    and e.visita_id   = p_visita_id
$$;

revoke all on function get_encuesta_publico(uuid, uuid) from public;
grant execute on function get_encuesta_publico(uuid, uuid) to anon, authenticated;


-- ═══════════════════════════════════════════════════════════════
-- (5) RESPONDER
--
-- Devuelve el link de Google SOLO con 4-5, para que la página no necesite otra
-- consulta ni conozca el umbral. El umbral vive acá y en un solo lugar.
-- ═══════════════════════════════════════════════════════════════

create or replace function responder_encuesta_publico(
  p_barberia_id uuid,
  p_visita_id   uuid,
  p_puntaje     smallint,
  p_comentario  text default null
)
returns table (ok boolean, link_reviews text, mensaje text)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_id   uuid;
  v_link text;
begin
  if p_puntaje is null or p_puntaje < 1 or p_puntaje > 5 then
    return query select false, null::text, 'El puntaje tiene que ser de 1 a 5.'::text;
    return;
  end if;

  -- La regla del comentario obligatorio, validada acá ADEMÁS del check de la
  -- tabla. El check protege el dato; esto devuelve un mensaje que la página
  -- puede mostrar, en vez de un error de constraint en crudo.
  if p_puntaje <= 3 and coalesce(btrim(p_comentario), '') = '' then
    return query select false, null::text,
      'Cuéntanos qué pasó, así podemos resolverlo.'::text;
    return;
  end if;

  -- El `respondida_at is null` va en el WHERE y no en un `if` previo: así
  -- "una sola respuesta" es atómico. Con un chequeo antes, dos envíos
  -- simultáneos podrían pasar los dos.
  update encuestas
     set puntaje       = p_puntaje,
         comentario    = nullif(btrim(p_comentario), ''),
         respondida_at = now()
   where barberia_id   = p_barberia_id
     and visita_id     = p_visita_id
     and respondida_at is null
  returning id into v_id;

  if v_id is null then
    -- No se distingue "ya respondida" de "no existe", a propósito: con un link
    -- sin token, decirle a un desconocido cuál de las dos es le confirma que
    -- esa visita existe.
    return query select false, null::text,
      'Esta encuesta ya fue respondida.'::text;
    return;
  end if;

  -- ⚠ `b.` NO ES OPCIONAL. `returns table (ok, link_reviews, mensaje)` crea
  -- en plpgsql una variable implícita por cada columna de salida, así que
  -- `link_reviews` a secas es ambiguo entre esa variable y la columna de
  -- barberias — y Postgres lo rechaza en tiempo de EJECUCIÓN, no al crear la
  -- función:
  --   ERROR 42702: column reference "link_reviews" is ambiguous
  -- Detectado corriendo el PASO 6 el 2026-09-12. No hay forma de que un test
  -- de texto lo vea: solo aparece ejecutando la función.
  select b.link_reviews into v_link from barberias b where b.id = p_barberia_id;

  return query select true,
    case when p_puntaje >= 4 then nullif(btrim(v_link), '') end,
    null::text;
end;
$$;

revoke all on function responder_encuesta_publico(uuid, uuid, smallint, text) from public;
grant execute on function responder_encuesta_publico(uuid, uuid, smallint, text) to anon, authenticated;


-- ═══════════════════════════════════════════════════════════════
-- VERIFICACIÓN (correr DESPUÉS, cada paso por separado)
-- ═══════════════════════════════════════════════════════════════

-- PASO 1 — Que estén las tres restricciones que sostienen las decisiones.
--
-- Esperado: las TRES filas, cada una con presente = true.
--
--   encuesta_mala_exige_comentario → el comentario obligatorio con 1-3
--   encuestas_puntaje_check        → el rango 1..5 (inline en la columna,
--                                    Postgres le pone ese nombre solo)
--   encuestas_visita_id_key        → una encuesta por visita
--
-- ⚠ SE PREGUNTA POR NOMBRE Y NO SE CUENTAN FILAS, a propósito. La primera
-- versión decía "esperado: 2 filas" y se olvidaba del check inline de la
-- columna, que yo mismo había escrito: dio 3 y pareció un problema que no
-- existía. Un total es frágil —se rompe cada vez que alguien agrega algo
-- legítimo— y no dice CUÁL falta. Preguntar por las que importan no tiene ese
-- problema, y una restricción de más nunca es la alarma.
--
-- select esperada,
--        exists (select 1 from pg_constraint
--                 where conrelid = 'encuestas'::regclass
--                   and conname = esperada) as presente,
--        (select pg_get_constraintdef(oid) from pg_constraint
--          where conrelid = 'encuestas'::regclass and conname = esperada) as definicion
-- from unnest(array['encuesta_mala_exige_comentario',
--                   'encuestas_puntaje_check',
--                   'encuestas_visita_id_key']) as esperada;


-- PASO 2 — Las dos funciones públicas son security definer con search_path,
-- y la del trigger NO quedó publicada como endpoint.
-- Esperado: 3 filas; las dos públicas con anon_puede = true, la del trigger
-- con anon_puede = false.
--
-- select p.proname, p.prosecdef as security_definer, p.proconfig as config,
--        has_function_privilege('anon', p.oid, 'execute') as anon_puede
-- from pg_proc p join pg_namespace n on n.oid = p.pronamespace
-- where n.nspname = 'public'
--   and p.proname in ('crear_encuesta_de_visita','get_encuesta_publico',
--                     'responder_encuesta_publico')
-- order by p.proname;


-- PASO 3 — El trigger está puesto en los dos eventos.
-- Esperado: 1 fila, con INSERT y UPDATE en la definición.
--
-- select tgname, pg_get_triggerdef(oid) as definicion
-- from pg_trigger where tgrelid = 'visitas'::regclass and not tgisinternal;


-- PASO 4 — EL TRIGGER NO PUEDE VOLTEAR UN COBRO. La prueba que justifica
-- todo el diseño.
--
-- Se rompe la tabla de encuestas a propósito (un check imposible), se inserta
-- una visita, y se comprueba que LA VISITA ENTRA IGUAL aunque la encuesta no
-- se pueda crear. Sin esto, el `exception when others` es una intención
-- escrita en un comentario.
--
-- ⚠ CORRER EL BLOQUE ENTERO EN UNA SOLA EJECUCIÓN. El SQL Editor de Supabase
-- no mantiene sesión entre ejecuciones: partido en pedazos, el begin no
-- envuelve nada y los inserts quedan en producción. Ya pasó una vez.
--
-- begin;
--   alter table encuestas add constraint zz_romper check (false);
--
--   insert into visitas (barberia_id, cliente_id, barbero_nombre, servicio,
--                        valor, fecha, hora, fuente, estado)
--   select b.id, c.id, 'ZZ Prueba', 'ZZ Prueba', 1000, current_date, '09:00',
--          'Manual', 'Atendida'
--   from barberias b
--   join clientes c on c.barberia_id = b.id
--   order by b.created_at limit 1;
--
--   -- Esperado: visitas = 1 (el cobro sobrevivió), encuestas = 0 (no se pudo
--   -- crear, y no importó). Si visitas = 0, el trigger volteó la operación.
--   select (select count(*) from visitas  where servicio = 'ZZ Prueba') as visitas,
--          (select count(*) from encuestas e
--             join visitas v on v.id = e.visita_id
--            where v.servicio = 'ZZ Prueba') as encuestas;
-- rollback;


-- PASO 5 — Y AHORA QUE SÍ LA CREA. El complemento del anterior: sin este, un
-- trigger que nunca hace nada pasaría el PASO 4 perfecto.
-- Esperado: visitas = 1 y encuestas = 1.
--
-- begin;
--   insert into visitas (barberia_id, cliente_id, barbero_nombre, servicio,
--                        valor, fecha, hora, fuente, estado)
--   select b.id, c.id, 'ZZ Prueba', 'ZZ Prueba2', 1000, current_date, '09:00',
--          'Manual', 'Atendida'
--   from barberias b
--   join clientes c on c.barberia_id = b.id
--   order by b.created_at limit 1;
--
--   select (select count(*) from visitas  where servicio = 'ZZ Prueba2') as visitas,
--          (select count(*) from encuestas e
--             join visitas v on v.id = e.visita_id
--            where v.servicio = 'ZZ Prueba2') as encuestas;
-- rollback;


-- PASO 6 — LOS TRES CASOS DE LA RPC, EN UN SOLO RESULTADO.
--
-- Todo en UNA consulta a propósito: así no hay partes que se puedan correr por
-- separado, que es lo que hizo perder la transacción dos veces el 2026-09-12.
--
-- Esperado: CUATRO filas, las cuatro con correcto = true.
--
-- ⚠ EL ORDEN DE LOS CASOS IMPORTA y está garantizado por DEPENDENCIA DE DATOS,
-- no por el orden en que aparecen escritos. Cada CTE hace `from <el anterior>,
-- lateral ...`, así que Postgres no puede evaluar el tercero antes que el
-- segundo. Sin esa cadena, el "responder dos veces" podría ejecutarse primero y
-- el resultado no significaría nada. Y como la función es VOLATILE, los CTE no
-- se inlinean: cada uno corre exactamente una vez.
--
-- La fila 0 es la PRECONDICIÓN. Si da correcto = false, las otras tres no
-- significan nada — la visita no se insertó y las llamadas están operando
-- sobre ids nulos.
--
-- begin;
--
--   insert into visitas (barberia_id, cliente_id, barbero_nombre, servicio,
--                        valor, fecha, hora, fuente, estado)
--   select b.id, c.id, 'ZZ Prueba', 'ZZ Prueba3', 1000, current_date, '09:00',
--          'Manual', 'Atendida'
--   from barberias b join clientes c on c.barberia_id = b.id
--   order by b.created_at limit 1;
--
--   with ids as (
--     select barberia_id as bid, id as vid
--     from visitas where servicio = 'ZZ Prueba3'
--   ),
--   pre as (
--     select (select count(*) from ids) as v,
--            (select count(*) from encuestas e
--               join ids on e.visita_id = ids.vid) as e
--   ),
--   caso_a as (   -- 2 estrellas SIN comentario: se rechaza
--     select r.ok, r.link_reviews, r.mensaje
--     from ids, lateral responder_encuesta_publico(ids.bid, ids.vid, 2::smallint, null) r
--   ),
--   caso_b as (   -- 5 estrellas SIN comentario: pasa, y devuelve el link
--     select r.ok, r.link_reviews, r.mensaje
--     from caso_a, ids,
--          lateral responder_encuesta_publico(ids.bid, ids.vid, 5::smallint, null) r
--   ),
--   caso_c as (   -- la MISMA visita otra vez: se rechaza
--     select r.ok, r.link_reviews, r.mensaje
--     from caso_b, ids,
--          lateral responder_encuesta_publico(ids.bid, ids.vid, 5::smallint, null) r
--   )
--   select 0 as n, 'precondicion: existe la visita y su encuesta' as caso,
--          (pre.v = 1 and pre.e = 1) as ok, true as esperado,
--          ((pre.v = 1 and pre.e = 1) is not distinct from true) as correcto,
--          'visitas=' || pre.v || ' encuestas=' || pre.e as detalle
--   from pre
--   union all
--   select 1, 'mala sin comentario -> rechaza', ok, false,
--          (ok is not distinct from false), mensaje from caso_a
--   union all
--   select 2, 'buena sin comentario -> acepta', ok, true,
--          (ok is not distinct from true),
--          coalesce('link: ' || link_reviews, 'sin link de Google cargado')
--     from caso_b
--   union all
--   select 3, 'responder dos veces -> rechaza', ok, false,
--          (ok is not distinct from false), mensaje from caso_c
--   order by n;
--
-- rollback;
--
-- CÓMO LEERLO: la columna `correcto` en las cuatro filas. Si alguna da false,
-- mirar `detalle`, que trae el mensaje que devolvió la función.
--
-- La fila 2 muestra el link de Google del negocio si lo tiene cargado en
-- Config, o "sin link" si no. Las dos cosas son válidas: la RPC devuelve el
-- link cuando existe, y null cuando el negocio no lo configuró.

-- PASO 7 — El scoping: con el barberia_id de OTRO negocio no se puede
-- responder, aunque se tenga el visita_id correcto.
-- Esperado: ok = false.
--
-- begin;
--   insert into visitas (barberia_id, cliente_id, barbero_nombre, servicio,
--                        valor, fecha, hora, fuente, estado)
--   select b.id, c.id, 'ZZ Prueba', 'ZZ Prueba4', 1000, current_date, '09:00',
--          'Manual', 'Atendida'
--   from barberias b join clientes c on c.barberia_id = b.id
--   order by b.created_at limit 1;
--
--   -- Misma precondición que el PASO 6, y por el mismo motivo: con la visita
--   -- inexistente, el scoping "falla" igual y el paso pasaría sin probar nada.
--   -- Esperado: visita = 1 y encuesta = 1.
--   select (select count(*) from visitas where servicio = 'ZZ Prueba4') as visita,
--          (select count(*) from encuestas e join visitas v on v.id = e.visita_id
--            where v.servicio = 'ZZ Prueba4') as encuesta;
--
--   -- Con el negocio equivocado: esperado ok = false.
--   select 'negocio ajeno' as caso, * from responder_encuesta_publico(
--     gen_random_uuid(),                                    -- negocio que no es
--     (select id from visitas where servicio = 'ZZ Prueba4'),
--     5::smallint, null);
--
--   -- Y con el negocio CORRECTO tiene que funcionar. Sin este contraste, una
--   -- función que rechazara siempre pasaría el caso de arriba perfecto.
--   select 'negocio correcto' as caso, * from responder_encuesta_publico(
--     (select barberia_id from visitas where servicio = 'ZZ Prueba4'),
--     (select id from visitas where servicio = 'ZZ Prueba4'),
--     5::smallint, null);
-- rollback;
