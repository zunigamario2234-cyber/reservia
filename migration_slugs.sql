-- =============================================================================
-- LINKS CORTOS DE RESERVA
--   mireservia.cl/reservar/<negocio>                 -> reservar en el negocio
--   mireservia.cl/reservar/<negocio>/<profesional>   -> reservar con ese profesional
--   mireservia.cl/reservar/<negocio>?sucursal=<slug> -> reservar en esa sucursal
-- El slug nace del nombre y NO cambia si después se renombra (los links ya
-- compartidos siguen funcionando). Los links largos (?id=…) siguen valiendo.
-- ⚠ SIN begin;/commit; A PROPÓSITO (el SQL Editor trocea por `;` los cuerpos).
-- =============================================================================
create or replace function public.slugify(t text)
returns text language sql immutable as $$
  select coalesce(nullif(trim(both '-' from regexp_replace(
    translate(lower(coalesce(t,'')), 'áàäâéèëêíìïîóòöôúùüûñ', 'aaaaeeeeiiiioooouuuun'),
    '[^a-z0-9]+', '-', 'g')), ''), 'negocio')
$$;

alter table public.barberias add column if not exists slug text;
alter table public.barberos add column if not exists slug text;
alter table public.sucursales add column if not exists slug text;

-- Relleno: el primero se queda con el nombre limpio, los repetidos llevan -2, -3…
with n as (
  select id, slugify(nombre) base,
         row_number() over (partition by slugify(nombre) order by created_at, id) rn
    from public.barberias where slug is null)
update public.barberias b set slug = case when n.rn = 1 then n.base else n.base || '-' || n.rn end
  from n where b.id = n.id;
with n as (
  select id, slugify(nombre) base,
         row_number() over (partition by barberia_id, slugify(nombre) order by created_at, id) rn
    from public.barberos where slug is null)
update public.barberos b set slug = case when n.rn = 1 then n.base else n.base || '-' || n.rn end
  from n where b.id = n.id;
with n as (
  select id, slugify(nombre) base,
         row_number() over (partition by barberia_id, slugify(nombre) order by created_at, id) rn
    from public.sucursales where slug is null)
update public.sucursales b set slug = case when n.rn = 1 then n.base else n.base || '-' || n.rn end
  from n where b.id = n.id;

create unique index if not exists barberias_slug_unico on public.barberias (slug);
create unique index if not exists barberos_slug_unico on public.barberos (barberia_id, slug);
create unique index if not exists sucursales_slug_unico on public.sucursales (barberia_id, slug);

-- Altas nuevas: se completa solo, con sufijo si ya existe.
create or replace function public.trg_set_slug()
returns trigger language plpgsql security definer set search_path to 'public' as $$
declare base text; cand text; i int := 1; existe boolean;
begin
  if new.slug is not null and btrim(new.slug) <> '' then return new; end if;
  base := slugify(new.nombre); cand := base;
  loop
    if tg_table_name = 'barberias' then
      select exists(select 1 from barberias where slug = cand) into existe;
    elsif tg_table_name = 'barberos' then
      select exists(select 1 from barberos where barberia_id = new.barberia_id and slug = cand) into existe;
    else
      select exists(select 1 from sucursales where barberia_id = new.barberia_id and slug = cand) into existe;
    end if;
    exit when not existe;
    i := i + 1; cand := base || '-' || i;
  end loop;
  new.slug := cand; return new;
end $$;
drop trigger if exists set_slug on public.barberias;
create trigger set_slug before insert on public.barberias for each row execute function public.trg_set_slug();
drop trigger if exists set_slug on public.barberos;
create trigger set_slug before insert on public.barberos for each row execute function public.trg_set_slug();
drop trigger if exists set_slug on public.sucursales;
create trigger set_slug before insert on public.sucursales for each row execute function public.trg_set_slug();
