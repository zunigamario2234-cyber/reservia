-- Fix urgente: el link público de reservas está roto en producción.
--
-- confirmarReserva() (reservar.html) hace insert().select().single() para
-- recuperar el id de la reserva recién creada. Postgres aplica la política
-- de SELECT de la tabla (reservas_select_own, privada) también al
-- RETURNING de un INSERT — y para un cliente anónimo esa política nunca
-- puede cumplirse, así que el insert entero se revierte con
-- "new row violates row-level security policy".
--
-- Esto estuvo enmascarado mientras existió la política comodín
-- "todo en reservas" (permisiva, using(true) para todos los comandos,
-- incluido select). Al borrarla en migration_cleanup_rls.sql (correcto,
-- era la fuga de seguridad que cerramos ese día) quedó expuesta esta
-- incompatibilidad real entre "insert público" + "select privado en el
-- returning". Reservas públicas probablemente vienen fallando desde ese
-- momento.
--
-- Fix: mismo patrón que get_club_vip_publico — una función security
-- definer hace el insert del lado del servidor (bypasea RLS del rol
-- anon) y devuelve SOLO el id, nunca la fila completa. reservas_select_own
-- sigue protegiendo el resto de los datos de clientes de otros negocios.
--
-- Ejecutar UNA VEZ en el SQL Editor de Supabase.

create or replace function crear_reserva_publica(
  p_barberia_id uuid,
  p_nombre_cliente text,
  p_whatsapp_cliente text,
  p_fecha date,
  p_hora time,
  p_email_cliente text default null,
  p_cumpleanos_cliente date default null,
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
begin
  insert into reservas (
    barberia_id, nombre_cliente, whatsapp_cliente, email_cliente,
    cumpleanos_cliente, fecha, hora, servicio, barbero_nombre,
    estado, procesado, notas, fuente
  ) values (
    p_barberia_id, p_nombre_cliente, p_whatsapp_cliente, p_email_cliente,
    p_cumpleanos_cliente, p_fecha, p_hora, p_servicio,
    coalesce(p_barbero_nombre, 'Por asignar'),
    'Confirmada', false, p_notas, 'Web propia'
  ) returning id into v_id;
  return v_id;
end;
$$;

revoke all on function crear_reserva_publica(uuid,text,text,date,time,text,date,text,text,text) from public;
grant execute on function crear_reserva_publica(uuid,text,text,date,time,text,date,text,text,text) to anon, authenticated;
