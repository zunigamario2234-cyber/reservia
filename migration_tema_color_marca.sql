-- ═══════════════════════════════════════════════════════════════════════
-- TEMA POR LOGO: color de marca y modo del tema en barberias.
--
-- YA ESTÁ APLICADA EN PRODUCCIÓN. Este archivo la deja registrada en el
-- repo; no hace falta volver a correrla. Las definiciones son las que hoy
-- tiene la base, no una reconstrucción.
--
-- Hoy solo las lee y las escribe el panel del tema en app.html. Las
-- páginas públicas y los correos todavía no las leen (Entregas 2 y 3).
--
-- color_marca: el acento que eligió el dueño en el panel del tema. NULL
--   significa "sin tema propio". El check exige un hex de seis dígitos,
--   con la misma expresión que hexValido() en tema.js, para que el valor
--   pueda ir a CSS sin escapar.
-- modo_tema: 'auto', 'claro' u 'oscuro'. El panel guarda el modo
--   CONCRETO (claro u oscuro), nunca 'auto'. 'auto' es el default de los
--   negocios que todavía no guardaron un tema.
--
-- No se sabe si modo_tema es NOT NULL; este archivo no lo declara.
-- ═══════════════════════════════════════════════════════════════════════

alter table barberias
  add column color_marca text default null,
  add column modo_tema text default 'auto'::text;

alter table barberias
  add constraint barberias_color_marca_hex
    check (((color_marca IS NULL) OR (color_marca ~ '^#[0-9A-Fa-f]{6}$'::text))),
  add constraint barberias_modo_tema_valido
    check ((modo_tema = ANY (ARRAY['auto'::text, 'claro'::text, 'oscuro'::text])));

-- ── Reversa ─────────────────────────────────────────────────────────────
-- alter table barberias drop constraint barberias_color_marca_hex, drop constraint barberias_modo_tema_valido, drop column color_marca, drop column modo_tema;
