-- Avisar al profesional también cuando la cita se cambia desde la agenda (dueño/recepción).
-- Antes solo quedaba registro (y correo) si el cliente modificaba desde el Club.
-- Un trigger registra en reserva_cambios cualquier cambio de día, hora, servicio o
-- profesional hecho por otra vía; la RPC del Club ya registra el suyo (se omite).
alter table public.reserva_cambios add column if not exists origen text not null default 'club';

create or replace function public._reservas_registrar_cambio()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $$
begin
  if (new.fecha is distinct from old.fecha or new.hora is distinct from old.hora
      or new.servicio is distinct from old.servicio or new.barbero_nombre is distinct from old.barbero_nombre)
     and coalesce(new.estado,'') <> 'Cancelada' and not coalesce(new.procesado,false)
     and not exists (select 1 from reserva_cambios c where c.reserva_id = new.id and c.created_at = now())
  then
    insert into reserva_cambios (reserva_id, barberia_id, anterior, nuevo, origen)
    values (new.id, new.barberia_id,
      jsonb_build_object('fecha', old.fecha, 'hora', old.hora, 'servicio', old.servicio, 'barbero', old.barbero_nombre),
      jsonb_build_object('fecha', new.fecha, 'hora', new.hora, 'servicio', new.servicio, 'barbero', new.barbero_nombre),
      'agenda');
  end if;
  return new;
end;
$$;

drop trigger if exists trg_reservas_registrar_cambio on public.reservas;
create trigger trg_reservas_registrar_cambio after update on public.reservas
  for each row execute function public._reservas_registrar_cambio();
