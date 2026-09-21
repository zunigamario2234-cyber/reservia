-- PUNTO 1 — El profesional ve su comisión por PRODUCTOS en Mi Agenda.
--
-- Hoy mi_agenda_comisiones lee solo `visitas`, o sea servicios. Los productos
-- que ese mismo profesional vendió viven en `cobro_productos` y no entran en
-- ningún lado de su vista: su comisión por venderlos solo se ve en el panel
-- del dueño.
--
-- ⚠ POR QUÉ SE AMPLÍA LA RPC Y **NO** SE TOCA LA RLS DE cobro_productos
-- Esa tabla tiene RLS solo-dueño (cobro_productos_select_own, con
-- auth_rol() = 'dueno'). Abrirla para que el barbero lea sus filas le daría
-- de paso las ventas de productos de TODOS sus compañeros, porque una policy
-- de select no puede distinguir "mis líneas" sin repetir acá el mismo filtro
-- por barbero_nombre. La RPC ya es SECURITY DEFINER y ya está scopeada por
-- auth_barbero_id(): ampliarla entrega exactamente las filas propias y nada
-- más, sin abrir la tabla a nadie.
--
-- ⚠ POR QUÉ DROP Y NO SOLO "CREATE OR REPLACE"
-- Cambia el RETURNS TABLE (entra la columna `tipo`), y Postgres no deja
-- cambiar el tipo de retorno con un replace. El DROP **pierde los permisos**,
-- así que el revoke/grant del final no es decorativo: sin él la función queda
-- sin el grant a authenticated y Mi Agenda deja de cargar las comisiones.
--
-- Ejecutar UNA VEZ, completo, en el SQL Editor de Supabase.


-- ═══════════════════════════════════════════════════════════════
-- (0) ANTES DE APLICAR — mirar qué hay hoy en la base.
--
-- El repo puede estar atrasado respecto de la base (ya pasó con
-- buscar_o_crear_cliente_club, que en esquema_actual.sql no guardaba el
-- email y en la base sí). Correr esto SOLO —no escribe nada— y comparar el
-- cuerpo con el que este archivo reemplaza. Si no coincide con la versión de
-- migration_mi_agenda.sql, parar y avisar antes de seguir.
--
--   select pg_get_functiondef(p.oid)
--   from pg_proc p join pg_namespace n on n.oid = p.pronamespace
--   where n.nspname = 'public' and p.proname = 'mi_agenda_comisiones';
-- ═══════════════════════════════════════════════════════════════


-- ═══════════════════════════════════════════════════════════════
-- (1) La función, ampliada.
-- ═══════════════════════════════════════════════════════════════

drop function if exists mi_agenda_comisiones(date, date);

create or replace function mi_agenda_comisiones(
  p_desde date default null,
  p_hasta date default null
)
returns table (
  tipo text,
  fecha date,
  servicio text,
  valor numeric,
  comision_monto numeric,
  estado text
)
language sql
stable
security definer
set search_path = public
as $function$
  -- Los servicios: exactamente el select que ya existía, con el
  -- discriminador nuevo delante. No cambia ni un filtro.
  select 'servicio'::text, v.fecha, v.servicio, v.valor, v.comision_monto, v.estado
  from visitas v
  where v.barberia_id = auth_barberia_id()
    and v.barbero_nombre = (select b.nombre from barberos b where b.id = auth_barbero_id())
    and auth_barbero_id() is not null
    and (p_desde is null or v.fecha >= p_desde)
    and (p_hasta is null or v.fecha <= p_hasta)

  union all

  -- Los productos. El filtro es el MISMO de arriba, columna por columna:
  -- barberia_id contra auth_barberia_id() y barbero_nombre contra el nombre
  -- del barbero logueado. `cobro_productos.valor` significa lo mismo que
  -- `visitas.valor` (bruto con IVA incluido, ya descontado, sin propina), así
  -- que los dos lados del union son sumables entre sí sin convertir nada.
  --
  -- El nombre del producto viaja en la columna `servicio` a propósito: el
  -- front ya agrupa por esa columna, y `tipo` es lo que los separa en dos
  -- bloques. El left join es left y no inner para que una línea cuyo producto
  -- se haya borrado del inventario no desaparezca de la comisión — la plata
  -- se pagó igual.
  select 'producto'::text, cp.fecha,
         coalesce(i.nombre, 'Producto'),
         cp.valor, cp.comision_monto, 'Vendido'::text
  from cobro_productos cp
  left join inventario i on i.id = cp.producto_id
  where cp.barberia_id = auth_barberia_id()
    and cp.barbero_nombre = (select b.nombre from barberos b where b.id = auth_barbero_id())
    and auth_barbero_id() is not null
    and (p_desde is null or cp.fecha >= p_desde)
    and (p_hasta is null or cp.fecha <= p_hasta)

  -- Por POSICIÓN y no por nombre: `fecha` es a la vez columna de las dos
  -- tablas y nombre de salida del RETURNS TABLE, y escribirlo suelto lo deja
  -- ambiguo.
  order by 2 desc
$function$;


-- ═══════════════════════════════════════════════════════════════
-- (2) Permisos — el DROP de arriba se los llevó.
--
-- Las dos líneas de revoke hacen falta y la segunda NO es redundante:
-- Supabase trae default privileges en el esquema public que otorgan EXECUTE
-- sobre toda función nueva a anon y authenticated. Eso es un grant EXPLÍCITO
-- A CADA ROL, no heredado de PUBLIC, así que quitárselo a PUBLIC deja el de
-- anon intacto. Verificado el 2026-09-11 con has_function_privilege.
-- ═══════════════════════════════════════════════════════════════

revoke all on function mi_agenda_comisiones(date,date) from public;
revoke all on function mi_agenda_comisiones(date,date) from anon;
grant execute on function mi_agenda_comisiones(date,date) to authenticated;


-- ═══════════════════════════════════════════════════════════════
-- (3) VERIFICACIÓN — no escribe nada, se puede correr suelta.
--
--   a) La firma nueva quedó, con la columna `tipo`:
--
--      select p.proname,
--             pg_get_function_result(p.oid) like '%tipo text%' as tiene_tipo,
--             p.prosrc like '%cobro_productos%'                as lee_productos,
--             p.prosecdef                                      as security_definer,
--             p.proconfig                                      as search_path
--      from pg_proc p join pg_namespace n on n.oid = p.pronamespace
--      where n.nspname = 'public' and p.proname = 'mi_agenda_comisiones';
--
--      Esperado: tiene_tipo t, lee_productos t, security_definer t,
--                search_path {search_path=public}
--
--   b) Los permisos volvieron, y anon NO quedó adentro:
--
--      select has_function_privilege('authenticated',
--               'mi_agenda_comisiones(date,date)', 'execute') as authenticated,
--             has_function_privilege('anon',
--               'mi_agenda_comisiones(date,date)', 'execute') as anon;
--
--      Esperado: authenticated t, anon f
--
--   c) La RLS de cobro_productos quedó intacta (sigue siendo solo-dueño):
--
--      select polname, pg_get_expr(polqual, polrelid) as using_expr
--      from pg_policy
--      where polrelid = 'public.cobro_productos'::regclass;
--
--      Esperado: cobro_productos_select_own y cobro_productos_delete_own,
--                las dos con auth_rol() = 'dueno' en el using.
-- ═══════════════════════════════════════════════════════════════
