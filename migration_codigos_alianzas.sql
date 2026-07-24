-- Códigos de canje para Alianzas, en las dos direcciones:
--   A) Cliente de la barbería canjea en el aliado — código corto persistente
--      por (cliente, alianza), reutilizable, cada canje queda registrado
--      aparte con fecha.
--   B) Cliente del aliado canjea en la barbería — código genérico sin
--      nombre asociado (el aliado no registra clientes en Reservia),
--      de un solo uso.
--
-- Ejecutar UNA VEZ, completo, en el SQL Editor de Supabase.

-- ═══════════════════════════════════════════════════════════════
-- (1) Columna nueva en alianzas: qué recibe el cliente DEL ALIADO en la
-- barbería (dirección B). Las columnas existentes (descripcion/beneficio)
-- ya describen la dirección A — qué recibe el cliente de la barbería en
-- el aliado — así que esto no las reemplaza, es el campo simétrico.
-- ═══════════════════════════════════════════════════════════════

alter table alianzas add column if not exists beneficio_reciproco text;

-- ═══════════════════════════════════════════════════════════════
-- (2) Tablas nuevas
-- ═══════════════════════════════════════════════════════════════

create table alianza_codigos (
  id uuid primary key default gen_random_uuid(),
  barberia_id uuid not null references barberias(id),
  alianza_id uuid not null references alianzas(id),
  cliente_id uuid references clientes(id),  -- null = genérico (dirección B)
  tipo text not null check (tipo in ('cliente','generico')),
  codigo text not null unique,
  activo boolean not null default true,
  created_at timestamptz not null default now()
);

-- Un solo código persistente por cliente+alianza (dirección A). No aplica
-- a los genéricos (dirección B): cada llamada de generar_codigo_generico_publico
-- crea una fila nueva a propósito.
create unique index alianza_codigos_unico_por_cliente
  on alianza_codigos(alianza_id, cliente_id) where tipo = 'cliente';

create table alianza_canjes (
  id uuid primary key default gen_random_uuid(),
  codigo_id uuid not null references alianza_codigos(id),
  barberia_id uuid not null references barberias(id),
  fecha timestamptz not null default now()
);

-- ═══════════════════════════════════════════════════════════════
-- (3) RLS. A diferencia de "alianzas" (select público a propósito, la
-- promo es información pública), acá nada se lee ni se escribe en forma
-- directa desde el cliente ni desde el aliado — ninguno de los dos tiene
-- sesión. Toda esa interacción pasa por los RPC security definer de más
-- abajo. Lo único que exponen estas policies es la lectura del propio
-- dueño/staff, para gestión y reportes.
-- ═══════════════════════════════════════════════════════════════

alter table alianza_codigos enable row level security;
create policy "alianza_codigos_select_own" on alianza_codigos for select using (barberia_id = auth_barberia_id());
create policy "alianza_codigos_update_own" on alianza_codigos for update using (barberia_id = auth_barberia_id()) with check (barberia_id = auth_barberia_id());
create policy "alianza_codigos_delete_own" on alianza_codigos for delete using (barberia_id = auth_barberia_id());

alter table alianza_canjes enable row level security;
create policy "alianza_canjes_select_own" on alianza_canjes for select using (barberia_id = auth_barberia_id());

-- ═══════════════════════════════════════════════════════════════
-- (4) Generador de código corto: 8 caracteres, alfabeto de 32 símbolos sin
-- confusables (sin 0/O, 1/I/L), ≈1 billón de combinaciones — más espacio
-- que el whatsapp-como-identificador de club.html (10 dígitos). No es
-- security definer ni se expone: es un helper interno de los RPC de abajo.
-- ═══════════════════════════════════════════════════════════════

create or replace function generar_codigo_alianza()
returns text
language plpgsql
as $$
declare
  v_chars text := 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';
  v_codigo text;
begin
  v_codigo := '';
  for i in 1..8 loop
    v_codigo := v_codigo || substr(v_chars, floor(random() * length(v_chars))::int + 1, 1);
  end loop;
  return v_codigo;
end;
$$;

-- ═══════════════════════════════════════════════════════════════
-- (5) Dirección A — club.html: get-or-create del código persistente del
-- cliente para esa alianza. p_barberia_id llega igual que en
-- get_club_vip_publico (además de p_cliente_id) para exigir el scoping
-- completo, nunca un solo id.
-- ═══════════════════════════════════════════════════════════════

create or replace function obtener_codigo_alianza_publico(p_barberia_id uuid, p_cliente_id uuid, p_alianza_id uuid)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_codigo text;
begin
  if not exists (select 1 from clientes where id = p_cliente_id and barberia_id = p_barberia_id) then
    raise exception 'Cliente inválido';
  end if;
  if not exists (select 1 from alianzas where id = p_alianza_id and barberia_id = p_barberia_id and activo = true) then
    raise exception 'Alianza inválida';
  end if;

  select codigo into v_codigo from alianza_codigos
    where alianza_id = p_alianza_id and cliente_id = p_cliente_id and tipo = 'cliente';
  if found then
    return v_codigo;
  end if;

  loop
    begin
      v_codigo := generar_codigo_alianza();
      insert into alianza_codigos (barberia_id, alianza_id, cliente_id, tipo, codigo)
        values (p_barberia_id, p_alianza_id, p_cliente_id, 'cliente', v_codigo);
      return v_codigo;
    exception when unique_violation then
      -- colisión de código global (rarísima) o llamada concurrente duplicada
      -- para el mismo cliente+alianza (el índice parcial la frena) — en ese
      -- segundo caso ya existe la fila, así que la traemos y listo.
      select codigo into v_codigo from alianza_codigos
        where alianza_id = p_alianza_id and cliente_id = p_cliente_id and tipo = 'cliente';
      if found then
        return v_codigo;
      end if;
    end;
  end loop;
end;
$$;

revoke all on function obtener_codigo_alianza_publico(uuid,uuid,uuid) from public;
grant execute on function obtener_codigo_alianza_publico(uuid,uuid,uuid) to anon, authenticated;

-- ═══════════════════════════════════════════════════════════════
-- (6) Dirección A — aliado.html: validar el código del cliente. Nunca
-- devuelve la fila de clientes, solo el primer nombre.
-- ═══════════════════════════════════════════════════════════════

create or replace function validar_codigo_alianza_publico(p_barberia_id uuid, p_alianza_id uuid, p_codigo text)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_codigo_id uuid;
  v_cliente_id uuid;
  v_nombre text;
begin
  select id, cliente_id into v_codigo_id, v_cliente_id from alianza_codigos
    where codigo = upper(trim(p_codigo))
      and alianza_id = p_alianza_id
      and barberia_id = p_barberia_id
      and tipo = 'cliente'
      and activo = true
      -- alianza desactivada cae acá también (mismo "not found"), nunca en
      -- una rama de error aparte, para no filtrarle esa distinción a
      -- alguien que esté probando códigos al azar.
      and exists (select 1 from alianzas a where a.id = p_alianza_id and a.barberia_id = p_barberia_id and a.activo = true);

  if not found then
    raise exception 'Código inválido';
  end if;

  select split_part(trim(nombre), ' ', 1) into v_nombre from clientes where id = v_cliente_id;

  insert into alianza_canjes (codigo_id, barberia_id) values (v_codigo_id, p_barberia_id);

  return v_nombre;
end;
$$;

revoke all on function validar_codigo_alianza_publico(uuid,uuid,text) from public;
grant execute on function validar_codigo_alianza_publico(uuid,uuid,text) to anon, authenticated;

-- ═══════════════════════════════════════════════════════════════
-- (7) Dirección B — aliado.html: generar un código genérico nuevo para
-- dárselo a un cliente del aliado. Nunca get-or-create: cada llamada es
-- un cliente distinto pidiendo un código para llevar a la barbería.
-- ═══════════════════════════════════════════════════════════════

create or replace function generar_codigo_generico_publico(p_barberia_id uuid, p_alianza_id uuid)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_codigo text;
begin
  if not exists (select 1 from alianzas where id = p_alianza_id and barberia_id = p_barberia_id and activo = true) then
    raise exception 'Alianza inválida';
  end if;

  loop
    begin
      v_codigo := generar_codigo_alianza();
      insert into alianza_codigos (barberia_id, alianza_id, cliente_id, tipo, codigo)
        values (p_barberia_id, p_alianza_id, null, 'generico', v_codigo);
      return v_codigo;
    exception when unique_violation then
      -- colisión de código global (rarísima) — reintenta con uno nuevo.
    end;
  end loop;
end;
$$;

revoke all on function generar_codigo_generico_publico(uuid,uuid) from public;
grant execute on function generar_codigo_generico_publico(uuid,uuid) to anon, authenticated;

-- ═══════════════════════════════════════════════════════════════
-- (8) Dirección B — app.html (Config → Alianzas): el dueño/staff valida el
-- código que trajo el cliente del aliado. Autenticado, identidad solo por
-- auth_barberia_id() (nunca recibida como parámetro, mismo molde que
-- mi_agenda_procesar_pago). De un solo uso: se desactiva al validarlo, y
-- si ya estaba desactivado se lo decimos explícito (no es info sensible,
-- es una cortesía para el staff — a diferencia del código inválido, que si
-- no se distingue).
-- ═══════════════════════════════════════════════════════════════

create or replace function validar_codigo_alianza_negocio(p_alianza_id uuid, p_codigo text)
returns timestamptz
language plpgsql
security definer
set search_path = public
as $$
declare
  v_barberia uuid := auth_barberia_id();
  v_codigo_id uuid;
  v_activo boolean;
  v_fecha timestamptz;
begin
  if v_barberia is null then
    raise exception 'No autorizado';
  end if;

  select id, activo into v_codigo_id, v_activo from alianza_codigos
    where codigo = upper(trim(p_codigo))
      and alianza_id = p_alianza_id
      and barberia_id = v_barberia
      and tipo = 'generico'
      -- alianza desactivada cae en "not found" (Código inválido), nunca en
      -- la rama de "ya fue usado" — esa distinción es una cortesía para el
      -- staff autenticado, no algo que corresponda mezclar con el estado
      -- de la alianza.
      and exists (select 1 from alianzas a where a.id = p_alianza_id and a.barberia_id = v_barberia and a.activo = true);

  if not found then
    raise exception 'Código inválido';
  end if;
  if not v_activo then
    raise exception 'Este código ya fue usado';
  end if;

  update alianza_codigos set activo = false where id = v_codigo_id;
  insert into alianza_canjes (codigo_id, barberia_id) values (v_codigo_id, v_barberia)
    returning fecha into v_fecha;

  return v_fecha;
end;
$$;

revoke all on function validar_codigo_alianza_negocio(uuid,text) from public;
grant execute on function validar_codigo_alianza_negocio(uuid,text) to authenticated;
