-- Bloqueos de varios días seguidos (vacaciones).
-- Se guardan como tipo 'dia_completo' con fecha (desde) y fecha_hasta (hasta, inclusive).
-- Un 'dia_completo' sin fecha_hasta sigue siendo un solo día, así los bloqueos
-- existentes no cambian.
alter table public.bloqueos_profesional add column if not exists fecha_hasta date;
alter table public.bloqueos_profesional drop constraint if exists bloqueos_profesional_fecha_hasta_check;
alter table public.bloqueos_profesional add constraint bloqueos_profesional_fecha_hasta_check
  check (fecha_hasta is null or (tipo = 'dia_completo' and fecha is not null and fecha_hasta >= fecha));
