-- Cierra el INSERT público sin restricción sobre reservas.
--
-- EL AGUJERO
-- `reservas_insert_public` era la ÚNICA política de INSERT de la tabla y
-- estaba definida como `for insert to public with check (true)`, o sea sin
-- ninguna condición. La anon key está embebida en todas las páginas públicas
-- —por diseño, la protección es RLS y no la clave—, así que cualquiera que la
-- copiara del fuente podía insertar filas arbitrarias en `reservas` para
-- CUALQUIER `barberia_id`, saltándose el único camino previsto para una
-- reserva pública, que es la RPC `crear_reserva_publica`.
--
-- CORRECCIÓN (2026-07-28): la versión original de este comentario decía que
-- así se salteaban "todas las validaciones que hace crear_reserva_publica
-- (disponibilidad del slot, horario, bloqueos)". Eso es FALSO y conviene que
-- quede escrito, porque induce a confiar en una defensa que no existe: la RPC
-- es un `insert` pelado, no valida absolutamente nada, y `reservas` no tiene
-- más constraints que la PK y la FK de barbería — ni siquiera unicidad de
-- slot. Las validaciones de disponibilidad, horario y bloqueos viven SOLO en
-- el navegador. Lo que esta política arregla es el scoping por negocio, que
-- es real; el resto era una suposición no verificada.
--
-- POR QUÉ NO ROMPE EL FLUJO PÚBLICO
-- Ninguna reserva de cliente pasa por esta política. Las tres puertas de
-- entrada son RPC `security definer`, que corren como su dueño y por eso no
-- evalúan RLS:
--   reservar.html   -> crear_reserva_publica
--   club.html       -> crear_reserva_publica_club
--   mi-agenda.html  -> mi_agenda_crear_reserva
-- El único `insert` directo a `reservas` en todo el repo es el de app.html
-- (reserva manual del dueño, ya autenticado), y ese sí pasa por acá — por eso
-- la política no se borra, se acota.
--
-- POR QUÉ SE RENOMBRA
-- Las otras tres políticas de la tabla ya son `_own` y exigen dueño del
-- negocio (`reservas_select_own`, `reservas_update_own`,
-- `reservas_delete_own`). El INSERT era la única que no. El nombre
-- `_insert_public` describía justamente lo que estaba mal.
--
-- EFECTO LATERAL BUSCADO
-- Hoy un profesional que cae en app.html puede insertar reservas: su
-- `checkSession()` solo mira si hay sesión, no el rol, así que entra igual
-- aunque RLS le bloquee casi todo lo demás. Después de esto, tampoco puede
-- insertar.

begin;

drop policy if exists reservas_insert_public on public.reservas;

create policy reservas_insert_own on public.reservas
  for insert
  to public
  with check (
    barberia_id = auth_barberia_id()
    and auth_rol() = 'dueno'
  );

commit;
