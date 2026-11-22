-- Comisión de la máquina (Point): el dueño anota su tasa de débito y crédito
-- (como sale en su cuenta de Mercado Pago, normalmente "% + IVA"). Al aprobarse
-- un pago con Point, el servidor (api/mp-point.js) calcula la comisión y la
-- anota como gasto variable en Costos, categoría "Comisión máquina". Se descuenta
-- de la parte del negocio: la comisión del profesional no cambia.
alter table public.mp_config add column if not exists tasa_debito numeric;
alter table public.mp_config add column if not exists tasa_credito numeric;
alter table public.mp_config add column if not exists tasa_mas_iva boolean not null default true;
alter table public.mp_point_ordenes add column if not exists comision_monto numeric;
alter table public.mp_point_ordenes add column if not exists costo_id uuid;
