-- Agrega el campo "rubro" a barberias para controlar si el Club VIP está disponible.
-- Ejecutar una sola vez en el SQL Editor de Supabase. Es idempotente (seguro de correr más de una vez).
-- Default = 'Barbería / Peluquería / Centro de estética' para no romper el Club VIP en negocios ya existentes.

alter table barberias add column if not exists rubro text not null default 'Barbería / Peluquería / Centro de estética';
