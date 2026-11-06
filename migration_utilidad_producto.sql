-- =============================================================================
-- UTILIDAD POR PRODUCTO
-- El costo de cada venta se congela al venderla (si el costo del producto sube
-- después, las ventas viejas no cambian). Vive en una tabla aparte, solo para el
-- dueño: cobro_productos la puede leer recepción (las ventas de hoy) y el costo
-- no debe verlo.
-- Las ventas anteriores a esta migración se rellenan con el costo ACTUAL del
-- producto: es una aproximación, no el costo del día de la venta.
-- ⚠ SIN begin;/commit; A PROPÓSITO (el SQL Editor trocea por `;` los cuerpos).
-- =============================================================================
create table if not exists public.cobro_productos_costo (
  cobro_producto_id uuid primary key references public.cobro_productos(id) on delete cascade,
  barberia_id uuid not null references public.barberias(id) on delete cascade,
  costo_unitario numeric not null default 0
);
alter table public.cobro_productos_costo enable row level security;
drop policy if exists cobro_productos_costo_dueno on public.cobro_productos_costo;
create policy cobro_productos_costo_dueno on public.cobro_productos_costo for select
  using (barberia_id = auth_barberia_id() and auth_rol() = 'dueno');

create or replace function public.cobro_productos_guardar_costo()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $function$
begin
  insert into cobro_productos_costo (cobro_producto_id, barberia_id, costo_unitario)
  select new.id, new.barberia_id, coalesce(i.costo_unitario, 0)
    from inventario i where i.id = new.producto_id
  on conflict (cobro_producto_id) do nothing;
  return new;
end;
$function$;
drop trigger if exists cobro_productos_costo_trg on public.cobro_productos;
create trigger cobro_productos_costo_trg after insert on public.cobro_productos
  for each row execute function public.cobro_productos_guardar_costo();

insert into public.cobro_productos_costo (cobro_producto_id, barberia_id, costo_unitario)
select cp.id, cp.barberia_id, coalesce(i.costo_unitario, 0)
  from public.cobro_productos cp left join public.inventario i on i.id = cp.producto_id
on conflict (cobro_producto_id) do nothing;
