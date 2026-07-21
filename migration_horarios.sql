-- Horario del negocio + bloqueos de horario por profesional.
-- Ejecutar UNA VEZ, completo, en el SQL Editor de Supabase.
--
-- IMPORTANTE: cada tabla tiene una política separada por operación
-- (select/insert/update/delete). Ninguna es "for all using(true)" —
-- ese patrón fue exactamente lo que causó la fuga que se cerró hoy
-- (migration_cleanup_rls.sql): una política permisiva "true" en
-- cualquier comando anula, por el OR de RLS, a todas las políticas
-- restrictivas que existan sobre la misma tabla y comando.

-- ═══════════════════════════════════════════════════════════════
-- Horario del negocio: apertura/cierre por día de semana.
-- Lectura pública (la necesita reservar.html sin login para calcular
-- disponibilidad), escritura solo del dueño. Mismo criterio que
-- servicios_select_public/barberos_select_public: no hay PII acá.
-- ═══════════════════════════════════════════════════════════════

create table if not exists horario_negocio (
  id uuid primary key default gen_random_uuid(),
  barberia_id uuid not null references barberias(id),
  dia_semana int not null check (dia_semana between 0 and 6), -- 0=domingo
  hora_apertura time,
  hora_cierre time,
  cerrado boolean not null default false,
  unique(barberia_id, dia_semana)
);

alter table horario_negocio enable row level security;
create policy "horario_negocio_select_public" on horario_negocio for select using (true);
create policy "horario_negocio_insert_own" on horario_negocio for insert with check (barberia_id = auth_barberia_id());
create policy "horario_negocio_update_own" on horario_negocio for update using (barberia_id = auth_barberia_id()) with check (barberia_id = auth_barberia_id());
create policy "horario_negocio_delete_own" on horario_negocio for delete using (barberia_id = auth_barberia_id());

-- ═══════════════════════════════════════════════════════════════
-- Bloqueos por profesional: puntual (rango de horas un día puntual),
-- día completo, o recurrente (mismo día de semana todas las semanas).
-- Lectura pública por el mismo motivo que horario_negocio — sin PII.
-- ═══════════════════════════════════════════════════════════════

create table if not exists bloqueos_profesional (
  id uuid primary key default gen_random_uuid(),
  barberia_id uuid not null references barberias(id),
  profesional_id uuid not null references barberos(id),
  tipo text not null check (tipo in ('puntual', 'dia_completo', 'recurrente')),
  fecha date, -- usado por 'puntual' y 'dia_completo'
  dia_semana int check (dia_semana between 0 and 6), -- usado por 'recurrente'
  hora_inicio time, -- usado por 'puntual' y 'recurrente'
  hora_fin time, -- usado por 'puntual' y 'recurrente'
  motivo text,
  activo boolean not null default true,
  created_at timestamptz not null default now()
);

alter table bloqueos_profesional enable row level security;
create policy "bloqueos_select_public" on bloqueos_profesional for select using (true);
create policy "bloqueos_insert_own" on bloqueos_profesional for insert with check (barberia_id = auth_barberia_id());
create policy "bloqueos_update_own" on bloqueos_profesional for update using (barberia_id = auth_barberia_id()) with check (barberia_id = auth_barberia_id());
create policy "bloqueos_delete_own" on bloqueos_profesional for delete using (barberia_id = auth_barberia_id());
