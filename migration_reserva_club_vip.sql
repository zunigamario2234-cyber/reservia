-- Permite reservar directamente desde club.html (Mi Club VIP), sin que el
-- cliente vuelva a escribir nombre/WhatsApp/email — ya lo identificamos por
-- el cliente_id que viene en el link (?id=<barberia>&cliente=<cliente_id>),
-- el mismo que ya usa get_club_vip_publico.
--
-- Por qué una función nueva en vez de ampliar get_club_vip_publico:
-- get_club_vip_publico ya está en uso (club.html la llama para nivel/
-- progreso) y devuelve una tabla con columnas fijas (cliente_id,
-- barberia_id, nombre, total_visitas, nivel) — Postgres no permite
-- agregarle columnas vía CREATE OR REPLACE sin dropearla y sin tocar todo
-- lo que ya depende de su forma actual. Además, exponer whatsapp/email en
-- una función que devuelve filas al cliente amplía la superficie de datos
-- que viaja al navegador sin necesidad: para crear la reserva no hace falta
-- que el cliente JS vea esos campos, solo que el servidor los use.
--
-- Por eso esta función no devuelve datos del cliente: los lee del lado del
-- servidor (misma tabla clientes que ya lee get_club_vip_publico) y hace el
-- insert directo, devolviendo solo el id — mismo patrón exacto que
-- crear_reserva_publica (creada en migration_crear_reserva_publica.sql):
-- security definer, exige barberia_id Y cliente_id (nunca uno solo, para
-- que no se pueda pedir/crear a nombre de un cliente de otro negocio ni de
-- un cliente_id adivinado de otro negocio), revoke de public + grant a
-- anon/authenticated.
--
-- Ejecutar UNA VEZ en el SQL Editor de Supabase.

create or replace function crear_reserva_publica_club(
  p_barberia_id uuid,
  p_cliente_id uuid,
  p_fecha date,
  p_hora time,
  p_servicio text default null,
  p_barbero_nombre text default null,
  p_notas text default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_id uuid;
  v_cliente clientes%rowtype;
begin
  select * into v_cliente
  from clientes
  where id = p_cliente_id and barberia_id = p_barberia_id;

  if not found then
    raise exception 'Cliente no encontrado para este negocio';
  end if;

  insert into reservas (
    barberia_id, nombre_cliente, whatsapp_cliente, email_cliente,
    cumpleanos_cliente, fecha, hora, servicio, barbero_nombre,
    estado, procesado, notas, fuente
  ) values (
    p_barberia_id,
    trim(v_cliente.nombre || ' ' || coalesce(v_cliente.apellido, '')),
    v_cliente.whatsapp, v_cliente.email, v_cliente.cumpleanos,
    p_fecha, p_hora, p_servicio,
    coalesce(p_barbero_nombre, 'Por asignar'),
    'Confirmada', false, p_notas, 'Club VIP'
  ) returning id into v_id;

  return v_id;
end;
$$;

revoke all on function crear_reserva_publica_club(uuid,uuid,date,time,text,text,text) from public;
grant execute on function crear_reserva_publica_club(uuid,uuid,date,time,text,text,text) to anon, authenticated;
