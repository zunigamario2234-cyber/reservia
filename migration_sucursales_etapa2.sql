-- =============================================================================
-- MULTISUCURSAL (etapa 2): horarios, inventario y gastos POR SUCURSAL.
-- Lo único que sigue siendo del negocio completo: clientes, servicios y Club VIP.
--  · horario_negocio: una fila por (sucursal, día). Una sucursal nueva nace con
--    una copia del horario de la principal.
--  · inventario: cada sucursal tiene su stock, código y precios. Una venta solo
--    puede usar un producto de la sucursal del profesional (lo exige la base).
--  · costos (gastos): cada gasto es de una sucursal.
--  · Recepción solo ve el inventario de su sucursal (vista inventario_recepcion).
--  · Todo negocio nuevo nace con su sucursal "Principal".
-- ⚠ SIN begin;/commit; A PROPÓSITO (el SQL Editor trocea por `;` los cuerpos).
-- =============================================================================

-- Negocios nuevos: sucursal Principal automática (antes solo se creaba en la migración).
create or replace function public.trg_crear_sucursal_principal()
returns trigger language plpgsql security definer set search_path to 'public' as $$
begin
  insert into sucursales (barberia_id, nombre, direccion, orden) values (new.id, 'Principal', new.direccion, 0);
  return new;
end $$;
drop trigger if exists crear_sucursal_principal on public.barberias;
create trigger crear_sucursal_principal after insert on public.barberias
  for each row execute function public.trg_crear_sucursal_principal();

-- Relleno por si algún negocio quedó sin sucursal.
insert into public.sucursales (barberia_id, nombre, direccion, orden)
select b.id, 'Principal', b.direccion, 0 from public.barberias b
 where not exists (select 1 from public.sucursales s where s.barberia_id = b.id);

-- ── Horarios ────────────────────────────────────────────────────────────────
alter table public.horario_negocio add column if not exists sucursal_id uuid references public.sucursales(id) on delete cascade;
update public.horario_negocio set sucursal_id = public.sucursal_principal(barberia_id) where sucursal_id is null;
alter table public.horario_negocio alter column sucursal_id set not null;
alter table public.horario_negocio drop constraint if exists horario_negocio_barberia_id_dia_semana_key;
create unique index if not exists horario_negocio_suc_dia on public.horario_negocio (sucursal_id, dia_semana);

create or replace function public.trg_sucursal_copia_horario()
returns trigger language plpgsql security definer set search_path to 'public' as $$
declare v_base uuid := sucursal_principal(new.barberia_id);
begin
  if v_base is not null and v_base <> new.id then
    insert into horario_negocio (barberia_id, sucursal_id, dia_semana, hora_apertura, hora_cierre, cerrado, hora_colacion_inicio, hora_colacion_fin)
    select barberia_id, new.id, dia_semana, hora_apertura, hora_cierre, cerrado, hora_colacion_inicio, hora_colacion_fin
      from horario_negocio where sucursal_id = v_base
    on conflict (sucursal_id, dia_semana) do nothing;
  end if;
  return new;
end $$;
drop trigger if exists copia_horario on public.sucursales;
create trigger copia_horario after insert on public.sucursales
  for each row execute function public.trg_sucursal_copia_horario();

-- ── Inventario ──────────────────────────────────────────────────────────────
alter table public.inventario add column if not exists sucursal_id uuid references public.sucursales(id);
update public.inventario set sucursal_id = public.sucursal_principal(barberia_id) where sucursal_id is null;
drop index if exists public.inventario_codigo_unico;
create unique index if not exists inventario_codigo_unico on public.inventario (sucursal_id, codigo) where codigo is not null;
create index if not exists inventario_sucursal on public.inventario (barberia_id, sucursal_id);

-- ── Gastos ──────────────────────────────────────────────────────────────────
alter table public.costos add column if not exists sucursal_id uuid references public.sucursales(id);
update public.costos set sucursal_id = public.sucursal_principal(barberia_id) where sucursal_id is null;
create index if not exists costos_sucursal on public.costos (barberia_id, sucursal_id, fecha);

-- Si no se indica sucursal, va a la principal; y siempre debe ser del mismo negocio.
create or replace function public.trg_sucursal_defecto_negocio()
returns trigger language plpgsql security definer set search_path to 'public' as $$
begin
  if new.sucursal_id is null then new.sucursal_id := sucursal_principal(new.barberia_id); end if;
  if not exists (select 1 from sucursales s where s.id = new.sucursal_id and s.barberia_id = new.barberia_id) then
    raise exception 'Sucursal no válida';
  end if;
  return new;
end $$;
drop trigger if exists set_sucursal on public.inventario;
create trigger set_sucursal before insert or update of sucursal_id on public.inventario
  for each row execute function public.trg_sucursal_defecto_negocio();
drop trigger if exists set_sucursal on public.costos;
create trigger set_sucursal before insert or update of sucursal_id on public.costos
  for each row execute function public.trg_sucursal_defecto_negocio();
drop trigger if exists set_sucursal on public.horario_negocio;
create trigger set_sucursal before insert or update of sucursal_id on public.horario_negocio
  for each row execute function public.trg_sucursal_defecto_negocio();

-- Una venta de producto solo descuenta stock de la sucursal del profesional.
-- (el nombre empieza con "zz" para correr DESPUÉS de set_sucursal, que completa la sucursal)
create or replace function public.trg_check_sucursal_producto()
returns trigger language plpgsql security definer set search_path to 'public' as $$
declare v uuid;
begin
  if new.producto_id is not null then
    select sucursal_id into v from inventario where id = new.producto_id;
    if v is not null and new.sucursal_id is not null and v <> new.sucursal_id then
      raise exception 'Ese producto es de otra sucursal';
    end if;
  end if;
  return new;
end $$;
drop trigger if exists zz_check_sucursal_producto on public.cobro_productos;
create trigger zz_check_sucursal_producto before insert on public.cobro_productos
  for each row execute function public.trg_check_sucursal_producto();

-- Recepción: solo el inventario de su sucursal (columna nueva al final).
create or replace view public.inventario_recepcion as
  select i.id, i.barberia_id, i.codigo, i.nombre, i.categoria, i.stock, i.precio_venta, i.sucursal_id
    from public.inventario i
   where i.barberia_id = auth_barberia_id()
     and auth_rol() in ('dueno', 'recepcion')
     and (auth_sucursal_scope() is null or i.sucursal_id = auth_sucursal_scope());
