-- Campos que quedaron afuera de la migración del rediseño de perfil de
-- negocio (sesión anterior): descripción del negocio (pedido original del
-- dueño, "una descripción del local") y especialidad corta del profesional
-- (distinto de "bio", que ya existe — esto es un título tipo "Barbero").
--
-- Ejecutar UNA VEZ, completo, en el SQL Editor de Supabase.

alter table barberias add column if not exists descripcion text;
alter table barberos add column if not exists especialidad text;
