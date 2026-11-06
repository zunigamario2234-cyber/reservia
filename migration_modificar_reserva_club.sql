-- =============================================================================
-- El cliente del Club puede MODIFICAR sus reservas (nunca cancelarlas)
--
-- · get_proximas_reservas_club: igual que get_proximas_reservas_publico pero con
--   el id de la reserva, que hace falta para poder modificarla.
-- · modificar_reserva_club: cambia fecha, hora, servicio y/o profesional de UNA
--   reserva futura del propio cliente. Valida en la base (no en la pantalla):
--   que la reserva sea suya, que no esté cancelada ni cobrada, que la hora no
--   haya pasado, que el profesional esté activo y que el horario esté libre.
--   Guarda el antes y el después en reserva_cambios; de ahí lee el correo que
--   avisa al profesional (el navegador no puede inventar qué cambió).
-- · No existe ninguna vía para cancelar o borrar desde el Club.
--
-- ⚠ SIN begin;/commit; A PROPÓSITO: el SQL Editor trocea por `;` y rompe el
-- cuerpo de las funciones.
-- =============================================================================

create table if not exists public.reserva_cambios (
  id          uuid primary key default gen_random_uuid(),
  reserva_id  uuid not null references public.reservas(id) on delete cascade,
  barberia_id uuid not null references public.barberias(id) on delete cascade,
  anterior    jsonb not null,
  nuevo       jsonb not null,
  created_at  timestamptz not null default now(),
  avisado_at  timestamptz
);
alter table public.reserva_cambios enable row level security;
-- Sin políticas: solo la lee y marca el endpoint del servidor (service role).

-- Misma regla de pertenencia que get_proximas_reservas_publico (ver
-- migration_proximas_reservas_club.sql): el teléfono normalizado empareja
-- cliente y reserva, y si el número lo comparten personas de distinto nombre no
-- se muestra ni se deja tocar nada.
create or replace function public._club_reserva_es_del_cliente(p_barberia_id uuid, p_cliente_id uuid, p_reserva_id uuid)
returns boolean
language sql
stable
security definer
set search_path to 'public'
as $$
  select exists (
    select 1
    from reservas r
    join clientes c on c.id = p_cliente_id and c.barberia_id = p_barberia_id
     and c.whatsapp_norm <> ''
     and not exists (
       select 1 from clientes c2
       where c2.barberia_id = c.barberia_id
         and c2.whatsapp_norm = c.whatsapp_norm
         and c2.id <> c.id
         and lower(split_part(trim(c2.nombre), ' ', 1)) <> lower(split_part(trim(c.nombre), ' ', 1))
     )
    where r.id = p_reserva_id
      and r.barberia_id = p_barberia_id
      and r.whatsapp_norm = c.whatsapp_norm
  );
$$;
revoke all on function public._club_reserva_es_del_cliente(uuid,uuid,uuid) from public, anon, authenticated;

create or replace function public.get_proximas_reservas_club(p_barberia_id uuid, p_cliente_id uuid)
returns table (id uuid, fecha date, hora time without time zone, servicio text, profesional text)
language sql
stable
security definer
set search_path to 'public'
as $$
  select r.id, r.fecha, r.hora, r.servicio, r.barbero_nombre
  from reservas r
  where r.barberia_id = p_barberia_id
    and _club_reserva_es_del_cliente(p_barberia_id, p_cliente_id, r.id)
    and r.procesado = false
    and coalesce(r.estado,'') <> 'Cancelada'
    and r.fecha >= (now() at time zone 'America/Santiago')::date
  order by r.fecha, r.hora;
$$;
revoke all on function public.get_proximas_reservas_club(uuid,uuid) from public;
grant execute on function public.get_proximas_reservas_club(uuid,uuid) to anon, authenticated;

create or replace function public.modificar_reserva_club(
  p_barberia_id uuid,
  p_cliente_id uuid,
  p_reserva_id uuid,
  p_fecha date,
  p_hora time without time zone,
  p_servicio text,
  p_barbero_nombre text,
  p_notas text default null
)
returns uuid
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_ahora timestamp := (now() at time zone 'America/Santiago');
  v_r reservas%rowtype;
  v_barbero text;
  v_servicio text;
  v_dur int;
  v_cambio uuid;
begin
  if not _club_reserva_es_del_cliente(p_barberia_id, p_cliente_id, p_reserva_id) then
    raise exception 'No encontramos esa reserva';
  end if;

  select * into v_r from reservas where id = p_reserva_id and barberia_id = p_barberia_id for update;
  if not found then raise exception 'No encontramos esa reserva'; end if;

  if v_r.procesado or coalesce(v_r.estado,'') = 'Cancelada' then
    raise exception 'Esta reserva ya no se puede modificar';
  end if;
  if (v_r.fecha + v_r.hora) < v_ahora then
    raise exception 'Esta reserva ya pasó';
  end if;
  if (p_fecha + p_hora) < v_ahora then
    raise exception 'Esa hora ya pasó. Vuelve a cargar la página y elige otra';
  end if;

  if p_barbero_nombre is null or btrim(p_barbero_nombre) = '' or lower(btrim(p_barbero_nombre)) = 'por asignar' then
    raise exception 'Tienes que elegir un profesional';
  end if;
  select nombre into v_barbero from barberos
   where barberia_id = p_barberia_id and lower(btrim(nombre)) = lower(btrim(p_barbero_nombre)) and activo = true
   limit 1;
  if v_barbero is null then
    raise exception 'El profesional elegido ya no está disponible. Vuelve a cargar la página';
  end if;

  select nombre, duracion_min into v_servicio, v_dur from servicios
   where barberia_id = p_barberia_id and activo = true and lower(btrim(nombre)) = lower(btrim(coalesce(p_servicio,'')))
   limit 1;
  if v_servicio is null then
    raise exception 'El servicio elegido ya no está disponible. Vuelve a cargar la página';
  end if;
  v_dur := coalesce(v_dur, 30);

  -- Horario libre para ese profesional (sin contarse a sí misma).
  if exists (
    select 1 from reservas o
    where o.barberia_id = p_barberia_id
      and o.id <> v_r.id
      and o.fecha = p_fecha
      and lower(btrim(coalesce(o.barbero_nombre,''))) = lower(btrim(v_barbero))
      and coalesce(o.estado,'') <> 'Cancelada'
      and o.hora < p_hora + make_interval(mins => v_dur)
      and p_hora < o.hora + make_interval(mins => coalesce(
            (select s.duracion_min from servicios s where s.barberia_id = o.barberia_id
               and lower(btrim(s.nombre)) = lower(btrim(coalesce(o.servicio,''))) limit 1), 30))
  ) then
    raise exception 'Ese horario se acaba de ocupar. Elige otro';
  end if;

  if p_fecha = v_r.fecha and p_hora = v_r.hora
     and lower(btrim(v_servicio)) = lower(btrim(coalesce(v_r.servicio,'')))
     and lower(btrim(v_barbero)) = lower(btrim(coalesce(v_r.barbero_nombre,''))) then
    raise exception 'No hiciste ningún cambio';
  end if;

  insert into reserva_cambios (reserva_id, barberia_id, anterior, nuevo)
  values (v_r.id, p_barberia_id,
    jsonb_build_object('fecha', v_r.fecha, 'hora', v_r.hora, 'servicio', v_r.servicio, 'barbero', v_r.barbero_nombre),
    jsonb_build_object('fecha', p_fecha, 'hora', p_hora, 'servicio', v_servicio, 'barbero', v_barbero))
  returning id into v_cambio;

  update reservas
     set fecha = p_fecha, hora = p_hora, servicio = v_servicio, barbero_nombre = v_barbero,
         notas = coalesce(nullif(btrim(p_notas), ''), notas)
   where id = v_r.id;

  return v_r.id;
end;
$function$;
revoke all on function public.modificar_reserva_club(uuid,uuid,uuid,date,time without time zone,text,text,text) from public;
grant execute on function public.modificar_reserva_club(uuid,uuid,uuid,date,time without time zone,text,text,text) to anon, authenticated;
