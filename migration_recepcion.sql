-- =============================================================================
-- ROL RECEPCIÓN
--
-- Una persona de confianza que atiende el mostrador: ve la agenda y las
-- reservas, agenda, cobra y cuadra la caja DEL DÍA. No ve reportes, costos,
-- comisiones, gift cards, inventario con costos ni ventas de días pasados.
--
-- Todo se impone en la base (RLS), no solo en la pantalla: aunque alguien
-- abra la consola del navegador, estas políticas son lo que manda.
--
-- Nada de lo que ya existe se amplía: las políticas del dueño siguen igual y
-- 'recepcion' arranca sin acceso a nada; solo se le suma lo de abajo.
-- =============================================================================

-- ── 0. Hueco que se cierra ──────────────────────────────────────────────────
-- perfiles_insert_own dejaba que cualquiera se insertara un perfil con
-- CUALQUIER rol distinto de 'dueno' en CUALQUIER negocio. Con 'profesional'
-- no da nada (falta el vínculo en barberos), pero con 'recepcion' sí daría
-- acceso. Ahora el auto-insert solo vale para 'profesional'; 'recepcion' solo
-- nace de reclamar_recepcion(), que exige una invitación hecha por el dueño.
drop policy if exists perfiles_insert_own on public.perfiles;
create policy perfiles_insert_own on public.perfiles
  for insert
  with check (
    id = auth.uid()
    and (
      rol = 'profesional'
      or (
        rol = 'dueno'
        and exists (select 1 from barberias b where b.id = perfiles.barberia_id and b.creado_por = auth.uid())
        and not exists (select 1 from perfiles p2 where p2.barberia_id = perfiles.barberia_id and p2.rol = 'dueno')
      )
    )
  );

-- ── 1. Invitaciones ─────────────────────────────────────────────────────────
create table if not exists public.recepcion_invitaciones (
  id          uuid primary key default gen_random_uuid(),
  barberia_id uuid not null references public.barberias(id) on delete cascade,
  email       text not null,
  nombre      text not null,
  created_at  timestamptz not null default now()
);
create unique index if not exists recepcion_invitaciones_email_uk on public.recepcion_invitaciones (lower(email));
alter table public.recepcion_invitaciones enable row level security;
-- Sin políticas: solo se toca desde las funciones de abajo.

create or replace function public.invitar_recepcion(p_email text, p_nombre text)
returns void
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  v_barberia uuid := auth_barberia_id();
  v_email text := lower(btrim(coalesce(p_email, '')));
begin
  if v_barberia is null or auth_rol() <> 'dueno' then
    raise exception 'No autorizado';
  end if;
  if v_email !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' then
    raise exception 'El correo no es válido';
  end if;
  if coalesce(btrim(p_nombre), '') = '' then
    raise exception 'Falta el nombre';
  end if;
  if exists (select 1 from auth.users u where lower(u.email) = v_email) then
    raise exception 'Ese correo ya tiene una cuenta en Reservia. Usa otro correo.';
  end if;
  insert into recepcion_invitaciones (barberia_id, email, nombre)
  values (v_barberia, v_email, btrim(p_nombre))
  on conflict (lower(email)) do update
    set barberia_id = excluded.barberia_id, nombre = excluded.nombre, created_at = now();
end;
$$;

-- La llama la persona recién registrada. El correo sale del JWT, no de un
-- argumento: no se puede reclamar una invitación ajena.
create or replace function public.reclamar_recepcion()
returns void
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  v_inv recepcion_invitaciones;
  v_email text := lower(coalesce(auth.jwt() ->> 'email', ''));
begin
  if auth.uid() is null or v_email = '' then
    raise exception 'No autorizado';
  end if;
  select * into v_inv from recepcion_invitaciones where lower(email) = v_email;
  if not found then
    raise exception 'No hay una invitación para este correo';
  end if;
  insert into perfiles (id, barberia_id, nombre, rol)
  values (auth.uid(), v_inv.barberia_id, v_inv.nombre, 'recepcion');
  delete from recepcion_invitaciones where id = v_inv.id;
end;
$$;

create or replace function public.listar_recepcion()
returns table(id uuid, nombre text, email text, desde timestamptz)
language plpgsql
security definer
set search_path to 'public'
as $$
begin
  if auth_barberia_id() is null or auth_rol() <> 'dueno' then
    raise exception 'No autorizado';
  end if;
  return query
    select p.id, p.nombre, u.email::text, u.created_at
      from perfiles p join auth.users u on u.id = p.id
     where p.barberia_id = auth_barberia_id() and p.rol = 'recepcion'
     order by u.created_at;
end;
$$;

-- Quitar el acceso borra la cuenta completa (no queda un usuario suelto).
create or replace function public.quitar_recepcion(p_id uuid)
returns void
language plpgsql
security definer
set search_path to 'public'
as $$
begin
  if auth_barberia_id() is null or auth_rol() <> 'dueno' then
    raise exception 'No autorizado';
  end if;
  if not exists (select 1 from perfiles where id = p_id and barberia_id = auth_barberia_id() and rol = 'recepcion') then
    raise exception 'No es una cuenta de recepción de este negocio';
  end if;
  delete from perfiles where id = p_id;
  delete from auth.users where id = p_id;
end;
$$;

-- ── 2. Lo que puede LEER / ESCRIBIR recepción ───────────────────────────────
-- Agenda y reservas: ver, crear y modificar (cambiar estado, mover, cancelar).
-- No puede borrar.
drop policy if exists reservas_recepcion_select on public.reservas;
create policy reservas_recepcion_select on public.reservas for select
  using (barberia_id = auth_barberia_id() and auth_rol() = 'recepcion');
drop policy if exists reservas_recepcion_insert on public.reservas;
create policy reservas_recepcion_insert on public.reservas for insert
  with check (barberia_id = auth_barberia_id() and auth_rol() = 'recepcion');
drop policy if exists reservas_recepcion_update on public.reservas;
create policy reservas_recepcion_update on public.reservas for update
  using (barberia_id = auth_barberia_id() and auth_rol() = 'recepcion')
  with check (barberia_id = auth_barberia_id() and auth_rol() = 'recepcion');

-- Clientes: buscar y dar de alta uno nuevo al reservar. No editar ni borrar.
drop policy if exists clientes_recepcion_select on public.clientes;
create policy clientes_recepcion_select on public.clientes for select
  using (barberia_id = auth_barberia_id() and auth_rol() = 'recepcion');
drop policy if exists clientes_recepcion_insert on public.clientes;
create policy clientes_recepcion_insert on public.clientes for insert
  with check (barberia_id = auth_barberia_id() and auth_rol() = 'recepcion');

-- Ventas: SOLO las de hoy (hora de Chile). Es lo que le permite cuadrar la caja
-- sin ver el historial ni los totales globales.
drop policy if exists visitas_recepcion_hoy on public.visitas;
create policy visitas_recepcion_hoy on public.visitas for select
  using (barberia_id = auth_barberia_id() and auth_rol() = 'recepcion'
         and fecha = (now() at time zone 'America/Santiago')::date);
drop policy if exists cobro_productos_recepcion_hoy on public.cobro_productos;
create policy cobro_productos_recepcion_hoy on public.cobro_productos for select
  using (barberia_id = auth_barberia_id() and auth_rol() = 'recepcion'
         and fecha = (now() at time zone 'America/Santiago')::date);

-- Plantillas de mensajes (las usa para armar el WhatsApp de confirmación).
drop policy if exists plantillas_recepcion_select on public.plantillas_mensajes;
create policy plantillas_recepcion_select on public.plantillas_mensajes for select
  using (barberia_id = auth_barberia_id() and auth_rol() = 'recepcion');

-- Productos para vender: SIN costo ni proveedor.
create or replace view public.inventario_recepcion as
  select i.id, i.barberia_id, i.codigo, i.nombre, i.categoria, i.stock, i.precio_venta
    from public.inventario i
   where i.barberia_id = auth_barberia_id()
     and auth_rol() in ('dueno', 'recepcion');
revoke all on public.inventario_recepcion from public, anon;
grant select on public.inventario_recepcion to authenticated;

-- ── 3. Cobrar ───────────────────────────────────────────────────────────────
do $$
declare d text; d2 text;
begin
  select pg_get_functiondef(p.oid) into d from pg_proc p where p.proname = 'registrar_cobro_conjunto';
  d2 := replace(d, 'auth_rol() <> ''dueno''', 'auth_rol() not in (''dueno'', ''recepcion'')');
  if d2 = d then raise exception 'registrar_cobro_conjunto no cambió'; end if;
  execute d2;
end $$;

-- Consultar una gift card por código (dueño y recepción), sin abrir la tabla.
create or replace function public.gift_card_consultar(p_codigo text)
returns table(codigo text, servicio text, valor numeric, estado text, vence date)
language plpgsql
security definer
set search_path to 'public'
as $$
begin
  if auth_barberia_id() is null or auth_rol() not in ('dueno', 'recepcion') then
    raise exception 'No autorizado';
  end if;
  return query
    select g.codigo, g.servicio, g.valor, g.estado, g.vence
      from gift_cards g
     where g.barberia_id = auth_barberia_id() and g.codigo = upper(btrim(p_codigo));
end;
$$;

-- ── 4. Método de pago en las líneas de producto (para la caja del día) ──────
-- Una venta de solo productos no tiene visita, así que no quedaba registrado
-- con qué se pagó. Ahora cada línea de producto guarda el método del cobro.
alter table public.cobro_productos add column if not exists metodo_pago text;
update public.cobro_productos cp
   set metodo_pago = v.metodo_pago
  from (select distinct on (cobro_id) cobro_id, metodo_pago from public.visitas where cobro_id is not null order by cobro_id) v
 where v.cobro_id = cp.cobro_id and cp.metodo_pago is null;
-- (y registrar_cobro_conjunto inserta metodo_pago = v_metodo en cobro_productos;
--  ver la definición vigente en la base)

-- ── 5. La invitación vale 15 minutos y se puede cancelar ────────────────────
create or replace function public.reclamar_recepcion()
returns void
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  v_inv recepcion_invitaciones;
  v_email text := lower(coalesce(auth.jwt() ->> 'email', ''));
begin
  if auth.uid() is null or v_email = '' then
    raise exception 'No autorizado';
  end if;
  select * into v_inv from recepcion_invitaciones
   where lower(email) = v_email and created_at > now() - interval '15 minutes';
  if not found then
    raise exception 'No hay una invitación vigente para este correo';
  end if;
  insert into perfiles (id, barberia_id, nombre, rol)
  values (auth.uid(), v_inv.barberia_id, v_inv.nombre, 'recepcion');
  delete from recepcion_invitaciones where id = v_inv.id;
end;
$$;

create or replace function public.cancelar_invitacion_recepcion(p_email text)
returns void
language plpgsql
security definer
set search_path to 'public'
as $$
begin
  if auth_barberia_id() is null or auth_rol() <> 'dueno' then
    raise exception 'No autorizado';
  end if;
  delete from recepcion_invitaciones
   where lower(email) = lower(btrim(p_email)) and barberia_id = auth_barberia_id();
end;
$$;
