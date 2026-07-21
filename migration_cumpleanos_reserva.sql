-- Agrega cumpleanos_cliente a "reservas", siguiendo el mismo patrón ya
-- existente de nombre_cliente/whatsapp_cliente/email_cliente: reservar.html
-- no crea un cliente directamente (eso solo pasa en procesarReserva()),
-- así que el dato tiene que sobrevivir en la propia fila de la reserva
-- hasta que se procese. Campo opcional, no bloquea la reserva.
--
-- No requiere cambios de RLS: reservas_insert_public ya permite insertar
-- cualquier columna de la tabla, y reservas_select_own/update_own ya
-- están scoped por barberia_id = auth_barberia_id().

alter table reservas add column if not exists cumpleanos_cliente date;
