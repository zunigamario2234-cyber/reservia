-- Exige un celular chileno válido en las reservas por link público.
--
-- Hoy crear_reserva_publica inserta p_whatsapp_cliente sin mirarlo, y
-- reservar.html solo comprueba que el campo no esté vacío. Cualquier cosa
-- entra: un fijo, un número a medias, ocho dígitos sueltos. Después esa ficha
-- no matchea con nada y alimenta la deuda del WhatsApp todos los días.
--
-- LA REGLA: 9 dígitos que empiezan en 9, aceptando prefijo +56/56, espacios
-- y guiones, y rechazando los obviamente falsos (los 8 dígitos después del 9
-- todos iguales: 999999999, 900000000, 911111111).
--
-- ═══════════════════════════════════════════════════════════════
-- ⚠ LO QUE ESTA MIGRACIÓN **NO** HACE, Y POR QUÉ IMPORTA
--
-- NO cambia el formato en que se guarda el número. Valida y rechaza; si el
-- número pasa, se inserta el texto crudo tal como lo escribió la persona.
--
-- No es un olvido. En la base conviven cuatro formatos del mismo número
-- ('+56 9 8754 2136', '+56987542136', '56987542136', '987542136') y hay RPCs
-- —registrar_cobro_conjunto entre ellas— que buscan al cliente por igualdad
-- EXACTA del texto. Si empezáramos a guardar normalizado ahora, los números
-- nuevos dejarían de matchear con las fichas viejas del mismo cliente: haríamos
-- más duplicados, no menos. La normalización al guardar va junto con la
-- unificación de los duplicados que ya existen, que es su propia tarea.
--
-- Tampoco toca ninguna fila existente. Las que no cumplen la regla se quedan
-- como están; esto solo mira lo que entra de ahora en adelante.
-- ═══════════════════════════════════════════════════════════════
--
-- ALCANCE DE LAS PUERTAS: se valida SOLO crear_reserva_publica.
--   · unirse_club_publico ya valida con este mismo criterio, escrito a mano
--     adentro. NO se refactoriza en esta entrega por decisión explícita: ese
--     refactor va con la tarea de unificación de duplicados, que va a tocar
--     la normalización de teléfonos igual. DEUDA ANOTADA: hasta entonces la
--     regla vive en dos lugares en SQL, y si alguien cambia uno hay que
--     cambiar el otro.
--   · crear_reserva_publica_club no recibe teléfono (reserva con
--     p_cliente_id, el cliente ya existe en el club).
--   · buscar_o_crear_cliente_club no necesita validar: crea la ficha a partir
--     del whatsapp DE LA RESERVA, así que si la reserva no se pudo crear,
--     nunca hay ficha de la cual preocuparse. Queda cubierta por herencia.
--   · El dueño (app.html) inserta directo en `reservas` con fuente 'Manual' y
--     NO pasa por esta RPC — a propósito: un fijo o un número extranjero los
--     carga él a mano. Esa es la vía de escape que hace aceptable rechazar en
--     el link público.
--
-- Ejecutar UNA VEZ, completo, en el SQL Editor de Supabase.


-- ═══════════════════════════════════════════════════════════════
-- (0) ANTES DE APLICAR — no escribe nada, correr suelto.
--
-- El repo puede estar atrasado respecto de la base: ya pasó con
-- buscar_o_crear_cliente_club. Comparar el cuerpo real con el que este
-- archivo reemplaza —el de migration_profesional_activo.sql, que es la última
-- que la redefinió— y si no coincide, PARAR y avisar. Esta migración
-- reproduce las tres validaciones que ya tiene (hora pasada, profesional
-- obligatorio, profesional activo) y solo AGREGA una cuarta: si el cuerpo
-- real trajera algo más, se perdería.
--
--   select pg_get_functiondef(p.oid)
--   from pg_proc p join pg_namespace n on n.oid = p.pronamespace
--   where n.nspname = 'public' and p.proname = 'crear_reserva_publica';
--
-- Y confirmar que la función nueva no existe ya con otro cuerpo:
--
--   select count(*) as debe_ser_0
--   from pg_proc p join pg_namespace n on n.oid = p.pronamespace
--   where n.nspname = 'public' and p.proname = 'celular_cl_norm';
-- ═══════════════════════════════════════════════════════════════


-- ═══════════════════════════════════════════════════════════════
-- (1) La regla, en UN solo lugar.
--
-- Devuelve los 9 dígitos si el número es un celular chileno válido, y NULL si
-- no. Que devuelva el normalizado en vez de un boolean es a propósito: la
-- tarea de unificación va a necesitar exactamente ese valor, y así no hay que
-- escribir la regla de nuevo entonces.
--
-- `immutable` porque es texto puro: no lee tablas ni la hora. Eso permite a
-- Postgres usarla en índices o columnas generadas más adelante.
-- ═══════════════════════════════════════════════════════════════

create or replace function celular_cl_norm(p_texto text)
returns text
language sql
immutable
as $function$
  select case
           -- Exactamente 9 dígitos. `right(..., 9)` ya recortó un prefijo +56
           -- o 56; si el número venía corto, acá no llega a 9 y se rechaza.
           when length(t.d) = 9
            -- El móvil chileno empieza en 9. Un fijo (2, 3, ...) no entra.
            and left(t.d, 1) = '9'
            -- Y los 8 dígitos que siguen no pueden ser todos el mismo:
            -- 999999999 y 900000000 son relleno, no teléfonos.
            and substr(t.d, 2, 8) <> repeat(substr(t.d, 2, 1), 8)
           then t.d
         end
  from (
    select right(regexp_replace(coalesce(p_texto, ''), '\D', '', 'g'), 9) as d
  ) t
$function$;

-- PostgREST publica como endpoint toda función del esquema public. Esta no
-- tiene nada que ofrecer afuera —es texto puro, no lee datos— así que no se
-- publica. Mismo tratamiento que email_para_ficha.
--
-- ⚠ HACEN FALTA LAS DOS LÍNEAS, y la segunda no es redundante: Supabase trae
-- default privileges que otorgan EXECUTE sobre toda función nueva a anon y
-- authenticated, con un grant EXPLÍCITO A CADA ROL. Quitárselo a PUBLIC deja
-- el de anon intacto, y con que quede uno la función sigue publicada.
--
-- Que esté revocada NO impide que crear_reserva_publica la use: esa es
-- SECURITY DEFINER y corre como su dueño.
revoke execute on function celular_cl_norm(text) from public;
revoke execute on function celular_cl_norm(text) from anon, authenticated;


-- ═══════════════════════════════════════════════════════════════
-- (2) crear_reserva_publica, con la validación agregada.
--
-- Cuerpo copiado de migration_profesional_activo.sql —la última que la
-- redefinió— con UN bloque nuevo. Las tres validaciones que ya tenía quedan
-- intactas, en el mismo orden y con los mismos mensajes.
--
-- NO cambia la firma, así que `create or replace` alcanza y los permisos se
-- conservan. Nada de drop acá: un drop le quitaría a anon el execute y las
-- reservas públicas dejarían de funcionar por completo.
-- ═══════════════════════════════════════════════════════════════

create or replace function public.crear_reserva_publica(
  p_barberia_id uuid,
  p_nombre_cliente text,
  p_whatsapp_cliente text,
  p_fecha date,
  p_hora time without time zone,
  p_email_cliente text default null::text,
  p_cumpleanos_cliente date default null::date,
  p_servicio text default null::text,
  p_barbero_nombre text default null::text,
  p_notas text default null::text
)
returns uuid
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_id uuid;
  v_barbero_nombre text;
begin
  -- La hora la decide el reloj del servidor, no el del cliente.
  if (p_fecha + p_hora) < (now() at time zone 'America/Santiago') then
    raise exception 'Esa hora ya pasó. Vuelve a cargar la página y elige otra';
  end if;

  if p_barbero_nombre is null
     or btrim(p_barbero_nombre) = ''
     or lower(btrim(p_barbero_nombre)) = 'por asignar' then
    raise exception 'Tienes que elegir un profesional para reservar';
  end if;

  -- Match normalizado, mismo criterio que el resolver de correos: la
  -- capitalización de este sistema no es confiable. Se queda con el nombre de
  -- la ficha, no con el que llegó del navegador.
  -- `activo = true` es el mismo criterio que usan reservar.html y club.html;
  -- excluye los null a propósito (ver el encabezado).
  select nombre into v_barbero_nombre
  from barberos
  where barberia_id = p_barberia_id
    and lower(btrim(nombre)) = lower(btrim(p_barbero_nombre))
    and activo = true
  limit 1;

  if v_barbero_nombre is null then
    raise exception 'El profesional elegido ya no está disponible. Vuelve a cargar la página';
  end if;

  -- ── LO NUEVO ──
  -- Va acá, DESPUÉS de las tres que ya existían, para no cambiar ningún
  -- mensaje que hoy se vea: quien llegue con la hora pasada sigue leyendo lo
  -- de la hora, que es lo útil —va a tener que recargar y elegir de nuevo
  -- igual—. El teléfono es lo último porque es lo único que se corrige sin
  -- recargar.
  --
  -- Mismo texto que unirse_club_publico, que ya está probado en producción.
  -- El mensaje viaja tal cual al navegador vía PostgREST y reservar.html lo
  -- muestra como 'Error al confirmar: <mensaje>'.
  if celular_cl_norm(p_whatsapp_cliente) is null then
    raise exception 'Revisa tu WhatsApp: son 9 dígitos y empieza en 9';
  end if;

  -- Se inserta p_whatsapp_cliente CRUDO, no el normalizado: ver el encabezado.
  -- Cambiarlo acá por celular_cl_norm(...) rompería el match exacto que hacen
  -- otras RPCs contra las fichas viejas.
  insert into reservas (
    barberia_id, nombre_cliente, whatsapp_cliente, email_cliente,
    cumpleanos_cliente, fecha, hora, servicio, barbero_nombre,
    estado, procesado, notas, fuente
  ) values (
    p_barberia_id, p_nombre_cliente, p_whatsapp_cliente, p_email_cliente,
    p_cumpleanos_cliente, p_fecha, p_hora, p_servicio,
    v_barbero_nombre,
    'Confirmada', false, p_notas, 'Web propia'
  ) returning id into v_id;
  return v_id;
end;
$function$;


-- ═══════════════════════════════════════════════════════════════
-- (3) VERIFICACIÓN — las tres son de solo lectura, van juntas en un Run.
--
--   a) La función nueva quedó bien, y NO publicada:
--
--      select p.proname, p.provolatile = 'i' as es_immutable,
--             has_function_privilege('anon', p.oid, 'execute')          as anon,
--             has_function_privilege('authenticated', p.oid, 'execute') as auth
--      from pg_proc p join pg_namespace n on n.oid = p.pronamespace
--      where n.nspname = 'public' and p.proname = 'celular_cl_norm';
--
--      Esperado: es_immutable t, anon f, auth f
--
--   b) ⚠ LA RPC PÚBLICA SIGUE SIENDO LLAMABLE POR anon. Acá el esperado es al
--      revés que en (a): si esto diera f, NADIE podría reservar por el link.
--
--      select p.proname,
--             has_function_privilege('anon', p.oid, 'execute') as anon_puede,
--             p.prosrc like '%celular_cl_norm%'                as tiene_la_validacion,
--             p.prosrc like '%America/Santiago%'               as conserva_hora_pasada,
--             p.prosrc like '%ya no está disponible%'           as conserva_prof_activo
--      from pg_proc p join pg_namespace n on n.oid = p.pronamespace
--      where n.nspname = 'public' and p.proname = 'crear_reserva_publica';
--
--      Esperado: anon_puede t, y las otras tres t — las dos últimas confirman
--      que no se perdió ninguna validación previa al reescribir el cuerpo.
--
--   c) LA TABLA DE CASOS. Son los MISMOS casos que corre el test JS, así que
--      esto es la mitad en la base de la prueba de paridad: si una fila da
--      distinto que su gemela en test-reserva-publica.html, las dos reglas se
--      separaron.
--
--      select c.entrada, celular_cl_norm(c.entrada) as resultado, c.esperado
--      from (values
--        ('987542136',        '987542136'),  -- pelado
--        ('+56987542136',     '987542136'),  -- con +56
--        ('56987542136',      '987542136'),  -- con 56
--        ('+56 9 8754 2136',  '987542136'),  -- con espacios
--        ('+56-9-8754-2136',  '987542136'),  -- con guiones
--        ('87542136',         null),         -- 8 dígitos: NO se repara
--        ('221234567',        null),         -- fijo, empieza en 2
--        ('999999999',        null),         -- relleno
--        ('900000000',        null),         -- relleno
--        ('911111111',        null),         -- relleno
--        ('9875421',          null),         -- corto
--        ('',                 null),         -- vacío
--        (null,               null),         -- nulo
--        ('no tengo',         null),         -- texto
--        ('912345678',        '912345678')   -- válido que NO es repetido
--      ) as c(entrada, esperado)
--      where celular_cl_norm(c.entrada) is distinct from c.esperado;
--
--      Esperado: CERO FILAS. La consulta devuelve solo los casos que fallan,
--      así que una tabla vacía es el verde. Si devuelve algo, cada fila
--      muestra qué entrada dio qué y qué se esperaba.
-- ═══════════════════════════════════════════════════════════════
