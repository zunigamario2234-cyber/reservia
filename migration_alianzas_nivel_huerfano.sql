-- Distingue "Todos" elegido a propósito de "huérfana" (el nivel al que
-- apuntaba se borró). Hasta ahora ambos casos guardaban nivel_minimo_id
-- = null y eran indistinguibles. A partir de ahora:
--
--   nivel_sin_restriccion = true  → "Todos", elegido explícitamente en
--     la UI. Visible para cualquier cliente en club.html, sin advertencia.
--
--   nivel_sin_restriccion = false y nivel_minimo_id = null → huérfana:
--     el nivel que tenía asignado se borró (on delete set null). Se
--     oculta en club.html hasta que el dueño la reasigne, y se marca
--     con una advertencia en Config → Alianzas para que no pase
--     desapercibida.
--
-- Ejecutar UNA VEZ en el SQL Editor de Supabase.

alter table alianzas add column if not exists nivel_sin_restriccion boolean not null default false;

-- Las alianzas que hoy tienen nivel_minimo_id null son legítimamente
-- "Todos" (vinieron así de migration_niveles_vip.sql o se eligieron así
-- desde la UI) — todavía no puede haber ninguna huérfana real, porque
-- el borrado de niveles recién queda habilitado con este cambio.
update alianzas set nivel_sin_restriccion = true where nivel_minimo_id is null;
