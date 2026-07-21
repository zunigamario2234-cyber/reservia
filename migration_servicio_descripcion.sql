-- Agrega descripción libre y opcional a "servicios".
-- Ejecutar UNA VEZ en el SQL Editor de Supabase.
--
-- No requiere cambios de RLS: "servicios_insert_own"/"servicios_update_own"
-- (ver migration_rls.sql) ya filtran por barberia_id = auth_barberia_id()
-- sin importar qué columnas se escriban, y "servicios_select_public" ya
-- permite leer la fila completa (incluida esta columna nueva) desde
-- reservar.html.

alter table servicios add column if not exists descripcion text;
