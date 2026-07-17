-- Row Level Security (RLS) multi-tenant para Reservia.
-- Ejecutar UNA VEZ, completo, en el SQL Editor de Supabase.
--
-- ORDEN DE DESPLIEGUE RECOMENDADO (importante, evita cortes):
--   1. Agregar la variable de entorno SUPABASE_SERVICE_ROLE_KEY en Vercel.
--   2. Desplegar el código actualizado de api/_lib/resend.js (usa esa key).
--   3. Recién ahí correr este script en Supabase.
-- Si corrés este script ANTES de los pasos 1-2, los emails automáticos
-- (enviar-encuesta, enviar-confirmacion) van a fallar temporalmente porque
-- todavía usan la anon key, que estas políticas dejan de dejar pasar.
--
-- Es idempotente en su mayoría (create policy fallaría si ya existe con el
-- mismo nombre — si necesitás re-ejecutar, borrá antes la policy puntual con
-- `drop policy if exists "<nombre>" on <tabla>;`).

-- ─── Función helper: barberia_id del usuario logueado ───
-- security definer: bypasea el RLS de "perfiles" al resolver esto, evitando
-- recursión (la policy de perfiles no depende de esta función).
create or replace function auth_barberia_id()
returns uuid
language sql
security definer
stable
as $$
  select barberia_id from perfiles where id = auth.uid()
$$;

-- ═══════════════════════════════════════════════════════════════
-- (a) TABLAS PRIVADAS DEL DUEÑO — solo el negocio dueño lee/escribe
-- ═══════════════════════════════════════════════════════════════

alter table clientes enable row level security;
create policy "clientes_own" on clientes for all
  using (barberia_id = auth_barberia_id())
  with check (barberia_id = auth_barberia_id());

alter table visitas enable row level security;
create policy "visitas_own" on visitas for all
  using (barberia_id = auth_barberia_id())
  with check (barberia_id = auth_barberia_id());

alter table inventario enable row level security;
create policy "inventario_own" on inventario for all
  using (barberia_id = auth_barberia_id())
  with check (barberia_id = auth_barberia_id());

alter table costos enable row level security;
create policy "costos_own" on costos for all
  using (barberia_id = auth_barberia_id())
  with check (barberia_id = auth_barberia_id());

alter table vip_historial enable row level security;
create policy "vip_historial_own" on vip_historial for all
  using (barberia_id = auth_barberia_id())
  with check (barberia_id = auth_barberia_id());

alter table plantillas_mensajes enable row level security;
create policy "plantillas_mensajes_own" on plantillas_mensajes for all
  using (barberia_id = auth_barberia_id())
  with check (barberia_id = auth_barberia_id());

alter table movimientos_stock enable row level security;
create policy "movimientos_stock_own" on movimientos_stock for all
  using (barberia_id = auth_barberia_id())
  with check (barberia_id = auth_barberia_id());

-- ═══════════════════════════════════════════════════════════════
-- (b) LECTURA PÚBLICA, ESCRITURA PRIVADA
-- reservar.html (sin login) necesita leer servicios/barberos/barberias.
-- ═══════════════════════════════════════════════════════════════

alter table servicios enable row level security;
create policy "servicios_select_public" on servicios for select using (true);
create policy "servicios_insert_own" on servicios for insert with check (barberia_id = auth_barberia_id());
create policy "servicios_update_own" on servicios for update using (barberia_id = auth_barberia_id()) with check (barberia_id = auth_barberia_id());
create policy "servicios_delete_own" on servicios for delete using (barberia_id = auth_barberia_id());

alter table barberos enable row level security;
create policy "barberos_select_public" on barberos for select using (true);
create policy "barberos_insert_own" on barberos for insert with check (barberia_id = auth_barberia_id());
create policy "barberos_update_own" on barberos for update using (barberia_id = auth_barberia_id()) with check (barberia_id = auth_barberia_id());
create policy "barberos_delete_own" on barberos for delete using (barberia_id = auth_barberia_id());

alter table barberias enable row level security;
create policy "barberias_select_public" on barberias for select using (true);
-- Insert abierto a cualquier usuario autenticado: hace falta para que un
-- usuario recién registrado (que todavía no tiene fila en "perfiles") pueda
-- crear su primer negocio.
create policy "barberias_insert_new" on barberias for insert
  with check (auth.uid() is not null);
create policy "barberias_update_own" on barberias for update
  using (id = auth_barberia_id())
  with check (id = auth_barberia_id());

-- ═══════════════════════════════════════════════════════════════
-- (c) RESERVAS — insert público (reservar.html), lectura/edición solo dueño.
-- La disponibilidad pública (horarios ocupados) se sirve desde la VISTA
-- reservas_disponibilidad más abajo, que NO expone datos del cliente.
-- ═══════════════════════════════════════════════════════════════

alter table reservas enable row level security;
create policy "reservas_insert_public" on reservas for insert with check (true);
create policy "reservas_select_own" on reservas for select using (barberia_id = auth_barberia_id());
create policy "reservas_update_own" on reservas for update using (barberia_id = auth_barberia_id()) with check (barberia_id = auth_barberia_id());
create policy "reservas_delete_own" on reservas for delete using (barberia_id = auth_barberia_id());

-- Vista pública de disponibilidad: solo hora/profesional/fecha/estado de
-- procesado, nunca nombre/whatsapp/email/notas del cliente. Las vistas en
-- Postgres corren con los permisos del dueño de la vista por defecto, así
-- que esto sigue funcionando para visitantes anónimos aunque la tabla base
-- "reservas" ya no sea legible públicamente.
create or replace view reservas_disponibilidad as
  select id, barberia_id, fecha, hora, barbero_nombre, procesado
  from reservas;

grant select on reservas_disponibilidad to anon, authenticated;

-- ═══════════════════════════════════════════════════════════════
-- (d) PERFILES — bootstrap de registro
-- ═══════════════════════════════════════════════════════════════

alter table perfiles enable row level security;
create policy "perfiles_select_own" on perfiles for select using (id = auth.uid());
create policy "perfiles_insert_own" on perfiles for insert with check (id = auth.uid());
create policy "perfiles_update_own" on perfiles for update using (id = auth.uid()) with check (id = auth.uid());
