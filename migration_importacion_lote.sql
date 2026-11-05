-- ══════════════════════════════════════════════════════════════════════
-- APLICADA en producción el 2026-11-05 (proyecto barbercrm). Ensayo: prueba_importacion_lote.sql — 53 de 53.
-- Fase 2 del importador de clientes: importación con LOTE, para poder deshacer.
--
-- Qué resuelve, de lo que mostró el análisis del importador:
--   · no había forma de deshacer una importación;
--   · un bloque de 500 que fallaba dejaba la importación A MEDIAS, sin rollback;
--   · el navegador escribía directo en `clientes`: la Fase 1 ya normaliza y
--     deduplica, pero una pestaña con la lista desactualizada, o dos
--     importaciones a la vez, seguían pudiendo crear fichas repetidas.
--
-- Diseño en una frase: el navegador manda las filas YA decididas a UNA función
-- que, en una sola transacción, crea el lote, inserta, completa y deja el
-- registro; y otra función deshace el lote.
--
-- Convenciones que sigue (las del proyecto): security definer + search_path
-- fijo, scoping por auth_barberia_id(), solo el dueño (auth_rol() = 'dueno'),
-- RLS sin comodines, el navegador nunca elige el barberia_id.
--
-- ⚠ ORDEN DE DESPLIEGUE (regla del proyecto: la migración va ANTES que el código).
--   1) esta migración  2) el ensayo (archivo aparte)  3) el cambio de app.html.
--
-- CAMBIOS DE ESTA VERSIÓN respecto del borrador anterior:
--   1. Un bloqueo por negocio (pg_advisory_xact_lock) al comienzo de importar.
--   2. «Completar» no pone un WhatsApp que ya tenga OTRA ficha del negocio: omite
--      ese campo y lo cuenta como saltado.
--   3. «Crear» y «completar» rechazan un teléfono con menos de 9 dígitos.
--   4. «Deshacer» cuenta también las encuestas como actividad.
--   5. «Deshacer» solo dentro de los 30 días de creada la importación.
--   6. Todos los errores en español claro, con el número de fila; incluida la
--      fecha de cumpleaños inválida.
--   7. El ensayo en transacción con ROLLBACK está en
--      borrador_fase2_ensayo_importacion_lote.sql.
-- ══════════════════════════════════════════════════════════════════════


-- ══════════════════════════════════════════════════════════════════════
-- DECISIONES QUE SIGUEN ABIERTAS (marcadas con «DECIDIR» abajo)
--   A. Tope de filas por llamada: 5000 en el borrador.
--   B. La función NO normaliza teléfonos: confía en que el navegador mande el
--      resultado de wspChile(). Solo exige 9 dígitos o más y calcula la clave de
--      dedupe (últimos 9 dígitos, igual que whatsapp_norm). ¿Quieres que además
--      rechace un teléfono que no sea un celular chileno (9 dígitos, empieza
--      en 9)? Hoy no lo hace.
--   C. AGREGUÉ por mi cuenta el mismo bloqueo en «deshacer» (no estaba en tu
--      lista): sin él, deshacer una importación mientras otra se está
--      escribiendo podría borrar o dejar a medias fichas del mismo negocio.
--      Si prefieres no tocarlo, es una línea marcada «DECIDIR (C)».
--   D. «saltados» cuenta lo que el servidor descartó, sea una FILA (la ficha ya
--      existía) o un CAMPO (el WhatsApp ya pertenecía a otra ficha). No se
--      distingue en el número; el detalle va en `avisos`.
-- ══════════════════════════════════════════════════════════════════════


-- ── 1) El lote ───────────────────────────────────────────────────────────
create table if not exists importaciones_clientes (
  id             uuid primary key default gen_random_uuid(),
  barberia_id    uuid not null references barberias(id) on delete cascade,
  creado_por     uuid,                                   -- auth.uid() de quien importó
  creado_en      timestamptz not null default now(),
  archivo        text,                                   -- nombre del archivo, solo informativo
  filas_enviadas integer not null default 0,
  creados        integer not null default 0,
  completados    integer not null default 0,             -- fichas existentes a las que se les completó algo
  saltados       integer not null default 0,             -- filas o campos que el servidor descartó
  estado         text not null default 'aplicada'
                 check (estado in ('aplicada', 'deshecha')),
  deshecha_en    timestamptz,
  deshecha_por   uuid
);
create index if not exists importaciones_clientes_barberia_idx
  on importaciones_clientes (barberia_id, creado_en desc);


-- ── 2) Qué fichas creó cada lote ─────────────────────────────────────────
-- Una columna nueva y NULLABLE en clientes: las fichas de siempre quedan en
-- NULL, igual que hoy. on delete set null: borrar el registro del lote no
-- debe borrar fichas.
alter table clientes
  add column if not exists importacion_id uuid
  references importaciones_clientes(id) on delete set null;
create index if not exists clientes_importacion_idx
  on clientes (importacion_id) where importacion_id is not null;


-- ── 3) Qué campos completó el lote en fichas que YA existían ─────────────
-- La Fase 1 solo completa campos vacíos, así que el «antes» siempre es vacío;
-- igual se guarda tal cual estaba (null o '') para devolverlo EXACTO.
create table if not exists importaciones_clientes_cambios (
  id             bigserial primary key,
  importacion_id uuid not null references importaciones_clientes(id) on delete cascade,
  barberia_id    uuid not null,
  cliente_id     uuid not null,                          -- sin FK a propósito: si la ficha se borra, el log queda
  campo          text not null
                 check (campo in ('apellido','whatsapp','email','cumpleanos','notas','barbero_preferido')),
  valor_antes    text,
  valor_despues  text
);
create index if not exists importaciones_cambios_lote_idx
  on importaciones_clientes_cambios (importacion_id);


-- ── 4) RLS: el navegador solo LEE; escribir es solo por las funciones ────
alter table importaciones_clientes enable row level security;
alter table importaciones_clientes_cambios enable row level security;

drop policy if exists importaciones_clientes_leer on importaciones_clientes;
create policy importaciones_clientes_leer on importaciones_clientes
  for select to authenticated
  using (barberia_id = auth_barberia_id() and auth_rol() = 'dueno');

drop policy if exists importaciones_cambios_leer on importaciones_clientes_cambios;
create policy importaciones_cambios_leer on importaciones_clientes_cambios
  for select to authenticated
  using (barberia_id = auth_barberia_id() and auth_rol() = 'dueno');

-- Sin políticas de insert/update/delete: nadie escribe directo. Y como las
-- tablas nuevas heredan los privilegios por defecto del esquema (en `clientes`
-- hoy anon tiene todo, protegido solo por RLS), se cierran de forma explícita.
revoke all on importaciones_clientes, importaciones_clientes_cambios from anon, authenticated;
grant select on importaciones_clientes, importaciones_clientes_cambios to authenticated;
revoke all on sequence importaciones_clientes_cambios_id_seq from anon, authenticated;


-- ── 5) Importar ──────────────────────────────────────────────────────────
-- p_filas: arreglo JSON con UNA entrada por fila que el usuario decidió
-- aplicar (las saltadas no se mandan):
--   { "accion": "crear",     "datos": { nombre, apellido, whatsapp, email,
--                                       cumpleanos, canal, notas, barbero_preferido } }
--   { "accion": "completar", "cliente_id": "<uuid>",
--                            "datos": { apellido, whatsapp, email, cumpleanos,
--                                       notas, barbero_preferido } }
--
-- TODO ocurre en una transacción: si algo falla, no queda NADA a medias.
-- Los mensajes de error van en español claro y dicen en qué fila ocurrió
-- (la posición dentro de las filas enviadas, empezando en 1).
create or replace function importar_clientes_lote(
  p_archivo text,
  p_filas   jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_barberia    uuid := auth_barberia_id();
  v_lote        uuid := gen_random_uuid();
  v_fila        jsonb;
  v_n           integer;
  v_datos       jsonb;
  v_cliente     clientes%rowtype;
  v_cid         uuid;
  v_dig         text;
  v_fecha       date;
  v_creados     integer := 0;
  v_completados integer := 0;
  v_saltados    integer := 0;
  v_avisos      text[]  := '{}';
  v_campo       text;
  v_nuevo       text;
  v_antes       text;
  v_cambio      boolean;
begin
  if v_barberia is null or auth_rol() <> 'dueno' then
    raise exception 'No tienes permiso para importar clientes: solo el dueño del negocio puede hacerlo.';
  end if;

  -- (1) UN importador a la vez por negocio. El bloqueo se libera solo al
  -- terminar la transacción. Una segunda importación (otra pestaña, otro
  -- dispositivo) ESPERA a que termine la primera en vez de fallar, y recién
  -- entonces revisa duplicados: así ve las fichas que la primera acaba de crear.
  perform pg_advisory_xact_lock(hashtextextended('importar_clientes:' || v_barberia::text, 0));

  if p_filas is null or jsonb_typeof(p_filas) <> 'array' then
    raise exception 'Las filas a importar llegaron en un formato que no entendemos. Vuelve a cargar el archivo e intenta de nuevo.';
  end if;
  if jsonb_array_length(p_filas) = 0 then
    raise exception 'No hay filas para importar.';
  end if;
  if jsonb_array_length(p_filas) > 5000 then                          -- DECIDIR (A)
    raise exception 'Son demasiadas filas para una sola importación (máximo 5000). Divide el archivo en partes.';
  end if;

  insert into importaciones_clientes (id, barberia_id, creado_por, archivo, filas_enviadas)
  values (v_lote, v_barberia, auth.uid(), left(p_archivo, 200), jsonb_array_length(p_filas));

  for v_fila, v_n in
    select e.valor, e.n from jsonb_array_elements(p_filas) with ordinality as e(valor, n)
  loop
    if jsonb_typeof(v_fila) <> 'object' then
      raise exception 'Fila %: no tiene el formato esperado.', v_n;
    end if;
    v_datos := coalesce(v_fila->'datos', '{}'::jsonb);
    if jsonb_typeof(v_datos) <> 'object' then
      raise exception 'Fila %: los datos del cliente no tienen el formato esperado.', v_n;
    end if;

    -- ── crear ──
    if v_fila->>'accion' = 'crear' then
      if coalesce(trim(v_datos->>'nombre'), '') = '' then
        raise exception 'Fila %: falta el nombre del cliente.', v_n;
      end if;

      v_dig := regexp_replace(coalesce(v_datos->>'whatsapp', ''), '\D', '', 'g');
      if v_dig = '' then
        raise exception 'Fila %: falta el teléfono (WhatsApp) del cliente.', v_n;
      elsif length(v_dig) < 9 then                                    -- (3)
        raise exception 'Fila %: el teléfono "%" tiene menos de 9 dígitos.', v_n, v_datos->>'whatsapp';
      end if;

      v_fecha := null;
      if coalesce(v_datos->>'cumpleanos', '') <> '' then
        begin
          v_fecha := (v_datos->>'cumpleanos')::date;
        exception when others then                                    -- (6)
          raise exception 'Fila %: la fecha de cumpleaños "%" no es válida (usa el formato AAAA-MM-DD, por ejemplo 1990-05-17).',
            v_n, v_datos->>'cumpleanos';
        end;
      end if;

      -- Defensa contra una lista desactualizada y contra dos filas iguales EN
      -- ESTE MISMO lote: si ya existe esa clave en el negocio, se descarta y se
      -- cuenta. (Las filas que este mismo lote ya insertó también se ven.)
      if exists (select 1 from clientes
                  where barberia_id = v_barberia and whatsapp_norm = right(v_dig, 9)) then
        v_saltados := v_saltados + 1;
        v_avisos := v_avisos || format('Fila %s: ya existe un cliente con el teléfono %s; no se creó otra ficha.',
                                       v_n, v_datos->>'whatsapp');
        continue;
      end if;

      insert into clientes (barberia_id, nombre, apellido, whatsapp, email, cumpleanos,
                            barbero_preferido, canal, notas, importacion_id)
      values (v_barberia,
              trim(v_datos->>'nombre'),
              nullif(v_datos->>'apellido', ''),
              v_datos->>'whatsapp',
              nullif(v_datos->>'email', ''),
              v_fecha,
              nullif(v_datos->>'barbero_preferido', ''),
              coalesce(nullif(v_datos->>'canal', ''), 'Importado'),
              nullif(v_datos->>'notas', ''),
              v_lote);
      v_creados := v_creados + 1;

    -- ── completar ──
    elsif v_fila->>'accion' = 'completar' then
      begin
        v_cid := (v_fila->>'cliente_id')::uuid;
      exception when others then
        raise exception 'Fila %: el identificador de la ficha a completar no es válido.', v_n;
      end;
      -- La ficha tiene que ser de ESTE negocio: el cliente_id viene del
      -- navegador y no se confía en él.
      select * into v_cliente from clientes
       where id = v_cid and barberia_id = v_barberia
       for update;
      if not found then
        raise exception 'Fila %: la ficha a completar no existe en este negocio.', v_n;
      end if;

      v_cambio := false;
      -- Lista cerrada de campos: nunca se arma SQL con claves que manda el cliente.
      foreach v_campo in array array['apellido','whatsapp','email','cumpleanos','notas','barbero_preferido'] loop
        v_nuevo := nullif(v_datos->>v_campo, '');
        continue when v_nuevo is null;

        -- Se valida lo que llega AUNQUE después no se use: un dato mal formado
        -- es un error del que lo manda, y no conviene dejarlo pasar en silencio.
        if v_campo = 'whatsapp' then
          v_dig := regexp_replace(v_nuevo, '\D', '', 'g');
          if length(v_dig) < 9 then                                   -- (3)
            raise exception 'Fila %: el teléfono "%" tiene menos de 9 dígitos.', v_n, v_nuevo;
          end if;
        elsif v_campo = 'cumpleanos' then
          begin
            perform v_nuevo::date;
          exception when others then                                  -- (6)
            raise exception 'Fila %: la fecha de cumpleaños "%" no es válida (usa el formato AAAA-MM-DD, por ejemplo 1990-05-17).',
              v_n, v_nuevo;
          end;
        end if;

        v_antes := case v_campo
          when 'apellido'          then v_cliente.apellido
          when 'whatsapp'          then v_cliente.whatsapp
          when 'email'             then v_cliente.email
          when 'cumpleanos'        then v_cliente.cumpleanos::text
          when 'notas'             then v_cliente.notas
          when 'barbero_preferido' then v_cliente.barbero_preferido
        end;
        continue when coalesce(trim(v_antes), '') <> '';       -- solo completa VACÍOS: nunca pisa

        -- (2) Un WhatsApp que ya es de OTRA ficha del negocio no se copia aquí:
        -- sería crear un duplicado por la puerta de atrás. Se omite el campo.
        if v_campo = 'whatsapp'
           and exists (select 1 from clientes
                        where barberia_id = v_barberia and id <> v_cliente.id
                          and whatsapp_norm = right(v_dig, 9)) then
          v_saltados := v_saltados + 1;
          v_avisos := v_avisos || format('Fila %s: el WhatsApp %s ya pertenece a otra ficha del negocio; se dejó sin completar.',
                                         v_n, v_nuevo);
          continue;
        end if;

        execute format('update clientes set %I = %L::%s where id = %L',
                       v_campo, v_nuevo, case when v_campo = 'cumpleanos' then 'date' else 'text' end, v_cliente.id);
        insert into importaciones_clientes_cambios
          (importacion_id, barberia_id, cliente_id, campo, valor_antes, valor_despues)
        values (v_lote, v_barberia, v_cliente.id, v_campo, v_antes, v_nuevo);
        v_cambio := true;
      end loop;
      if v_cambio then v_completados := v_completados + 1; end if;

    else
      raise exception 'Fila %: la acción "%" no se reconoce (solo "crear" o "completar").',
        v_n, coalesce(v_fila->>'accion', '(vacía)');
    end if;
  end loop;

  update importaciones_clientes
     set creados = v_creados, completados = v_completados, saltados = v_saltados
   where id = v_lote;

  return jsonb_build_object('importacion_id', v_lote, 'creados', v_creados,
                            'completados', v_completados, 'saltados', v_saltados,
                            'avisos', to_jsonb(v_avisos));
end;
$$;

revoke all on function importar_clientes_lote(text, jsonb) from public, anon;
grant execute on function importar_clientes_lote(text, jsonb) to authenticated;


-- ── 6) Deshacer ──────────────────────────────────────────────────────────
-- Devuelve cuántas fichas borró, cuáles conservó y cuántos campos devolvió.
--
--  · SOLO dentro de los 30 días de creada la importación (5).
--  · Los campos completados se devuelven a su valor de antes SOLO si siguen
--    valiendo lo que puso el lote: si el dueño los editó después, no se pisan.
--  · Las fichas CREADAS por el lote se borran SOLO si no tienen actividad.
--    Con actividad se conservan (y se desligan del lote), y se informan.
--    Actividad = una visita, un nivel VIP, un código de alianza, una encuesta (4)
--    o una reserva con el mismo teléfono.
create or replace function deshacer_importacion_clientes(p_importacion_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_barberia     uuid := auth_barberia_id();
  v_lote         importaciones_clientes%rowtype;
  v_borrados     integer := 0;
  v_devueltos    integer := 0;
  v_conservados  uuid[]  := '{}';
  v_cambio       record;
  v_actual       text;
  v_cli          record;
begin
  if v_barberia is null or auth_rol() <> 'dueno' then
    raise exception 'No tienes permiso para deshacer importaciones: solo el dueño del negocio puede hacerlo.';
  end if;

  -- DECIDIR (C): el mismo bloqueo que importar, para que deshacer no se cruce
  -- con una importación que se está escribiendo en este mismo negocio.
  perform pg_advisory_xact_lock(hashtextextended('importar_clientes:' || v_barberia::text, 0));

  select * into v_lote from importaciones_clientes
   where id = p_importacion_id and barberia_id = v_barberia
   for update;
  if not found then
    raise exception 'No encontramos esa importación en tu negocio.';
  end if;
  if v_lote.estado = 'deshecha' then
    raise exception 'Esa importación ya se deshizo el %.',
      to_char(v_lote.deshecha_en at time zone 'America/Santiago', 'DD-MM-YYYY');
  end if;
  if now() - v_lote.creado_en > interval '30 days' then              -- (5)
    raise exception 'Esta importación se hizo el %, hace más de 30 días, y ya no se puede deshacer.',
      to_char(v_lote.creado_en at time zone 'America/Santiago', 'DD-MM-YYYY');
  end if;

  -- a) campos completados: se devuelven si siguen intactos
  for v_cambio in
    select * from importaciones_clientes_cambios
     where importacion_id = p_importacion_id
  loop
    execute format('select %I::text from clientes where id = %L and barberia_id = %L',
                   v_cambio.campo, v_cambio.cliente_id, v_barberia) into v_actual;
    if v_actual is not distinct from v_cambio.valor_despues then
      execute format('update clientes set %I = %L::%s where id = %L',
                     v_cambio.campo, v_cambio.valor_antes,
                     case when v_cambio.campo = 'cumpleanos' then 'date' else 'text' end,
                     v_cambio.cliente_id);
      v_devueltos := v_devueltos + 1;
    end if;
  end loop;

  -- b) fichas creadas: se borran las que no tienen actividad
  for v_cli in
    select id, whatsapp_norm from clientes
     where importacion_id = p_importacion_id and barberia_id = v_barberia
  loop
    if exists (select 1 from visitas         where cliente_id = v_cli.id)
    or exists (select 1 from vip_historial   where cliente_id = v_cli.id)
    or exists (select 1 from alianza_codigos where cliente_id = v_cli.id)
    or exists (select 1 from encuestas       where cliente_id = v_cli.id)          -- (4)
    or exists (select 1 from reservas
                where barberia_id = v_barberia and whatsapp_norm = v_cli.whatsapp_norm
                  and coalesce(v_cli.whatsapp_norm, '') <> '')
    then
      update clientes set importacion_id = null where id = v_cli.id;   -- se conserva
      v_conservados := v_conservados || v_cli.id;
    else
      delete from clientes where id = v_cli.id;
      v_borrados := v_borrados + 1;
    end if;
  end loop;

  update importaciones_clientes
     set estado = 'deshecha', deshecha_en = now(), deshecha_por = auth.uid()
   where id = p_importacion_id;

  return jsonb_build_object('borrados', v_borrados,
                            'conservados_con_actividad', cardinality(v_conservados),
                            'conservados_ids', to_jsonb(v_conservados),
                            'campos_devueltos', v_devueltos);
end;
$$;

revoke all on function deshacer_importacion_clientes(uuid) from public, anon;
grant execute on function deshacer_importacion_clientes(uuid) to authenticated;


-- ══════════════════════════════════════════════════════════════════════
-- LO QUE FALTA REVISAR ANTES DE EJECUTAR ESTO (no está resuelto en el borrador)
--   · ⚠ DEUDA CONOCIDA: las 5 funciones security definer sin search_path fijo
--     (memoria «Deuda MEDIA: search_path»). Estas dos sí lo fijan; el resto no
--     se toca acá.
--   · `reservas` no se liga a `clientes` por clave foránea sino por
--     whatsapp_norm: por eso el chequeo de actividad compara esa columna.
--   · Las claves foráneas a `clientes` son cuatro: visitas (SET NULL),
--     vip_historial (CASCADE), alianza_codigos (sin acción: BLOQUEARÍA el
--     borrado) y encuestas (SET NULL). Las cuatro están en el chequeo de
--     actividad; si se agrega una tabla nueva que apunte a clientes, hay que
--     sumarla acá.
--   · `clientes.barberia_id` no es NOT NULL en el esquema: la función siempre
--     lo escribe, pero conviene confirmar que no hay filas con NULL.
--   · El índice único (barberia_id, whatsapp_norm) NO está acá. La función
--     verifica duplicados por dentro y el bloqueo evita la carrera, pero el
--     cierre definitivo es el índice que propone migration_fusion_clientes.sql,
--     y va en su propio paso.
--   · Ensayo: SOLO en «ZZ prueba bucket» (archivo aparte, con ROLLBACK).
--
-- ── Reversa (por si hubiera que volver atrás) ───────────────────────────
-- drop function if exists deshacer_importacion_clientes(uuid);
-- drop function if exists importar_clientes_lote(text, jsonb);
-- drop table if exists importaciones_clientes_cambios;
-- alter table clientes drop column if exists importacion_id;
-- drop table if exists importaciones_clientes;
-- ══════════════════════════════════════════════════════════════════════
