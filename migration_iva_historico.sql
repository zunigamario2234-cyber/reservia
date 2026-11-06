-- =============================================================================
-- HISTORIAL DE IVA IMPORTADO
-- Para quien empieza a usar la plataforma con un año (o más) de IVA llevado en
-- Excel: se importa mes a mes (débito, crédito, remanente) y queda junto al IVA
-- que la plataforma calcula desde ahora. Una fila por negocio y mes. Solo dueño.
-- ⚠ SIN begin;/commit; A PROPÓSITO (el SQL Editor trocea por `;` los cuerpos).
-- =============================================================================
create table if not exists public.iva_historico (
  id uuid primary key default gen_random_uuid(),
  barberia_id uuid not null references public.barberias(id) on delete cascade,
  mes text not null check (mes ~ '^[0-9]{4}-(0[1-9]|1[0-2])$'),
  ventas_brutas numeric,
  iva_debito numeric not null default 0 check (iva_debito >= 0),
  iva_credito numeric not null default 0 check (iva_credito >= 0),
  remanente numeric,
  nota text,
  origen text not null default 'importado',
  created_at timestamptz not null default now(),
  unique (barberia_id, mes)
);
alter table public.iva_historico enable row level security;
drop policy if exists iva_historico_dueno on public.iva_historico;
create policy iva_historico_dueno on public.iva_historico for all
  using (barberia_id = auth_barberia_id() and auth_rol() = 'dueno')
  with check (barberia_id = auth_barberia_id() and auth_rol() = 'dueno');
revoke all on public.iva_historico from anon;
