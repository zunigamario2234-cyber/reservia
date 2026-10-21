-- ═══════════════════════════════════════════════════════════════════════
-- TEMA POR LOGO: color de fondo detectado del logo, en barberias.
--
-- APLICADA EN PRODUCCIÓN EL 2026-10-20 por Mario, desde el SQL Editor.
-- Este archivo la deja registrada en el repo; no hace falta volver a
-- correrla. El SQL es el que se aplicó, no una reconstrucción.
--
-- Verificación corrida después de aplicar:
--   columna_ok = 1      (la columna existe, text, nullable)
--   total      = 13     (las 13 barberías)
--   con_valor  = 0      (ninguna tiene valor todavía)
-- Ese con_valor = 0 es lo que garantiza que ningún negocio cambió de
-- apariencia al aplicarla: la columna nace vacía para todos.
--
-- PARA QUÉ SIRVE. Las tres páginas públicas pintan la franja detrás del
-- logo con un #12131f fijo (reservar.html:23, club.html:24,
-- unirse.html:22). Eso recorta las esquinas de un logo con fondo opaco
-- propio y deja franjas oscuras alrededor de uno que no es cuadrado. Esta
-- columna guarda el fondo que el panel DETECTÓ en el logo, para que la
-- franja use ese color en vez del fijo.
--
-- QUIÉN LA ESCRIBE: solo el panel del dueño, en app.html, por dos vías.
--   · subirLogoBlob: en el MISMO update que logo_url, para que las dos
--     columnas no puedan quedar en desacuerdo. Si el análisis falla, si el
--     fondo no es uniforme o si el logo es transparente, escribe NULL —
--     nunca deja el valor del logo anterior.
--   · temaGuardar: solo cuando hay un análisis vigente del logo actual. Si
--     el análisis está pendiente, falló o no hay logo, NO toca la columna,
--     porque el valor guardado ya corresponde al logo actual y escribir
--     NULL por un análisis incompleto borraría un valor bueno.
-- Ninguna página pública escribe acá. El análisis del logo ocurre
-- únicamente en el panel; las páginas solo leen.
--
-- modo_tema NO SE TOCA al subir un logo: es decisión del dueño y se cambia
-- solo desde el selector.
--
-- LAS PÁGINAS PÚBLICAS LA IGNORAN cuando color_marca es NULL. Sin esa
-- regla, un negocio sin color de marca cambiaría de aspecto solo por haber
-- subido un logo, y eso rompe "sin color de marca = exactamente como hoy".
--
-- GRANTS: no hacen falta. El GRANT de anon sobre barberias es a nivel
-- TABLA (verificado en information_schema.table_privileges: SELECT, INSERT,
-- UPDATE y otros), así que una columna nueva lo hereda sin GRANT extra. La
-- escritura la sigue cerrando barberias_update_own, que exige
-- id = auth_barberia_id() y auth_rol() = 'dueno'; comprobado con la llave
-- anónima, un PATCH a color_marca devuelve 200 con cuerpo [] y no escribe
-- nada. Ojo con eso al verificar: el 200 no significa que haya escrito.
--
-- El check es el mismo de color_marca, carácter por carácter, y la misma
-- expresión que hexValido() en tema.js: el valor se inyecta en estilos, así
-- que cualquier otra cosa sería inyección de CSS.
-- ═══════════════════════════════════════════════════════════════════════

alter table barberias
  add column if not exists color_fondo_logo text;

alter table barberias
  add constraint barberias_color_fondo_logo_hex
    check ((color_fondo_logo is null) or (color_fondo_logo ~ '^#[0-9A-Fa-f]{6}$'));

-- ── Verificación ────────────────────────────────────────────────────────
-- select count(*) as columna_ok
--   from information_schema.columns
--  where table_schema='public' and table_name='barberias'
--    and column_name='color_fondo_logo' and data_type='text' and is_nullable='YES';
--
-- select count(*) as total, count(color_fondo_logo) as con_valor
--   from barberias;
--
-- Y que el check rechaza lo que no es un hex. Va entre begin y rollback
-- porque la prueba ESCRIBE, y el SQL Editor de Supabase no mantiene sesión
-- entre ejecuciones: el bloque se selecciona entero y se corre de una.
--
-- begin;
--   update barberias set color_fondo_logo = 'rojo'
--    where id = 'd75633ff-4f6a-4f32-b5b4-83b62ee80f24';   -- debe FALLAR
-- rollback;
--
-- begin;
--   update barberias set color_fondo_logo = '#12131f;}body{display:none'
--    where id = 'd75633ff-4f6a-4f32-b5b4-83b62ee80f24';   -- debe FALLAR
-- rollback;

-- ── Reversa ─────────────────────────────────────────────────────────────
-- No toca color_marca ni modo_tema, no toca ninguna política y no reabre
-- ningún permiso. Una página que ya leyera color_fondo_logo recibiría
-- undefined y caería a su rama de NULL, que es la apariencia de hoy.
--
-- alter table barberias drop constraint if exists barberias_color_fondo_logo_hex, drop column if exists color_fondo_logo;
