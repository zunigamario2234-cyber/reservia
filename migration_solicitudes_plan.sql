-- =============================================================================
-- SOLICITUDES DEL PLAN PRO (mientras no hay pasarela de pago).
-- Quien aprieta «Solicitar plan Pro» en la landing, o elige Pro al registrarse,
-- deja una fila acá. /api/solicitar-plan-pro la escribe con la service_role key
-- y le avisa por correo al equipo de Reservia, que responde con los datos de
-- transferencia y activa el plan a mano cuando llega el pago:
--     update barberias set plan = 'pro' where id = '<barberia_id>';
--     update solicitudes_plan set estado = 'activada' where id = '<id>';
-- Aditiva. Sin políticas a propósito: con RLS activado y sin políticas, ni anon
-- ni un usuario autenticado pueden leer ni escribir; solo la service_role.
-- =============================================================================
create table if not exists public.solicitudes_plan (
  id            uuid primary key default gen_random_uuid(),
  created_at    timestamptz not null default now(),
  plan          text not null default 'pro' check (plan in ('pro')),
  nombre        text not null,
  negocio       text not null,
  email         text not null,
  whatsapp      text not null,
  profesionales text,
  mensaje       text,
  origen        text,
  barberia_id   uuid,
  estado        text not null default 'nueva'
                check (estado in ('nueva','contactada','pagada','activada','descartada')),
  notas         text
);
alter table public.solicitudes_plan enable row level security;
revoke all on public.solicitudes_plan from anon, authenticated;
create index if not exists solicitudes_plan_fecha on public.solicitudes_plan (created_at desc);
create index if not exists solicitudes_plan_email on public.solicitudes_plan (lower(email), created_at desc);

-- ── El plan solo lo cambia Reservia ─────────────────────────────────────────
-- Las políticas de barberias dejan a cualquier usuario autenticado crear su
-- negocio y al dueño editarlo; sin esto podría ponerse plan = 'pro' él mismo
-- desde el navegador. Este trigger fuerza 'free' al crear y bloquea cambios del
-- plan cuando la llamada viene de un usuario (anon/authenticated). El SQL Editor
-- y la service_role siguen pudiendo activar el Pro.
create or replace function public.trg_proteger_plan()
returns trigger language plpgsql security definer set search_path to 'public' as $$
begin
  -- Las funciones admin_* marcan la transacción antes de cambiar el plan.
  if coalesce(current_setting('reservia.admin', true), '') = '1' then
    return new;
  end if;
  if coalesce(auth.role(), '') in ('anon', 'authenticated') then
    if tg_op = 'INSERT' then
      new.plan := 'free';
    elsif new.plan is distinct from old.plan then
      new.plan := old.plan;
    end if;
  end if;
  return new;
end $$;
drop trigger if exists proteger_plan on public.barberias;
create trigger proteger_plan before insert or update of plan on public.barberias
  for each row execute function public.trg_proteger_plan();

-- ── Panel de administración (admin.html) ────────────────────────────────────
-- Solo las cuentas de la tabla superadmins pueden usarlo. No tiene políticas:
-- se llena desde el SQL Editor / service_role (ver "Alta del administrador").
--   insert into superadmins (user_id) select id from auth.users where email = '<correo>';
create table if not exists public.superadmins (user_id uuid primary key references auth.users(id) on delete cascade);
alter table public.superadmins enable row level security;
revoke all on public.superadmins from anon, authenticated;

create or replace function public.es_admin()
returns boolean language sql stable security definer set search_path to 'public' as $$
  select exists (select 1 from superadmins where user_id = auth.uid())
$$;

-- Solicitudes con el plan actual del negocio (si ya tiene cuenta).
create or replace function public.admin_solicitudes()
returns jsonb language plpgsql stable security definer set search_path to 'public' as $$
begin
  if not es_admin() then raise exception 'No autorizado'; end if;
  return coalesce((
    select jsonb_agg(to_jsonb(x) order by x.created_at desc) from (
      select s.id, s.created_at, s.nombre, s.negocio, s.email, s.whatsapp, s.profesionales,
             s.mensaje, s.origen, s.barberia_id, s.estado, s.notas,
             b.plan as plan_actual, b.nombre as negocio_cuenta
        from solicitudes_plan s left join barberias b on b.id = s.barberia_id
       order by s.created_at desc limit 300) x
  ), '[]'::jsonb);
end $$;

-- Todos los negocios, para ver su plan y vincular una solicitud que llegó desde la landing.
create or replace function public.admin_negocios()
returns jsonb language plpgsql stable security definer set search_path to 'public' as $$
begin
  if not es_admin() then raise exception 'No autorizado'; end if;
  return coalesce((
    select jsonb_agg(to_jsonb(x) order by x.created_at desc) from (
      select b.id, b.nombre, b.email, b.whatsapp, b.plan, b.created_at, b.activo
        from barberias b order by b.created_at desc limit 500) x
  ), '[]'::jsonb);
end $$;

-- Cambia el plan de un negocio (encender / apagar el Pro).
create or replace function public.admin_set_plan(p_barberia uuid, p_plan text)
returns void language plpgsql security definer set search_path to 'public' as $$
begin
  if not es_admin() then raise exception 'No autorizado'; end if;
  if p_plan not in ('free', 'pro') then raise exception 'Plan no válido'; end if;
  perform set_config('reservia.admin', '1', true);
  update barberias set plan = p_plan where id = p_barberia;
  if not found then raise exception 'Negocio no encontrado'; end if;
  if p_plan = 'pro' then
    update solicitudes_plan set estado = 'activada'
     where barberia_id = p_barberia and estado in ('nueva', 'contactada', 'pagada');
  end if;
end $$;

-- Estado y notas de una solicitud; opcionalmente la vincula a un negocio.
create or replace function public.admin_actualizar_solicitud(p_id uuid, p_estado text, p_notas text default null, p_barberia uuid default null)
returns void language plpgsql security definer set search_path to 'public' as $$
begin
  if not es_admin() then raise exception 'No autorizado'; end if;
  if p_estado not in ('nueva', 'contactada', 'pagada', 'activada', 'descartada') then
    raise exception 'Estado no válido';
  end if;
  update solicitudes_plan
     set estado = p_estado,
         notas = coalesce(p_notas, notas),
         barberia_id = coalesce(p_barberia, barberia_id)
   where id = p_id;
  if not found then raise exception 'Solicitud no encontrada'; end if;
end $$;

revoke all on function public.es_admin() from public, anon;
revoke all on function public.admin_solicitudes() from public, anon;
revoke all on function public.admin_negocios() from public, anon;
revoke all on function public.admin_set_plan(uuid, text) from public, anon;
revoke all on function public.admin_actualizar_solicitud(uuid, text, text, uuid) from public, anon;
grant execute on function public.es_admin() to authenticated;
grant execute on function public.admin_solicitudes() to authenticated;
grant execute on function public.admin_negocios() to authenticated;
grant execute on function public.admin_set_plan(uuid, text) to authenticated;
grant execute on function public.admin_actualizar_solicitud(uuid, text, text, uuid) to authenticated;
