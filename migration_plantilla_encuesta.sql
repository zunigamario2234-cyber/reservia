-- La plantilla 'Encuesta', para el canal de WhatsApp.
--
-- POR QUÉ
-- El ~12% de los clientes no tiene correo en su ficha (medido el 2026-09-11),
-- así que a esos la encuesta les llega por WhatsApp, desde la lista de
-- Mensajes. Ese mensaje sale de una plantilla editable, igual que Cumpleaños,
-- Bienvenida y Recuperar inactivo.
--
-- `buildMsg()` en app.html devuelve NULL si la plantilla no existe o está
-- inactiva, y entonces el botón de WhatsApp directamente no se dibuja. Sin
-- este seed, la lista se vería vacía de botones y parecería rota.
--
-- ⚠ LA VARIABLE SE LLAMA {link_encuesta} Y NO {link}, A PROPÓSITO.
-- buildMsg ya define `link` como alias del link de RESERVAS
-- (app.html, junto a `link_reservas` y `setmore`). Una plantilla que usara
-- {link} le mandaría al cliente el link para reservar en vez del de la
-- encuesta — y sin ningún error: el placeholder se reemplaza igual, solo que
-- por la URL equivocada. Es el mismo tipo de bug que ya ocurrió con las
-- plantillas seed de Bienvenida, donde {negocio} y {link} nunca se
-- reemplazaban y los clientes recibían el texto literal.
--
-- Variables que esta plantilla puede usar:
--   {nombre}         — el del cliente, lo pasa la lista
--   {link_encuesta}  — el link personal de ESA visita, lo pasa la lista
--   {negocio}        — nombre del negocio, lo resuelve buildMsg solo
--
-- Esta migración NO define funciones, así que puede ir envuelta en
-- begin;/commit;.

begin;

-- Una fila por negocio que todavía no la tenga. `plantillas_mensajes` no tiene
-- unique en (barberia_id, evento), así que la idempotencia la da el
-- `not exists` — correrla dos veces no duplica.
insert into plantillas_mensajes (barberia_id, evento, mensaje, activo)
select b.id,
       'Encuesta',
       '¡Hola {nombre}! Gracias por venir a {negocio}. ¿Nos cuentas cómo te fue? '
       || 'Te toma menos de un minuto: {link_encuesta}',
       true
from barberias b
where not exists (
  select 1 from plantillas_mensajes p
  where p.barberia_id = b.id and p.evento = 'Encuesta'
);

commit;


-- ═══════════════════════════════════════════════════════════════
-- VERIFICACIÓN
-- ═══════════════════════════════════════════════════════════════

-- PASO 1 — Todos los negocios tienen la plantilla, y ninguno la tiene dos veces.
-- Esperado: 1 fila, con las tres columnas iguales entre sí.
--
-- select (select count(*) from barberias) as negocios,
--        (select count(*) from plantillas_mensajes where evento = 'Encuesta') as plantillas,
--        (select count(distinct barberia_id) from plantillas_mensajes
--          where evento = 'Encuesta') as negocios_con_plantilla;


-- PASO 2 — El texto trae {link_encuesta} y NO {link}.
-- Esperado: cero filas. Si alguna aparece, esa plantilla le mandaría al
-- cliente el link de reservas en lugar del de la encuesta.
--
-- ⚠ El regex busca {link} como palabra completa: {link_encuesta} contiene
-- "{link" y un `like '%{link}%'` mal escrito daría falsos positivos.
--
-- select barberia_id, mensaje
-- from plantillas_mensajes
-- where evento = 'Encuesta'
--   and (mensaje !~ '\{link_encuesta\}' or mensaje ~ '\{link\}');
