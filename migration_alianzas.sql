-- Alianzas (convenios con negocios externos) + vistas públicas para
-- club.html (la página de "Mi Club VIP" que ve el cliente final, sin login).
-- Ejecutar UNA VEZ, completo, en el SQL Editor de Supabase.

-- ═══════════════════════════════════════════════════════════════
-- Tabla "alianzas": igual patrón que "servicios"/"barberos" — lectura
-- pública (la necesita club.html sin login), escritura solo del dueño.
-- ═══════════════════════════════════════════════════════════════

create table if not exists alianzas (
  id uuid primary key default gen_random_uuid(),
  barberia_id uuid not null references barberias(id),
  nombre text not null,
  descripcion text,
  beneficio text,
  nivel_minimo text not null default 'Todos', -- 'Todos' | 'Plata' | 'Oro' | 'Diamante'
  logo_url text,
  link text,
  activo boolean not null default true,
  created_at timestamptz not null default now()
);

alter table alianzas enable row level security;
create policy "alianzas_select_public" on alianzas for select using (true);
create policy "alianzas_insert_own" on alianzas for insert with check (barberia_id = auth_barberia_id());
create policy "alianzas_update_own" on alianzas for update using (barberia_id = auth_barberia_id()) with check (barberia_id = auth_barberia_id());
create policy "alianzas_delete_own" on alianzas for delete using (barberia_id = auth_barberia_id());

-- ═══════════════════════════════════════════════════════════════
-- Funciones RPC públicas para club.html — NO vistas.
--
-- Una vista pública (select using(true)) queda expuesta también como
-- endpoint REST sin filtro obligatorio: GET /rest/v1/club_vip_publico
-- sin parámetros devolvería la tabla ENTERA (clientes, niveles VIP e
-- historial de TODOS los negocios) a cualquiera con la anon key, que
-- es pública en el JS del frontend. Que club.html siempre la consulte
-- filtrada no es una barrera real — cualquiera puede pegarle directo
-- al REST endpoint sin pasar por la página.
--
-- Por eso estas dos son funciones "security definer" que EXIGEN
-- barberia_id y cliente_id como parámetros obligatorios (no hay forma
-- de invocarlas sin ambos) y devuelven como máximo la fila de ESE
-- cliente puntual — nunca un listado. Si cliente_id no pertenece a
-- barberia_id, el where las filtra y devuelven 0 filas (no error).
--
-- El umbral de nivel (5/10/20 visitas) está duplicado acá a propósito
-- para que club.html pueda calcularlo sin depender de app.html. Si
-- cambian los umbrales en getNivel() (app.html), hay que actualizar
-- también este case.
-- ═══════════════════════════════════════════════════════════════

create or replace function get_club_vip_publico(p_barberia_id uuid, p_cliente_id uuid)
returns table (
  cliente_id uuid,
  barberia_id uuid,
  nombre text,
  total_visitas bigint,
  nivel text
)
language sql
security definer
set search_path = public
as $$
  select
    c.id as cliente_id,
    c.barberia_id,
    c.nombre,
    count(v.id) as total_visitas,
    case
      when count(v.id) >= 20 then 'Diamante'
      when count(v.id) >= 10 then 'Oro'
      when count(v.id) >= 5 then 'Plata'
      else 'Sin nivel'
    end as nivel
  from clientes c
  left join visitas v on v.cliente_id = c.id
  where c.id = p_cliente_id
    and c.barberia_id = p_barberia_id
  group by c.id, c.barberia_id, c.nombre;
$$;

revoke all on function get_club_vip_publico(uuid, uuid) from public;
grant execute on function get_club_vip_publico(uuid, uuid) to anon, authenticated;

create or replace function get_club_vip_historial_publico(p_barberia_id uuid, p_cliente_id uuid)
returns table (
  id uuid,
  cliente_id uuid,
  barberia_id uuid,
  nivel text,
  beneficio text,
  fecha_ganado timestamptz,
  fecha_expira timestamptz,
  canjeado boolean
)
language sql
security definer
set search_path = public
as $$
  select id, cliente_id, barberia_id, nivel, beneficio, fecha_ganado, fecha_expira, canjeado
  from vip_historial
  where cliente_id = p_cliente_id
    and barberia_id = p_barberia_id
  order by fecha_ganado desc;
$$;

revoke all on function get_club_vip_historial_publico(uuid, uuid) from public;
grant execute on function get_club_vip_historial_publico(uuid, uuid) to anon, authenticated;
