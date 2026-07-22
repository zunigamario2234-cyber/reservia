-- Mi Agenda: segundo rol de usuario (profesional), con login propio,
-- separado del dueño. Primera vez que "rol" en perfiles deja de ser
-- decorativo y pasa a ser un límite de seguridad real — leer los puntos
-- (3) y (5) con atención, son los que más cambian. El punto (3) es un
-- fix urgente de un problema preexistente (no introducido por Mi Agenda)
-- que se vuelve crítico con este cambio: cierra la posibilidad de que
-- cualquier cuenta autenticada se autoasigne rol='dueno' de un negocio
-- ajeno.
--
-- Ejecutar UNA VEZ, completo, en el SQL Editor de Supabase.

-- ═══════════════════════════════════════════════════════════════
-- (1) Columnas nuevas
-- ═══════════════════════════════════════════════════════════════

-- Vínculo entre una cuenta de Supabase Auth y su fila de barberos. Nullable:
-- un barbero puede existir sin cuenta (como hoy) hasta que el dueño lo invite.
-- "on delete set null": si se borra el auth.users (no ocurre hoy desde la app,
-- pero por las dudas), la fila de barberos no se rompe, solo pierde el vínculo.
alter table barberos add column if not exists auth_user_id uuid unique references auth.users(id) on delete set null;

-- Visibilidad SOLO en Mi Agenda — nunca borra ni pisa el estado real
-- (Pendiente/Confirmada/Atendida/Cancelada/etc.), que sigue intacto para las
-- ventas, comisiones y reportes del dueño en app.html. "Eliminar" desde Mi
-- Agenda = "dejo de verla en mi agenda", no "esto nunca pasó".
alter table reservas add column if not exists oculto_profesional boolean not null default false;
alter table visitas add column if not exists oculto_profesional boolean not null default false;

-- Quién creó el negocio — necesaria para el fix del punto (3). Se fija sola
-- (default auth.uid()) cuando el insert no la manda explícitamente, que es
-- el caso de doReg() en index.html hoy — no hace falta tocar ese archivo.
alter table barberias add column if not exists creado_por uuid references auth.users(id);
alter table barberias alter column creado_por set default auth.uid();

-- Backfill: negocios ya existentes (creados antes de esta columna) quedan
-- asociados al uid que hoy tiene rol='dueno' en ese negocio. No cambia
-- ningún permiso de las cuentas actuales, solo deja el dato consistente
-- para que la política del punto (3) funcione igual en negocios viejos.
update barberias b set creado_por = (
  select p.id from perfiles p where p.barberia_id = b.id and p.rol = 'dueno' limit 1
) where b.creado_por is null;

-- ═══════════════════════════════════════════════════════════════
-- (2) Funciones helper (mismo molde que auth_barberia_id(), ya existente)
-- ═══════════════════════════════════════════════════════════════

create or replace function auth_rol()
returns text
language sql
security definer
stable
as $$
  select rol from perfiles where id = auth.uid()
$$;

-- null si el usuario no es un profesional vinculado y activo — cubre tanto
-- "nunca se linkeó" como "el dueño lo desactivó/eliminó de barberos" con un
-- solo chequeo, sin repetir la condición "activo" en cada función de abajo.
create or replace function auth_barbero_id()
returns uuid
language sql
security definer
stable
as $$
  select id from barberos where auth_user_id = auth.uid() and activo = true
$$;

-- ═══════════════════════════════════════════════════════════════
-- (3) URGENTE — cierre de auto-declaración de dueño. perfiles_insert_own
-- hoy exige solo id=auth.uid(), sin validar que barberia_id sea un negocio
-- que esa persona haya creado. Cualquier cuenta autenticada podía insertar
-- {barberia_id: <cualquier negocio existente>, rol:'dueno'} y autoasignarse
-- dueño de un negocio ajeno — barberia_id no es secreto, aparece en
-- cualquier link de reservar.html/club.html. Esto es anterior a esta
-- migración, pero se vuelve crítico ahora que rol='dueno' pasa a ser un
-- límite de seguridad real (punto 5) en vez de decorativo.
--
-- Fix: barberias_insert_new exige que "creado_por" sea auth.uid() — nunca
-- lo que mande el payload, así que no se puede falsear. perfiles_insert_own
-- exige, SOLO para rol='dueno', que barberia_id sea un negocio creado por
-- esa misma persona Y que todavía no tenga un dueño asignado (evita que
-- una segunda persona reclame el mismo negocio recién creado).
--
-- rol='profesional' no necesita esta restricción: su acceso real nunca
-- sale de la fila de perfiles en sí — depende exclusivamente de
-- barberos.auth_user_id, que solo un dueño ya autenticado puede setear
-- (barberos_update_own, punto 5). Una fila de perfiles con rol='profesional'
-- y un barberia_id inventado no destraba ningún dato: auth_barbero_id()
-- sigue devolviendo null porque nadie la vinculó desde barberos.
-- ═══════════════════════════════════════════════════════════════

drop policy if exists "barberias_insert_new" on barberias;
create policy "barberias_insert_new" on barberias for insert
  with check (auth.uid() is not null and creado_por = auth.uid());

drop policy if exists "perfiles_insert_own" on perfiles;
create policy "perfiles_insert_own" on perfiles for insert
  with check (
    id = auth.uid()
    and (
      rol <> 'dueno'
      or (
        exists (select 1 from barberias b where b.id = barberia_id and b.creado_por = auth.uid())
        and not exists (select 1 from perfiles p2 where p2.barberia_id = barberia_id and p2.rol = 'dueno')
      )
    )
  );

-- ═══════════════════════════════════════════════════════════════
-- (4) Cierre de auto-ascenso: "rol" y "barberia_id" de perfiles ya no se
-- pueden tocar vía update de cliente. Antes de este cambio no importaba
-- (rol era decorativo); en cuanto el resto de las políticas empiecen a
-- exigir auth_rol()='dueno', un profesional podría auto-promoverse con
-- update({rol:'dueno'}) si esto no se cierra acá.
-- ═══════════════════════════════════════════════════════════════

revoke update on perfiles from authenticated;
grant update (nombre) on perfiles to authenticated;

-- ═══════════════════════════════════════════════════════════════
-- (5) Tightening: todas las políticas "_own" existentes pasan a exigir
-- auth_rol()='dueno' además del barberia_id. El profesional pierde acceso
-- directo a estas tablas — su acceso (recortado a lo suyo) vive solo en
-- las funciones security definer de la sección (6), que bypasean RLS.
-- Ninguna de estas cambia su alcance para el dueño: mismo barberia_id de
-- siempre, con el agregado de "y sos dueño". Como hoy "dueno" es el único
-- rol que existe en producción, esto no cambia nada para las cuentas
-- actuales — solo cierra la puerta para las nuevas cuentas de profesional.
-- ═══════════════════════════════════════════════════════════════

drop policy if exists "clientes_own" on clientes;
create policy "clientes_own" on clientes for all
  using (barberia_id = auth_barberia_id() and auth_rol() = 'dueno')
  with check (barberia_id = auth_barberia_id() and auth_rol() = 'dueno');

drop policy if exists "visitas_own" on visitas;
create policy "visitas_own" on visitas for all
  using (barberia_id = auth_barberia_id() and auth_rol() = 'dueno')
  with check (barberia_id = auth_barberia_id() and auth_rol() = 'dueno');

drop policy if exists "inventario_own" on inventario;
create policy "inventario_own" on inventario for all
  using (barberia_id = auth_barberia_id() and auth_rol() = 'dueno')
  with check (barberia_id = auth_barberia_id() and auth_rol() = 'dueno');

drop policy if exists "costos_own" on costos;
create policy "costos_own" on costos for all
  using (barberia_id = auth_barberia_id() and auth_rol() = 'dueno')
  with check (barberia_id = auth_barberia_id() and auth_rol() = 'dueno');

drop policy if exists "vip_historial_own" on vip_historial;
create policy "vip_historial_own" on vip_historial for all
  using (barberia_id = auth_barberia_id() and auth_rol() = 'dueno')
  with check (barberia_id = auth_barberia_id() and auth_rol() = 'dueno');

drop policy if exists "plantillas_mensajes_own" on plantillas_mensajes;
create policy "plantillas_mensajes_own" on plantillas_mensajes for all
  using (barberia_id = auth_barberia_id() and auth_rol() = 'dueno')
  with check (barberia_id = auth_barberia_id() and auth_rol() = 'dueno');

drop policy if exists "movimientos_stock_own" on movimientos_stock;
create policy "movimientos_stock_own" on movimientos_stock for all
  using (barberia_id = auth_barberia_id() and auth_rol() = 'dueno')
  with check (barberia_id = auth_barberia_id() and auth_rol() = 'dueno');

drop policy if exists "servicios_insert_own" on servicios;
create policy "servicios_insert_own" on servicios for insert
  with check (barberia_id = auth_barberia_id() and auth_rol() = 'dueno');
drop policy if exists "servicios_update_own" on servicios;
create policy "servicios_update_own" on servicios for update
  using (barberia_id = auth_barberia_id() and auth_rol() = 'dueno')
  with check (barberia_id = auth_barberia_id() and auth_rol() = 'dueno');
drop policy if exists "servicios_delete_own" on servicios;
create policy "servicios_delete_own" on servicios for delete
  using (barberia_id = auth_barberia_id() and auth_rol() = 'dueno');

drop policy if exists "barberos_insert_own" on barberos;
create policy "barberos_insert_own" on barberos for insert
  with check (barberia_id = auth_barberia_id() and auth_rol() = 'dueno');
drop policy if exists "barberos_update_own" on barberos;
create policy "barberos_update_own" on barberos for update
  using (barberia_id = auth_barberia_id() and auth_rol() = 'dueno')
  with check (barberia_id = auth_barberia_id() and auth_rol() = 'dueno');
drop policy if exists "barberos_delete_own" on barberos;
create policy "barberos_delete_own" on barberos for delete
  using (barberia_id = auth_barberia_id() and auth_rol() = 'dueno');

drop policy if exists "barberias_update_own" on barberias;
create policy "barberias_update_own" on barberias for update
  using (id = auth_barberia_id() and auth_rol() = 'dueno')
  with check (id = auth_barberia_id() and auth_rol() = 'dueno');

drop policy if exists "reservas_select_own" on reservas;
create policy "reservas_select_own" on reservas for select
  using (barberia_id = auth_barberia_id() and auth_rol() = 'dueno');
drop policy if exists "reservas_update_own" on reservas;
create policy "reservas_update_own" on reservas for update
  using (barberia_id = auth_barberia_id() and auth_rol() = 'dueno')
  with check (barberia_id = auth_barberia_id() and auth_rol() = 'dueno');
drop policy if exists "reservas_delete_own" on reservas;
create policy "reservas_delete_own" on reservas for delete
  using (barberia_id = auth_barberia_id() and auth_rol() = 'dueno');
-- reservas_insert_public NO se toca: sigue pública (reservar.html / club.html).

drop policy if exists "horario_negocio_insert_own" on horario_negocio;
create policy "horario_negocio_insert_own" on horario_negocio for insert
  with check (barberia_id = auth_barberia_id() and auth_rol() = 'dueno');
drop policy if exists "horario_negocio_update_own" on horario_negocio;
create policy "horario_negocio_update_own" on horario_negocio for update
  using (barberia_id = auth_barberia_id() and auth_rol() = 'dueno')
  with check (barberia_id = auth_barberia_id() and auth_rol() = 'dueno');
drop policy if exists "horario_negocio_delete_own" on horario_negocio;
create policy "horario_negocio_delete_own" on horario_negocio for delete
  using (barberia_id = auth_barberia_id() and auth_rol() = 'dueno');

drop policy if exists "bloqueos_insert_own" on bloqueos_profesional;
create policy "bloqueos_insert_own" on bloqueos_profesional for insert
  with check (barberia_id = auth_barberia_id() and auth_rol() = 'dueno');
drop policy if exists "bloqueos_update_own" on bloqueos_profesional;
create policy "bloqueos_update_own" on bloqueos_profesional for update
  using (barberia_id = auth_barberia_id() and auth_rol() = 'dueno')
  with check (barberia_id = auth_barberia_id() and auth_rol() = 'dueno');
drop policy if exists "bloqueos_delete_own" on bloqueos_profesional;
create policy "bloqueos_delete_own" on bloqueos_profesional for delete
  using (barberia_id = auth_barberia_id() and auth_rol() = 'dueno');

drop policy if exists "alianzas_insert_own" on alianzas;
create policy "alianzas_insert_own" on alianzas for insert
  with check (barberia_id = auth_barberia_id() and auth_rol() = 'dueno');
drop policy if exists "alianzas_update_own" on alianzas;
create policy "alianzas_update_own" on alianzas for update
  using (barberia_id = auth_barberia_id() and auth_rol() = 'dueno')
  with check (barberia_id = auth_barberia_id() and auth_rol() = 'dueno');
drop policy if exists "alianzas_delete_own" on alianzas;
create policy "alianzas_delete_own" on alianzas for delete
  using (barberia_id = auth_barberia_id() and auth_rol() = 'dueno');

drop policy if exists "niveles_vip_insert_own" on niveles_vip;
create policy "niveles_vip_insert_own" on niveles_vip for insert
  with check (barberia_id = auth_barberia_id() and auth_rol() = 'dueno');
drop policy if exists "niveles_vip_update_own" on niveles_vip;
create policy "niveles_vip_update_own" on niveles_vip for update
  using (barberia_id = auth_barberia_id() and auth_rol() = 'dueno')
  with check (barberia_id = auth_barberia_id() and auth_rol() = 'dueno');
drop policy if exists "niveles_vip_delete_own" on niveles_vip;
create policy "niveles_vip_delete_own" on niveles_vip for delete
  using (barberia_id = auth_barberia_id() and auth_rol() = 'dueno');

-- ═══════════════════════════════════════════════════════════════
-- (6) RPCs de Mi Agenda — todas security definer, todas resuelven la
-- identidad del profesional ÚNICAMENTE a partir de auth.uid() (nunca de
-- un parámetro que mande el cliente): no existe forma de pedir/crear/
-- cancelar datos de un colega pasando otro id. Grant solo a
-- "authenticated" (no "anon" — a diferencia de las RPCs públicas de
-- club.html/reservar.html, estas requieren sesión real).
-- ═══════════════════════════════════════════════════════════════

-- Agenda del día: reservas + visitas propias, con nombre/whatsapp del
-- cliente ya resuelto (mismo criterio de "reservas" que la Agenda interna
-- de app.html: se matchea por barbero_nombre, ver nota en el punto (7)).
create or replace function mi_agenda_citas(p_fecha date)
returns table (
  id uuid,
  tipo text,
  fecha date,
  hora time,
  servicio text,
  estado text,
  procesado boolean,
  nombre_cliente text,
  whatsapp_cliente text,
  valor numeric,
  comision_monto numeric,
  notas text
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_barbero_id uuid := auth_barbero_id();
  v_nombre text;
  v_barberia uuid := auth_barberia_id();
begin
  if v_barbero_id is null then
    return;
  end if;
  -- "where barberos.id" (calificado), no "where id": esta función devuelve
  -- una tabla con columna "id" (returns table), que plpgsql declara como
  -- variable implícita — "id" sin calificar queda ambiguo entre esa
  -- variable y barberos.id.
  select nombre into v_nombre from barberos where barberos.id = v_barbero_id;

  return query
  select r.id, 'reserva'::text, r.fecha, r.hora, r.servicio, r.estado, r.procesado,
         r.nombre_cliente, r.whatsapp_cliente, null::numeric, null::numeric, r.notas
  from reservas r
  where r.barberia_id = v_barberia and r.barbero_nombre = v_nombre
    and r.fecha = p_fecha and r.oculto_profesional = false
  union all
  select v.id, 'visita'::text, v.fecha, v.hora, v.servicio, v.estado, true,
         c.nombre, c.whatsapp, v.valor, v.comision_monto, v.notas
  from visitas v
  left join clientes c on c.id = v.cliente_id
  where v.barberia_id = v_barberia and v.barbero_nombre = v_nombre
    and v.fecha = p_fecha and v.oculto_profesional = false
  order by 4; -- "hora" es columna de salida (returns table) → variable
              -- implícita de plpgsql, igual que "id" arriba; se ordena por
              -- posición (4 = hora) para no repetir la misma ambigüedad.
end;
$$;

-- Cancelar: cambia estado a 'Cancelada'. Sigue visible para el dueño con
-- su estado real, no se toca oculto_profesional.
create or replace function mi_agenda_cancelar_cita(p_id uuid, p_tipo text)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_barbero_id uuid := auth_barbero_id();
  v_nombre text;
  v_barberia uuid := auth_barberia_id();
  v_rows int;
begin
  if v_barbero_id is null then
    raise exception 'No autorizado';
  end if;
  select nombre into v_nombre from barberos where id = v_barbero_id;

  if p_tipo = 'reserva' then
    update reservas set estado = 'Cancelada'
      where id = p_id and barberia_id = v_barberia and barbero_nombre = v_nombre;
  elsif p_tipo = 'visita' then
    update visitas set estado = 'Cancelada'
      where id = p_id and barberia_id = v_barberia and barbero_nombre = v_nombre;
  else
    raise exception 'Tipo inválido';
  end if;

  get diagnostics v_rows = row_count;
  return v_rows > 0;
end;
$$;

-- Eliminar (desde Mi Agenda): NO es un delete real, NO toca el estado.
-- Solo marca oculto_profesional=true — deja de aparecer en mi_agenda_citas
-- pero el dueño sigue viendo la fila intacta (estado original incluido)
-- en app.html, porque ninguna consulta del dueño filtra por esta columna.
create or replace function mi_agenda_eliminar_cita(p_id uuid, p_tipo text)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_barbero_id uuid := auth_barbero_id();
  v_nombre text;
  v_barberia uuid := auth_barberia_id();
  v_rows int;
begin
  if v_barbero_id is null then
    raise exception 'No autorizado';
  end if;
  select nombre into v_nombre from barberos where id = v_barbero_id;

  if p_tipo = 'reserva' then
    update reservas set oculto_profesional = true
      where id = p_id and barberia_id = v_barberia and barbero_nombre = v_nombre;
  elsif p_tipo = 'visita' then
    update visitas set oculto_profesional = true
      where id = p_id and barberia_id = v_barberia and barbero_nombre = v_nombre;
  else
    raise exception 'Tipo inválido';
  end if;

  get diagnostics v_rows = row_count;
  return v_rows > 0;
end;
$$;

-- Buscar cliente existente del negocio (para armar una reserva nueva).
-- Devuelve solo id/nombre/whatsapp, nunca la ficha completa — el profesional
-- puede buscar cualquier cliente del negocio para agendarlo (no solo los
-- suyos: cualquiera puede querer agendar con él por primera vez), pero esto
-- es una búsqueda acotada (15 resultados, sin historial ni notas), no acceso
-- de lectura a la tabla clientes completa.
create or replace function mi_agenda_buscar_cliente(p_query text)
returns table(id uuid, nombre text, whatsapp text)
language sql
security definer
set search_path = public
stable
as $$
  select c.id, c.nombre, c.whatsapp
  from clientes c
  where c.barberia_id = auth_barberia_id()
    and auth_barbero_id() is not null
    and (c.nombre ilike '%' || p_query || '%' or c.whatsapp ilike '%' || p_query || '%')
  order by c.nombre
  limit 15
$$;

-- Crear una reserva nueva, siempre atribuida a uno mismo — barbero_nombre
-- se resuelve server-side, nunca viaja como parámetro: no hay forma de
-- crear una reserva a nombre de otro profesional desde acá.
create or replace function mi_agenda_crear_reserva(
  p_nombre_cliente text,
  p_whatsapp_cliente text,
  p_fecha date,
  p_hora time,
  p_servicio text default null,
  p_notas text default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_barbero_id uuid := auth_barbero_id();
  v_nombre text;
  v_barberia uuid := auth_barberia_id();
  v_id uuid;
begin
  if v_barbero_id is null then
    raise exception 'No autorizado';
  end if;
  select nombre into v_nombre from barberos where id = v_barbero_id;

  insert into reservas (
    barberia_id, nombre_cliente, whatsapp_cliente, fecha, hora,
    servicio, barbero_nombre, estado, procesado, notas, fuente
  ) values (
    v_barberia, p_nombre_cliente, p_whatsapp_cliente, p_fecha, p_hora,
    p_servicio, v_nombre, 'Confirmada', false, p_notas, 'Mi Agenda'
  ) returning id into v_id;

  return v_id;
end;
$$;

-- Ventas y comisiones propias, en bruto (una fila por visita) para que el
-- front agrupe por mes y por servicio como haga falta — mismo criterio que
-- ya usa app.html (sumar comision_monto ya guardado, no recalcularlo).
-- p_desde/p_hasta null = sin límite (para "Ver historial completo").
create or replace function mi_agenda_comisiones(p_desde date default null, p_hasta date default null)
returns table(fecha date, servicio text, valor numeric, comision_monto numeric, estado text)
language sql
security definer
set search_path = public
stable
as $$
  select v.fecha, v.servicio, v.valor, v.comision_monto, v.estado
  from visitas v
  where v.barberia_id = auth_barberia_id()
    and v.barbero_nombre = (select nombre from barberos where id = auth_barbero_id())
    and auth_barbero_id() is not null
    and (p_desde is null or v.fecha >= p_desde)
    and (p_hasta is null or v.fecha <= p_hasta)
  order by v.fecha desc
$$;

revoke all on function mi_agenda_citas(date) from public;
grant execute on function mi_agenda_citas(date) to authenticated;

revoke all on function mi_agenda_cancelar_cita(uuid,text) from public;
grant execute on function mi_agenda_cancelar_cita(uuid,text) to authenticated;

revoke all on function mi_agenda_eliminar_cita(uuid,text) from public;
grant execute on function mi_agenda_eliminar_cita(uuid,text) to authenticated;

revoke all on function mi_agenda_buscar_cliente(text) from public;
grant execute on function mi_agenda_buscar_cliente(text) to authenticated;

revoke all on function mi_agenda_crear_reserva(text,text,date,time,text,text) from public;
grant execute on function mi_agenda_crear_reserva(text,text,date,time,text,text) to authenticated;

revoke all on function mi_agenda_comisiones(date,date) from public;
grant execute on function mi_agenda_comisiones(date,date) to authenticated;

-- ═══════════════════════════════════════════════════════════════
-- (7) Nota conocida, no resuelta en esta migración: el vínculo profesional↔
-- cita es por barbero_nombre (texto), no por un barbero_id (FK). Es la
-- misma limitación que ya tiene toda la Agenda de app.html y reservar.html
-- — no es nueva de Mi Agenda. Efecto práctico: si el dueño le cambia el
-- nombre a un profesional en Config → Equipo, sus citas/comisiones ya
-- guardadas con el nombre viejo dejan de matchear en mi_agenda_* hasta
-- que se les actualice el barbero_nombre (mismo comportamiento que ya
-- tiene la Agenda del dueño hoy, no algo que esta migración empeore).
-- ═══════════════════════════════════════════════════════════════
