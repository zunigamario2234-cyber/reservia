-- =============================================================================
-- NUNCA DOS RESERVAS QUE SE CRUCEN PARA EL MISMO PROFESIONAL
-- Incidente 23-11-2026 (Essentials, FELIPE): a las 14:38 se reservó 18:30
-- (Essentials Plus, 85 min) por el Club y a las 14:41 otra persona reservó 18:00
-- (Corte, 60 min) por la web, con la página abierta desde antes. Las funciones
-- de reserva solo revisaban choques cuando el servicio pedía abono, y el panel
-- tampoco revisaba al mover una cita.
-- Este trigger revisa en la BASE, para cualquier camino (web, Club, panel, Mi
-- Agenda, mover una cita), que la nueva hora con su duración no se cruce con
-- otra reserva activa del mismo profesional (misma vista reservas_disponibilidad
-- que usa la página de reservas). Un candado por profesional y día evita que dos
-- reservas simultáneas pasen las dos. Editar notas o cobrar no lo dispara.
-- =============================================================================
create or replace function public.trg_reserva_sin_choque()
returns trigger
language plpgsql security definer set search_path to 'public'
as $$
declare v_dur int; v_hora time;
begin
  if coalesce(new.estado,'') in ('Cancelada','No asistió') then return new; end if;
  if new.fecha is null or new.hora is null or new.barbero_nombre is null
     or btrim(new.barbero_nombre) = '' or lower(btrim(new.barbero_nombre)) = 'por asignar' then
    return new;
  end if;
  if tg_op = 'UPDATE'
     and new.fecha is not distinct from old.fecha and new.hora is not distinct from old.hora
     and lower(btrim(coalesce(new.barbero_nombre,''))) = lower(btrim(coalesce(old.barbero_nombre,'')))
     and new.servicio is not distinct from old.servicio
     and coalesce(old.estado,'') not in ('Cancelada','No asistió') then
    return new;
  end if;
  perform pg_advisory_xact_lock(hashtextextended(new.barberia_id::text || '|' || lower(btrim(new.barbero_nombre)) || '|' || new.fecha::text, 0));
  v_dur := _abono_duracion(new.barberia_id, new.servicio);
  select d.hora into v_hora
    from reservas_disponibilidad d
   where d.barberia_id = new.barberia_id
     and lower(btrim(d.barbero_nombre)) = lower(btrim(new.barbero_nombre))
     and d.fecha = new.fecha
     and d.id is distinct from new.id
     and ((new.fecha + new.hora), (new.fecha + new.hora) + make_interval(mins => greatest(v_dur, 1)))
         overlaps ((d.fecha + d.hora), (d.fecha + d.hora) + make_interval(mins => greatest(d.duracion_min, 1)))
   order by d.hora limit 1;
  if found then
    raise exception 'Ese horario ya está ocupado: % tiene otra reserva a las % que se cruza. Elige otra hora.',
      btrim(new.barbero_nombre), to_char(v_hora, 'HH24:MI') using errcode = 'P0001';
  end if;
  return new;
end;
$$;
drop trigger if exists reservas_sin_choque on public.reservas;
create trigger reservas_sin_choque before insert or update on public.reservas
  for each row execute function public.trg_reserva_sin_choque();
