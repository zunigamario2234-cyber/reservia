-- Que el profesional vea la nota del CLIENTE en su agenda del día.
--
-- POR QUÉ
-- `clientes.notas` existe desde siempre y es donde el dueño anota lo que hay
-- que saber de una persona: una alergia, que prefiere poco charla, que paga
-- siempre en efectivo. Hoy solo la ve él, y enterrada dentro de "editar
-- cliente" — así que el profesional que va a atender no se entera de una
-- alergia antes de atender, que es el caso que motivó esto.
--
-- La nota es privada por dos vías, las dos comprobadas: la política
-- `clientes_own` exige `auth_rol() = 'dueno'`, y `get_club_vip_publico` no
-- devuelve la columna. El cliente nunca la ve, y eso NO cambia acá.
--
-- ═══════════════════════════════════════════════════════════════
-- SON DOS NOTAS DISTINTAS Y SE LLAMAN IGUAL
--
--   `reservas.notas` / `visitas.notas` → sobre ESTE turno. La escribe el
--      cliente al reservar (el formulario público tiene un campo abierto) o el
--      dueño. Sirve hoy y se vence.
--   `clientes.notas`                   → sobre la PERSONA. La escribe el
--      dueño. Sirve siempre.
--
-- La primera YA se devuelve, en la columna `notas`, y el profesional está
-- acostumbrado a verla con un 📝. Por eso la nueva se llama `cliente_notas` y
-- NO se toca la vieja: renombrar las dos obliga a reaprender las dos.
--
-- ═══════════════════════════════════════════════════════════════
-- ALCANCE: SOLO LOS CLIENTES QUE ESE PROFESIONAL TIENE AGENDADOS ESE DÍA
--
-- Decidido por el dueño. Su decisión previa —"abrir todas las notas, sin
-- separar las de equipo de las privadas"— era sobre NO curarlas, no sobre
-- ampliar quién las ve.
--
-- Por eso esto va como columna de `mi_agenda_citas` y no como RPC nueva: el
-- alcance sale gratis (solo hay notas de las citas que ya devuelve), no suma
-- superficie pública, y el frontend ya la llama.
--
-- ⚠ `mi_agenda_buscar_cliente` NO se toca. Ahí cualquier profesional puede
-- buscar cualquier cliente del negocio, así que agregarle las notas sería
-- exponerlas todas — justo lo que el alcance elegido evita.
--
-- ═══════════════════════════════════════════════════════════════
-- EL GUARDIA DEL TELÉFONO COMPARTIDO, Y POR QUÉ ACÁ PESA MÁS
--
-- `reservas` no tiene cliente_id: se cruza por whatsapp_norm. Y en la base
-- conviven personas DISTINTAS con el mismo número (una pareja, un papá con su
-- hijo).
--
-- En las próximas reservas del club, equivocarse ahí significaba filtrar
-- datos. Acá significa mostrarle al profesional la nota de OTRA persona — y si
-- esa nota dice "alérgico al tinte" aplicada a quien no corresponde, el error
-- deja de ser de privacidad y pasa a poder hacer daño.
--
-- Tres capas, y la tercera es la que resuelve el caso difícil:
--   1. whatsapp_norm no vacío — una ficha sin teléfono matchearía contra todas
--      las reservas sin teléfono del negocio.
--   2. mismo PRIMER nombre — no el completo: el completo bloquearía también
--      las fichas duplicadas de la misma persona, que son la mayoría de los
--      números repetidos.
--   3. `count(*) = 1` sobre las fichas que TIENEN nota. Ante dos fichas
--      distintas con nota y el mismo teléfono y nombre, no se muestra ninguna.
--
-- El paso 3 es una elección deliberada entre dos errores: esconder una nota
-- que correspondía, o mostrar una que no. Se prefiere esconder — un
-- profesional que no ve nota pregunta; uno que ve la nota equivocada actúa
-- sobre ella. Es el mismo criterio de get_proximas_reservas_publico: ante la
-- duda, nada.
--
-- Contar solo las fichas CON nota (y no todas las que matchean) es lo que
-- salva el caso benigno: si de dos fichas duplicadas de la misma persona solo
-- una tiene la nota escrita, esa se muestra.
--
-- En las VISITAS no hace falta nada de esto: `v.cliente_id` es un vínculo
-- exacto, sin ambigüedad posible.
--
-- ═══════════════════════════════════════════════════════════════
-- ⚠ POR QUÉ HAY UN `DROP` Y NO SOLO UN `CREATE OR REPLACE`
--
-- Agregar una columna a un RETURNS TABLE cambia el TIPO DE RETORNO de la
-- función, y Postgres rechaza eso con "cannot change return type of existing
-- function". No hay forma de evitarlo: hay que dropear y volver a crear.
--
-- Dos consecuencias que esta migración maneja:
--
--   · LOS PERMISOS SE PIERDEN con el drop. En Supabase, los default
--     privileges del esquema public vuelven a otorgar EXECUTE a anon,
--     authenticated y service_role sobre la función nueva — pero eso hay que
--     COMPROBARLO, no suponerlo. El PASO 0 saca la foto de los permisos
--     actuales y el PASO 3 la compara.
--
--   · ENTRE EL DROP Y EL CREATE LA FUNCIÓN NO EXISTE. Si un profesional carga
--     su agenda en ese instante, le da error. Correr las dos sentencias
--     JUNTAS, en una sola ejecución, y de preferencia fuera de horario de
--     atención. La ventana es de un segundo, pero existe.
--
-- Esta migración DEFINE UNA FUNCIÓN, así que va SIN begin;/commit; — con
-- dollar-quoting el SQL Editor de Supabase falla en silencio devolviendo
-- éxito.
-- ═══════════════════════════════════════════════════════════════


-- ═══════════════════════════════════════════════════════════════
-- PASO 0 — LA FOTO DE LOS PERMISOS, ANTES DE DROPEAR.
--
-- Anota este resultado. Después del cambio tiene que ser IDÉNTICO. Si no lo
-- es, el drop se llevó un permiso que hay que restaurar a mano — y el síntoma
-- sería que Mi Agenda deja de cargar citas sin decir por qué.
-- ═══════════════════════════════════════════════════════════════

-- select p.proname, p.proacl
-- from pg_proc p join pg_namespace n on n.oid = p.pronamespace
-- where n.nspname = 'public' and p.proname = 'mi_agenda_citas';


-- ═══════════════════════════════════════════════════════════════
-- EL CAMBIO — las dos sentencias JUNTAS, en una sola ejecución.
-- ═══════════════════════════════════════════════════════════════

drop function if exists mi_agenda_citas(date);

CREATE OR REPLACE FUNCTION public.mi_agenda_citas(p_fecha date)
 RETURNS TABLE(id uuid, tipo text, fecha date, hora time without time zone, servicio text, estado text, procesado boolean, nombre_cliente text, whatsapp_cliente text, valor numeric, comision_monto numeric, notas text, cliente_notas text)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_barbero_id uuid := auth_barbero_id();
  v_nombre text;
  v_barberia uuid := auth_barberia_id();
begin
  if v_barbero_id is null then
    return;
  end if;
  select nombre into v_nombre from barberos where barberos.id = v_barbero_id;

  return query
  select r.id, 'reserva'::text, r.fecha, r.hora, r.servicio, r.estado, r.procesado,
         r.nombre_cliente, r.whatsapp_cliente, null::numeric, null::numeric, r.notas,
         -- La nota del CLIENTE. Ver el guardia del teléfono compartido arriba:
         -- el `count(*) = 1` es lo que hace que ante dos personas distintas con
         -- el mismo número no se muestre ninguna, en vez de mostrar la que
         -- salga primero.
         (select case when count(*) = 1 then min(c.notas) end
            from clientes c
           where c.barberia_id = r.barberia_id
             and coalesce(r.whatsapp_norm, '') <> ''
             and c.whatsapp_norm = r.whatsapp_norm
             and lower(split_part(btrim(c.nombre), ' ', 1))
                 = lower(split_part(btrim(r.nombre_cliente), ' ', 1))
             and coalesce(btrim(c.notas), '') <> '')
  from reservas r
  where r.barberia_id = v_barberia and r.barbero_nombre = v_nombre
    and r.fecha = p_fecha and r.oculto_profesional = false
    and r.procesado = false
  union all
  -- En las visitas el vínculo es exacto (v.cliente_id), así que la nota sale
  -- directo del join que ya existía. Sin adivinanzas.
  select v.id, 'visita'::text, v.fecha, v.hora, v.servicio, v.estado, true,
         c.nombre, c.whatsapp, v.valor, v.comision_monto, v.notas,
         c.notas
  from visitas v
  left join clientes c on c.id = v.cliente_id
  where v.barberia_id = v_barberia and v.barbero_nombre = v_nombre
    and v.fecha = p_fecha and v.oculto_profesional = false
  order by 4;
end;
$function$;

-- ⚠ ESTAS DOS LÍNEAS NO SON OPCIONALES, y la primera versión de este archivo
-- las omitía. Postgres otorga EXECUTE a PUBLIC por defecto en toda función
-- nueva; el DROP se llevó el revoke que tenía la original
-- (migration_mi_agenda.sql:465) y el CREATE volvió a aplicar el default.
--
-- Comprobado en la base el 2026-09-11: sin esto, proacl pasa de
--   {postgres=X/…,anon=X/…,authenticated=X/…,service_role=X/…}
-- a tener un `=X/postgres` de más al principio, que es PUBLIC.
--
-- No era un agujero —anon ya tenía EXECUTE explícito y la función se corta
-- sola con `if v_barbero_id is null then return`, así que un anónimo obtiene
-- cero filas— pero rompe la convención que sigue todo el repo, y PUBLIC
-- alcanza a cualquier rol que exista o se cree después.
--
-- El grant va aunque `authenticated` ya aparezca en el ACL: revoke ... from
-- public no lo toca (son entradas distintas), y dejarlo explícito hace estas
-- dos sentencias repetibles y simétricas con las otras cinco funciones de Mi
-- Agenda.
revoke all on function mi_agenda_citas(date) from public;
grant execute on function mi_agenda_citas(date) to authenticated;


-- ═══════════════════════════════════════════════════════════════
-- VERIFICACIÓN (correr DESPUÉS, cada paso por separado)
-- ═══════════════════════════════════════════════════════════════

-- PASO 1 — La función existe, devuelve la columna nueva, y sigue siendo
-- security definer con el search_path fijo.
-- Esperado: 1 fila, security_definer = true, config = {search_path=public},
-- y `cliente_notas` en la lista de argumentos de salida.
--
-- select p.proname, p.prosecdef as security_definer, p.proconfig as config,
--        pg_get_function_result(p.oid) as devuelve
-- from pg_proc p join pg_namespace n on n.oid = p.pronamespace
-- where n.nspname = 'public' and p.proname = 'mi_agenda_citas';


-- PASO 2 — La gente de afuera sigue sin poder sacar nada.
-- La función se corta sola con `if v_barbero_id is null then return`, así que
-- un anónimo no obtiene filas aunque pueda llamarla. Esto lo comprueba en vez
-- de confiar en la lectura del código.
-- Esperado: CERO filas.
--
-- begin;
--   set local role anon;
--   select count(*) as filas_que_ve_un_anonimo from mi_agenda_citas(current_date);
-- rollback;


-- PASO 3 — LOS PERMISOS QUEDARON COMO ESTABAN.
-- Esperado: `proacl` IDÉNTICO al del PASO 0.
--
-- ⚠ MIRAR EN LAS DOS DIRECCIONES, no solo si falta algo. La primera versión de
-- este paso decía "si falta un rol, re-otorgarlo" — y lo que pasó el
-- 2026-09-11 fue lo contrario: SOBRÓ una entrada `=X/postgres` (PUBLIC),
-- porque el DROP se llevó el revoke de la migración original y el CREATE
-- volvió a aplicar el default de Postgres. Por eso ahora el bloque de arriba
-- termina con el revoke y el grant.
--
--   · Si FALTA un rol → Mi Agenda deja de cargar citas sin explicar por qué.
--   · Si SOBRA `=X/postgres` → no se perdió nada, pero las dos líneas del
--     final no se corrieron. Correrlas y volver a comparar.
--
-- select p.proname, p.proacl
-- from pg_proc p join pg_namespace n on n.oid = p.pronamespace
-- where n.nspname = 'public' and p.proname = 'mi_agenda_citas';


-- PASO 4 — EL GUARDIA DEL TELÉFONO COMPARTIDO, SIN INSERTAR NADA.
--
-- Un guardia que nunca se ejercita no prueba nada. Este corre la MISMA
-- expresión que tiene el cuerpo de la función contra filas fabricadas en el
-- aire: no toca ninguna tabla, no deja rastro, y se puede repetir cuando sea.
--
-- ⚠ POR QUÉ ASÍ Y NO INSERTANDO. La primera versión de este paso creaba
-- clientes y una reserva dentro de begin;/rollback;. El 2026-09-11 salió mal:
-- el bloque se corrió en partes, y el SQL Editor de Supabase NO MANTIENE
-- SESIÓN ENTRE EJECUCIONES —cada Run es una conexión nueva del pool— así que
-- el `begin` de una ejecución no envuelve los inserts de la siguiente. Cayeron
-- en autocommit, el `rollback` final no revirtió nada, y quedaron dos fichas y
-- una reserva de prueba en producción. En la corrida siguiente esa reserva
-- huérfana coincidía en nombre y día con la nueva, y el resultado mostró dos
-- filas donde debía haber una.
--
-- Es el mismo mecanismo que hace fallar begin;/commit; con funciones: el
-- editor trocea por `;`. Y afecta también a set_config(..., true), que es
-- local a la transacción y muere con ella.
--
-- Corrido y confirmado el 2026-09-11: las seis filas con ok = true.
--
-- Cada caso mata una mutación distinta. El 1 importa tanto como el 2: sin él,
-- un guardia que devolviera null SIEMPRE pasaría los otros cinco.
--
-- with cli(caso, barberia_id, nombre, whatsapp_norm, notas) as (values
--   (1,'b1','Ana Perez','987654321','ALERGIA'),
--   (2,'b1','Ana Perez','987654321','ALERGIA'),
--   (2,'b1','Ana Soto', '987654321','OTRA NOTA'),
--   (3,'b1','Ana Perez','987654321','ALERGIA'),
--   (3,'b1','Ana Soto', '987654321', null),
--   (4,'b1','Ana Perez','',         'ALERGIA'),
--   (5,'b1','Beto Perez','987654321','ALERGIA'),
--   (6,'b2','Ana Perez','987654321','ALERGIA')
-- ),
-- res(caso, barberia_id, nombre_cliente, whatsapp_norm, descripcion, esperado) as (values
--   (1,'b1','Ana Perez','987654321','una sola ficha con nota',                 'ALERGIA'),
--   (2,'b1','Ana Perez','987654321','dos personas distintas, las dos con nota', null),
--   (3,'b1','Ana Perez','987654321','ficha duplicada, solo una con nota',      'ALERGIA'),
--   (4,'b1','Ana Perez','',         'la reserva no tiene telefono',             null),
--   (5,'b1','Ana Perez','987654321','el primer nombre no coincide',             null),
--   (6,'b1','Ana Perez','987654321','la ficha es de otro negocio',              null)
-- )
-- select r.caso, r.descripcion, g.obtenido, r.esperado,
--        g.obtenido is not distinct from r.esperado as ok
-- from res r
-- cross join lateral (
--   -- Idéntica a la del cuerpo de mi_agenda_citas, salvo el `c.caso = r.caso`,
--   -- que solo separa los escenarios entre sí. Si se toca una, tocar la otra.
--   select case when count(*) = 1 then min(c.notas) end as obtenido
--   from cli c
--   where c.caso = r.caso
--     and c.barberia_id = r.barberia_id
--     and coalesce(r.whatsapp_norm, '') <> ''
--     and c.whatsapp_norm = r.whatsapp_norm
--     and lower(split_part(btrim(c.nombre), ' ', 1))
--         = lower(split_part(btrim(r.nombre_cliente), ' ', 1))
--     and coalesce(btrim(c.notas), '') <> ''
-- ) g
-- order by r.caso;
--
-- LO QUE ESTE PASO NO CUBRE: que la expresión esté bien CABLEADA dentro de la
-- función. Eso lo cubre test-mi-agenda.html, que verifica contra el texto de
-- la migración que las cuatro condiciones estén presentes. Entre los dos queda
-- cubierto sin insertar nada en producción.


-- PASO 4b — DE PUNTA A PUNTA, SOLO SI HACE FALTA.
--
-- El PASO 4 prueba la expresión; esto prueba la función entera, incluida la
-- puerta de auth_barbero_id(). Cuesta más y puede dejar basura, así que se usa
-- solo cuando se quiere confirmar el camino real.
--
-- ⚠⚠ TRES CONDICIONES, LAS TRES OBLIGATORIAS:
--
--   1. EL BLOQUE ENTERO EN UNA SOLA EJECUCIÓN. Seleccionar todo y apretar Run
--      una vez. Partido en pedazos, los inserts caen en autocommit y quedan en
--      producción — ya pasó una vez.
--   2. Hace falta un profesional que YA HAYA INICIADO SESIÓN alguna vez, porque
--      auth_barbero_id() cruza barberos.auth_user_id con auth.uid():
--        select id, nombre, auth_user_id from barberos
--        where barberia_id = '<ID>' and auth_user_id is not null and activo;
--      Si eso da cero filas, este paso no se puede correr.
--   3. Reemplazar <AUTH-USER-ID>, <NOMBRE-PROFESIONAL> y <ID-DE-TU-BARBERIA>.
--
-- El delete inicial y la precondición NO son adorno: son lo que impide que un
-- residuo de una corrida anterior envenene esta.
--
-- begin;
--
--   delete from reservas where nombre_cliente like 'ZZ %';
--   delete from clientes where nombre like 'ZZ %';
--
--   -- Si esto no da 0, algo quedó de antes y hay que mirarlo ANTES de seguir.
--   select (select count(*) from clientes where nombre like 'ZZ %')
--        + (select count(*) from reservas where nombre_cliente like 'ZZ %')
--          as residuos_esperado_cero;
--
--   -- auth.uid() lee el 'sub' de acá. Es LOCAL a esta transacción.
--   select set_config('request.jwt.claims',
--     json_build_object('sub','<AUTH-USER-ID>')::text, true);
--
--   -- Puerta de entrada: si esto no da true, lo de abajo no prueba nada.
--   select auth_barbero_id() is not null as sesion_simulada_ok;
--
--   insert into clientes (barberia_id, nombre, whatsapp, notas) values
--     ('<ID-DE-TU-BARBERIA>', 'ZZ Ana Prueba',  '+56 9 0000 0009', 'Alergica al tinte'),
--     ('<ID-DE-TU-BARBERIA>', 'ZZ Beto Prueba', '+56 9 0000 0009', 'Prefiere poco charla');
--
--   insert into reservas (barberia_id, nombre_cliente, whatsapp_cliente,
--                         fecha, hora, servicio, barbero_nombre, estado)
--   values ('<ID-DE-TU-BARBERIA>', 'ZZ Ana Prueba', '+56 9 0000 0009',
--           current_date, '09:00', 'ZZ Prueba Notas', '<NOMBRE-PROFESIONAL>', 'Pendiente');
--
--   -- (A) Solo una ficha comparte el primer nombre → count = 1.
--   --     Esperado: filas = 1 y nota = 'Alergica al tinte'.
--   select 'A' as caso, count(*) as filas, min(cliente_notas) as nota
--   from mi_agenda_citas(current_date) where servicio = 'ZZ Prueba Notas';
--
--   -- (B) Ahora las dos son "ZZ Ana", las dos con nota. Ya no se puede saber
--   --     cuál corresponde. Esperado: filas = 1 y nota EN NULL.
--   update clientes set nombre = 'ZZ Ana Otra' where nombre = 'ZZ Beto Prueba';
--   select 'B' as caso, count(*) as filas, min(cliente_notas) as nota
--   from mi_agenda_citas(current_date) where servicio = 'ZZ Prueba Notas';
--
-- rollback;
--
-- Se cuenta `filas` en las dos: si sale 2, hay una reserva de prueba vieja
-- mezclada y el resultado no significa nada. Fue exactamente lo que pasó la
-- primera vez.
--
-- ⚠ SI EL BLOQUE FALLA A MITAD DE CAMINO, correr esto antes de reintentar:
--   delete from reservas where nombre_cliente like 'ZZ %';
--   delete from clientes where nombre like 'ZZ %';
