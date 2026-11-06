-- =============================================================================
-- MODO "BOLETA DE HONORARIOS" para las comisiones
--
-- No es un modo nuevo de calcular la comisión: la base sigue siendo el NETO
-- (precio sin IVA), igual que 'neto_iva'. Por eso barberias.modo_comision queda
-- en 'neto_iva' y la RPC de cobro no cambia. Lo nuevo es una capa encima:
--   · barberias.usa_honorarios        -> el negocio paga con boleta de honorarios
--   · honorarios_retencion_paga       -> 'profesional' (todo) o 'dividido'
--   · honorarios_pct_profesional      -> si es dividido, % que paga el profesional
-- y un trigger que congela en cada visita el desglose (IVA, retención, quién la
-- paga, líquido), para que cambiar el porcentaje o el modo después NO altere lo
-- ya cobrado.
--
-- La tasa de retención del SII es por ley, año a año (2026 15,25%, 2027 16%,
-- 2028 17%): se guarda en una tabla y se aplica según el AÑO de la visita, sin
-- que nadie la edite.
--
-- ⚠ SIN begin;/commit; A PROPÓSITO (el SQL Editor trocea por `;` los cuerpos).
-- =============================================================================

alter table public.barberias
  add column if not exists usa_honorarios boolean not null default false,
  add column if not exists honorarios_retencion_paga text not null default 'profesional',
  add column if not exists honorarios_pct_profesional numeric not null default 50;
alter table public.barberias drop constraint if exists barberias_honorarios_paga_chk;
alter table public.barberias add constraint barberias_honorarios_paga_chk
  check (honorarios_retencion_paga in ('profesional','dividido') and honorarios_pct_profesional between 0 and 100);

create table if not exists public.retencion_honorarios_tasas (
  desde_anio int primary key,
  pct numeric not null check (pct >= 0 and pct <= 100)
);
insert into public.retencion_honorarios_tasas (desde_anio, pct) values
  (2024, 13.75), (2025, 14.5), (2026, 15.25), (2027, 16), (2028, 17)
on conflict (desde_anio) do nothing;
alter table public.retencion_honorarios_tasas enable row level security;
drop policy if exists tasas_retencion_lectura on public.retencion_honorarios_tasas;
create policy tasas_retencion_lectura on public.retencion_honorarios_tasas for select to authenticated using (true);

alter table public.visitas
  add column if not exists iva_monto numeric,
  add column if not exists retencion_pct numeric,
  add column if not exists retencion_total numeric,
  add column if not exists retencion_profesional numeric,
  add column if not exists retencion_negocio numeric,
  add column if not exists liquido_profesional numeric;

create or replace function public.tasa_retencion_honorarios(p_fecha date)
returns numeric
language sql
stable
set search_path to 'public'
as $$
  select pct from retencion_honorarios_tasas
   where desde_anio <= extract(year from p_fecha)::int
   order by desde_anio desc limit 1;
$$;

create or replace function public.visitas_honorarios()
returns trigger
language plpgsql
set search_path to 'public'
as $function$
declare
  b barberias%rowtype;
  v_tasa numeric;
  v_total numeric;
  v_prof numeric;
begin
  if tg_op = 'UPDATE'
     and new.comision_monto is not distinct from old.comision_monto
     and new.valor is not distinct from old.valor
     and new.fecha is not distinct from old.fecha then
    return new;
  end if;
  if new.comision_monto is null then return new; end if;
  select * into b from barberias where id = new.barberia_id;
  if not found or not b.usa_honorarios then return new; end if;

  v_tasa  := tasa_retencion_honorarios(new.fecha);
  v_total := round(new.comision_monto * coalesce(v_tasa, 0) / 100);
  v_prof  := case when b.honorarios_retencion_paga = 'dividido'
                  then round(v_total * b.honorarios_pct_profesional / 100)
                  else v_total end;
  new.iva_monto              := round(coalesce(new.valor, 0) * coalesce(b.iva_pct, 19) / (100 + coalesce(b.iva_pct, 19)));
  new.retencion_pct          := v_tasa;
  new.retencion_total        := v_total;
  new.retencion_profesional  := v_prof;
  new.retencion_negocio      := v_total - v_prof;
  new.liquido_profesional    := new.comision_monto - v_prof;
  return new;
end;
$function$;

drop trigger if exists visitas_honorarios_trg on public.visitas;
create trigger visitas_honorarios_trg before insert or update on public.visitas
  for each row execute function public.visitas_honorarios();
