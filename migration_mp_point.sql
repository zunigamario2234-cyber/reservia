-- =============================================================================
-- MERCADO PAGO POINT (terminal de cobro con tarjeta integrada al cobro).
-- El Access Token de cada negocio es una credencial: vive SOLO en esta tabla,
-- sin políticas y sin permisos para anon/authenticated. Lo leen únicamente las
-- funciones serverless (service_role). El navegador nunca recibe el token;
-- solo sabe si hay Point activo y los últimos 4 caracteres (para el dueño).
-- Aditiva: no toca ninguna tabla existente.
-- =============================================================================
create table if not exists public.mp_config (
  barberia_id    uuid primary key references public.barberias(id) on delete cascade,
  access_token   text not null,
  mp_user_id     text,
  terminal_id    text,
  terminal_nombre text,
  activo         boolean not null default false,
  updated_at     timestamptz not null default now()
);
alter table public.mp_config enable row level security;
revoke all on public.mp_config from anon, authenticated;

-- Libro de órdenes enviadas a la terminal: sirve para no cobrar dos veces, para
-- recuperar un pago aprobado si la pantalla se cerró, y para auditar.
create table if not exists public.mp_point_ordenes (
  id                 uuid primary key default gen_random_uuid(),
  created_at         timestamptz not null default now(),
  barberia_id        uuid not null references public.barberias(id) on delete cascade,
  order_id           text not null unique,
  external_reference text not null,
  monto              integer not null check (monto > 0),
  estado             text not null default 'created',
  metodo             text,
  creado_por         uuid,
  pagado_at          timestamptz
);
alter table public.mp_point_ordenes enable row level security;
revoke all on public.mp_point_ordenes from anon, authenticated;
create index if not exists mp_point_ordenes_negocio on public.mp_point_ordenes (barberia_id, created_at desc);

-- Lo único que ve el navegador: ¿hay Point activo en mi negocio?
create or replace function public.mp_point_config()
returns jsonb language plpgsql stable security definer set search_path to 'public' as $$
declare v_b uuid; v_rol text; c mp_config;
begin
  select barberia_id, rol into v_b, v_rol from perfiles where id = auth.uid();
  if v_b is null then return jsonb_build_object('conectado', false, 'activo', false); end if;
  select * into c from mp_config where barberia_id = v_b;
  if not found then return jsonb_build_object('conectado', false, 'activo', false); end if;
  return jsonb_build_object(
    'conectado', true,
    'activo', c.activo and c.terminal_id is not null,
    'terminal_nombre', c.terminal_nombre,
    'terminal_elegida', c.terminal_id is not null,
    'token_final', case when v_rol = 'dueno' then right(c.access_token, 4) else null end);
end $$;
revoke all on function public.mp_point_config() from public, anon;
grant execute on function public.mp_point_config() to authenticated;

-- Forma del pago que informó Mercado Pago (tipo de tarjeta, cuotas, claves recibidas).
-- Sirve para afinar el reconocimiento de débito/crédito sin adivinar.
alter table public.mp_point_ordenes add column if not exists pago_detalle jsonb;
