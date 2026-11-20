-- =============================================================================
-- BOLETAS ELECTRÓNICAS AUTOMÁTICAS AL COBRAR
--
-- Al registrar un cobro, Reservia le pide a un PROVEEDOR que emita las boletas
-- ante el SII y guarda el resultado (estado, folio, PDF). El proveedor es
-- intercambiable y se elige por negocio:
--   · 'ninguno'    → no se emite nada (default: nadie cambia de comportamiento
--                    hasta que el dueño lo active).
--   · 'simulado'   → no toca el SII; folios de mentira. Para probar el flujo.
--   · 'emisso'     → Emisso Connect (emite por E-Boleta del SII).
--   · 'boleteados' → plataforma propia Boleteados (solución de mercado).
-- Cambiar de proveedor es cambiar esta columna; el resto de Reservia no se toca.
--
-- UNA O DOS BOLETAS POR ATENCIÓN (lo decide el contador)
--   · 'una' (camino A): el local emite una boleta por el total del cobro.
--   · 'dos' (camino B): cada profesional configurado como emisor emite SU
--     boleta por su parte, y el local emite por el resto (incluye productos).
--     Un profesional SIN emisor configurado no emite: su parte va en la boleta
--     del local. Así un salón puede tener profesionales que boletean y otros no.
--
-- NUNCA DOS VECES LA MISMA BOLETA
-- `llave` = origen + emisor + profesional + tipo, única por negocio. Reintentar
-- el mismo cobro (doble clic, red que se corta, reintento automático) no crea
-- filas nuevas, y la idem_key de cada fila viaja al proveedor como
-- Idempotency-Key: aunque el proveedor reciba dos veces la misma boleta, emite
-- una.
--
-- QUIÉN ESCRIBE
-- Solo el servidor (api/boletas.js, service_role). El navegador solo LEE sus
-- boletas: si pudiera escribir, podría marcar como "emitida" una boleta que el
-- SII nunca vio.
--
-- ⚠ SIN begin;/commit; A PROPÓSITO (el SQL Editor trocea por `;` los cuerpos).
-- Correr completo, de una, en el SQL Editor de Supabase.
-- =============================================================================

-- ── Configuración por negocio ────────────────────────────────────────────────
alter table public.barberias
  add column if not exists boletas_proveedor text not null default 'ninguno',
  add column if not exists boletas_modo text not null default 'una',
  add column if not exists boletas_tipo_dte integer not null default 39,
  add column if not exists boletas_emisor_ref text,
  add column if not exists boletas_enviar_correo boolean not null default true;
alter table public.barberias drop constraint if exists barberias_boletas_chk;
alter table public.barberias add constraint barberias_boletas_chk
  check (boletas_proveedor in ('ninguno','simulado','emisso','boleteados')
         and boletas_modo in ('una','dos')
         and boletas_tipo_dte in (39,41));

comment on column public.barberias.boletas_emisor_ref is
  'Id del LOCAL como emisor en el proveedor: la conexión de Emisso (conn_…) o el id del emisor en Boleteados. No es secreto.';

-- ── Configuración por profesional (solo aplica con boletas_modo = 'dos') ─────
alter table public.barberos
  add column if not exists boletas_emisor_ref text,
  add column if not exists boletas_tipo_dte integer;
alter table public.barberos drop constraint if exists barberos_boletas_tipo_chk;
alter table public.barberos add constraint barberos_boletas_tipo_chk
  check (boletas_tipo_dte is null or boletas_tipo_dte in (39,41));

comment on column public.barberos.boletas_emisor_ref is
  'Id del PROFESIONAL como emisor en el proveedor. Vacío = no emite boleta propia; su parte va en la boleta del local.';

-- ── Las boletas ──────────────────────────────────────────────────────────────
create table if not exists public.boletas (
  id uuid primary key default gen_random_uuid(),
  barberia_id uuid not null references public.barberias(id) on delete cascade,
  -- Origen: un cobro del panel (cobro_id) o un pago de Mi Agenda (visita_id).
  cobro_id uuid,
  visita_id uuid,
  origen text not null,
  emisor text not null,
  barbero_id uuid references public.barberos(id) on delete set null,
  emisor_ref text,
  proveedor text not null,
  tipo_dte integer not null,
  monto_total integer not null,
  detalle text,
  medio_pago text,
  cliente_id uuid,
  cliente_nombre text,
  cliente_correo text,
  llave text not null,
  idem_key uuid not null default gen_random_uuid(),
  estado text not null default 'pendiente',
  folio text,
  pdf_url text,
  proveedor_ref text,
  error text,
  intentos integer not null default 0,
  proximo_intento timestamptz not null default now(),
  correo_enviado_at timestamptz,
  fecha date not null default ((now() at time zone 'America/Santiago')::date),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint boletas_emisor_chk check (emisor in ('local','profesional')),
  constraint boletas_tipo_chk check (tipo_dte in (39,41)),
  constraint boletas_monto_chk check (monto_total > 0),
  constraint boletas_estado_chk check (estado in ('pendiente','enviando','en_proceso','emitida','rechazada','error','desconocido')),
  constraint boletas_origen_chk check (cobro_id is not null or visita_id is not null),
  constraint boletas_llave_unica unique (barberia_id, llave)
);

comment on table public.boletas is
  'Boletas electrónicas pedidas al proveedor por cada cobro. Las escribe solo api/boletas.js. estado: pendiente → enviando → emitida | en_proceso (el proveedor avisa después) | rechazada (definitivo) | error (se reintenta) | desconocido (se reintenta con la MISMA idem_key).';

create index if not exists boletas_barberia_fecha_idx on public.boletas (barberia_id, fecha desc);
create index if not exists boletas_cobro_idx on public.boletas (cobro_id) where cobro_id is not null;
create index if not exists boletas_visita_idx on public.boletas (visita_id) where visita_id is not null;
create index if not exists boletas_reintento_idx on public.boletas (proximo_intento)
  where estado in ('pendiente','error','desconocido','en_proceso');

alter table public.boletas enable row level security;
revoke all on public.boletas from anon, authenticated;
grant select on public.boletas to authenticated;

-- Dueño y recepción ven todas las del negocio; cada profesional, las suyas.
drop policy if exists boletas_lectura on public.boletas;
create policy boletas_lectura on public.boletas for select to authenticated
  using (
    barberia_id = auth_barberia_id()
    and (auth_rol() in ('dueno','recepcion')
         or (auth_rol() = 'profesional' and barbero_id = auth_barbero_id()))
  );

-- ── VERIFICACIÓN (correr aparte, después) ────────────────────────────────────
-- select column_name from information_schema.columns
--  where table_name = 'barberias' and column_name like 'boletas_%';
--   → 5 filas
-- select count(*) from public.boletas;   → 0, sin error
--
-- ── OPCIONAL: reintentos automáticos cada 5 minutos ──────────────────────────
-- El plan gratis de Vercel solo permite un cron al día, así que el reintento lo
-- dispara Supabase (pg_cron + pg_net). Reemplaza <SECRETO> por el valor de la
-- variable BOLETAS_CRON_SECRET de Vercel. Sin esto, los reintentos igual
-- ocurren cada vez que el dueño abre la pantalla Impuestos.
--
-- create extension if not exists pg_cron;
-- create extension if not exists pg_net;
-- select cron.schedule('boletas-reintentar', '*/5 * * * *', $cron$
--   select net.http_post(
--     url := 'https://www.mireservia.cl/api/boletas',
--     headers := '{"Content-Type":"application/json","X-Cron-Secret":"<SECRETO>"}'::jsonb,
--     body := '{"accion":"cron"}'::jsonb
--   );
-- $cron$);
