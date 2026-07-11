-- Agrega el campo "estado" a reservas y visitas para la vista de Agenda con colores por estado.
-- Ejecutar una sola vez en el SQL Editor de Supabase. Es idempotente (seguro de correr más de una vez).

alter table reservas add column if not exists estado text not null default 'Pendiente';
update reservas set estado='Atendida' where procesado=true and estado='Pendiente';

alter table visitas add column if not exists estado text not null default 'Atendida';
