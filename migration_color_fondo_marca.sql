-- =============================================================================
-- FONDO CON EL COLOR DE LA MARCA.
-- Además de claro/oscuro, el dueño puede pintar el fondo del panel y de sus
-- páginas públicas con un color de su logo (gris, verde, vino…) y dejar otro
-- color del logo como acento. NULL = tema neutro de siempre (claro u oscuro).
-- El modo se deduce del propio color de fondo, así que modo_tema no cambia.
-- Aditiva. DEBE APLICARSE ANTES de subir el código: club.html, unirse.html y
-- mi-agenda.html piden esta columna.
-- =============================================================================
alter table public.barberias add column if not exists color_fondo_marca text
  check (color_fondo_marca is null or color_fondo_marca ~ '^#[0-9A-Fa-f]{6}$');
