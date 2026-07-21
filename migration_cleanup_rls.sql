-- Elimina 12 políticas RLS "comodín" (ALL, using(true), with check(true))
-- que quedaron activas en paralelo a las políticas restrictivas de
-- migration_rls.sql. Postgres evalúa las políticas permisivas con OR:
-- alcanza con que UNA sola política diga "true" para que la fila pase,
-- sin importar cuántas políticas restrictivas también existan sobre la
-- misma tabla. Estas 12 políticas "todo en X" (para todos los comandos,
-- using(true), with check(true)) anulaban en la práctica el filtro por
-- barberia_id de clientes_own/visitas_own/reservas_select_own/etc.,
-- dejando esas tablas legibles y escribibles por completo con la sola
-- anon key — la misma clase de fuga cross-tenant que ya se había
-- cerrado antes, pero reintroducida por estas políticas paralelas.
--
-- Ya se corrieron manualmente en producción (Supabase SQL Editor) el
-- día que se detectó la fuga vía curl con la anon key. Este archivo
-- queda solo como registro histórico en el repo — no hace falta
-- volver a ejecutarlo.

drop policy if exists "todo en clientes" on clientes;
drop policy if exists "todo en visitas" on visitas;
drop policy if exists "todo en reservas" on reservas;
drop policy if exists "todo en barberias" on barberias;
drop policy if exists "todo en barberos" on barberos;
drop policy if exists "todo en costos" on costos;
drop policy if exists "todo en inventario" on inventario;
drop policy if exists "todo en movimientos" on movimientos_stock;
drop policy if exists "todo en perfiles" on perfiles;
drop policy if exists "todo en plantillas" on plantillas_mensajes;
drop policy if exists "todo en servicios" on servicios;
drop policy if exists "todo en vip" on vip_historial;
