-- Desglose del cobro en visitas: precio de lista, descuento y propina.
--
-- POR QUÉ
-- Hoy el cobro no se puede editar: procesarReserva() toma el precio del
-- servicio por nombre y lo inserta tal cual. Por eso hay reservas de Essential
-- Studio marcadas "Confirmada" sin pago procesado: la plata YA se cobró en
-- físico con otro precio, y el sistema no sabe registrar ese monto. Lo que
-- falta no es crear un cobro nuevo, es poder REGISTRAR el real.
--
-- LA INVARIANTE QUE NO SE TOCA
-- `valor` sigue significando exactamente lo mismo que hasta ahora: lo que pagó
-- el cliente por el SERVICIO, bruto (con IVA incluido), después del descuento
-- y SIN propina. Gracias a eso ningún lector existente cambia — módulo de IVA,
-- reportes, dashboard y comisiones siguen leyendo `valor` y siguen estando
-- bien. Ver [[reservia-iva-precio-bruto]]: el IVA se extrae de adentro de
-- `valor` con ivaDe(), nunca se suma por fuera.
--
--   valor = precio_lista - descuento_monto
--
-- Con una salvedad que apareció al escribir el modal: cobrar POR ENCIMA del
-- precio de lista es legítimo (un servicio que se alargó, un recargo), y ahí
-- no hay descuento. En ese caso descuento_monto queda en 0 —no negativo, que
-- el check rechaza— y la igualdad de arriba no se cumple. Vale entonces la
-- forma general: descuento_monto = max(0, precio_lista - valor). Un recargo
-- explícito, si algún día se necesita, va en su propia columna; hoy no se
-- inventa una.
--
-- POR QUÉ LA PROPINA VA EN COLUMNA APARTE Y NO DENTRO DE valor
-- Metida adentro haría dos daños silenciosos: inflaría el IVA débito
-- —declararías IVA sobre plata que no es venta— y entraría al reparto de
-- comisión sin que nadie lo hubiera decidido. Afuera, las dos cosas se
-- resuelven solas porque el módulo de IVA y calcularComision() suman `valor`.
--
-- DECISIONES DE NEGOCIO YA TOMADAS (2026-07-31, con el dueño)
--   · La comisión se calcula sobre el precio COBRADO, no sobre el de lista:
--     el descuento lo absorben los dos. Es lo que el código ya hacía, así que
--     ni calcularComision() ni su copia en plpgsql de mi_agenda_procesar_pago
--     cambian.
--   · La propina va ENTERA al profesional, fuera del reparto. El dueño le debe
--     comisión + propina, así que el reporte por profesional necesita una
--     columna de propinas o quedaría debiendo plata sin verla.
--
-- POR QUÉ SE GUARDAN pct Y monto DE CADA UNO
-- El pct es la intención y el monto es el resultado congelado. Re-derivar el
-- monto desde el pct más adelante arrastraría redondeo, y si servicios.precio
-- cambia, precio_lista es lo único que protege lo ya cerrado. Es la misma
-- filosofía de comision_monto, que ya se congela al atender.
--
-- POR QUÉ NO HAY CHECK DE LA INVARIANTE
-- Tentador, pero rompería el flujo de editar una cita: guardarCita() hace
-- update con `valor` adentro y sin las columnas nuevas, así que un CHECK
-- reventaría con un error crudo de Postgres en la cara del dueño. En vez de
-- eso, guardarCita() limpia el desglose cuando el valor cambia — si editas el
-- monto a mano, deja de saberse cómo se compuso, y eso es lo honesto. Los
-- checks que sí van son de rango, que ningún flujo legítimo puede violar.
--
-- LAS FILAS VIEJAS QUEDAN EN NULL A PROPÓSITO
-- No se rellena precio_lista = valor hacia atrás. Es cierto que antes no había
-- descuentos, pero rellenarlo inventaría una foto de precio que nadie tomó.
-- NULL significa "cobrado antes de que existiera el desglose", que es la
-- verdad. Cualquier reporte que sume descuentos tiene que tratar NULL como 0.
--
-- Agregar columnas nullable (y propina con default) es metadata-only en
-- Postgres moderno: no reescribe la tabla ni la bloquea de forma apreciable.

alter table public.visitas
  add column if not exists precio_lista     numeric,
  add column if not exists descuento_pct    numeric,
  add column if not exists descuento_monto  numeric,
  add column if not exists propina          numeric not null default 0,
  add column if not exists propina_pct      numeric;

comment on column public.visitas.precio_lista is
  'Precio del servicio al momento de cobrar, congelado. NULL en cobros anteriores al desglose.';
comment on column public.visitas.descuento_pct is
  'Porcentaje de descuento aplicado. NULL si el precio final se escribió a mano.';
comment on column public.visitas.descuento_monto is
  'Plata descontada, congelada. Invariante: valor = precio_lista - descuento_monto.';
comment on column public.visitas.propina is
  'Propina en plata. FUERA de valor: no lleva IVA ni entra al reparto de comisión.';
comment on column public.visitas.propina_pct is
  'Tramo de propina elegido (5/10/15/20). NULL cuando se escribió un monto fijo.';

-- Rangos que ningún flujo legítimo puede violar. No incluyen la invariante
-- valor = precio_lista - descuento_monto (ver el encabezado).
alter table public.visitas
  add constraint visitas_propina_no_negativa
    check (propina >= 0);

alter table public.visitas
  add constraint visitas_descuento_pct_rango
    check (descuento_pct is null or (descuento_pct >= 0 and descuento_pct <= 100));

alter table public.visitas
  add constraint visitas_descuento_monto_no_negativo
    check (descuento_monto is null or descuento_monto >= 0);

alter table public.visitas
  add constraint visitas_propina_pct_rango
    check (propina_pct is null or (propina_pct >= 0 and propina_pct <= 100));


-- =============================================================================
-- PASO 1 — VERIFICAR QUE LAS COLUMNAS EXISTEN Y CON EL TIPO CORRECTO
--
-- select column_name, data_type, is_nullable, column_default
-- from information_schema.columns
-- where table_schema = 'public' and table_name = 'visitas'
--   and column_name in ('precio_lista','descuento_pct','descuento_monto',
--                       'propina','propina_pct')
-- order by column_name;
--
-- Tienen que aparecer las CINCO. `propina` con is_nullable = NO y default 0;
-- las otras cuatro nullable y sin default.
--
-- =============================================================================
-- PASO 2 — VERIFICAR QUE NO SE ROMPIÓ NINGUNA FILA EXISTENTE
-- Las columnas nuevas no tocan `valor`, así que los totales que alimentan el
-- IVA y las comisiones tienen que dar exactamente lo mismo que antes.
--
-- select count(*)                            as visitas,
--        sum(valor)                          as bruto_total,
--        count(*) filter (where propina = 0) as sin_propina,
--        count(*) filter (where precio_lista is null) as sin_desglose
-- from visitas;
--
-- sin_propina y sin_desglose tienen que ser IGUALES al total: ninguna fila
-- vieja estrena desglose.
--
-- ⚠ `limit 1` SIN `order by` NO ELIGE SIEMPRE LA MISMA FILA
-- Los pasos 3 y 4 apuntan a una fila cualquiera, pero tienen que apuntar a LA
-- MISMA en el update y en el select que lo comprueba. Sin `order by`, Postgres
-- puede devolver filas distintas en dos consultas idénticas según el plan que
-- elija, y el paso 4 termina leyendo una fila que nunca se actualizó: se ve
-- como que la migración falló cuando el que falló fue el test. Detectado por
-- Mario al correrlo. Por eso va `order by id`, que es determinista.
--
-- =============================================================================
-- PASO 3 — PROBAR QUE LOS CHECKS MUERDEN (con rollback obligatorio)
-- Un check que no rechaza nada no está protegiendo nada.
--
-- begin;
--   -- Las cuatro tienen que fallar con 23514 (check_violation).
--   update visitas set propina = -1
--    where id = (select id from visitas order by id limit 1);
-- rollback;
--
-- begin;
--   update visitas set descuento_pct = 150
--    where id = (select id from visitas order by id limit 1);
-- rollback;
--
-- begin;
--   update visitas set descuento_monto = -5
--    where id = (select id from visitas order by id limit 1);
-- rollback;
--
-- begin;
--   update visitas set propina_pct = 101
--    where id = (select id from visitas order by id limit 1);
-- rollback;
--
-- =============================================================================
-- PASO 4 — PROBAR QUE UN COBRO CON DESGLOSE VÁLIDO SÍ ENTRA
-- Sin esto, un check demasiado estricto rompe el flujo real y no se nota
-- hasta que el dueño intenta cobrar.
--
-- begin;
--   update visitas
--      set precio_lista = 15000, descuento_pct = 15, descuento_monto = 2250,
--          valor = 12750, propina = 1275, propina_pct = 10
--    where id = (select id from visitas order by id limit 1);
--
--   select precio_lista, descuento_monto, valor,
--          valor = precio_lista - descuento_monto as cuadra_la_invariante,
--          propina
--   from visitas
--   where id = (select id from visitas order by id limit 1);
-- rollback;
--
-- cuadra_la_invariante tiene que decir true.
