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
