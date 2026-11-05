-- ══════════════════════════════════════════════════════════════════════
-- Ensayo EJECUTADO el 2026-11-05 en producción (53 de 53) y la función de prueba se borró después.
-- ENSAYO de importar_clientes_lote() y deshacer_importacion_clientes(),
-- contra «ZZ prueba bucket». No deja NADA: todo ocurre dentro de un bloque que
-- se revierte solo.
--
-- ════════════════════════════════════════════
-- ⚠ POR QUÉ ES UNA FUNCIÓN Y NO UN begin/rollback SUELTO
--
-- Es el mismo método que prueba_fusion_clientes.sql, por la misma razón que
-- explica ese archivo: el SQL Editor de Supabase NO mantiene sesión entre
-- Runs. Con un begin ... rollback suelto, correrlo partido deja los inserts de
-- la segunda mitad en autocommit, el rollback no revierte nada y quedan fichas
-- de prueba en un negocio real. Como función, el bloque interno
-- begin/exception/end es una subtransacción: la excepción final lo revierte
-- TODO y los resultados sobreviven en una variable plpgsql (no transaccional).
--
-- Correrla no puede ensuciar la base aunque se interrumpa a la mitad.
-- ════════════════════════════════════════════
--
-- QUÉ HACE (se simula al DUEÑO de ZZ prueba bucket con los claims del token,
-- sin cambiar de rol: las dos funciones son security definer y validan con
-- auth_barberia_id() / auth_rol()):
--
--   A. SIN actividad: importa 3 clientes nuevos y completa 1 ficha existente;
--      deshace; y compara con EXCEPT en AMBOS sentidos que la tabla `clientes`
--      del negocio quedó IDÉNTICA a como estaba al inicio.
--   B. CON actividad: importa 3 nuevos y completa 1 ficha. Al primero le pone
--      una VISITA, al segundo SOLO una ENCUESTA (la visita se desliga), al
--      tercero nada. Deshace: se borra solo el tercero, se conservan los otros
--      dos, y la ficha completada vuelve a su estado. El EXCEPT debe mostrar
--      EXACTAMENTE las 2 fichas conservadas y nada más.
--   C. Las reglas nuevas: teléfono < 9 dígitos (crear y completar), fecha
--      inválida, WhatsApp de otra ficha, ventana de 30 días, permisos, tope de
--      filas, errores en español, privilegios y el bloqueo por negocio.
--
-- ORDEN: la migración (borrador_fase2_importacion_lote.sql) tiene que estar
-- aplicada ANTES: este ensayo prueba las funciones, no las crea.
--
-- CÓMO SE USA — tres ejecuciones separadas:
--
--   1. Este archivo completo (crea la función de ensayo).
--   2. select * from prueba_importacion_lote();
--   3. drop function prueba_importacion_lote();
--
-- El paso 2 va aparte porque el editor muestra solo el resultado de la última
-- sentencia: con el drop en el mismo Run, el veredicto no se vería.


create or replace function prueba_importacion_lote()
returns table (caso text, obtenido text, esperado text, ok boolean)
language plpgsql
as $function$
declare
  -- Sobrevive al rollback del bloque interno: las variables de plpgsql no son
  -- transaccionales. Es lo que permite revertir y devolver el veredicto.
  v_res      jsonb := '[]'::jsonb;
  v_barberia uuid;
  v_owner    uuid;
  v_f1 uuid; v_f2 uuid; v_f3 uuid;
  v_ini jsonb; v_fin jsonb;
  v_r jsonb; v_lote uuid; v_msg text;
  v_n1 uuid; v_n2 uuid; v_n3 uuid; v_vis uuid;
  v_filas jsonb;
begin
  -- Antes del bloque interno: si falta algo, es un error real y NO debe
  -- tragarse el manejador (una prueba rota que devuelve cero filas engaña).
  if (select count(*) from barberias where nombre = 'ZZ prueba bucket') <> 1 then
    raise exception 'Se esperaba exactamente UN negocio llamado "ZZ prueba bucket" y hay %.',
      (select count(*) from barberias where nombre = 'ZZ prueba bucket');
  end if;
  select id into v_barberia from barberias where nombre = 'ZZ prueba bucket';
  select p.id into v_owner from perfiles p
   where p.barberia_id = v_barberia and p.rol = 'dueno' order by p.id limit 1;
  if v_owner is null then
    raise exception 'ZZ prueba bucket no tiene un perfil con rol "dueno": no se puede simular al dueño.';
  end if;

  begin
    -- ── Los claims del dueño de ZZ ──
    -- is_local = true: se deshacen solos al revertir el bloque.
    perform set_config('request.jwt.claims',
      json_build_object('sub', v_owner, 'role', 'authenticated')::text, true);
    perform set_config('request.jwt.claim.sub', v_owner::text, true);

    -- ── Fichas base (se crean ANTES de la foto «inicio») ──
    insert into clientes (barberia_id, nombre, whatsapp, email, apellido, canal)
      values (v_barberia, 'ZZ Ensayo Base', '+56 9 1000 0001', null, null, 'ZZ Ensayo') returning id into v_f1;
    insert into clientes (barberia_id, nombre, whatsapp, canal)
      values (v_barberia, 'ZZ Ensayo Otro', '+56 9 1000 0002', 'ZZ Ensayo') returning id into v_f2;
    insert into clientes (barberia_id, nombre, whatsapp, canal)
      values (v_barberia, 'ZZ Ensayo Sin Telefono', null, 'ZZ Ensayo') returning id into v_f3;

    -- Foto «inicio»: la fila COMPLETA de cada ficha del negocio, en jsonb. Así
    -- el EXCEPT compara todas las columnas, incluida importacion_id.
    v_ini := (select coalesce(jsonb_agg(to_jsonb(c) order by c.id), '[]'::jsonb)
                from clientes c where c.barberia_id = v_barberia);

    -- Las 3 fichas nuevas + completar la ficha base: se reutiliza en A y en B.
    -- ═══════════════════ A. SIN ACTIVIDAD ═══════════════════
    v_filas := jsonb_build_array(
      jsonb_build_object('accion','crear','datos', jsonb_build_object('nombre','ZZ Nuevo Uno','whatsapp','+56 9 2000 0001','cumpleanos','1990-05-17')),
      jsonb_build_object('accion','crear','datos', jsonb_build_object('nombre','ZZ Nuevo Dos','whatsapp','+56 9 2000 0002')),
      jsonb_build_object('accion','crear','datos', jsonb_build_object('nombre','ZZ Nuevo Tres','whatsapp','+56 9 2000 0003')),
      jsonb_build_object('accion','completar','cliente_id', v_f1,
        'datos', jsonb_build_object('email','ensayo.base@example.com','apellido','Ensayo')));
    v_r := importar_clientes_lote('ensayo-A.csv', v_filas);
    v_lote := (v_r->>'importacion_id')::uuid;
    v_res := v_res || jsonb_build_object('caso','A01 importar: creados','obtenido',v_r->>'creados','esperado','3');
    v_res := v_res || jsonb_build_object('caso','A02 importar: completados','obtenido',v_r->>'completados','esperado','1');
    v_res := v_res || jsonb_build_object('caso','A03 importar: saltados','obtenido',v_r->>'saltados','esperado','0');
    v_res := v_res || jsonb_build_object('caso','A04 la ficha base quedó con el correo',
      'obtenido',(select email from clientes where id = v_f1),'esperado','ensayo.base@example.com');
    v_res := v_res || jsonb_build_object('caso','A05 las 3 fichas nuevas quedan ligadas al lote',
      'obtenido',(select count(*)::text from clientes where importacion_id = v_lote),'esperado','3');
    v_res := v_res || jsonb_build_object('caso','A06 se tomó el bloqueo por negocio (advisory, de este proceso)',
      'obtenido',(select (count(*) > 0)::text from pg_locks where locktype = 'advisory' and pid = pg_backend_pid() and granted),
      'esperado','true');

    v_r := deshacer_importacion_clientes(v_lote);
    v_res := v_res || jsonb_build_object('caso','A07 deshacer: borrados','obtenido',v_r->>'borrados','esperado','3');
    v_res := v_res || jsonb_build_object('caso','A08 deshacer: conservados','obtenido',v_r->>'conservados_con_actividad','esperado','0');
    v_res := v_res || jsonb_build_object('caso','A09 deshacer: campos devueltos (correo y apellido)','obtenido',v_r->>'campos_devueltos','esperado','2');
    v_res := v_res || jsonb_build_object('caso','A10 la importación quedó «deshecha»',
      'obtenido',(select estado from importaciones_clientes where id = v_lote),'esperado','deshecha');

    v_fin := (select coalesce(jsonb_agg(to_jsonb(c) order by c.id), '[]'::jsonb)
                from clientes c where c.barberia_id = v_barberia);
    v_res := v_res || jsonb_build_object('caso','A11 EXCEPT inicio − final = 0 filas',
      'obtenido',(select count(*)::text from (select e from jsonb_array_elements(v_ini) e except select e from jsonb_array_elements(v_fin) e) x),'esperado','0');
    v_res := v_res || jsonb_build_object('caso','A12 EXCEPT final − inicio = 0 filas',
      'obtenido',(select count(*)::text from (select e from jsonb_array_elements(v_fin) e except select e from jsonb_array_elements(v_ini) e) x),'esperado','0');

    -- ═══════════════════ B. CON ACTIVIDAD ═══════════════════
    v_filas := jsonb_build_array(
      jsonb_build_object('accion','crear','datos', jsonb_build_object('nombre','ZZ Con Visita','whatsapp','+56 9 3000 0001')),
      jsonb_build_object('accion','crear','datos', jsonb_build_object('nombre','ZZ Con Encuesta','whatsapp','+56 9 3000 0002')),
      jsonb_build_object('accion','crear','datos', jsonb_build_object('nombre','ZZ Sin Nada','whatsapp','+56 9 3000 0003')),
      jsonb_build_object('accion','completar','cliente_id', v_f1,
        'datos', jsonb_build_object('email','ensayo.base@example.com','apellido','Ensayo')));
    v_r := importar_clientes_lote('ensayo-B.csv', v_filas);
    v_lote := (v_r->>'importacion_id')::uuid;
    v_res := v_res || jsonb_build_object('caso','B01 importar: creados y completados',
      'obtenido',(v_r->>'creados') || '/' || (v_r->>'completados'),'esperado','3/1');
    select id into v_n1 from clientes where importacion_id = v_lote and nombre = 'ZZ Con Visita';
    select id into v_n2 from clientes where importacion_id = v_lote and nombre = 'ZZ Con Encuesta';
    select id into v_n3 from clientes where importacion_id = v_lote and nombre = 'ZZ Sin Nada';

    -- Actividad 1: una VISITA para el primero (el trigger de encuestas también
    -- crea una encuesta para él).
    insert into visitas (barberia_id, cliente_id, barbero_nombre, servicio, valor, fecha, fuente, estado)
      values (v_barberia, v_n1, 'ZZ Ensayo', 'ZZ Ensayo', 1000, current_date, 'Manual', 'Atendida');
    -- Actividad 2: SOLO una encuesta para el segundo. La visita que la origina
    -- se desliga del cliente (visitas.cliente_id admite NULL): queda la encuesta
    -- como única huella.
    insert into visitas (barberia_id, cliente_id, barbero_nombre, servicio, valor, fecha, fuente, estado)
      values (v_barberia, v_n2, 'ZZ Ensayo', 'ZZ Ensayo', 1000, current_date, 'Manual', 'Atendida') returning id into v_vis;
    update visitas set cliente_id = null where id = v_vis;
    v_res := v_res || jsonb_build_object('caso','B02 precondición: el primero tiene una visita',
      'obtenido',(select count(*)::text from visitas where cliente_id = v_n1),'esperado','1');
    v_res := v_res || jsonb_build_object('caso','B03 precondición: el segundo NO tiene visitas',
      'obtenido',(select count(*)::text from visitas where cliente_id = v_n2),'esperado','0');
    v_res := v_res || jsonb_build_object('caso','B04 precondición: el segundo SÍ tiene una encuesta (la creó el trigger)',
      'obtenido',(select count(*)::text from encuestas where cliente_id = v_n2),'esperado','1');

    v_r := deshacer_importacion_clientes(v_lote);
    v_res := v_res || jsonb_build_object('caso','B05 deshacer: borrados (solo el que no tenía nada)','obtenido',v_r->>'borrados','esperado','1');
    v_res := v_res || jsonb_build_object('caso','B06 deshacer: conservados (visita y encuesta)','obtenido',v_r->>'conservados_con_actividad','esperado','2');
    v_res := v_res || jsonb_build_object('caso','B07 deshacer: campos devueltos','obtenido',v_r->>'campos_devueltos','esperado','2');
    v_res := v_res || jsonb_build_object('caso','B08 la ficha con visita sigue existiendo',
      'obtenido',(select count(*)::text from clientes where id = v_n1),'esperado','1');
    v_res := v_res || jsonb_build_object('caso','B09 la ficha con SOLO encuesta sigue existiendo',
      'obtenido',(select count(*)::text from clientes where id = v_n2),'esperado','1');
    v_res := v_res || jsonb_build_object('caso','B10 la ficha sin actividad se borró',
      'obtenido',(select count(*)::text from clientes where id = v_n3),'esperado','0');
    v_res := v_res || jsonb_build_object('caso','B11 las conservadas quedan desligadas del lote',
      'obtenido',(select count(*)::text from clientes where id in (v_n1, v_n2) and importacion_id is null),'esperado','2');
    v_res := v_res || jsonb_build_object('caso','B12 la visita sigue ahí',
      'obtenido',(select count(*)::text from visitas where cliente_id = v_n1),'esperado','1');

    v_fin := (select coalesce(jsonb_agg(to_jsonb(c) order by c.id), '[]'::jsonb)
                from clientes c where c.barberia_id = v_barberia);
    v_res := v_res || jsonb_build_object('caso','B13 EXCEPT inicio − final = 0 filas (la ficha completada volvió a su estado)',
      'obtenido',(select count(*)::text from (select e from jsonb_array_elements(v_ini) e except select e from jsonb_array_elements(v_fin) e) x),'esperado','0');
    v_res := v_res || jsonb_build_object('caso','B14 EXCEPT final − inicio = EXACTAMENTE las 2 conservadas',
      'obtenido',(select count(*)::text from (select e from jsonb_array_elements(v_fin) e except select e from jsonb_array_elements(v_ini) e) x),'esperado','2');
    v_res := v_res || jsonb_build_object('caso','B15 y esas 2 son las del primero y del segundo',
      'obtenido',(select string_agg(x.e->>'nombre', ',' order by x.e->>'nombre')
                    from (select e from jsonb_array_elements(v_fin) e except select e from jsonb_array_elements(v_ini) e) x),
      'esperado','ZZ Con Encuesta,ZZ Con Visita');

    -- ═══════════════════ C. REGLAS NUEVAS ═══════════════════
    -- C1 teléfono con menos de 9 dígitos al CREAR
    begin
      perform importar_clientes_lote('c.csv', jsonb_build_array(jsonb_build_object('accion','crear',
        'datos', jsonb_build_object('nombre','ZZ Corto','whatsapp','+56 9 123'))));
      v_msg := '(no lanzó error)';
    exception when others then v_msg := sqlerrm; end;
    v_res := v_res || jsonb_build_object('caso','C01 crear con teléfono de menos de 9 dígitos se rechaza',
      'obtenido',case when v_msg like '%menos de 9 dígitos%' then 'menos de 9 dígitos' else v_msg end,'esperado','menos de 9 dígitos');
    v_res := v_res || jsonb_build_object('caso','C02 el mensaje dice en qué fila',
      'obtenido',case when v_msg like 'Fila 1:%' then 'Fila 1' else v_msg end,'esperado','Fila 1');

    -- C3 teléfono con menos de 9 dígitos al COMPLETAR (la ficha sin teléfono)
    begin
      perform importar_clientes_lote('c.csv', jsonb_build_array(jsonb_build_object('accion','completar','cliente_id', v_f3,
        'datos', jsonb_build_object('whatsapp','12345678'))));
      v_msg := '(no lanzó error)';
    exception when others then v_msg := sqlerrm; end;
    v_res := v_res || jsonb_build_object('caso','C03 completar con teléfono de menos de 9 dígitos se rechaza',
      'obtenido',case when v_msg like '%menos de 9 dígitos%' then 'menos de 9 dígitos' else v_msg end,'esperado','menos de 9 dígitos');

    -- C4 teléfono vacío al crear
    begin
      perform importar_clientes_lote('c.csv', jsonb_build_array(jsonb_build_object('accion','crear',
        'datos', jsonb_build_object('nombre','ZZ Sin Tel'))));
      v_msg := '(no lanzó error)';
    exception when others then v_msg := sqlerrm; end;
    v_res := v_res || jsonb_build_object('caso','C04 crear sin teléfono se rechaza',
      'obtenido',case when v_msg like '%falta el teléfono%' then 'falta el teléfono' else v_msg end,'esperado','falta el teléfono');

    -- C5 fecha inválida al crear (30 de febrero)
    begin
      perform importar_clientes_lote('c.csv', jsonb_build_array(jsonb_build_object('accion','crear',
        'datos', jsonb_build_object('nombre','ZZ Fecha','whatsapp','+56 9 4000 0001','cumpleanos','2026-02-30'))));
      v_msg := '(no lanzó error)';
    exception when others then v_msg := sqlerrm; end;
    v_res := v_res || jsonb_build_object('caso','C05 crear con fecha inválida (30 de febrero): error claro',
      'obtenido',case when v_msg like '%fecha de cumpleaños "2026-02-30" no es válida%AAAA-MM-DD%' then 'fecha inválida, con formato' else v_msg end,
      'esperado','fecha inválida, con formato');

    -- C6 fecha con texto al completar
    begin
      perform importar_clientes_lote('c.csv', jsonb_build_array(jsonb_build_object('accion','completar','cliente_id', v_f1,
        'datos', jsonb_build_object('cumpleanos','no es fecha'))));
      v_msg := '(no lanzó error)';
    exception when others then v_msg := sqlerrm; end;
    v_res := v_res || jsonb_build_object('caso','C06 completar con fecha inválida: error claro',
      'obtenido',case when v_msg like '%fecha de cumpleaños "no es fecha" no es válida%' then 'fecha inválida' else v_msg end,'esperado','fecha inválida');

    -- C7 WhatsApp que ya es de OTRA ficha: se omite el campo y cuenta como saltado
    v_r := importar_clientes_lote('c.csv', jsonb_build_array(jsonb_build_object('accion','completar','cliente_id', v_f3,
      'datos', jsonb_build_object('whatsapp','56910000002','apellido','Soto'))));
    v_res := v_res || jsonb_build_object('caso','C07 completar con un WhatsApp de otra ficha: saltados',
      'obtenido',v_r->>'saltados','esperado','1');
    v_res := v_res || jsonb_build_object('caso','C08 …la ficha NO recibió ese WhatsApp',
      'obtenido',coalesce((select whatsapp from clientes where id = v_f3), '(nulo)'),'esperado','(nulo)');
    v_res := v_res || jsonb_build_object('caso','C09 …pero sí el resto de los campos (apellido)',
      'obtenido',coalesce((select apellido from clientes where id = v_f3), '(nulo)'),'esperado','Soto');
    v_res := v_res || jsonb_build_object('caso','C10 …y el aviso lo cuenta en español',
      'obtenido',case when (v_r->'avisos'->>0) like '%ya pertenece a otra ficha%' then 'ya pertenece a otra ficha' else coalesce(v_r->>'avisos','(sin aviso)') end,
      'esperado','ya pertenece a otra ficha');

    -- C11 crear con el teléfono de una ficha existente (distinto formato): se salta
    v_r := importar_clientes_lote('c.csv', jsonb_build_array(jsonb_build_object('accion','crear',
      'datos', jsonb_build_object('nombre','ZZ Repetido','whatsapp','910000001'))));
    v_res := v_res || jsonb_build_object('caso','C11 crear con el teléfono de una ficha existente: creados/saltados',
      'obtenido',(v_r->>'creados') || '/' || (v_r->>'saltados'),'esperado','0/1');

    -- C12 dos filas con el MISMO teléfono (escrito de dos maneras) en el MISMO lote:
    -- la segunda se salta, porque la primera ya quedó insertada dentro de esta transacción
    v_r := importar_clientes_lote('c.csv', jsonb_build_array(
      jsonb_build_object('accion','crear','datos', jsonb_build_object('nombre','ZZ Gemelo Uno','whatsapp','+56 9 5000 0009')),
      jsonb_build_object('accion','crear','datos', jsonb_build_object('nombre','ZZ Gemelo Dos','whatsapp','950000009'))));
    v_res := v_res || jsonb_build_object('caso','C12 dos filas con el mismo teléfono en el mismo lote: creados/saltados',
      'obtenido',(v_r->>'creados') || '/' || (v_r->>'saltados'),'esperado','1/1');

    -- C13 ventana de 30 días: a los 31 días se rechaza; a los 29 se puede
    v_r := importar_clientes_lote('c.csv', jsonb_build_array(jsonb_build_object('accion','crear',
      'datos', jsonb_build_object('nombre','ZZ Antiguo','whatsapp','+56 9 6000 0001'))));
    v_lote := (v_r->>'importacion_id')::uuid;
    update importaciones_clientes set creado_en = now() - interval '31 days' where id = v_lote;
    begin
      perform deshacer_importacion_clientes(v_lote);
      v_msg := '(no lanzó error)';
    exception when others then v_msg := sqlerrm; end;
    v_res := v_res || jsonb_build_object('caso','C13 deshacer a los 31 días: error claro en español',
      'obtenido',case when v_msg like 'Esta importación se hizo el %, hace más de 30 días, y ya no se puede deshacer.' then 'más de 30 días' else v_msg end,
      'esperado','más de 30 días');
    update importaciones_clientes set creado_en = now() - interval '29 days' where id = v_lote;
    v_r := deshacer_importacion_clientes(v_lote);
    v_res := v_res || jsonb_build_object('caso','C14 deshacer a los 29 días sí se puede (borrados)',
      'obtenido',v_r->>'borrados','esperado','1');

    -- C15 deshacer dos veces
    begin
      perform deshacer_importacion_clientes(v_lote);
      v_msg := '(no lanzó error)';
    exception when others then v_msg := sqlerrm; end;
    v_res := v_res || jsonb_build_object('caso','C15 deshacer una importación ya deshecha: error claro',
      'obtenido',case when v_msg like 'Esa importación ya se deshizo el %' then 'ya se deshizo' else v_msg end,'esperado','ya se deshizo');

    -- C16 acción desconocida, identificador inválido y ficha de otro negocio
    begin
      perform importar_clientes_lote('c.csv', jsonb_build_array(jsonb_build_object('accion','borrar','datos','{}'::jsonb)));
      v_msg := '(no lanzó error)';
    exception when others then v_msg := sqlerrm; end;
    v_res := v_res || jsonb_build_object('caso','C16 acción desconocida: error claro',
      'obtenido',case when v_msg like '%la acción "borrar" no se reconoce%' then 'no se reconoce' else v_msg end,'esperado','no se reconoce');
    begin
      perform importar_clientes_lote('c.csv', jsonb_build_array(jsonb_build_object('accion','completar','cliente_id','no-es-un-uuid','datos','{}'::jsonb)));
      v_msg := '(no lanzó error)';
    exception when others then v_msg := sqlerrm; end;
    v_res := v_res || jsonb_build_object('caso','C17 identificador de ficha inválido: error claro',
      'obtenido',case when v_msg like '%identificador de la ficha a completar no es válido%' then 'identificador inválido' else v_msg end,'esperado','identificador inválido');
    begin
      perform importar_clientes_lote('c.csv', jsonb_build_array(jsonb_build_object('accion','completar','cliente_id', gen_random_uuid(),'datos','{}'::jsonb)));
      v_msg := '(no lanzó error)';
    exception when others then v_msg := sqlerrm; end;
    v_res := v_res || jsonb_build_object('caso','C18 ficha que no es de este negocio: error claro',
      'obtenido',case when v_msg like '%no existe en este negocio%' then 'no existe en este negocio' else v_msg end,'esperado','no existe en este negocio');

    -- C19 tope de filas
    begin
      perform importar_clientes_lote('c.csv', (select jsonb_agg(jsonb_build_object('accion','crear','datos','{}'::jsonb)) from generate_series(1, 5001)));
      v_msg := '(no lanzó error)';
    exception when others then v_msg := sqlerrm; end;
    v_res := v_res || jsonb_build_object('caso','C19 más de 5000 filas: error claro',
      'obtenido',case when v_msg like '%máximo 5000%' then 'máximo 5000' else v_msg end,'esperado','máximo 5000');

    -- C20 permisos: alguien que no es el dueño (un perfil inexistente)
    perform set_config('request.jwt.claims', json_build_object('sub', gen_random_uuid(), 'role','authenticated')::text, true);
    perform set_config('request.jwt.claim.sub', gen_random_uuid()::text, true);
    begin
      perform importar_clientes_lote('c.csv', jsonb_build_array(jsonb_build_object('accion','crear',
        'datos', jsonb_build_object('nombre','ZZ Intruso','whatsapp','+56 9 7000 0001'))));
      v_msg := '(no lanzó error)';
    exception when others then v_msg := sqlerrm; end;
    v_res := v_res || jsonb_build_object('caso','C20 quien no es el dueño no puede importar',
      'obtenido',case when v_msg like 'No tienes permiso para importar clientes%' then 'sin permiso' else v_msg end,'esperado','sin permiso');
    begin
      perform deshacer_importacion_clientes(v_lote);
      v_msg := '(no lanzó error)';
    exception when others then v_msg := sqlerrm; end;
    v_res := v_res || jsonb_build_object('caso','C21 quien no es el dueño no puede deshacer',
      'obtenido',case when v_msg like 'No tienes permiso para deshacer importaciones%' then 'sin permiso' else v_msg end,'esperado','sin permiso');
    -- se vuelve al dueño
    perform set_config('request.jwt.claims', json_build_object('sub', v_owner, 'role','authenticated')::text, true);
    perform set_config('request.jwt.claim.sub', v_owner::text, true);

    -- C22 privilegios de ejecución
    v_res := v_res || jsonb_build_object('caso','C22 anon NO puede ejecutar importar',
      'obtenido',has_function_privilege('anon','importar_clientes_lote(text,jsonb)','execute')::text,'esperado','false');
    v_res := v_res || jsonb_build_object('caso','C23 authenticated SÍ puede ejecutar importar',
      'obtenido',has_function_privilege('authenticated','importar_clientes_lote(text,jsonb)','execute')::text,'esperado','true');
    v_res := v_res || jsonb_build_object('caso','C24 anon NO puede ejecutar deshacer',
      'obtenido',has_function_privilege('anon','deshacer_importacion_clientes(uuid)','execute')::text,'esperado','false');
    v_res := v_res || jsonb_build_object('caso','C25 authenticated SÍ puede ejecutar deshacer',
      'obtenido',has_function_privilege('authenticated','deshacer_importacion_clientes(uuid)','execute')::text,'esperado','true');
    v_res := v_res || jsonb_build_object('caso','C26 las tablas del lote no se pueden escribir desde el navegador',
      'obtenido',(has_table_privilege('authenticated','importaciones_clientes','insert')
               or has_table_privilege('authenticated','importaciones_clientes','update')
               or has_table_privilege('authenticated','importaciones_clientes','delete'))::text,'esperado','false');

    -- ── Revertir TODO ──
    -- Esta excepción es la que deshace el bloque. Los resultados ya están en
    -- v_res, que no es transaccional y sobrevive.
    raise exception 'ROLLBACK_PRUEBA';

  exception when others then
    -- Solo se traga la propia. Un error real —una columna que falta, una
    -- función sin crear— se vuelve a lanzar: si se tragara todo, una prueba
    -- rota devolvería cero filas y parecería que no hay nada que reportar.
    if sqlerrm <> 'ROLLBACK_PRUEBA' then
      raise;
    end if;
  end;

  return query
  select x.caso, x.obtenido, x.esperado,
         x.obtenido is not distinct from x.esperado
  from jsonb_to_recordset(v_res) as x(caso text, obtenido text, esperado text)
  order by x.caso;
end;
$function$;

-- Función de prueba: no tiene por qué estar al alcance de nadie más.
revoke execute on function prueba_importacion_lote() from public;
revoke execute on function prueba_importacion_lote() from anon, authenticated;


-- ════════════════════════════════════════════
-- EJECUCIÓN — en Runs aparte de este archivo.
--
--   select * from prueba_importacion_lote();
--
--   Todos los casos con ok = true. Donde falle, `obtenido` y `esperado` quedan
--   lado a lado: el valor real es lo que dice qué se rompió.
--
-- Y al terminar, para no dejarla viva en producción:
--
--   drop function prueba_importacion_lote();
--
-- ⚠ Si la llamada devuelve CERO FILAS, no es que todo pasó: es que algo falló
-- antes de llegar a los checks. El manejador re-lanza los errores que no son
-- el ROLLBACK_PRUEBA, así que un error real se ve como error.
--
-- Comprobación de que no quedó nada (debería ser innecesaria, porque el bloque
-- se revierte solo, pero cuesta un Run):
--
--   select (select count(*) from clientes where nombre like 'ZZ Ensayo%'
--                                            or nombre like 'ZZ Nuevo%'
--                                            or nombre like 'ZZ Con %'
--                                            or nombre like 'ZZ Gemelo%')            as fichas,
--          (select count(*) from importaciones_clientes
--            where archivo in ('ensayo-A.csv','ensayo-B.csv','c.csv'))              as lotes;
--
--   Esperado: 0, 0.
-- ════════════════════════════════════════════
