-- Conecta dos mensajes de WhatsApp que hoy están hardcodeados (reservar.html
-- y mi-agenda.html) al sistema de plantillas editables (Config → Plantillas
-- de mensajes, tabla plantillas_mensajes, buildMsg() en app.html).
--
-- Ejecutar UNA VEZ, completo, en el SQL Editor de Supabase.

-- ═══════════════════════════════════════════════════════════════
-- (1) RPC pública: devuelve SOLO el texto de una plantilla activa por
-- barberia_id + evento — nada más de la tabla. security definer porque
-- plantillas_mensajes_own exige auth_rol()='dueno', y ni un cliente
-- anónimo (reservar.html) ni un profesional logueado (mi-agenda.html)
-- pasan ese chequeo. Devuelve null si no existe o está inactiva — el
-- llamador (JS) cae a su propio texto hardcodeado en ese caso, nunca deja
-- al usuario sin mensaje.
-- ═══════════════════════════════════════════════════════════════

create or replace function obtener_plantilla_publica(p_barberia_id uuid, p_evento text)
returns text
language sql
security definer
set search_path = public
stable
as $$
  select mensaje from plantillas_mensajes
  where barberia_id = p_barberia_id and evento = p_evento and activo = true
  limit 1
$$;

revoke all on function obtener_plantilla_publica(uuid,text) from public;
grant execute on function obtener_plantilla_publica(uuid,text) to anon, authenticated;

-- ═══════════════════════════════════════════════════════════════
-- (2) Backfill: negocios ya existentes (creados antes de este cambio)
-- necesitan estas plantillas también, si no se quedan sin mensaje al
-- migrar el código. Mismo cuidado que el backfill de "Club nivel N" en
-- la sesión de Niveles VIP — "insert where not exists", nunca pisa una
-- plantilla que el dueño ya haya personalizado o desactivado.
--
-- "Confirmación reserva" entra también en el backfill por las dudas: ya
-- se sembraba para negocios nuevos desde antes de esta sesión, pero un
-- negocio muy viejo podría no tenerla.
-- ═══════════════════════════════════════════════════════════════

insert into plantillas_mensajes (barberia_id, evento, mensaje, activo)
select b.id, 'Confirmación reserva',
  E'✅ ¡Hola {nombre}! Tu reserva está confirmada.\n📅 {fecha} a las {hora}\n✂️ {servicio} con {profesional}\n📍 {direccion}',
  true
from barberias b
where not exists (
  select 1 from plantillas_mensajes p where p.barberia_id = b.id and p.evento = 'Confirmación reserva'
);

insert into plantillas_mensajes (barberia_id, evento, mensaje, activo)
select b.id, 'Cita cancelada',
  'Hola {nombre}, te escribo por tu cita en {barberia} del {fecha} a las {hora} hrs ({servicio}), que quedó cancelada. ¡Cualquier cosa, contáctanos!',
  true
from barberias b
where not exists (
  select 1 from plantillas_mensajes p where p.barberia_id = b.id and p.evento = 'Cita cancelada'
);

insert into plantillas_mensajes (barberia_id, evento, mensaje, activo)
select b.id, 'Cliente confirma reserva',
  E'Hola! Quiero confirmar mi reserva en {barberia}:\n📅 {fecha} a las {hora} hrs\n✂️ {servicio} con {profesional}\nNombre: {nombre}',
  true
from barberias b
where not exists (
  select 1 from plantillas_mensajes p where p.barberia_id = b.id and p.evento = 'Cliente confirma reserva'
);
