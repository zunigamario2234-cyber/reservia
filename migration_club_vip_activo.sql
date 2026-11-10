-- =============================================================================
-- CLUB VIP ENCENDIDO / APAGADO POR NEGOCIO.
-- El dueño decide si usa el Club VIP (Config → Negocio). Apagado: se esconde todo
-- lo del club en el panel, no se avisan subidas de nivel y los links públicos
-- (club.html, unirse.html) dicen que el club no está activo. No se borra nada:
-- clientes e historial se conservan. Por defecto queda activo, igual que hoy.
-- Aditiva. DEBE APLICARSE ANTES de subir el código (club.html y unirse.html
-- piden esta columna).
-- =============================================================================
alter table public.barberias add column if not exists club_vip_activo boolean not null default true;
