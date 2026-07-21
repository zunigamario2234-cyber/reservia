-- Niveles VIP configurables por negocio (reemplaza Plata/Oro/Diamante
-- hardcodeados). Ejecutar UNA VEZ, completo, en el SQL Editor de Supabase.
--
-- Cada tabla tiene una política separada por operación (select/insert/
-- update/delete). Ninguna es "for all using(true)" — ver
-- migration_cleanup_rls.sql sobre por qué ese patrón es peligroso.

-- ═══════════════════════════════════════════════════════════════
-- Tabla "niveles_vip": lectura pública (la necesita club.html sin
-- login para calcular ícono/beneficio/próxima-meta), escritura solo
-- del dueño. Sin PII, mismo criterio que servicios/horario_negocio/
-- bloqueos_profesional/alianzas.
-- ═══════════════════════════════════════════════════════════════

create table if not exists niveles_vip (
  id uuid primary key default gen_random_uuid(),
  barberia_id uuid not null references barberias(id),
  orden int not null,
  nombre text not null,
  visitas_minimas int not null,
  beneficio text,
  created_at timestamptz not null default now(),
  unique(barberia_id, orden)
);

alter table niveles_vip enable row level security;
create policy "niveles_vip_select_public" on niveles_vip for select using (true);
create policy "niveles_vip_insert_own" on niveles_vip for insert with check (barberia_id = auth_barberia_id());
create policy "niveles_vip_update_own" on niveles_vip for update using (barberia_id = auth_barberia_id()) with check (barberia_id = auth_barberia_id());
create policy "niveles_vip_delete_own" on niveles_vip for delete using (barberia_id = auth_barberia_id());

-- Seed: cada negocio existente recibe los 3 niveles actuales, para que
-- nadie quede sin niveles configurados de un día para otro. Inofensivo
-- para negocios que no usan el Club VIP (el rubro sigue controlando si
-- la sección se muestra).
insert into niveles_vip (barberia_id, orden, nombre, visitas_minimas, beneficio)
select id, 1, 'Plata', 5, '10% descuento' from barberias
union all
select id, 2, 'Oro', 10, 'Servicio gratis' from barberias
union all
select id, 3, 'Diamante', 20, 'VIP total' from barberias;

-- ═══════════════════════════════════════════════════════════════
-- Plantillas de mensaje: se enganchan por posición ('Club nivel N',
-- N = orden), no por nombre — así siguen disparando aunque el negocio
-- renombre un nivel. Renombra las filas existentes para no cortar los
-- mensajes de negocios que ya los tenían configurados.
-- ═══════════════════════════════════════════════════════════════

update plantillas_mensajes set evento='Club nivel 1' where evento='Club Plata';
update plantillas_mensajes set evento='Club nivel 2' where evento='Club Oro';
update plantillas_mensajes set evento='Club nivel 3' where evento='Club Diamante';

-- ═══════════════════════════════════════════════════════════════
-- Alianzas: nivel_minimo pasa de texto fijo a referencia por ID.
-- "on delete set null": si se borra el nivel referenciado, la alianza
-- cae a null (= "Todos", sin restricción) en vez de romperse.
-- ═══════════════════════════════════════════════════════════════

alter table alianzas add column if not exists nivel_minimo_id uuid references niveles_vip(id) on delete set null;

update alianzas a
set nivel_minimo_id = nv.id
from niveles_vip nv
where nv.barberia_id = a.barberia_id
  and nv.nombre = a.nivel_minimo
  and a.nivel_minimo in ('Plata','Oro','Diamante');
-- 'Todos' (o cualquier otro valor) queda nivel_minimo_id = null,
-- que ya significa "sin restricción" — mismo comportamiento de hoy.

alter table alianzas drop column nivel_minimo;

-- ═══════════════════════════════════════════════════════════════
-- Redefine get_club_vip_publico (creada en migration_alianzas.sql):
-- el nivel ya no sale de un case fijo 20/10/5, sale de niveles_vip.
-- Mismos parámetros y firma que antes, mismo criterio de seguridad
-- (security definer, exige barberia_id Y cliente_id).
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
  with base as (
    select
      c.id as cliente_id,
      c.barberia_id,
      c.nombre,
      count(v.id) as total_visitas
    from clientes c
    left join visitas v on v.cliente_id = c.id
    where c.id = p_cliente_id
      and c.barberia_id = p_barberia_id
    group by c.id, c.barberia_id, c.nombre
  )
  select
    base.cliente_id,
    base.barberia_id,
    base.nombre,
    base.total_visitas,
    coalesce(
      (
        select nv.nombre
        from niveles_vip nv
        where nv.barberia_id = base.barberia_id
          and nv.visitas_minimas <= base.total_visitas
        order by nv.orden desc
        limit 1
      ),
      'Sin nivel'
    ) as nivel
  from base;
$$;

revoke all on function get_club_vip_publico(uuid, uuid) from public;
grant execute on function get_club_vip_publico(uuid, uuid) to anon, authenticated;
