-- =============================================================================
-- MULTISUCURSAL (etapa 1)
-- Un negocio (barberias) puede tener varias sucursales. Los clientes, servicios,
-- inventario, gastos y horarios siguen siendo del negocio (compartidos). Cada
-- profesional, reserva, visita y venta de producto pertenece a una sucursal.
--  · El dueño ve todo y puede filtrar por sucursal (se filtra en la app).
--  · Recepción y profesionales ven SOLO su sucursal (política RESTRICTIVA en la
--    base, no solo en la pantalla).
--  · Los negocios de una sola sucursal no notan nada: todo queda en "Principal".
-- sucursal_id se completa solo con triggers (desde el profesional), así que las
-- funciones de reserva y cobro existentes no cambian.
-- ⚠ SIN begin;/commit; A PROPÓSITO (el SQL Editor trocea por `;` los cuerpos).
-- =============================================================================
create table if not exists public.sucursales (
  id uuid primary key default gen_random_uuid(),
  barberia_id uuid not null references public.barberias(id) on delete cascade,
  nombre text not null check (btrim(nombre) <> ''),
  direccion text,
  telefono text,
  activa boolean not null default true,
  orden integer not null default 0,
  created_at timestamptz not null default now()
);
create unique index if not exists sucursales_nombre_unico on public.sucursales (barberia_id, lower(btrim(nombre)));
alter table public.sucursales enable row level security;

drop policy if exists sucursales_select_public on public.sucursales;
create policy sucursales_select_public on public.sucursales for select using (true);
drop policy if exists sucursales_dueno_insert on public.sucursales;
create policy sucursales_dueno_insert on public.sucursales for insert
  with check (barberia_id = auth_barberia_id() and auth_rol() = 'dueno');
drop policy if exists sucursales_dueno_update on public.sucursales;
create policy sucursales_dueno_update on public.sucursales for update
  using (barberia_id = auth_barberia_id() and auth_rol() = 'dueno')
  with check (barberia_id = auth_barberia_id() and auth_rol() = 'dueno');
drop policy if exists sucursales_dueno_delete on public.sucursales;
create policy sucursales_dueno_delete on public.sucursales for delete
  using (barberia_id = auth_barberia_id() and auth_rol() = 'dueno');

alter table public.barberias add column if not exists sucursales_modo text not null default 'compartido'
  check (sucursales_modo in ('compartido','separado'));

-- Una sucursal "Principal" por negocio existente.
insert into public.sucursales (barberia_id, nombre, direccion, orden)
select b.id, 'Principal', b.direccion, 0 from public.barberias b
 where not exists (select 1 from public.sucursales s where s.barberia_id = b.id);

alter table public.barberos add column if not exists sucursal_id uuid references public.sucursales(id);
alter table public.reservas add column if not exists sucursal_id uuid references public.sucursales(id);
alter table public.visitas add column if not exists sucursal_id uuid references public.sucursales(id);
alter table public.cobro_productos add column if not exists sucursal_id uuid references public.sucursales(id);
alter table public.perfiles add column if not exists sucursal_id uuid references public.sucursales(id);
alter table public.recepcion_invitaciones add column if not exists sucursal_id uuid references public.sucursales(id);

create or replace function public.sucursal_principal(p_barberia uuid)
returns uuid language sql stable security definer set search_path to 'public' as $$
  select id from sucursales where barberia_id = p_barberia order by orden, created_at limit 1
$$;

-- Relleno de lo existente: todo a la sucursal principal de su negocio.
update public.barberos set sucursal_id = public.sucursal_principal(barberia_id) where sucursal_id is null;
update public.reservas set sucursal_id = public.sucursal_principal(barberia_id) where sucursal_id is null;
update public.visitas set sucursal_id = public.sucursal_principal(barberia_id) where sucursal_id is null;
update public.cobro_productos set sucursal_id = public.sucursal_principal(barberia_id) where sucursal_id is null;
update public.perfiles set sucursal_id = public.sucursal_principal(barberia_id)
 where sucursal_id is null and rol = 'recepcion';

create index if not exists reservas_sucursal on public.reservas (barberia_id, sucursal_id, fecha);
create index if not exists visitas_sucursal on public.visitas (barberia_id, sucursal_id, fecha);
create index if not exists barberos_sucursal on public.barberos (barberia_id, sucursal_id);

-- Triggers: la sucursal sale del profesional (por id o por nombre), si no, la principal.
create or replace function public.trg_set_sucursal_barbero()
returns trigger language plpgsql security definer set search_path to 'public' as $$
begin
  if new.sucursal_id is null then new.sucursal_id := sucursal_principal(new.barberia_id); end if;
  return new;
end $$;
drop trigger if exists set_sucursal on public.barberos;
create trigger set_sucursal before insert on public.barberos
  for each row execute function public.trg_set_sucursal_barbero();

create or replace function public.trg_set_sucursal_por_nombre()
returns trigger language plpgsql security definer set search_path to 'public' as $$
declare v uuid;
begin
  if new.sucursal_id is null then
    select b.sucursal_id into v from barberos b
     where b.barberia_id = new.barberia_id
       and lower(btrim(b.nombre)) = lower(btrim(new.barbero_nombre))
     order by b.activo desc limit 1;
    new.sucursal_id := coalesce(v, sucursal_principal(new.barberia_id));
  end if;
  return new;
end $$;
drop trigger if exists set_sucursal on public.reservas;
create trigger set_sucursal before insert on public.reservas
  for each row execute function public.trg_set_sucursal_por_nombre();
drop trigger if exists set_sucursal on public.cobro_productos;
create trigger set_sucursal before insert on public.cobro_productos
  for each row execute function public.trg_set_sucursal_por_nombre();

create or replace function public.trg_set_sucursal_visita()
returns trigger language plpgsql security definer set search_path to 'public' as $$
declare v uuid;
begin
  if new.sucursal_id is null then
    if new.barbero_id is not null then
      select sucursal_id into v from barberos where id = new.barbero_id;
    end if;
    if v is null then
      select b.sucursal_id into v from barberos b
       where b.barberia_id = new.barberia_id
         and lower(btrim(b.nombre)) = lower(btrim(new.barbero_nombre))
       order by b.activo desc limit 1;
    end if;
    new.sucursal_id := coalesce(v, sucursal_principal(new.barberia_id));
  end if;
  return new;
end $$;
drop trigger if exists set_sucursal on public.visitas;
create trigger set_sucursal before insert on public.visitas
  for each row execute function public.trg_set_sucursal_visita();

-- A qué sucursal está atado quien inicia sesión. NULL = ve todas (dueño, anónimo).
create or replace function public.auth_sucursal_scope()
returns uuid language sql stable security definer set search_path to 'public', 'pg_temp' as $$
  select case p.rol
           when 'recepcion' then p.sucursal_id
           when 'profesional' then (select b.sucursal_id from barberos b where b.auth_user_id = p.id and b.activo limit 1)
           else null
         end
    from perfiles p where p.id = auth.uid()
$$;

-- Restrictivas: se suman (AND) a las políticas que ya existen.
drop policy if exists sucursal_scope on public.reservas;
create policy sucursal_scope on public.reservas as restrictive for all
  using (auth_sucursal_scope() is null or sucursal_id = auth_sucursal_scope())
  with check (auth_sucursal_scope() is null or sucursal_id = auth_sucursal_scope());
drop policy if exists sucursal_scope on public.visitas;
create policy sucursal_scope on public.visitas as restrictive for all
  using (auth_sucursal_scope() is null or sucursal_id = auth_sucursal_scope())
  with check (auth_sucursal_scope() is null or sucursal_id = auth_sucursal_scope());
drop policy if exists sucursal_scope on public.cobro_productos;
create policy sucursal_scope on public.cobro_productos as restrictive for all
  using (auth_sucursal_scope() is null or sucursal_id = auth_sucursal_scope())
  with check (auth_sucursal_scope() is null or sucursal_id = auth_sucursal_scope());
drop policy if exists sucursal_scope on public.barberos;
create policy sucursal_scope on public.barberos as restrictive for select
  using (auth_sucursal_scope() is null or sucursal_id = auth_sucursal_scope());

-- Recepción: se invita a una sucursal concreta.
drop function if exists public.invitar_recepcion(text, text);
create or replace function public.invitar_recepcion(p_email text, p_nombre text, p_sucursal_id uuid default null)
returns void language plpgsql security definer set search_path to 'public' as $$
declare
  v_barberia uuid := auth_barberia_id();
  v_email text := lower(btrim(coalesce(p_email, '')));
  v_suc uuid;
begin
  if v_barberia is null or auth_rol() <> 'dueno' then raise exception 'No autorizado'; end if;
  if v_email !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' then raise exception 'El correo no es válido'; end if;
  if coalesce(btrim(p_nombre), '') = '' then raise exception 'Falta el nombre'; end if;
  if exists (select 1 from auth.users u where lower(u.email) = v_email) then
    raise exception 'Ese correo ya tiene una cuenta en Reservia. Usa otro correo.';
  end if;
  v_suc := coalesce(p_sucursal_id, sucursal_principal(v_barberia));
  if not exists (select 1 from sucursales where id = v_suc and barberia_id = v_barberia) then
    raise exception 'Sucursal no válida';
  end if;
  insert into recepcion_invitaciones (barberia_id, email, nombre, sucursal_id)
  values (v_barberia, v_email, btrim(p_nombre), v_suc)
  on conflict (lower(email)) do update
    set barberia_id = excluded.barberia_id, nombre = excluded.nombre,
        sucursal_id = excluded.sucursal_id, created_at = now();
end $$;

create or replace function public.reclamar_recepcion()
returns void language plpgsql security definer set search_path to 'public' as $$
declare
  v_inv recepcion_invitaciones;
  v_email text := lower(coalesce(auth.jwt() ->> 'email', ''));
begin
  if auth.uid() is null or v_email = '' then raise exception 'No autorizado'; end if;
  select * into v_inv from recepcion_invitaciones
   where lower(email) = v_email and created_at > now() - interval '15 minutes';
  if not found then raise exception 'No hay una invitación vigente para este correo'; end if;
  insert into perfiles (id, barberia_id, nombre, rol, sucursal_id)
  values (auth.uid(), v_inv.barberia_id, v_inv.nombre, 'recepcion',
          coalesce(v_inv.sucursal_id, sucursal_principal(v_inv.barberia_id)));
  delete from recepcion_invitaciones where id = v_inv.id;
end $$;

drop function if exists public.listar_recepcion();
create or replace function public.listar_recepcion()
returns table(id uuid, nombre text, email text, desde timestamptz, sucursal_id uuid)
language plpgsql security definer set search_path to 'public' as $$
begin
  if auth_barberia_id() is null or auth_rol() <> 'dueno' then raise exception 'No autorizado'; end if;
  return query
    select p.id, p.nombre, u.email::text, u.created_at, p.sucursal_id
      from perfiles p join auth.users u on u.id = p.id
     where p.barberia_id = auth_barberia_id() and p.rol = 'recepcion'
     order by u.created_at;
end $$;

create or replace function public.asignar_sucursal_recepcion(p_id uuid, p_sucursal_id uuid)
returns void language plpgsql security definer set search_path to 'public' as $$
begin
  if auth_barberia_id() is null or auth_rol() <> 'dueno' then raise exception 'No autorizado'; end if;
  if not exists (select 1 from sucursales where id = p_sucursal_id and barberia_id = auth_barberia_id()) then
    raise exception 'Sucursal no válida';
  end if;
  update perfiles set sucursal_id = p_sucursal_id
   where id = p_id and barberia_id = auth_barberia_id() and rol = 'recepcion';
  if not found then raise exception 'Recepción no encontrada'; end if;
end $$;
