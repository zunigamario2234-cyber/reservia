-- ═══════════════════════════════════════════════════════════════════════
-- BUCKET `fotos` — PASO C: límite de tamaño y tipos permitidos.
--
-- APLICADO EN PRODUCCIÓN EL 2026-10-13.
--
-- Cierra lo que el paso A dejó deliberadamente afuera. El paso A arregló
-- QUIÉN puede escribir (solo el dueño, solo en su carpeta); esto limita QUÉ
-- se puede escribir.
--
-- ⚠ POR QUÉ NO PODÍA IR ANTES DEL PASO B
-- guardarServicio y guardarAlianza subían el ARCHIVO CRUDO del input, sin
-- pasar por el recortador y sin contentType. Medido con una fuente de
-- 4000x3000 (12 MP, lo que entrega un celular):
--
--   crudo, JPEG q0.95 ............ 11,56 MB   577% del límite
--   recortado a 512x512 q0.92 .... 0,19 MB     ~10% del límite
--
-- Con el límite puesto antes del paso B, Servicios y Alianzas se habrían
-- roto para cualquiera que subiera una foto del teléfono.
--
-- Desde el paso B las cinco subidas pasan por el recortador y declaran
-- contentType = blob.type, que solo puede ser uno de estos tres.
--
-- ⚠ allowed_mime_types FILTRA EL ENCABEZADO DECLARADO, NO EL CONTENIDO
-- No valida que el archivo sea realmente una imagen. La garantía del tipo
-- real la da el recortador, que re-codifica: lo que se sube es siempre lo
-- que salió del canvas. Las dos capas son complementarias, no redundantes.
--
-- SVG queda afuera a propósito: servido desde un bucket público puede
-- llevar scripts, y el recortador lo convierte a mapa de bits de todas
-- formas, así que ninguna subida legítima lo necesita. El dominio de
-- extDeMime() en app.html es exactamente {jpg, png, webp}, los mismos tres
-- tipos: si alguien agrega un formato al recortador y se olvida del bucket,
-- la subida falla de inmediato en vez de guardar algo inconsistente.
-- ═══════════════════════════════════════════════════════════════════════

begin;

update storage.buckets
   set file_size_limit    = 2097152,
       allowed_mime_types = array['image/jpeg','image/png','image/webp']
 where id = 'fotos';

commit;


-- ═══════════════════════════════════════════════════════════════════════
-- VERIFICACIÓN — correr después del commit.
--
-- Esperado:
--   public              = true       ← que SIGA en true es parte de esto:
--                                      si se apagara, se caen las imágenes
--                                      de los 13 negocios
--   file_size_limit     = 2097152
--   allowed_mime_types  = {image/jpeg,image/png,image/webp}
-- ═══════════════════════════════════════════════════════════════════════
-- select id, public, file_size_limit, allowed_mime_types
--   from storage.buckets
--  where id = 'fotos';


-- ═══════════════════════════════════════════════════════════════════════
-- ESTADO MEDIDO ANTES DE APLICAR (2026-10-13)
--
-- Las dos consultas que se corrieron para decidir el límite:
--
--   select (storage.foldername(name))[1] as carpeta,
--          count(*)                                  as objetos,
--          count(*) filter (where (metadata->>'mimetype') not in
--                ('image/jpeg','image/png','image/webp')) as tipo_fuera_de_norma,
--          count(*) filter (where (metadata->>'size')::bigint > 2097152) as sobre_2mb,
--          max((metadata->>'size')::bigint)           as mas_grande
--     from storage.objects
--    where bucket_id = 'fotos'
--    group by 1 order by 1;
--
--   select name, metadata->>'mimetype' as tipo,
--          (metadata->>'size')::bigint as bytes
--     from storage.objects
--    where bucket_id = 'fotos'
--      and ( (metadata->>'mimetype') not in ('image/jpeg','image/png','image/webp')
--         or (metadata->>'size')::bigint > 2097152 )
--    order by (metadata->>'size')::bigint desc;
--
-- Resultado: CERO objetos fuera de norma. El más grande pesa 1.578.705
-- bytes, el 75% del límite de 2.097.152 — el número más ajustado de todos,
-- pero por debajo. Es un objeto legado y el límite no lo toca: solo mira
-- subidas nuevas. Las que vienen del recortador no pasan de 0,60 MB ni en
-- el peor caso (un PNG de ruido puro, que comprime peor que cualquier foto
-- real).
-- ═══════════════════════════════════════════════════════════════════════


-- ═══════════════════════════════════════════════════════════════════════
-- ROLLBACK — ejecutable, listo para pegar.
--
-- Vuelve al estado anterior: sin límite de tamaño y sin restricción de
-- tipo. A diferencia del rollback del paso A, esto NO TOCA NINGUNA
-- POLÍTICA: no reabre ningún permiso, solo quita las dos barreras de
-- contenido. Un anónimo sigue sin poder escribir, borrar ni listar.
-- ═══════════════════════════════════════════════════════════════════════
-- begin;
--
-- update storage.buckets
--    set file_size_limit    = null,
--        allowed_mime_types = null
--  where id = 'fotos';
--
-- commit;
