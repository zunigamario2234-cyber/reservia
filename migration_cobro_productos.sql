-- Entrega 2: productos del inventario en el mismo cobro que las reservas.
--
-- Continúa migration_cobro_conjunto.sql (Entrega 1), que ya dejó visitas.cobro_id
-- y registrar_cobro_conjunto(). Acá se agregan los productos, su comisión y el
-- descuento de stock.
--
-- ═══════════════════════════════════════════════════════════════
-- POR QUÉ LOS PRODUCTOS NO VAN COMO FILAS DE `visitas`
-- Sería lo más cómodo para el IVA y los reportes, que ya suman visitas.valor.
-- Pero `visitas` también alimenta el CONTEO de citas: getCitas() decide los
-- niveles del Club VIP, y renderProfesionals() las metas. Un cliente que compra
-- cinco shampoos subiría a Plata sin haberse cortado el pelo nunca, en silencio
-- y sin forma de notarlo hasta que reclame un beneficio que no le corresponde.
-- Por eso los productos viven aparte, y del lado del navegador se arma un
-- S.ventas que une las dos fuentes SOLO para los lectores de ingresos.
--
-- LA INVARIANTE QUE HACE QUE ESO FUNCIONE
-- cobro_productos.valor significa EXACTAMENTE lo mismo que visitas.valor: lo
-- que pagó el cliente por esa línea, bruto (con IVA incluido), ya descontado y
-- sin propina. Gracias a eso sumar ingresos es sumar dos columnas con el mismo
-- significado, y ivaDe() sirve sin tocarse. Ver [[reservia-iva-precio-bruto]].
--
-- ═══════════════════════════════════════════════════════════════
-- POR QUÉ LA FIRMA DE LA RPC NO CAMBIA
-- Agregar un cuarto parámetro p_productos CREARÍA una función nueva: Postgres
-- trata distinta aridad como sobrecarga, no como reemplazo. Quedarían dos
-- versiones conviviendo, y dropear la vieja abriría una ventana en la que el
-- frontend ya desplegado no puede cobrar nada.
--
-- En vez de eso p_lineas —que ya es jsonb— gana un discriminador por elemento:
--
--   {"tipo":"reserva",  "reserva_id":…, "valor":…, "precio_lista":…, "propina":…}
--   {"tipo":"producto", "producto_id":…, "cantidad":2, "precio_unitario":…,
--    "valor":…, "barbero_nombre":"Mario"}
--
-- Un elemento SIN "tipo" se trata como reserva, así que el frontend actual
-- sigue funcionando igual mientras se despliega el nuevo. create or replace
-- puro, sin drop y sin ventana de ruptura.
--
-- ═══════════════════════════════════════════════════════════════
-- DECISIONES DE NEGOCIO, TOMADAS CON EL DUEÑO
--   · El producto paga comisión al profesional QUE LO VENDIÓ, con su propio
--     porcentaje (barberos.comision_producto_pct, default 0). NO se reusa
--     comision_pct, que es el de servicios: sobre un shampoo de $10.000 al 50%
--     el negocio entregaría $5.000, casi seguro más de lo que deja el producto.
--     Con default 0 nadie cobra comisión de producto hasta que el dueño la
--     active explícitamente.
--   · El profesional de cada producto es OBLIGATORIO y no se preselecciona.
--     Un clic más por línea, pero nadie se lleva comisión por omisión — que es
--     justo el riesgo en el caso padre/hijo con profesionales distintos.
--   · El descuento del cobro se imputa SOLO a los servicios; los productos van
--     a precio lleno. Así ningún profesional ve bajar su comisión por el
--     descuento de un producto que no vendió. En el reporte dividido eso se ve
--     como que servicios rinde menos y productos aparece entero: es el precio
--     aceptado a sabiendas de esa protección.
--
-- ⚠ SIGUE SIN UNIFICARSE la lógica de comisión (deudas #1 y #2). Esta RPC
-- repite el mismo cálculo por tercera vez dentro del archivo. Decisión del
-- dueño: no crece el alcance acá, se resuelve junto con Mi Agenda en su tarea.
--
-- ═══════════════════════════════════════════════════════════════
-- ⚠ CÓMO SE CORRE
-- Define funciones con dollar-quoting, así que va SIN begin;/commit; — esa
-- combinación el SQL Editor de Supabase la falla en silencio devolviendo
-- éxito. Correr completo, de una, y después verificar con los pasos del final.
--
-- ⚠ ANTES DE CORRER: el PASO 0 de abajo no es opcional. El índice único de
-- código falla si hay duplicados, y el autogenerador de app.html
-- ('PRD-' + length+1) puede haberlos creado desde el último chequeo.


-- ═══════════════════════════════════════════════════════════════
-- (1) Comisión de productos por profesional
-- ═══════════════════════════════════════════════════════════════

alter table public.barberos
  add column if not exists comision_producto_pct numeric not null default 0;

alter table public.barberos
  drop constraint if exists barberos_comision_producto_pct_rango;
alter table public.barberos
  add constraint barberos_comision_producto_pct_rango
    check (comision_producto_pct >= 0 and comision_producto_pct <= 100);

comment on column public.barberos.comision_producto_pct is
  'Porcentaje de comisión por venta de productos. Default 0: nadie cobra hasta que el dueño lo active. Es OTRO porcentaje que comision_pct, que aplica a servicios.';


-- ═══════════════════════════════════════════════════════════════
-- (2) Código de producto único POR NEGOCIO
-- Nunca global: dos barberías distintas tienen que poder usar ambas "PRD-001".
-- Parcial porque la columna es nullable y un producto sin código es legítimo.
-- ═══════════════════════════════════════════════════════════════

create unique index if not exists inventario_codigo_unico
  on public.inventario (barberia_id, codigo) where codigo is not null;


-- ═══════════════════════════════════════════════════════════════
-- (3) Las líneas de producto de cada cobro
-- ═══════════════════════════════════════════════════════════════

create table if not exists public.cobro_productos (
  id uuid primary key default gen_random_uuid(),
  cobro_id uuid not null,
  barberia_id uuid not null references barberias(id) on delete cascade,
  producto_id uuid not null references inventario(id),
  barbero_nombre text not null,
  cantidad integer not null,
  precio_unitario numeric not null,
  descuento_monto numeric not null default 0,
  valor numeric not null,
  comision_monto numeric not null default 0,
  fecha date not null,
  created_at timestamptz not null default now(),
  constraint cobro_productos_cantidad_positiva check (cantidad > 0),
  constraint cobro_productos_valor_no_negativo check (valor >= 0),
  constraint cobro_productos_descuento_no_negativo check (descuento_monto >= 0)
);

comment on table public.cobro_productos is
  'Líneas de producto de un cobro. valor tiene el MISMO significado que visitas.valor: bruto con IVA incluido, ya descontado, sin propina.';

-- Se agrupa por cobro_id igual que las visitas, y se filtra por mes para el
-- IVA y los reportes.
create index if not exists cobro_productos_cobro_id_idx on public.cobro_productos (cobro_id);
create index if not exists cobro_productos_barberia_fecha_idx on public.cobro_productos (barberia_id, fecha);

-- RLS con el mismo molde que el resto del inventario: solo el dueño, y nada
-- se escribe directo desde el cliente — todo pasa por la RPC de abajo.
alter table public.cobro_productos enable row level security;

drop policy if exists cobro_productos_select_own on public.cobro_productos;
create policy cobro_productos_select_own on public.cobro_productos
  for select using (barberia_id = auth_barberia_id() and auth_rol() = 'dueno');

drop policy if exists cobro_productos_delete_own on public.cobro_productos;
create policy cobro_productos_delete_own on public.cobro_productos
  for delete using (barberia_id = auth_barberia_id() and auth_rol() = 'dueno');


-- ═══════════════════════════════════════════════════════════════
-- (4) La RPC, ampliada. Misma firma que en la Entrega 1.
-- ═══════════════════════════════════════════════════════════════

create or replace function registrar_cobro_conjunto(
  p_lineas jsonb,
  p_metodo_pago text,
  p_total_declarado numeric
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_barberia uuid := auth_barberia_id();
  v_cobro_id uuid := gen_random_uuid();
  v_linea jsonb;
  v_tipo text;
  v_reserva reservas%rowtype;
  v_cliente_id uuid;
  v_fecha date;
  v_valor numeric;
  v_propina numeric;
  v_suma numeric := 0;
  v_comision_pct numeric;
  v_modo_comision text;
  v_iva_pct numeric;
  v_base numeric;
  v_comision_monto numeric;
  -- Productos
  v_producto_id uuid;
  v_prod_nombre text;
  v_cantidad integer;
  v_precio_unitario numeric;
  v_barbero_nombre text;
  v_hay_reserva boolean := false;
begin
  if v_barberia is null or auth_rol() <> 'dueno' then
    raise exception 'No autorizado';
  end if;
  if p_lineas is null or jsonb_array_length(p_lineas) = 0 then
    raise exception 'El cobro no tiene ninguna línea';
  end if;

  select modo_comision, iva_pct into v_modo_comision, v_iva_pct
    from barberias where id = v_barberia;

  -- ── PASADA 1: las reservas ────────────────────────────────────────────
  -- Van primero para que v_fecha quede resuelta antes de los productos, que
  -- heredan la fecha del cobro. Si se recorriera una sola vez, un producto
  -- listado antes de la reserva se guardaría con fecha nula.
  for v_linea in select * from jsonb_array_elements(p_lineas) loop
    v_tipo := coalesce(v_linea->>'tipo', 'reserva');
    if v_tipo <> 'reserva' then
      continue;
    end if;
    v_hay_reserva := true;

    select * into v_reserva from reservas
      where id = (v_linea->>'reserva_id')::uuid and barberia_id = v_barberia;
    if not found then
      raise exception 'Reserva no encontrada en este negocio';
    end if;
    -- Se revalida acá y no solo en la UI: entre que se abrió el modal y se
    -- confirmó, la reserva pudo cobrarse desde Mi Agenda. Aborta TODO.
    if v_reserva.procesado then
      raise exception 'La reserva de % ya fue cobrada', v_reserva.nombre_cliente;
    end if;

    -- Alcance del mismo día, exigido en la base y no solo en el frontend.
    if v_fecha is null then
      v_fecha := v_reserva.fecha;
    elsif v_reserva.fecha <> v_fecha then
      raise exception 'Un cobro conjunto no puede mezclar fechas distintas';
    end if;

    -- Cliente por whatsapp, mismo criterio que mi_agenda_procesar_pago.
    -- Adentro de la transacción, así que dos líneas del mismo cliente no
    -- pueden duplicar la ficha.
    select c.id into v_cliente_id from clientes c
      where c.barberia_id = v_barberia and c.whatsapp = v_reserva.whatsapp_cliente;
    if v_cliente_id is null then
      insert into clientes (barberia_id, nombre, whatsapp, cumpleanos, canal, fecha_registro)
      values (v_barberia, v_reserva.nombre_cliente, v_reserva.whatsapp_cliente,
              v_reserva.cumpleanos_cliente, 'Reserva Web', v_reserva.fecha)
      returning id into v_cliente_id;
    end if;

    v_valor   := round(coalesce((v_linea->>'valor')::numeric, 0));
    v_propina := round(coalesce((v_linea->>'propina')::numeric, 0));
    if v_valor < 0 or v_propina < 0 then
      raise exception 'Ni el valor ni la propina pueden ser negativos';
    end if;
    v_suma := v_suma + v_valor + v_propina;

    select comision_pct into v_comision_pct from barberos
      where barberia_id = v_barberia and nombre = v_reserva.barbero_nombre;
    v_comision_pct := coalesce(v_comision_pct, 50);

    -- La comisión va sobre lo COBRADO (ya prorrateado el descuento), nunca
    -- sobre el precio de lista, y la propina queda fuera del reparto.
    if v_modo_comision = 'neto_iva' then
      v_base := v_valor - (v_valor * coalesce(v_iva_pct, 19) / (100 + coalesce(v_iva_pct, 19)));
    else
      v_base := v_valor;
    end if;
    v_comision_monto := round(v_base * v_comision_pct / 100);

    insert into visitas (
      barberia_id, cliente_id, barbero_nombre, servicio, valor, fecha, hora,
      fuente, estado, comision_monto, metodo_pago, cobro_id,
      precio_lista, descuento_pct, descuento_monto, propina, propina_pct
    ) values (
      v_barberia, v_cliente_id, coalesce(v_reserva.barbero_nombre, ''),
      coalesce(v_reserva.servicio, ''), v_valor, v_reserva.fecha, v_reserva.hora,
      'Reserva', 'Atendida', v_comision_monto, p_metodo_pago, v_cobro_id,
      nullif((v_linea->>'precio_lista')::numeric, 0),
      (v_linea->>'descuento_pct')::numeric,
      (v_linea->>'descuento_monto')::numeric,
      v_propina,
      (v_linea->>'propina_pct')::numeric
    );

    update reservas set procesado = true, estado = 'Atendida' where id = v_reserva.id;
  end loop;

  -- Un cobro de solo productos es legítimo (alguien entra y compra un shampoo):
  -- ahí no hay reserva que fije la fecha y se usa la de hoy.
  if v_fecha is null then
    v_fecha := current_date;
  end if;

  -- ── PASADA 2: los productos ───────────────────────────────────────────
  for v_linea in select * from jsonb_array_elements(p_lineas) loop
    if coalesce(v_linea->>'tipo', 'reserva') <> 'producto' then
      continue;
    end if;

    v_producto_id     := (v_linea->>'producto_id')::uuid;
    v_cantidad        := coalesce((v_linea->>'cantidad')::integer, 0);
    v_precio_unitario := round(coalesce((v_linea->>'precio_unitario')::numeric, 0));
    v_valor           := round(coalesce((v_linea->>'valor')::numeric, 0));
    v_barbero_nombre  := nullif(trim(coalesce(v_linea->>'barbero_nombre', '')), '');

    if v_cantidad <= 0 then
      raise exception 'La cantidad de un producto tiene que ser mayor que cero';
    end if;
    if v_valor < 0 then
      raise exception 'El valor de un producto no puede ser negativo';
    end if;

    select nombre into v_prod_nombre from inventario
      where id = v_producto_id and barberia_id = v_barberia;
    if not found then
      raise exception 'Producto no encontrado en este negocio';
    end if;

    -- El profesional es obligatorio y tiene que existir: de él sale la
    -- comisión, y adjudicarla por omisión es plata de otro mal asignada.
    if v_barbero_nombre is null then
      raise exception 'Falta elegir el profesional que vendió %', v_prod_nombre;
    end if;
    select comision_producto_pct into v_comision_pct from barberos
      where barberia_id = v_barberia and nombre = v_barbero_nombre;
    if not found then
      raise exception 'El profesional % no existe en este negocio', v_barbero_nombre;
    end if;
    v_comision_pct := coalesce(v_comision_pct, 0);

    -- Descuento de stock ATÓMICO. El update relativo (stock = stock - n) hace
    -- que Postgres bloquee la fila, así que dos cobros simultáneos del mismo
    -- producto se serializan en vez de pisarse. El `stock >= v_cantidad` en el
    -- where impide vender lo que no hay, y como no afecta filas se detecta con
    -- `not found`. El patrón viejo del navegador —leer el stock, restar en JS y
    -- escribir el absoluto— perdía unidades sin ningún error visible.
    update inventario set stock = stock - v_cantidad
      where id = v_producto_id and barberia_id = v_barberia and stock >= v_cantidad;
    if not found then
      raise exception 'Stock insuficiente de %', v_prod_nombre;
    end if;

    insert into movimientos_stock (barberia_id, producto_id, tipo, cantidad, motivo, responsable, fecha)
    values (v_barberia, v_producto_id, 'salida', v_cantidad, 'Venta', v_barbero_nombre, v_fecha);

    -- Misma base que los servicios: si el negocio calcula sobre el neto, los
    -- productos siguen el mismo criterio. Lo que cambia es el PORCENTAJE.
    if v_modo_comision = 'neto_iva' then
      v_base := v_valor - (v_valor * coalesce(v_iva_pct, 19) / (100 + coalesce(v_iva_pct, 19)));
    else
      v_base := v_valor;
    end if;
    v_comision_monto := round(v_base * v_comision_pct / 100);

    insert into cobro_productos (
      cobro_id, barberia_id, producto_id, barbero_nombre, cantidad,
      precio_unitario, descuento_monto, valor, comision_monto, fecha
    ) values (
      v_cobro_id, v_barberia, v_producto_id, v_barbero_nombre, v_cantidad,
      v_precio_unitario, round(coalesce((v_linea->>'descuento_monto')::numeric, 0)),
      v_valor, v_comision_monto, v_fecha
    );

    v_suma := v_suma + v_valor;
  end loop;

  -- La red que atrapa un prorrateo mal redondeado en JS antes de que quede
  -- guardado. Sin esto, la caja y la suma de ventas se separan de a pesos y
  -- nadie se entera hasta que no cuadra el IVA.
  if round(p_total_declarado) <> round(v_suma) then
    raise exception 'El total no cuadra con las líneas (% vs %)',
      round(p_total_declarado), round(v_suma);
  end if;

  return v_cobro_id;
end;
$$;

revoke all on function registrar_cobro_conjunto(jsonb,text,numeric) from public;
grant execute on function registrar_cobro_conjunto(jsonb,text,numeric) to authenticated;


-- =============================================================================
-- PASO 0 — ANTES DE CORRER TODO ESTO: DUPLICADOS DE CÓDIGO
-- El índice del bloque (2) FALLA si hay dos productos con el mismo código en
-- un negocio. El autogenerador de app.html usa 'PRD-' + (cantidad de productos
-- + 1), así que borrar un producto y crear otro puede repetir un código. Que el
-- chequeo haya dado limpio antes NO sirve como garantía hoy.
--
-- select barberia_id, codigo, count(*) as veces, string_agg(nombre, ' | ') as productos
-- from inventario
-- where codigo is not null
-- group by barberia_id, codigo
-- having count(*) > 1;
--
-- Tiene que devolver CERO filas. Si devuelve alguna, corregir esos códigos a
-- mano antes de seguir.
--
-- =============================================================================
-- PASO 1 — VERIFICAR QUE LA FUNCIÓN SE ACTUALIZÓ DE VERDAD
-- El SQL Editor puede devolver éxito sin aplicar nada.
--
-- select proname,
--        pg_get_functiondef(oid) like '%cobro_productos%' as maneja_productos,
--        pg_get_functiondef(oid) like '%stock >= v_cantidad%' as descuenta_stock,
--        pg_get_functiondef(oid) like '%search_path%' as fija_search_path
-- from pg_proc where proname = 'registrar_cobro_conjunto';
--
-- Las tres columnas tienen que decir true, y tiene que haber UNA sola fila: si
-- aparecen dos, se creó una sobrecarga en vez de reemplazar y hay que dropear
-- la que sobra.
--
-- =============================================================================
-- PASO 2 — TABLA, COLUMNA E ÍNDICES
--
-- select column_name, data_type, is_nullable, column_default
-- from information_schema.columns
-- where table_schema='public' and table_name='cobro_productos' order by ordinal_position;
--
-- select column_name, column_default from information_schema.columns
-- where table_schema='public' and table_name='barberos' and column_name='comision_producto_pct';
--
-- select indexname from pg_indexes
-- where schemaname='public' and indexname in
--   ('inventario_codigo_unico','cobro_productos_cobro_id_idx','cobro_productos_barberia_fecha_idx');
--
-- comision_producto_pct tiene que traer default 0. Los tres índices tienen que existir.
--
-- =============================================================================
-- PASO 3 — QUE NADA VIEJO SE HAYA TOCADO
--
-- select count(*) as visitas, sum(valor) as bruto_total from visitas;
-- select count(*) as productos_vendidos from cobro_productos;
-- select count(*) as profesionales, count(*) filter (where comision_producto_pct = 0) as en_cero
-- from barberos;
--
-- productos_vendidos = 0, y profesionales = en_cero: nadie estrena comisión de
-- producto sin que el dueño la active.
--
-- =============================================================================
-- ⚠ PARA LOS PASOS 4 A 7 (igual que en la Entrega 1)
-- auth_barberia_id() y auth_rol() leen el JWT: corriendo SQL sin sesión
-- devuelven null y la RPC corta con 'No autorizado' antes de probar nada. Hay
-- que simular la sesión DENTRO de la transacción:
--
--   select set_config('request.jwt.claims',
--                     json_build_object('sub','<auth_user_id-del-dueño>')::text, true);
--
-- El `true` la hace local a la transacción, así que el rollback la limpia.
-- Y nada de \gset: no existe en el SQL Editor, es un metacomando de psql.
--
-- =============================================================================
-- PASO 4 — QUE EL PROFESIONAL SEA OBLIGATORIO (con rollback)
--
-- begin;
--   select set_config('request.jwt.claims', json_build_object('sub','<uid>')::text, true);
--   select registrar_cobro_conjunto(
--     '[{"tipo":"producto","producto_id":"<id-producto>","cantidad":1,
--        "precio_unitario":10000,"valor":10000}]'::jsonb,
--     'Efectivo', 10000);
-- rollback;
--
-- Tiene que cortar con 'Falta elegir el profesional que vendió …'.
--
-- =============================================================================
-- PASO 5 — QUE NO SE PUEDA VENDER SIN STOCK (con rollback)
-- Usar una cantidad mayor al stock actual del producto.
--
-- begin;
--   select set_config('request.jwt.claims', json_build_object('sub','<uid>')::text, true);
--   select registrar_cobro_conjunto(
--     '[{"tipo":"producto","producto_id":"<id-producto>","cantidad":99999,
--        "precio_unitario":10000,"valor":10000,"barbero_nombre":"<profesional>"}]'::jsonb,
--     'Efectivo', 10000);
-- rollback;
--
-- Tiene que cortar con 'Stock insuficiente de …'.
--
-- =============================================================================
-- PASO 6 — UN COBRO MIXTO QUE SÍ ENTRA, Y DESCUENTA STOCK (con rollback)
-- Con una reserva real sin cobrar y un producto con stock. Ajustar los montos.
--
-- begin;
--   select set_config('request.jwt.claims', json_build_object('sub','<uid>')::text, true);
--   create temp table _st as
--     select stock as antes from inventario where id = '<id-producto>';
--
--   select registrar_cobro_conjunto(
--     '[{"tipo":"reserva","reserva_id":"<id-reserva>","valor":15000,"precio_lista":15000,"propina":0},
--       {"tipo":"producto","producto_id":"<id-producto>","cantidad":2,
--        "precio_unitario":5000,"valor":10000,"barbero_nombre":"<profesional>"}]'::jsonb,
--     'Efectivo', 25000);
--
--   select (select antes from _st) as stock_antes,
--          (select stock from inventario where id = '<id-producto>') as stock_despues,
--          -- ⚠ NO contar `visitas where cobro_id is not null` a secas: desde que
--          -- la Entrega 1 está en producción, eso cuenta TODO el histórico de
--          -- cobros y no las de esta transacción. Se filtra por el cobro recién
--          -- creado, que es el único que tiene líneas en cobro_productos.
--          (select count(*) from visitas
--             where cobro_id = (select cobro_id from cobro_productos limit 1)) as visitas_de_este_cobro,
--          (select count(*) from cobro_productos) as lineas_producto,
--          (select count(distinct cobro_id) from cobro_productos) as cobros,
--          (select comision_monto from cobro_productos limit 1) as comision_producto,
--          (select count(*) from movimientos_stock where tipo = 'salida') as salidas;
-- rollback;
--
-- stock_despues = stock_antes - 2, visitas_de_este_cobro = 1, lineas_producto = 1,
-- cobros = 1, salidas = 1. Y comision_producto = 0 mientras comision_producto_pct
-- siga en 0, que es el default: para verla distinta de cero hay que subírsela
-- antes al profesional (también dentro de la transacción, así el rollback lo
-- limpia).
--
-- =============================================================================
-- PASO 7 — QUE EL TOTAL SIGA CUADRANDO CON PRODUCTOS (con rollback)
-- Mismo bloque que el PASO 6 pero declarando un total equivocado (por ejemplo
-- 25001). Tiene que cortar con 'El total no cuadra con las líneas'.
--
-- Sin esto, un error de redondeo en el JS entra a la base en silencio y el
-- descuadre recién aparece cuando no cuaja el IVA a fin de mes.
