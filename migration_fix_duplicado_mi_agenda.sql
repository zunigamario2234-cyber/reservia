-- Fix: mi_agenda_citas() mostraba duplicada una cita ya procesada — una vez
-- como reserva (sin precio, porque reservas no tiene valor/comision_monto) y
-- otra vez como la visita generada al procesarla (con precio). Causa: al
-- procesar, app.html pone reservas.procesado=true pero no borra ni oculta la
-- fila (correcto, la necesita para reportes del dueño); mi_agenda_citas() no
-- filtraba por esa columna en el SELECT de reservas. Fix: agregar
-- "r.procesado = false" a ese SELECT, para que una vez procesada la cita se
-- vea una sola vez (como visita).
--
-- Ejecutar UNA VEZ, completo, en el SQL Editor de Supabase.

create or replace function mi_agenda_citas(p_fecha date)
returns table (
  id uuid,
  tipo text,
  fecha date,
  hora time,
  servicio text,
  estado text,
  procesado boolean,
  nombre_cliente text,
  whatsapp_cliente text,
  valor numeric,
  comision_monto numeric,
  notas text
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_barbero_id uuid := auth_barbero_id();
  v_nombre text;
  v_barberia uuid := auth_barberia_id();
begin
  if v_barbero_id is null then
    return;
  end if;
  select nombre into v_nombre from barberos where barberos.id = v_barbero_id;

  return query
  select r.id, 'reserva'::text, r.fecha, r.hora, r.servicio, r.estado, r.procesado,
         r.nombre_cliente, r.whatsapp_cliente, null::numeric, null::numeric, r.notas
  from reservas r
  where r.barberia_id = v_barberia and r.barbero_nombre = v_nombre
    and r.fecha = p_fecha and r.oculto_profesional = false
    and r.procesado = false
  union all
  select v.id, 'visita'::text, v.fecha, v.hora, v.servicio, v.estado, true,
         c.nombre, c.whatsapp, v.valor, v.comision_monto, v.notas
  from visitas v
  left join clientes c on c.id = v.cliente_id
  where v.barberia_id = v_barberia and v.barbero_nombre = v_nombre
    and v.fecha = p_fecha and v.oculto_profesional = false
  order by 4;
end;
$$;
