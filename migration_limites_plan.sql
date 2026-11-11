-- =============================================================================
-- LÍMITES DEL PLAN. Se aplican en la base (no en el navegador) para que nadie
-- los salte:
--   Gratis: hasta 50 clientes y 1 profesional activo.
--   Pro:    clientes sin límite y hasta 5 profesionales activos.
-- Clientes: solo se frena lo que crea el dueño o su equipo desde la app
-- (usuarios autenticados). Un cliente nuevo que reserva por la página pública
-- (anon) siempre se registra: no se le cierra la puerta a quien va a pagar.
-- El SQL Editor y la service_role no tienen tope.
-- Aditiva; no toca datos existentes (los negocios que ya superan el tope
-- siguen funcionando, solo no pueden agregar más).
-- =============================================================================
create or replace function public.trg_limite_clientes()
returns trigger language plpgsql security definer set search_path to 'public' as $$
declare v_plan text; v_n int;
begin
  if coalesce(auth.role(), '') <> 'authenticated' then return new; end if;
  select plan into v_plan from barberias where id = new.barberia_id;
  if coalesce(v_plan, 'free') = 'pro' then return new; end if;
  select count(*) into v_n from clientes where barberia_id = new.barberia_id;
  if v_n >= 50 then
    raise exception 'Llegaste al límite de 50 clientes del plan gratis. Pasa al plan Pro para agregar más.'
      using errcode = 'P0001';
  end if;
  return new;
end $$;

create or replace function public.trg_limite_profesionales()
returns trigger language plpgsql security definer set search_path to 'public' as $$
declare v_plan text; v_n int; v_max int;
begin
  if coalesce(auth.role(), '') not in ('authenticated', 'anon') then return new; end if;
  if new.activo is not true then return new; end if;
  if tg_op = 'UPDATE' and old.activo is true then return new; end if;
  select plan into v_plan from barberias where id = new.barberia_id;
  v_max := case when coalesce(v_plan, 'free') = 'pro' then 5 else 1 end;
  select count(*) into v_n from barberos
   where barberia_id = new.barberia_id and activo is true
     and id is distinct from new.id;
  if v_n >= v_max then
    raise exception '%', case when v_max = 1
      then 'El plan gratis incluye 1 profesional. Pasa al plan Pro para agregar hasta 5.'
      else 'El plan Pro incluye hasta 5 profesionales activos.' end
      using errcode = 'P0001';
  end if;
  return new;
end $$;

create trigger limite_clientes before insert on public.clientes
  for each row execute function public.trg_limite_clientes();
create trigger limite_profesionales before insert or update of activo on public.barberos
  for each row execute function public.trg_limite_profesionales();
