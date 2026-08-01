-- Alta directa al Club VIP: permite unirse escaneando un QR en el local,
-- sin tener que reservar una cita primero.
--
-- CONTEXTO. Hasta ahora la única forma de entrar al club era como efecto
-- secundario de reservar en reservar.html (buscar_o_crear_cliente_club, que
-- exige un p_reserva_id). Esta migración abre una segunda puerta que no
-- necesita reserva previa, y reemplaza el ancla del reserva_id por dos
-- protecciones distintas: un token por negocio y un cupo por hora.
--
-- POR QUÉ EL TOKEN NO VA EN "barberias". barberias_select_public es
-- "for select using (true)" y RLS no filtra columnas: una columna de token
-- ahí sería legible por cualquiera con la anon key
-- (GET /rest/v1/barberias?select=id,token). Por eso vive en su propia tabla
-- con RLS cerrada, que solo leen esta función (security definer) y el dueño.
--
-- QUÉ NO TOCA. procesarReserva(), buscar_o_crear_cliente_club y el dedup de
-- reservar.html/club.html siguen con match EXACTO, a propósito: cambiar el
-- dedup real puede fusionar o partir fichas de personas reales y merece su
-- propio análisis. La normalización de acá aplica SOLO a este flujo nuevo.
--
-- Ejecutar UNA VEZ en el SQL Editor de Supabase. Sin begin;/commit; porque
-- define funciones (el editor no aplica dollar-quoting dentro de una
-- transacción explícita y falla en silencio devolviendo éxito).

-- ═══════════════════════════════════════════════════════════════
-- (1) Tabla de tokens, uno por negocio
-- Sin políticas de insert/update/delete: nadie escribe acá desde el
-- navegador. Solo la escribe obtener_club_token() (security definer, que
-- bypasea RLS) y service_role. El select queda scopeado al dueño para que
-- app.html pueda mostrar el link del QR.
-- ═══════════════════════════════════════════════════════════════

create table if not exists club_tokens (
  barberia_id uuid primary key references barberias(id) on delete cascade,
  token text not null unique,
  created_at timestamptz default now()
);

alter table club_tokens enable row level security;

drop policy if exists "club_tokens_select_own" on club_tokens;
create policy "club_tokens_select_own" on club_tokens for select
  using (barberia_id = auth_barberia_id());

-- ═══════════════════════════════════════════════════════════════
-- (2) Columna normalizada de WhatsApp — PURAMENTE ADITIVA
-- Últimos 9 dígitos = el móvil chileno sin el prefijo 56. Mismo criterio que
-- normWsp9() en app.html. Es generada y stored: no hay forma de que quede
-- desincronizada de la columna whatsapp, y no hay que rellenar nada a mano.
--
-- Nada del código existente la lee, así que agregarla no cambia ningún
-- comportamiento actual. La usa solo unirse_club_publico().
--
-- Los 4 formatos que conviven en la base normalizan al mismo valor:
--   '+56 9 8754 2136' | '+56987542136' | '56987542136' | '987542136'
--     -> todos dan '987542136'
--
-- El índice NO es único a propósito: hoy la base está limpia (verificado con
-- el diagnóstico de duplicados, 0 filas), pero las otras puertas de alta
-- siguen con match exacto y pueden crear un duplicado legítimamente. Un
-- índice único los haría fallar con un error opaco en vez de crear la ficha.
-- ═══════════════════════════════════════════════════════════════

alter table clientes
  add column if not exists whatsapp_norm text
  generated always as (right(regexp_replace(coalesce(whatsapp,''), '\D', '', 'g'), 9)) stored;

create index if not exists idx_clientes_barberia_whatsapp_norm
  on clientes (barberia_id, whatsapp_norm);

-- ═══════════════════════════════════════════════════════════════
-- (3) Generador de token
-- Mismo alfabeto sin confusables que generar_codigo_alianza(), pero 16
-- caracteres en vez de 8: aquel se dicta de viva voz en un mostrador y se
-- escribe a mano, este viaja dentro de un QR y nadie lo tipea, así que no hay
-- razón para escatimar entropía. 31^16 ≈ 4e23 combinaciones.
-- No es security definer ni se expone: helper interno de (4).
-- ═══════════════════════════════════════════════════════════════

create or replace function generar_club_token()
returns text
language plpgsql
as $$
declare
  v_chars text := 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';
  v_token text;
begin
  v_token := '';
  for i in 1..16 loop
    v_token := v_token || substr(v_chars, floor(random() * length(v_chars))::int + 1, 1);
  end loop;
  return v_token;
end;
$$;

-- ═══════════════════════════════════════════════════════════════
-- (4) Token del negocio, get-or-create — la llama app.html para armar el QR
-- Get-or-create (mismo patrón que obtener_codigo_alianza_publico) en vez de
-- sembrar tokens en esta migración o de un trigger sobre barberias: así los
-- negocios que se registren MAÑANA también tienen token sin que nadie se
-- acuerde de nada. No recibe barberia_id: lo saca de la sesión, para que un
-- dueño no pueda pedir el token de otro negocio.
--
-- Exige rol 'dueno', mismo criterio que el resto de la configuración del
-- negocio (barberias_update_own, alianzas_update_own, etc.): el token define
-- quién puede dar de alta clientes en el club, así que es configuración, no
-- operación diaria. Un profesional con sesión no lo obtiene.
-- ═══════════════════════════════════════════════════════════════

create or replace function obtener_club_token()
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_barberia uuid := auth_barberia_id();
  v_token text;
begin
  if v_barberia is null then
    raise exception 'Sin negocio en la sesión';
  end if;

  -- "is distinct from" y no "<>": auth_rol() devuelve null si no hay fila en
  -- perfiles, y null <> 'dueno' es null, que no entra al if y dejaría pasar.
  if auth_rol() is distinct from 'dueno' then
    raise exception 'Solo el dueño puede obtener el link del Club VIP';
  end if;

  select token into v_token from club_tokens where barberia_id = v_barberia;
  if found then
    return v_token;
  end if;

  loop
    begin
      v_token := generar_club_token();
      insert into club_tokens (barberia_id, token) values (v_barberia, v_token);
      return v_token;
    exception when unique_violation then
      -- Colisión global de token (rarísima) o dos pestañas del dueño pidiendo
      -- a la vez (la PK de barberia_id la frena). En el segundo caso la fila
      -- ya existe: la traemos y listo.
      select token into v_token from club_tokens where barberia_id = v_barberia;
      if found then
        return v_token;
      end if;
    end;
  end loop;
end;
$$;

-- ═══════════════════════════════════════════════════════════════
-- (5) El alta directa
--
-- ORDEN DE LAS VALIDACIONES, y por qué:
--   token -> nombre -> whatsapp -> ¿ya existe? -> cupo -> insert
--
-- El chequeo de "ya existe" va ANTES del cupo a propósito: alguien que YA es
-- cliente no está creando nada, así que no debe consumir cupo ni quedar
-- bloqueado cuando el cupo se agota. El costo conocido de este orden es que
-- las consultas de existencia no quedan limitadas por el cupo — o sea, se
-- puede sondear si un teléfono es cliente de un negocio sin tope. Es el mismo
-- oráculo de pertenencia que ya introduce la respuesta diferenciada, y
-- cerrarlo requeriría una tabla de intentos (o el captcha, que quedó
-- documentado como escalada). Se acepta a sabiendas.
--
-- QUÉ DEVUELVE. (estado, cliente_id) con estado en 'nuevo' | 'existente'.
-- Cuando es 'existente' el cliente_id va en NULL a propósito: el navegador no
-- debe poder redirigir a la ficha de alguien que ya existía, porque eso haría
-- que conocer un teléfono diera acceso a su nombre, su nivel y sus códigos de
-- canje. Decisión de producto del dueño, 2026-07-31. No devolver el id es lo
-- que hace que esa decisión no dependa de que el frontend se porte bien.
-- ═══════════════════════════════════════════════════════════════

create or replace function unirse_club_publico(
  p_barberia_id uuid,
  p_token text,
  p_nombre text,
  p_whatsapp text,
  p_cumpleanos date default null
)
returns table (estado text, cliente_id uuid)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_token text;
  v_norm text;
  v_canonico text;
  v_existente uuid;
  v_nuevo uuid;
  v_altas int;
  c_cupo_hora constant int := 20;
begin
  select token into v_token from club_tokens where barberia_id = p_barberia_id;
  if v_token is null or p_token is null or v_token <> p_token then
    raise exception 'Este link no es válido. Pídele el QR al negocio';
  end if;

  if p_nombre is null or btrim(p_nombre) = '' then
    raise exception 'Escribe tu nombre';
  end if;

  -- Se exigen exactamente 9 dígitos empezando en 9: el móvil chileno. Un
  -- número fijo o extranjero no entra por acá y lo carga el dueño a mano —
  -- intercambio aceptado para un QR en un local en Chile.
  --
  -- Este largo fijo también elimina de raíz el peligro de matchear por vacío:
  -- una ficha vieja sin whatsapp tiene whatsapp_norm = '', que nunca puede
  -- ser igual a una cadena de 9 caracteres.
  v_norm := right(regexp_replace(coalesce(p_whatsapp,''), '\D', '', 'g'), 9);
  if length(v_norm) <> 9 or substr(v_norm, 1, 1) <> '9' then
    raise exception 'Revisa tu WhatsApp: son 9 dígitos y empieza en 9';
  end if;

  select id into v_existente
  from clientes
  where barberia_id = p_barberia_id and whatsapp_norm = v_norm
  limit 1;

  if v_existente is not null then
    return query select 'existente'::text, null::uuid;
    return;
  end if;

  select count(*) into v_altas
  from clientes
  where barberia_id = p_barberia_id
    and canal = 'Club QR'
    and created_at > now() - interval '1 hour';

  if v_altas >= c_cupo_hora then
    raise exception 'Hubo muchas inscripciones seguidas. Intenta de nuevo en un rato';
  end if;

  -- Se guarda en formato canónico, no como lo escribió la persona: las filas
  -- NUEVAS de este flujo quedan todas iguales. Las viejas no se tocan.
  v_canonico := '+56 ' || substr(v_norm,1,1) || ' ' || substr(v_norm,2,4) || ' ' || substr(v_norm,6,4);

  insert into clientes (barberia_id, nombre, whatsapp, cumpleanos, canal, fecha_registro)
  values (p_barberia_id, btrim(p_nombre), v_canonico, p_cumpleanos, 'Club QR', current_date)
  returning id into v_nuevo;

  return query select 'nuevo'::text, v_nuevo;
end;
$$;

-- ═══════════════════════════════════════════════════════════════
-- (6) Permisos
-- ═══════════════════════════════════════════════════════════════

revoke all on function generar_club_token() from public;

revoke all on function obtener_club_token() from public;
grant execute on function obtener_club_token() to authenticated;

revoke all on function unirse_club_publico(uuid,text,text,text,date) from public;
grant execute on function unirse_club_publico(uuid,text,text,text,date) to anon, authenticated;

-- =============================================================================
-- VERIFICACIÓN — correr DESPUÉS, por separado. No es opcional: el SQL Editor
-- de Supabase puede devolver éxito sin haber aplicado nada.
-- =============================================================================
--
-- PASO 1 — Las tres funciones existen, con la forma esperada.
-- Las tres filas tienen que aparecer; unirse_club_publico y obtener_club_token
-- con es_security_definer = true.
--
-- select proname,
--        prosecdef                       as es_security_definer,
--        proconfig                       as search_path,
--        prosrc like '%whatsapp_norm%'   as usa_la_columna_normalizada,
--        prosrc like '%existente%'       as devuelve_estado,
--        prosrc like '%dueno%'           as exige_rol_dueno
-- from pg_proc
-- where proname in ('unirse_club_publico','obtener_club_token','generar_club_token')
-- order by proname;
--
-- PASO 2 — La columna generada existe y es realmente generada.
-- is_generated tiene que decir ALWAYS.
--
-- select column_name, is_generated, generation_expression
-- from information_schema.columns
-- where table_schema='public' and table_name='clientes' and column_name='whatsapp_norm';
--
-- PASO 3 — La normalización une los cuatro formatos. Inserta, así que va con
-- rollback obligatorio. Las dos filas tienen que mostrar el MISMO
-- whatsapp_norm = '987542136'.
--
-- begin;
--   insert into clientes (barberia_id, nombre, whatsapp, canal)
--   select id, 'Prueba Formato A', '+56 9 8754 2136', 'Prueba' from barberias limit 1;
--
--   insert into clientes (barberia_id, nombre, whatsapp, canal)
--   select id, 'Prueba Formato B', '987542136', 'Prueba' from barberias limit 1;
--
--   select nombre, whatsapp, whatsapp_norm from clientes where canal = 'Prueba';
-- rollback;
--
-- PASO 4 — La RPC rechaza un token inválido. Tiene que fallar con P0001
-- 'Este link no es válido...'. No necesita rollback: no llega a insertar.
--
-- select * from unirse_club_publico(
--   '<id-de-tu-barberia>'::uuid, 'TOKEN-FALSO', 'Prueba', '+56 9 1111 1111', null
-- );
--
-- PASO 5 — La RPC reconoce a un cliente que ya existe y NO devuelve su id.
-- Usa el whatsapp de un cliente real del negocio. Tiene que devolver
-- estado='existente' y cliente_id=null.
--
-- select * from unirse_club_publico(
--   '<id-de-tu-barberia>'::uuid,
--   (select token from club_tokens where barberia_id = '<id-de-tu-barberia>'::uuid),
--   'Prueba', '<whatsapp-de-un-cliente-existente>', null
-- );
--
-- PASO 6 — El alta real funciona, con rollback para no dejar basura.
-- Tiene que devolver estado='nuevo' con un uuid, y la ficha tiene que quedar
-- con whatsapp en formato canónico '+56 9 XXXX XXXX' y canal='Club QR'.
--
-- begin;
--   select * from unirse_club_publico(
--     '<id-de-tu-barberia>'::uuid,
--     (select token from club_tokens where barberia_id = '<id-de-tu-barberia>'::uuid),
--     'Prueba Alta Directa', '9 8888 7777', null
--   );
--   select nombre, whatsapp, whatsapp_norm, canal, fecha_registro
--   from clientes where canal = 'Club QR' and nombre = 'Prueba Alta Directa';
-- rollback;
