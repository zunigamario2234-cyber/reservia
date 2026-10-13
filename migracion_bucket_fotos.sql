-- ═══════════════════════════════════════════════════════════════════════
-- BUCKET `fotos` — cerrar la escritura anónima.
--
-- PROBLEMA QUE ARREGLA
-- Las cuatro políticas actuales (`subir fotos`, `actualizar fotos`,
-- `eliminar fotos`, `ver fotos`) están asignadas al rol `public` con la
-- única condición `bucket_id = 'fotos'`. El rol `public` de Postgres
-- incluye `anon`, así que cualquiera con la llave anónima — que es pública
-- por diseño y viaja en toda página — puede sobrescribir el logo de
-- cualquier negocio, borrar todas las imágenes de todos, listar el bucket
-- completo y subir archivos sin límite (riesgo de facturación).
--
-- POR QUÉ ES SEGURO CERRARLO
-- No existe una sola escritura anónima legítima. Las cinco rutas que el
-- código escribe están todas en app.html, detrás del login:
--   logos/{barberia_id}/logo.jpg                 subirLogoBlob
--   portadas/{barberia_id}/portada.jpg           subirPortadaBlob
--   profesionales/{barberia_id}/{ts}.jpg         guardarProfesional
--   servicios/{barberia_id}/{ts}.{ext}           guardarServicio
--   alianzas/{barberia_id}/{ts}.{ext}            guardarAlianza
-- Y nadie llama list(), remove(), download(), move() ni copy(): solo
-- upload() y getPublicUrl(), que es construcción de string sin red.
--
-- Las cinco tablas destino (barberias, barberos, servicios, alianzas)
-- ya exigen auth_barberia_id() Y auth_rol() = 'dueno', así que la política
-- del bucket puede ser una sola, uniforme, sin distinguir carpeta.
--
-- ⚠ VA EN UNA TRANSACCIÓN A PROPÓSITO.
-- Entre el DROP y el CREATE el bucket queda sin ninguna política, o sea
-- cerrado para todos. Si un CREATE fallara a mitad de camino y no hubiera
-- transacción, las subidas del dueño quedarían rotas hasta que alguien lo
-- note. Este archivo no contiene cuerpos con $$, así que envolverlo en
-- begin/commit es seguro: no aplica la trampa del editor que descarta en
-- silencio las definiciones con $$ dentro de una transacción.
--
-- ⚠ SI EL EDITOR RECHAZA EL CREATE POLICY por no ser dueño de
-- storage.objects, hay que hacerlo desde Storage → Policies en el panel.
-- ═══════════════════════════════════════════════════════════════════════


-- ═══════════════════════════════════════════════════════════════════════
-- EVIDENCIA VERIFICADA EN EL CÓDIGO ANTES DE ESCRIBIR ESTO
-- (lo que sostiene que la política no deja afuera a nadie legítimo)
--
-- (a) EL LITERAL DEL ROL ES 'dueno'.
--     perfiles.rol es `text DEFAULT 'barbero'::text`, SIN check constraint:
--     el valor no lo garantiza la base, lo garantiza el código. Los dos
--     caminos que crean el perfil de un dueño escriben el mismo literal:
--       · ingresar.html:189  signUp(..., options:{data:{rol:'dueno'}})
--         que handle_new_user() lee con
--         coalesce(new.raw_user_meta_data->>'rol', 'dueno')
--       · ingresar.html:198  perfiles.insert({..., rol:'dueno'})
--     Y el proyecto usa solo tres valores: dueno (146 apariciones),
--     profesional (11), barbero (2). No existe 'owner' ni 'admin'.
--     ⚠ LA PRUEBA MÁS FUERTE: nueve políticas VIVAS de barberias,
--     servicios, alianzas, barberos y barbero_servicios ya exigen
--     auth_rol() = 'dueno'. Si el literal no calzara, el dueño hoy no
--     podría guardar un servicio ni editar su negocio. Esta política no
--     es más estricta que lo que ya gobierna cada escritura suya.
--
-- (b) NINGUNA SUBIDA OCURRE ANTES DE QUE EXISTA LA FILA.
--     ingresar.html NO TOCA STORAGE: cero subidas en el registro
--     (verificado: ni `storage`, ni `upload`, ni un input de archivo).
--     Orden de doReg(): signUp -> barberias.insert -> perfiles.insert con
--     barberia_id -> servicios/horario_negocio/niveles_vip.
--     Y app.html no puede cargar sin negocio: loadAll() hace
--       select * from barberias where id = perfiles.barberia_id
--       if(eb||!b) throw 'No encontramos el negocio asociado a tu cuenta'
--     así que S.barberia siempre existe cuando el panel es usable, y las
--     cinco rutas se construyen con S.barberia.id. auth_barberia_id()
--     null no puede coincidir con una subida: el panel falla antes.
--
-- (c) LAS CINCO RUTAS TIENEN EXACTAMENTE 3 SEGMENTOS.
--     Las cinco plantillas (app.html 2830, 2958, 3043, 6225, 6249) usan
--     todas S.barberia.id como segundo segmento, y ninguna agrega
--     subniveles ni el id del profesional:
--       logos/{id}/logo.jpg                  foldername = 2  PASA
--       portadas/{id}/portada.jpg            foldername = 2  PASA
--       profesionales/{id}/{Date.now()}.jpg  foldername = 2  PASA
--       servicios/{id}/{Date.now()}.{ext}    foldername = 2  PASA
--       alianzas/{id}/{Date.now()}.{ext}     foldername = 2  PASA
--     Date.now() es un número: no puede traer barras. La ÚNICA forma de
--     pasar de 3 segmentos es el `ext` sin sanitizar de servicios y
--     alianzas, y ese caso es justo el que queremos bloquear:
--       servicios/{id}/{ts}.png/../../logos/OTRO/logo  foldername = 7
--
-- (d) QUIÉNES SUBEN HOY.
--     Los cinco puntos están en app.html y ninguno comprueba el rol. La
--     única referencia a `rol` en las ~6.400 líneas del panel es la
--     etiqueta de la barra lateral (app.html:1519). Y ingresar.html manda
--     a TODOS a app.html sin mirar el rol (líneas 147, 231, 246), así que
--     un `profesional` o un `barbero` llega al panel del dueño y hoy la
--     subida le funciona (y el guardado en la tabla le falla, dejando un
--     archivo huérfano). No existe superadmin en el proyecto: cero
--     apariciones de superadmin/super_admin en todo el código.
--     => Con esta migración, solo el dueño sube. Es un CAMBIO DE
--        COMPORTAMIENTO para profesionales, intencional, y necesita el
--        mensaje claro que va en el paso B.
-- ═══════════════════════════════════════════════════════════════════════


-- ═══════════════════════════════════════════════════════════════════════
-- PASO -1 — CORRER ESTO SOLO, PRIMERO, Y GUARDAR LA SALIDA.
--
-- Esta salida ES la fuente de verdad del rollback. El rollback escrito al
-- final de este archivo reconstruye las políticas según cómo fueron
-- descritas, no según un dump: si difieren, manda esta salida.
--
-- ⚠ CORRERLA SOLA. Si se ejecuta el archivo entero de una vez, el editor
-- muestra únicamente el resultado del último select y este volcado se
-- pierde — justo el que necesitamos guardar antes de borrar las políticas.
-- ═══════════════════════════════════════════════════════════════════════
select policyname, cmd, roles::text, qual, with_check
  from pg_policies
 where schemaname = 'storage' and tablename = 'objects'
 order by policyname;


-- ═══════════════════════════════════════════════════════════════════════
-- DE ACÁ PARA ABAJO: recién después de guardar la salida de arriba.
-- ═══════════════════════════════════════════════════════════════════════

begin;

-- ───────────────────────────────────────────────────────────────────────
-- PASO 0 — Prerrequisito: fijar search_path en las dos funciones auth.
--
-- Hoy las dos son LANGUAGE sql STABLE SECURITY DEFINER con proconfig
-- NULL (confirmado), y sus cuerpos nombran `perfiles` sin calificar:
--   auth_barberia_id() -> select barberia_id from perfiles where id = auth.uid()
--   auth_rol()         -> select rol         from perfiles where id = auth.uid()
--
-- Las políticas de las TABLAS funcionan porque las evalúa PostgREST, cuyo
-- search_path incluye public. Las de storage.objects las evalúa
-- storage-api, con OTRA conexión y otro search_path. Si ahí `perfiles` no
-- resuelve, la política no deniega: ERRORA, y se corta toda subida.
--
-- Esto además paga una deuda MEDIA ya conocida del proyecto.
--
-- RENDIMIENTO: no hay degradación. Una función SQL con cláusula SET no se
-- expande en línea, pero estas ya no se expandían por ser SECURITY
-- DEFINER (el planificador se niega: expandirla correría su cuerpo con
-- los privilegios de quien llama). Lo único que se agrega es un
-- guardar/restaurar de GUC por llamada.
--
-- pg_temp va AL FINAL a propósito: si quedara primero, un pg_temp.perfiles
-- creado por el usuario secuestraría la función.
--
-- ⚠ Estas dos funciones las usan ~50 políticas vivas. El cambio es
-- estrictamente más seguro, pero es camino caliente: abrir el panel
-- inmediatamente después y confirmar que carga.
-- ───────────────────────────────────────────────────────────────────────
alter function public.auth_barberia_id() set search_path = public, pg_temp;
alter function public.auth_rol()         set search_path = public, pg_temp;


-- ───────────────────────────────────────────────────────────────────────
-- PASO 1 — Fuera las cuatro políticas abiertas.
-- ───────────────────────────────────────────────────────────────────────
drop policy if exists "subir fotos"      on storage.objects;
drop policy if exists "actualizar fotos" on storage.objects;
drop policy if exists "eliminar fotos"   on storage.objects;
drop policy if exists "ver fotos"        on storage.objects;


-- ───────────────────────────────────────────────────────────────────────
-- PASO 2 — Escritura: solo el dueño, solo su carpeta.
--
-- Las cuatro condiciones que importan:
--   array_length = 2       exactamente carpeta/barberia_id/archivo
--   [1] in (...)           la carpeta es una de las cinco conocidas
--   [2] = su barberia_id   no puede escribir en la de otro
--   auth_rol() = 'dueno'   igual que las cinco tablas destino
--
-- El array_length NO es decorativo: bloquea el path traversal que hoy
-- permite el `ext` sin sanitizar de guardarServicio/guardarAlianza
-- (fotoFile.name.split('.').pop() no puede traer un punto, pero sí
-- barras). Un nombre con ../ produce más de dos segmentos de carpeta y la
-- política lo rechaza, independiente de que el front se arregle o no.
--
-- La comparación de [2] es TEXTO contra TEXTO, no uuid. Castear a uuid
-- erraría ante una ruta cuyo segundo segmento no sea un uuid, y un error
-- dentro de una política es un 500 en vez de un 403 limpio.
--
-- La condición va repetida en vez de extraída a una función auxiliar: son
-- políticas contiguas e idénticas, y una función en `public` quedaría
-- publicada como RPC por PostgREST.
-- ───────────────────────────────────────────────────────────────────────
create policy fotos_insert_dueno on storage.objects
  for insert to authenticated
  with check (
    bucket_id = 'fotos'
    and array_length(storage.foldername(name), 1) = 2
    and (storage.foldername(name))[1] in ('logos','portadas','profesionales','servicios','alianzas')
    and (storage.foldername(name))[2] = public.auth_barberia_id()::text
    and public.auth_rol() = 'dueno'
  );

-- upsert:true necesita INSERT y UPDATE.
-- USING decide qué fila puede tocar; WITH CHECK, cómo puede quedar. Las
-- dos con la misma condición, para que no pueda mover un archivo desde su
-- carpeta hacia la de otro.
create policy fotos_update_dueno on storage.objects
  for update to authenticated
  using (
    bucket_id = 'fotos'
    and array_length(storage.foldername(name), 1) = 2
    and (storage.foldername(name))[1] in ('logos','portadas','profesionales','servicios','alianzas')
    and (storage.foldername(name))[2] = public.auth_barberia_id()::text
    and public.auth_rol() = 'dueno'
  )
  with check (
    bucket_id = 'fotos'
    and array_length(storage.foldername(name), 1) = 2
    and (storage.foldername(name))[1] in ('logos','portadas','profesionales','servicios','alianzas')
    and (storage.foldername(name))[2] = public.auth_barberia_id()::text
    and public.auth_rol() = 'dueno'
  );

-- Hoy nadie llama remove(). Se crea igual porque la Entrega 1 del tema por
-- logo la va a necesitar para limpiar el logo.jpg huérfano cuando el
-- formato del recorte pase a PNG/WebP.
create policy fotos_delete_dueno on storage.objects
  for delete to authenticated
  using (
    bucket_id = 'fotos'
    and array_length(storage.foldername(name), 1) = 2
    and (storage.foldername(name))[1] in ('logos','portadas','profesionales','servicios','alianzas')
    and (storage.foldername(name))[2] = public.auth_barberia_id()::text
    and public.auth_rol() = 'dueno'
  );


-- ───────────────────────────────────────────────────────────────────────
-- PASO 3 — Lectura.
--
-- NO se crea política SELECT para anónimos. El bucket es público, así que
-- /storage/v1/object/public/... no pasa por RLS y las imágenes siguen
-- cargando en reservar.html, club.html, unirse.html, aliado.html y en los
-- correos. Sin política SELECT, un anónimo deja de poder LISTAR el bucket,
-- que es justo lo que queremos cortar.
--
-- Sí se le da SELECT al dueño sobre su propia carpeta, por una razón
-- práctica: supabase-js con upsert:true puede consultar si el objeto ya
-- existe antes de decidir INSERT o UPDATE. Sin SELECT eso podría fallar de
-- una forma difícil de diagnosticar. No abre nada que no sea suyo.
--
-- Acá no va el array_length: es solo lectura de lo propio, y si alguna
-- ruta vieja tuviera más segmentos, igual queremos que el dueño la vea.
-- ───────────────────────────────────────────────────────────────────────
create policy fotos_select_propia on storage.objects
  for select to authenticated
  using (
    bucket_id = 'fotos'
    and (storage.foldername(name))[2] = public.auth_barberia_id()::text
  );

commit;


-- ═══════════════════════════════════════════════════════════════════════
-- VERIFICACIÓN — correr DESPUÉS del commit, una consulta por vez.
-- El editor muestra solo el resultado del último select.
-- ═══════════════════════════════════════════════════════════════════════

-- (1) Las políticas: deben ser EXACTAMENTE cuatro, todas {authenticated}.
--     Esperado: fotos_delete_dueno DELETE, fotos_insert_dueno INSERT,
--               fotos_select_propia SELECT, fotos_update_dueno UPDATE.
-- select policyname, cmd, roles::text
--   from pg_policies
--  where schemaname = 'storage' and tablename = 'objects'
--  order by policyname;

-- (2) Que no quede NINGUNA política abierta a public o anon.
--     Esperado: 0
-- select count(*) as politicas_abiertas
--   from pg_policies
--  where schemaname = 'storage' and tablename = 'objects'
--    and (roles::text like '%public%' or roles::text like '%anon%');

-- (3) Que el search_path quedó fijo en las dos funciones.
--     Esperado: proconfig = {search_path=public,pg_temp} en las dos,
--               y prosecdef = true en las dos (no se tocó).
-- select p.proname, p.proconfig, p.prosecdef
--   from pg_proc p
--   join pg_namespace n on n.oid = p.pronamespace
--  where n.nspname = 'public'
--    and p.proname in ('auth_barberia_id','auth_rol')
--  order by p.proname;

-- (4) Estado del bucket. Los límites NO se tocan en esta migración.
--     Esperado hoy: public = true, file_size_limit y allowed_mime_types
--     en null.
-- select id, public, file_size_limit, allowed_mime_types
--   from storage.buckets
--  where id = 'fotos';


-- ═══════════════════════════════════════════════════════════════════════
-- LÍMITES DEL BUCKET — NO VAN ACÁ. Van en una migración posterior,
-- después de arreglar el front.
--
-- update storage.buckets
--    set file_size_limit    = 2097152,
--        allowed_mime_types = array['image/jpeg','image/png','image/webp']
--  where id = 'fotos';
--
-- POR QUÉ NO AHORA: rompería dos pantallas.
--  · guardarServicio y guardarAlianza suben el ARCHIVO CRUDO del input, no
--    un blob recortado. Una foto de celular pesa 5–8 MB: con 2 MB,
--    Servicios y Alianzas dejan de funcionar.
--  · Esas dos suben SIN contentType, así que supabase-js manda el `type`
--    que declara el navegador. Un iPhone puede entregar image/heic, que el
--    whitelist rechaza: fallaría para usuarios de iPhone y no para otros,
--    el peor tipo de error.
--
-- Y allowed_mime_types filtra el encabezado declarado, no el contenido
-- real. La garantía de tipo real la da pasar todo por el recortador, que
-- re-codifica la imagen.
-- ═══════════════════════════════════════════════════════════════════════


-- ═══════════════════════════════════════════════════════════════════════
-- ROLLBACK — NO CORRER salvo que las políticas nuevas corten subidas
-- legítimas y haga falta volver atrás mientras se diagnostica.
--
-- ⚠ ESTO REABRE EL BUCKET A CUALQUIERA. Es el estado vulnerable de hoy.
-- No dejarlo así: es un puente para diagnosticar, no un destino.
--
-- ⚠ Reconstruye las cuatro políticas según cómo fueron descritas (rol
-- `public`, única condición bucket_id = 'fotos'). Si la salida guardada en
-- el PASO -1 difiere, manda esa salida, no esto.
--
-- El `reset search_path` del final casi nunca conviene: el estado con
-- search_path fijo es el seguro. Solo revertirlo si se demuestra que
-- rompió algo.
-- ═══════════════════════════════════════════════════════════════════════
-- begin;
--
-- drop policy if exists fotos_insert_dueno  on storage.objects;
-- drop policy if exists fotos_update_dueno  on storage.objects;
-- drop policy if exists fotos_delete_dueno  on storage.objects;
-- drop policy if exists fotos_select_propia on storage.objects;
--
-- create policy "subir fotos" on storage.objects
--   for insert to public with check (bucket_id = 'fotos');
-- create policy "actualizar fotos" on storage.objects
--   for update to public using (bucket_id = 'fotos') with check (bucket_id = 'fotos');
-- create policy "eliminar fotos" on storage.objects
--   for delete to public using (bucket_id = 'fotos');
-- create policy "ver fotos" on storage.objects
--   for select to public using (bucket_id = 'fotos');
--
-- -- Solo si se demuestra que el PASO 0 rompió algo:
-- -- alter function public.auth_barberia_id() reset search_path;
-- -- alter function public.auth_rol()         reset search_path;
--
-- commit;
