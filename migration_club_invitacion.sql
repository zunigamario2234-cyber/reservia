-- Correo de bienvenida al Club en la PRIMERA visita cobrada de un cliente.
-- Esta columna marca que ya se le mandó (se reclama antes de enviar, así que
-- repetir el cobro o la llamada nunca duplica el correo).
alter table public.clientes add column if not exists club_invitado_at timestamptz;
