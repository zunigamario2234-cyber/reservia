-- Cobro conjunto: varias reservas del MISMO DÍA pagadas juntas.
--
-- POR QUÉ UNA RPC Y NO N INSERTS DESDE EL NAVEGADOR
-- procesarReserva() hace insert de visita + update de reserva, una reserva por
-- vez, desde el cliente. Con tres reservas son siete operaciones sueltas: si se
-- corta en la mitad, el cliente pagó todo y el sistema registró una parte, sin
-- forma de deshacerlo. Acá es todo o nada.
--
-- LO QUE NO CAMBIA
-- `valor` sigue significando lo mismo: lo cobrado por ESE servicio, bruto (IVA
-- incluido), ya descontado y SIN propina. Por eso el módulo de IVA, el
-- dashboard, los reportes y las comisiones siguen funcionando sin tocarse.
-- Ver migration_precio_descuento_propina.sql.
--
-- EL PRORRATEO LO HACE EL NAVEGADOR, NO ESTA FUNCIÓN
-- Mismo criterio que procesarReserva(): el monto y el desglose ya vienen
-- decididos por m-cobro, que es lo que el dueño VE en pantalla antes de
-- confirmar. Acá no se resuelve ningún precio — pero sí se VALIDA que la suma
-- de las líneas cuadre con el total declarado, para que un error de redondeo
-- en JS no entre a la base como descuadre silencioso.
--
-- EL REPARTO, DECIDIDO CON EL DUEÑO (2026-08-05)
--   · El descuento se imputa SOLO a los servicios, proporcional a su precio de
--     lista. Los productos (Entrega 2) se cobran a precio lleno, para que un
--     profesional nunca vea bajar su comisión por el descuento de un producto
--     que no vendió.
--   · La propina se reparte proporcional a lo cobrado por cada profesional.
--     Como el prorrateo es proporcional a `valor`, se cumple que
--     propina_i = valor_i * pct / 100, así que propina_pct sigue siendo cierto
--     en cada visita y no hace falta cambiarle el significado a esa columna.
--
-- ⚠ DEUDA CONOCIDA, ACEPTADA A SABIENDAS (2026-08-05, decisión del dueño)
-- El cálculo de comisión de acá abajo es la QUINTA copia de la misma lógica
-- (app.html calcularComision, mi_agenda_procesar_pago, el helper ivaDe y el
-- render de comisiones). NO se unifica en esta entrega a propósito, para no
-- inflar su alcance. Suma a las deudas #1 y #2, que se resuelven juntas en su
-- propia tarea.
--
-- ⚠ CÓMO SE CORRE
-- Este archivo define una función con dollar-quoting, así que va SIN
-- begin;/commit; — esa combinación el SQL Editor de Supabase la falla en
-- silencio devolviendo éxito. Correr completo, de una, y después verificar con
-- el PASO 1 de abajo que el cuerpo realmente cambió.

alter table public.visitas
  add column if not exists cobro_id uuid;

comment on column public.visitas.cobro_id is
  'Agrupa las visitas pagadas en un mismo cobro conjunto. NULL = cobro individual (todas las anteriores a esta función).';

create index if not exists visitas_cobro_id_idx
  on public.visitas (cobro_id) where cobro_id is not null;


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
begin
  if v_barberia is null or auth_rol() <> 'dueno' then
    raise exception 'No autorizado';
  end if;
  if p_lineas is null or jsonb_array_length(p_lineas) = 0 then
    raise exception 'El cobro no tiene ninguna reserva';
  end if;

  select modo_comision, iva_pct into v_modo_comision, v_iva_pct
    from barberias where id = v_barberia;

  for v_linea in select * from jsonb_array_elements(p_lineas) loop
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

    -- Cliente por whatsapp, mismo criterio que procesarReserva() y
    -- mi_agenda_procesar_pago. Adentro de la transacción, así que dos líneas
    -- del mismo cliente no pueden duplicar la ficha.
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

  -- La red que atrapa un prorrateo mal redondeado en JS antes de que quede
  -- guardado. Sin esto, la caja y la suma de visitas se separan de a pesos y
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
-- PASO 1 — VERIFICAR QUE LA FUNCIÓN SE CREÓ DE VERDAD
-- El SQL Editor puede devolver éxito sin haber aplicado nada. Esto mira el
-- cuerpo real en pg_proc, no la falta de queja.
--
-- select proname,
--        pg_get_functiondef(oid) like '%cobro_id%'      as tiene_cuerpo_nuevo,
--        pg_get_functiondef(oid) like '%search_path%'   as fija_search_path
-- from pg_proc where proname = 'registrar_cobro_conjunto';
--
-- Las dos columnas tienen que decir true. Si no aparece ninguna fila, la
-- función no se creó: volver a correr el archivo completo.
--
-- =============================================================================
-- PASO 2 — VERIFICAR LA COLUMNA Y EL ÍNDICE
--
-- select column_name, data_type, is_nullable
-- from information_schema.columns
-- where table_schema = 'public' and table_name = 'visitas' and column_name = 'cobro_id';
--
-- select indexname from pg_indexes
-- where schemaname = 'public' and tablename = 'visitas' and indexname = 'visitas_cobro_id_idx';
--
-- cobro_id tiene que ser uuid y nullable. El índice tiene que existir.
--
-- =============================================================================
-- PASO 3 — QUE NINGUNA FILA VIEJA SE HAYA TOCADO
-- La columna es aditiva: los totales que alimentan IVA y comisiones tienen que
-- dar exactamente lo mismo que antes de correr esto.
--
-- select count(*)                                   as visitas,
--        sum(valor)                                 as bruto_total,
--        count(*) filter (where cobro_id is null)   as sin_cobro_conjunto
-- from visitas;
--
-- sin_cobro_conjunto tiene que ser IGUAL al total: ninguna fila vieja estrena
-- agrupador.
--
-- =============================================================================
-- ⚠ DOS COSAS QUE HAY QUE SABER ANTES DE CORRER LOS PASOS 4 A 6
-- (verificadas por Mario al aplicar esta migración, 2026-08-18)
--
--   · El SQL Editor de Supabase NO soporta \gset: es un metacomando de psql,
--     no SQL. Para capturar el uuid que devuelve la función hay que envolver
--     la prueba en un bloque do $$ ... $$ y guardarlo en una variable.
--
--   · auth_barberia_id() y auth_rol() leen el JWT, así que corriendo SQL
--     directo (sin sesión) devuelven null y la RPC corta con 'No autorizado'
--     antes de probar nada. Hay que simular la sesión DENTRO de la
--     transacción de prueba:
--
--       select set_config('request.jwt.claims',
--                         json_build_object('sub','<auth_user_id-del-dueño>')::text,
--                         true);
--
--     El `true` final la hace local a la transacción, así que el rollback la
--     limpia. Sin esto, los pasos 4 a 6 fallan siempre con el mismo error y
--     parece que la función está rota cuando lo que falta es la identidad.
--
-- =============================================================================
-- PASO 4 — QUE LA VALIDACIÓN DEL TOTAL MUERDA (con rollback obligatorio)
-- Una validación que no rechaza nada no protege nada. Reemplazar el uuid por
-- una reserva REAL sin cobrar del negocio de prueba.
--
-- begin;
--   -- Total declarado que no cuadra con la línea: tiene que fallar.
--   select registrar_cobro_conjunto(
--     '[{"reserva_id":"00000000-0000-0000-0000-000000000000","valor":10000,"propina":0}]'::jsonb,
--     'Efectivo',
--     99999
--   );
-- rollback;
--
-- Tiene que cortar con 'El total no cuadra con las líneas'. Si en vez de eso
-- dice 'Reserva no encontrada en este negocio', el uuid de prueba no se
-- reemplazó — ese error llega ANTES y no prueba la validación del total.
--
-- =============================================================================
-- PASO 5 — QUE NO SE PUEDAN MEZCLAR FECHAS (con rollback obligatorio)
-- Con dos reservas reales sin cobrar de DÍAS DISTINTOS:
--
-- begin;
--   select registrar_cobro_conjunto(
--     '[{"reserva_id":"<uuid-dia-A>","valor":10000,"propina":0},
--       {"reserva_id":"<uuid-dia-B>","valor":10000,"propina":0}]'::jsonb,
--     'Efectivo',
--     20000
--   );
-- rollback;
--
-- Tiene que cortar con 'Un cobro conjunto no puede mezclar fechas distintas'.
--
-- =============================================================================
-- PASO 6 — QUE UN COBRO VÁLIDO SÍ ENTRE, Y CUADRE (con rollback obligatorio)
-- Con dos reservas reales sin cobrar del MISMO DÍA:
--
-- begin;
--   select set_config('request.jwt.claims',
--                     json_build_object('sub','<auth_user_id-del-dueño>')::text, true);
--
--   -- Sin \gset (no existe en el SQL Editor): el uuid se captura en un bloque.
--   do $b$
--   declare v_cobro uuid;
--   begin
--     v_cobro := registrar_cobro_conjunto(
--       '[{"reserva_id":"<uuid-1>","valor":17429,"precio_lista":20000,"descuento_monto":2571,"propina":1975,"propina_pct":10},
--         {"reserva_id":"<uuid-2>","valor":13071,"precio_lista":15000,"descuento_monto":1929,"propina":1481,"propina_pct":10}]'::jsonb,
--       'Efectivo',
--       33956
--     );
--     raise notice 'cobro_id = %', v_cobro;
--   end
--   $b$;
--
--   -- Las dos visitas comparten cobro_id, y la suma cuadra con lo declarado.
--   select count(*)                    as lineas,
--          count(distinct cobro_id)    as cobros,
--          sum(valor) + sum(propina)   as total,
--          sum(comision_monto)         as comisiones
--   from visitas where cobro_id is not null;
--
--   -- Y las reservas quedaron marcadas.
--   select id, procesado, estado from reservas
--   where id in ('<uuid-1>','<uuid-2>');
-- rollback;
--
-- lineas = 2, cobros = 1, total = 33956, y las dos reservas con
-- procesado = true y estado = 'Atendida'.
