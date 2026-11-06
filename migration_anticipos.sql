-- =============================================================================
-- ANTICIPOS A PROFESIONALES
-- El dueño anota lo que le adelantó a un profesional; en Reportes → Profesionales
-- se resta de lo que hay que transferirle en el período. Solo el dueño la ve y la
-- edita (recepción y profesionales no tienen política: no ven ni escriben nada).
-- ⚠ SIN begin;/commit; A PROPÓSITO (el SQL Editor trocea por `;` los cuerpos).
-- =============================================================================
create table if not exists public.anticipos_profesional (
  id uuid primary key default gen_random_uuid(),
  barberia_id uuid not null references public.barberias(id) on delete cascade,
  barbero_nombre text not null,
  fecha date not null default (now() at time zone 'America/Santiago')::date,
  monto numeric not null check (monto > 0),
  nota text,
  created_at timestamptz not null default now()
);
create index if not exists anticipos_profesional_barberia_fecha
  on public.anticipos_profesional (barberia_id, fecha);

alter table public.anticipos_profesional enable row level security;

drop policy if exists anticipos_dueno_select on public.anticipos_profesional;
create policy anticipos_dueno_select on public.anticipos_profesional for select
  using (barberia_id = auth_barberia_id() and auth_rol() = 'dueno');
drop policy if exists anticipos_dueno_insert on public.anticipos_profesional;
create policy anticipos_dueno_insert on public.anticipos_profesional for insert
  with check (barberia_id = auth_barberia_id() and auth_rol() = 'dueno');
drop policy if exists anticipos_dueno_update on public.anticipos_profesional;
create policy anticipos_dueno_update on public.anticipos_profesional for update
  using (barberia_id = auth_barberia_id() and auth_rol() = 'dueno')
  with check (barberia_id = auth_barberia_id() and auth_rol() = 'dueno');
drop policy if exists anticipos_dueno_delete on public.anticipos_profesional;
create policy anticipos_dueno_delete on public.anticipos_profesional for delete
  using (barberia_id = auth_barberia_id() and auth_rol() = 'dueno');

revoke all on public.anticipos_profesional from anon;
