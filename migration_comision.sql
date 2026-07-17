-- Modo de cálculo de comisión configurable por negocio, y snapshot de la
-- comisión real pagada en cada visita (para que cambiar el modo NO afecte
-- retroactivamente citas ya atendidas).
-- Ejecutar una sola vez en el SQL Editor de Supabase. Es idempotente.

alter table barberias add column if not exists modo_comision text not null default 'total';
alter table visitas add column if not exists comision_monto numeric;
