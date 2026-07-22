-- Permite armar el link de Club VIP para el cliente justo después de que
-- reserva por primera vez en reservar.html, sin esperar a que el dueño
-- "Procese" la reserva (que es cuando hoy se crea la ficha de cliente,
-- en procesarReserva() de app.html).
--
-- Mismo criterio de "quién es este cliente" que procesarReserva(): busca
-- por barberia_id + whatsapp exacto (sin normalizar formato) antes de
-- crear uno nuevo — un solo criterio de dedup en toda la app, no dos.
--
-- Exige p_reserva_id (no solo barberia_id): lee nombre/whatsapp/fecha/
-- cumpleaños DIRECTO de la reserva ya creada, en vez de recibirlos como
-- parámetros de texto sueltos. Esto cierra dos cosas a la vez: (a) no se
-- puede llamar esta función "en el aire" para sembrar clientes falsos en
-- un negocio sin haber reservado antes — tiene que existir una reserva
-- real con ese barberia_id, y (b) no hay forma de que el nombre/whatsapp
-- que se guarda en clientes diverja de lo que realmente quedó guardado
-- en la reserva.
--
-- Ejecutar UNA VEZ en el SQL Editor de Supabase.

create or replace function buscar_o_crear_cliente_club(
  p_barberia_id uuid,
  p_reserva_id uuid
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_cliente_id uuid;
  v_reserva reservas%rowtype;
begin
  select * into v_reserva
  from reservas
  where id = p_reserva_id and barberia_id = p_barberia_id;

  if not found then
    raise exception 'Reserva no encontrada para este negocio';
  end if;

  select id into v_cliente_id
  from clientes
  where barberia_id = p_barberia_id and whatsapp = v_reserva.whatsapp_cliente
  limit 1;

  if v_cliente_id is not null then
    return v_cliente_id;
  end if;

  insert into clientes (barberia_id, nombre, whatsapp, cumpleanos, canal, fecha_registro)
  values (
    p_barberia_id, v_reserva.nombre_cliente, v_reserva.whatsapp_cliente,
    v_reserva.cumpleanos_cliente, 'Reserva Web', v_reserva.fecha
  )
  returning id into v_cliente_id;

  return v_cliente_id;
end;
$$;

revoke all on function buscar_o_crear_cliente_club(uuid,uuid) from public;
grant execute on function buscar_o_crear_cliente_club(uuid,uuid) to anon, authenticated;
