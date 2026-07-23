-- Rediseño de reservar.html tipo perfil de negocio + relación
-- profesional↔servicio para filtrar quién ofrece qué.
--
-- Ejecutar UNA VEZ, completo, en el SQL Editor de Supabase.

-- ═══════════════════════════════════════════════════════════════
-- (1) barberias: portada + contacto/redes nuevos. telefono ya existe,
-- no se toca.
-- ═══════════════════════════════════════════════════════════════

alter table barberias add column if not exists foto_portada text;
alter table barberias add column if not exists instagram text;
alter table barberias add column if not exists email text;

-- ═══════════════════════════════════════════════════════════════
-- (2) barberos: bio para el perfil público del profesional.
-- ═══════════════════════════════════════════════════════════════

alter table barberos add column if not exists bio text;

-- ═══════════════════════════════════════════════════════════════
-- (3) Tabla nueva: qué profesional ofrece qué servicio.
--
-- barberia_id se guarda directo en la fila (no solo derivable via join)
-- porque así están escopeadas TODAS las tablas de este negocio para
-- RLS — mismo patrón que reservas/visitas/clientes, nunca depender de
-- un join para saber a qué negocio pertenece una fila.
--
-- Lectura pública (using(true) SOLO en el select, no "for all") porque
-- reservar.html la necesita sin sesión — mismo criterio ya usado en
-- barberias_select_public. Escritura exige auth_rol()='dueno', igual
-- que el resto de tablas de configuración.
-- ═══════════════════════════════════════════════════════════════

create table if not exists barbero_servicios (
  id uuid primary key default gen_random_uuid(),
  barberia_id uuid not null references barberias(id) on delete cascade,
  barbero_id uuid not null references barberos(id) on delete cascade,
  servicio_id uuid not null references servicios(id) on delete cascade,
  activo boolean not null default true,
  unique (barbero_id, servicio_id)
);

alter table barbero_servicios enable row level security;

create policy "barbero_servicios_select_public" on barbero_servicios
  for select using (true);

create policy "barbero_servicios_insert_own" on barbero_servicios
  for insert with check (barberia_id = auth_barberia_id() and auth_rol() = 'dueno');

create policy "barbero_servicios_update_own" on barbero_servicios
  for update
  using (barberia_id = auth_barberia_id() and auth_rol() = 'dueno')
  with check (barberia_id = auth_barberia_id() and auth_rol() = 'dueno');

create policy "barbero_servicios_delete_own" on barbero_servicios
  for delete using (barberia_id = auth_barberia_id() and auth_rol() = 'dueno');

-- ═══════════════════════════════════════════════════════════════
-- (4) Backfill obligatorio: una fila activa=true por CADA combinación
-- barbero×servicio que ya exista hoy en cada negocio — sin esto,
-- todos los negocios existentes se quedan sin profesionales
-- disponibles al desplegar el filtro nuevo en reservar.html.
-- ═══════════════════════════════════════════════════════════════

insert into barbero_servicios (barberia_id, barbero_id, servicio_id, activo)
select b.barberia_id, b.id, s.id, true
from barberos b
join servicios s on s.barberia_id = b.barberia_id
where not exists (
  select 1 from barbero_servicios bs
  where bs.barbero_id = b.id and bs.servicio_id = s.id
);
