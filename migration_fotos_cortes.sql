-- =============================================================================
-- Fotos de cortes: el profesional (o el dueño) sube hasta 2 fotos por cita; cualquier
-- profesional las ve en la ficha del cliente para saber qué se hizo antes, y el
-- cliente las ve y descarga desde el Club.
--
-- · Las fotos viajan YA comprimidas desde el navegador (≈1280 px, JPEG ~0,7:
--   100–250 KB). El bucket rechaza todo lo que pase de 1 MB.
-- · Bucket público con nombres UUID imposibles de adivinar; el listado solo sale
--   por las funciones de abajo (la tabla no tiene políticas: nadie la lee directo).
-- · La "cita" se identifica por negocio + fecha + hora + profesional (igual que
--   la agenda empareja reserva y visita), así la foto sigue a la cita aunque se
--   cobre y la reserva pase a ser visita. El cliente, por su WhatsApp normalizado.
-- ⚠ SIN begin;/commit; A PROPÓSITO (el SQL Editor trocea por `;`).
-- =============================================================================

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('cortes', 'cortes', true, 1048576, array['image/jpeg','image/webp'])
on conflict (id) do update set public = true, file_size_limit = 1048576, allowed_mime_types = array['image/jpeg','image/webp'];

drop policy if exists cortes_insert on storage.objects;
create policy cortes_insert on storage.objects for insert to authenticated
  with check (bucket_id = 'cortes' and (storage.foldername(name))[1] = (auth_barberia_id())::text);
drop policy if exists cortes_select on storage.objects;
create policy cortes_select on storage.objects for select to authenticated
  using (bucket_id = 'cortes' and (storage.foldername(name))[1] = (auth_barberia_id())::text);
drop policy if exists cortes_delete on storage.objects;
create policy cortes_delete on storage.objects for delete to authenticated
  using (bucket_id = 'cortes' and (storage.foldername(name))[1] = (auth_barberia_id())::text);

create table if not exists public.cortes_fotos (
  id             uuid primary key default gen_random_uuid(),
  barberia_id    uuid not null references public.barberias(id) on delete cascade,
  fecha          date not null,
  hora           time not null,
  barbero_nombre text not null,
  servicio       text,
  cliente_id     uuid,
  whatsapp_norm  text not null default '',
  nombre_cliente text,
  path           text not null,
  url            text not null,
  subida_por     uuid default auth.uid(),
  created_at     timestamptz not null default now()
);
create index if not exists cortes_fotos_cita_idx on public.cortes_fotos (barberia_id, fecha, hora);
create index if not exists cortes_fotos_wsp_idx on public.cortes_fotos (barberia_id, whatsapp_norm);
alter table public.cortes_fotos enable row level security;
-- Sin políticas: todo pasa por las funciones security definer de abajo.

-- Datos de la cita (reserva o visita) y permiso de quien llama.
create or replace function public._cita_foto_datos(p_tipo text, p_id uuid)
returns table (barberia_id uuid, fecha date, hora time, barbero_nombre text, servicio text,
               cliente_id uuid, whatsapp_norm text, nombre_cliente text)
language plpgsql stable security definer set search_path to 'public'
as $$
declare v_bar uuid := auth_barberia_id(); v_rol text := auth_rol(); v_mio text; v_cita text;
begin
  if v_bar is null then raise exception 'No autorizado'; end if;
  if p_tipo = 'reserva' then
    return query
      select r.barberia_id, r.fecha, r.hora, r.barbero_nombre, r.servicio,
             (select c.id from clientes c where c.barberia_id = r.barberia_id and coalesce(r.whatsapp_norm,'') <> '' and c.whatsapp_norm = r.whatsapp_norm limit 1),
             coalesce(r.whatsapp_norm,''), r.nombre_cliente
      from reservas r where r.id = p_id and r.barberia_id = v_bar;
  elsif p_tipo = 'visita' then
    return query
      select v.barberia_id, v.fecha, v.hora, v.barbero_nombre, v.servicio, v.cliente_id,
             coalesce(c.whatsapp_norm,''), c.nombre
      from visitas v left join clientes c on c.id = v.cliente_id
      where v.id = p_id and v.barberia_id = v_bar;
  else
    raise exception 'Tipo de cita inválido';
  end if;
  if not found then raise exception 'No encontramos esa cita'; end if;
  -- Un profesional solo toca SUS citas; dueño y recepción, todas.
  if coalesce(v_rol,'') not in ('dueno','recepcion') then
    select b.nombre into v_mio from barberos b where b.id = auth_barbero_id();
    select x.n into v_cita from (
      select r.barbero_nombre as n from reservas r where p_tipo = 'reserva' and r.id = p_id
      union all select v.barbero_nombre from visitas v where p_tipo = 'visita' and v.id = p_id) x limit 1;
    if v_mio is null or lower(btrim(coalesce(v_cita,''))) <> lower(btrim(v_mio)) then
      raise exception 'Esta cita no es tuya';
    end if;
  end if;
end;
$$;
revoke all on function public._cita_foto_datos(text,uuid) from public, anon, authenticated;

create or replace function public.agenda_foto_agregar(p_tipo text, p_id uuid, p_path text, p_url text)
returns uuid
language plpgsql security definer set search_path to 'public'
as $$
declare d record; v_n int; v_id uuid;
begin
  select * into d from _cita_foto_datos(p_tipo, p_id);
  if split_part(p_path, '/', 1) <> d.barberia_id::text then raise exception 'Ruta de foto inválida'; end if;
  select count(*) into v_n from cortes_fotos f
   where f.barberia_id = d.barberia_id and f.fecha = d.fecha and f.hora = d.hora
     and lower(btrim(f.barbero_nombre)) = lower(btrim(d.barbero_nombre))
     and ((d.whatsapp_norm <> '' and f.whatsapp_norm = d.whatsapp_norm)
          or (d.whatsapp_norm = '' and f.whatsapp_norm = '' and lower(btrim(coalesce(f.nombre_cliente,''))) = lower(btrim(coalesce(d.nombre_cliente,'')))));
  if v_n >= 2 then raise exception 'Máximo 2 fotos por cita'; end if;
  insert into cortes_fotos (barberia_id, fecha, hora, barbero_nombre, servicio, cliente_id, whatsapp_norm, nombre_cliente, path, url)
  values (d.barberia_id, d.fecha, d.hora, d.barbero_nombre, d.servicio, d.cliente_id, d.whatsapp_norm, d.nombre_cliente, p_path, p_url)
  returning id into v_id;
  return v_id;
end;
$$;
revoke all on function public.agenda_foto_agregar(text,uuid,text,text) from public, anon;
grant execute on function public.agenda_foto_agregar(text,uuid,text,text) to authenticated;

-- Fotos de ESTA cita (es_actual) + cortes anteriores del mismo cliente (últimos 12).
create or replace function public.agenda_fotos_cita(p_tipo text, p_id uuid)
returns table (id uuid, es_actual boolean, url text, fecha date, hora time, servicio text, barbero_nombre text)
language plpgsql stable security definer set search_path to 'public'
as $$
declare d record;
begin
  select * into d from _cita_foto_datos(p_tipo, p_id);
  return query
  select t.id, t.es_actual, t.url, t.fecha, t.hora, t.servicio, t.barbero_nombre from (
    select f.id,
           (f.fecha = d.fecha and f.hora = d.hora and lower(btrim(f.barbero_nombre)) = lower(btrim(d.barbero_nombre))) as es_actual,
           f.url, f.fecha, f.hora, f.servicio, f.barbero_nombre, f.created_at
    from cortes_fotos f
    where f.barberia_id = d.barberia_id
      and ((d.whatsapp_norm <> '' and f.whatsapp_norm = d.whatsapp_norm)
           or (d.whatsapp_norm = '' and f.whatsapp_norm = '' and lower(btrim(coalesce(f.nombre_cliente,''))) = lower(btrim(coalesce(d.nombre_cliente,'')))))
  ) t
  order by t.es_actual desc, t.fecha desc, t.hora desc, t.created_at
  limit 14;
end;
$$;
revoke all on function public.agenda_fotos_cita(text,uuid) from public, anon;
grant execute on function public.agenda_fotos_cita(text,uuid) to authenticated;

-- Borra la fila y devuelve la ruta para que el navegador borre el archivo.
create or replace function public.agenda_foto_eliminar(p_foto_id uuid)
returns text
language plpgsql security definer set search_path to 'public'
as $$
declare f cortes_fotos%rowtype; v_mio text;
begin
  select * into f from cortes_fotos where cortes_fotos.id = p_foto_id and cortes_fotos.barberia_id = auth_barberia_id();
  if not found then raise exception 'No encontramos esa foto'; end if;
  if coalesce(auth_rol(),'') not in ('dueno','recepcion') then
    select nombre into v_mio from barberos where id = auth_barbero_id();
    if v_mio is null or lower(btrim(v_mio)) <> lower(btrim(f.barbero_nombre)) then
      raise exception 'Solo quien atendió la cita puede borrar la foto';
    end if;
  end if;
  delete from cortes_fotos where cortes_fotos.id = f.id;
  return f.path;
end;
$$;
revoke all on function public.agenda_foto_eliminar(uuid) from public, anon;
grant execute on function public.agenda_foto_eliminar(uuid) to authenticated;

-- Club: el cliente ve SUS fotos. Misma regla de pertenencia que las reservas del
-- Club: teléfono normalizado, y si lo comparten personas de distinto nombre no se muestra nada.
create or replace function public.get_club_fotos_cortes(p_barberia_id uuid, p_cliente_id uuid)
returns table (id uuid, url text, fecha date, hora time, servicio text, profesional text)
language sql stable security definer set search_path to 'public'
as $$
  select f.id, f.url, f.fecha, f.hora, f.servicio, f.barbero_nombre
  from cortes_fotos f
  join clientes c on c.id = p_cliente_id and c.barberia_id = p_barberia_id
   and c.whatsapp_norm <> '' and f.whatsapp_norm = c.whatsapp_norm
   and not exists (
     select 1 from clientes c2
     where c2.barberia_id = c.barberia_id and c2.whatsapp_norm = c.whatsapp_norm and c2.id <> c.id
       and lower(split_part(trim(c2.nombre), ' ', 1)) <> lower(split_part(trim(c.nombre), ' ', 1)))
  where f.barberia_id = p_barberia_id
  order by f.fecha desc, f.hora desc, f.created_at
  limit 60;
$$;
revoke all on function public.get_club_fotos_cortes(uuid,uuid) from public;
grant execute on function public.get_club_fotos_cortes(uuid,uuid) to anon, authenticated;
