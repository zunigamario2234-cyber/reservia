-- =============================================================================
-- MULTISUCURSAL (etapa 3): SERVICIOS POR SUCURSAL.
-- Después de esta etapa solo siguen siendo del negocio completo: clientes y Club VIP.
-- Horarios, inventario, gastos (etapa 2) y ahora servicios son de cada sucursal.
--  · servicios.sucursal_id: cada servicio pertenece a una sucursal (lo existente
--    queda en la Principal). Precio, duración, comisión y abono se editan por sucursal.
--  · copiar_servicios_sucursal(origen, destino): el dueño copia los servicios de una
--    sucursal (p. ej. la matriz) a otra. No duplica los que ya existen por nombre y
--    deja activos a los profesionales de la sucursal destino en esos servicios.
--  · Recepción y profesionales ven solo los servicios de su sucursal (política
--    restrictiva en la base). El dueño ve todos y filtra en la app.
-- Aditiva: no borra ni cambia datos existentes.
-- ⚠ SIN begin;/commit; A PROPÓSITO (el SQL Editor trocea por `;` los cuerpos).
-- =============================================================================
alter table public.servicios add column if not exists sucursal_id uuid references public.sucursales(id);
update public.servicios set sucursal_id = public.sucursal_principal(barberia_id) where sucursal_id is null;
create index if not exists servicios_sucursal on public.servicios (barberia_id, sucursal_id);

-- Si no se indica sucursal, va a la principal; y siempre debe ser del mismo negocio.
drop trigger if exists set_sucursal on public.servicios;
create trigger set_sucursal before insert or update of sucursal_id on public.servicios
  for each row execute function public.trg_sucursal_defecto_negocio();

drop policy if exists sucursal_scope on public.servicios;
create policy sucursal_scope on public.servicios as restrictive for select
  using (auth_sucursal_scope() is null or sucursal_id = auth_sucursal_scope());

create or replace function public.copiar_servicios_sucursal(p_origen uuid, p_destino uuid)
returns integer language plpgsql security definer set search_path to 'public' as $$
declare
  v_b uuid := auth_barberia_id();
  n integer;
begin
  if v_b is null or auth_rol() <> 'dueno' then raise exception 'No autorizado'; end if;
  if p_origen is null or p_destino is null or p_origen = p_destino then
    raise exception 'Elige dos sucursales distintas';
  end if;
  if (select count(*) from sucursales where barberia_id = v_b and id in (p_origen, p_destino)) <> 2 then
    raise exception 'Sucursal no válida';
  end if;
  -- Copia todas las columnas del servicio y solo cambia id, sucursal y fecha.
  -- Los que ya existen en el destino (mismo nombre) se saltan.
  insert into servicios
    select (jsonb_populate_record(null::servicios,
             to_jsonb(s) || jsonb_build_object('id', gen_random_uuid(), 'sucursal_id', p_destino, 'created_at', now()))).*
      from servicios s
     where s.barberia_id = v_b and s.sucursal_id = p_origen
       and not exists (select 1 from servicios d
                        where d.barberia_id = v_b and d.sucursal_id = p_destino
                          and lower(btrim(d.nombre)) = lower(btrim(s.nombre)));
  get diagnostics n = row_count;
  -- Los profesionales de la sucursal destino pueden hacer los servicios nuevos.
  insert into barbero_servicios (barberia_id, barbero_id, servicio_id, activo)
    select v_b, b.id, sv.id, true
      from barberos b
      join servicios sv on sv.barberia_id = v_b and sv.sucursal_id = p_destino
     where b.barberia_id = v_b and b.sucursal_id = p_destino
       and not exists (select 1 from barbero_servicios x where x.barbero_id = b.id and x.servicio_id = sv.id);
  return n;
end $$;
revoke all on function public.copiar_servicios_sucursal(uuid, uuid) from public, anon;
grant execute on function public.copiar_servicios_sucursal(uuid, uuid) to authenticated;
