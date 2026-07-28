-- =============================================================================
-- ESQUEMA ACTUAL DE LA BASE DE DATOS — Reservia
--
--   ESTO ES LO QUE SE CORRE PARA RECONSTRUIR LA BASE DESDE CERO.
--
--   Los archivos migration_*.sql son HISTORIAL, no estado. Correrlos en
--   orden NO reconstruye nada: 12 de las 19 tablas nunca tuvieron DDL
--   versionado porque se crearon a mano en el dashboard de Supabase, así
--   que las migraciones dan por sentado un esquema que ningún archivo del
--   repo construye. Sirven para entender POR QUÉ algo es como es, no para
--   levantar la base. Ver README.md.
--
-- Generado el 2026-07-28 desde el schema `public` de producción.
--
-- Es una FOTO, no un archivo vivo: en cuanto cambies la base este archivo
-- queda viejo. Después de aplicar una migración, regeneralo (instrucciones
-- al final) y commitealo junto con ella.
--
-- -----------------------------------------------------------------------------
-- QUÉ CONTIENE
--   19 tablas · 61 constraints · 1 índice · 23 funciones · 1 vista
--   RLS activo en las 19 tablas · 49 políticas
--   Permisos de tabla para anon / authenticated / service_role
--
-- QUÉ NO CONTIENE
--   · Los datos. Esto es solo estructura — si se pierde el proyecto, esto
--     devuelve la forma de la base, no su contenido. El respaldo de datos
--     es un problema aparte y hoy NO está resuelto.
--   · Los schemas auth, storage y realtime, que administra Supabase y que
--     un proyecto nuevo ya trae armados.
--   · Comentarios (COMMENT ON), configuración de Realtime/publicaciones y
--     permisos a nivel de columna.
--   · Triggers: hoy no hay ninguno en el schema public. Si algún día se
--     agrega uno, la consulta del final ya lo captura.
--
-- -----------------------------------------------------------------------------
-- ORDEN DE EJECUCIÓN
--   Las secciones ya están en el orden correcto y se corre de arriba a
--   abajo, de una. Las claves foráneas van como ALTER TABLE después de
--   crear todas las tablas, así que no hay dependencias circulares que
--   resolver a mano.
--
--   Sobre un proyecto de Supabase recién creado, antes de correr esto hay
--   que crear las extensiones de la sección 0.
-- =============================================================================


-- =============================================================================
-- 0. EXTENSIONES
-- Las cinco son estándar de Supabase y un proyecto nuevo ya las trae. Van
-- igual, para que este archivo describa la base completa y no dependa de
-- que el default de Supabase siga siendo el mismo más adelante.
-- Ninguna vive en `public`: Supabase las aísla en su propio schema.
-- =============================================================================

CREATE EXTENSION IF NOT EXISTS pg_stat_statements WITH SCHEMA extensions;  -- 1.11
CREATE EXTENSION IF NOT EXISTS pgcrypto           WITH SCHEMA extensions;  -- 1.3
CREATE EXTENSION IF NOT EXISTS "uuid-ossp"        WITH SCHEMA extensions;  -- 1.1
CREATE EXTENSION IF NOT EXISTS supabase_vault     WITH SCHEMA vault;       -- 0.3.1
-- plpgsql (1.0, pg_catalog) viene con Postgres, no hace falta crearla.


-- =============================================================================
-- 1. TABLAS
-- Sin claves foráneas: van todas juntas en la sección 2.
-- =============================================================================

-- alianza_canjes
CREATE TABLE IF NOT EXISTS public.alianza_canjes (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  codigo_id uuid NOT NULL,
  barberia_id uuid NOT NULL,
  fecha timestamp with time zone DEFAULT now() NOT NULL
);

-- alianza_codigos
CREATE TABLE IF NOT EXISTS public.alianza_codigos (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  barberia_id uuid NOT NULL,
  alianza_id uuid NOT NULL,
  cliente_id uuid,
  tipo text NOT NULL,
  codigo text NOT NULL,
  activo boolean DEFAULT true NOT NULL,
  created_at timestamp with time zone DEFAULT now() NOT NULL
);

-- alianzas
CREATE TABLE IF NOT EXISTS public.alianzas (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  barberia_id uuid NOT NULL,
  nombre text NOT NULL,
  descripcion text,
  beneficio text,
  logo_url text,
  link text,
  activo boolean DEFAULT true NOT NULL,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  nivel_minimo_id uuid,
  nivel_sin_restriccion boolean DEFAULT false NOT NULL,
  beneficio_reciproco text
);

-- barberias
CREATE TABLE IF NOT EXISTS public.barberias (
  id uuid DEFAULT uuid_generate_v4() NOT NULL,
  nombre text NOT NULL,
  direccion text,
  telefono text,
  whatsapp text,
  email_contacto text,
  link_setmore text,
  link_reviews text,
  iva_pct numeric DEFAULT 19,
  plan text DEFAULT 'free'::text,
  activo boolean DEFAULT true,
  created_at timestamp with time zone DEFAULT now(),
  logo_url text,
  rubro text DEFAULT 'Barbería / Peluquería / Centro de estética'::text NOT NULL,
  modo_comision text DEFAULT 'total'::text NOT NULL,
  creado_por uuid DEFAULT auth.uid(),
  foto_portada text,
  instagram text,
  email text,
  descripcion text
);

-- barbero_servicios
CREATE TABLE IF NOT EXISTS public.barbero_servicios (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  barberia_id uuid NOT NULL,
  barbero_id uuid NOT NULL,
  servicio_id uuid NOT NULL,
  activo boolean DEFAULT true NOT NULL
);

-- barberos
CREATE TABLE IF NOT EXISTS public.barberos (
  id uuid DEFAULT uuid_generate_v4() NOT NULL,
  barberia_id uuid,
  nombre text NOT NULL,
  whatsapp text,
  email text,
  comision_pct numeric DEFAULT 50,
  meta_visitas integer DEFAULT 80,
  activo boolean DEFAULT true,
  foto_url text,
  created_at timestamp with time zone DEFAULT now(),
  meta_citas integer DEFAULT 80,
  auth_user_id uuid,
  puede_procesar_pagos boolean DEFAULT false NOT NULL,
  bio text,
  especialidad text
);

-- bloqueos_profesional
CREATE TABLE IF NOT EXISTS public.bloqueos_profesional (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  barberia_id uuid NOT NULL,
  profesional_id uuid NOT NULL,
  tipo text NOT NULL,
  fecha date,
  dia_semana integer,
  hora_inicio time without time zone,
  hora_fin time without time zone,
  motivo text,
  activo boolean DEFAULT true NOT NULL,
  created_at timestamp with time zone DEFAULT now() NOT NULL
);

-- clientes
CREATE TABLE IF NOT EXISTS public.clientes (
  id uuid DEFAULT uuid_generate_v4() NOT NULL,
  barberia_id uuid,
  nombre text NOT NULL,
  apellido text,
  whatsapp text,
  email text,
  cumpleanos date,
  barbero_preferido text,
  canal text DEFAULT 'Directo'::text,
  notas text,
  fecha_registro date DEFAULT CURRENT_DATE,
  created_at timestamp with time zone DEFAULT now()
);

-- costos
CREATE TABLE IF NOT EXISTS public.costos (
  id uuid DEFAULT uuid_generate_v4() NOT NULL,
  barberia_id uuid,
  fecha date NOT NULL,
  descripcion text NOT NULL,
  tipo text DEFAULT 'fijo'::text,
  categoria text,
  monto_neto numeric DEFAULT 0,
  iva numeric DEFAULT 0,
  total numeric DEFAULT 0,
  created_at timestamp with time zone DEFAULT now()
);

-- horario_negocio
CREATE TABLE IF NOT EXISTS public.horario_negocio (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  barberia_id uuid NOT NULL,
  dia_semana integer NOT NULL,
  hora_apertura time without time zone,
  hora_cierre time without time zone,
  cerrado boolean DEFAULT false NOT NULL,
  hora_colacion_inicio time without time zone,
  hora_colacion_fin time without time zone
);

-- inventario
CREATE TABLE IF NOT EXISTS public.inventario (
  id uuid DEFAULT uuid_generate_v4() NOT NULL,
  barberia_id uuid,
  codigo text,
  nombre text NOT NULL,
  categoria text,
  proveedor text,
  stock integer DEFAULT 0,
  stock_min integer DEFAULT 2,
  stock_max integer DEFAULT 20,
  costo_unitario numeric DEFAULT 0,
  precio_venta numeric DEFAULT 0,
  ultima_revision date DEFAULT CURRENT_DATE,
  created_at timestamp with time zone DEFAULT now()
);

-- movimientos_stock
CREATE TABLE IF NOT EXISTS public.movimientos_stock (
  id uuid DEFAULT uuid_generate_v4() NOT NULL,
  barberia_id uuid,
  producto_id uuid,
  tipo text NOT NULL,
  cantidad integer NOT NULL,
  costo_unitario numeric,
  proveedor text,
  motivo text,
  responsable text,
  notas text,
  fecha date DEFAULT CURRENT_DATE,
  created_at timestamp with time zone DEFAULT now()
);

-- niveles_vip
CREATE TABLE IF NOT EXISTS public.niveles_vip (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  barberia_id uuid NOT NULL,
  orden integer NOT NULL,
  nombre text NOT NULL,
  visitas_minimas integer NOT NULL,
  beneficio text,
  created_at timestamp with time zone DEFAULT now() NOT NULL
);

-- perfiles
CREATE TABLE IF NOT EXISTS public.perfiles (
  id uuid NOT NULL,
  barberia_id uuid,
  nombre text,
  rol text DEFAULT 'barbero'::text,
  whatsapp text,
  comision_pct numeric DEFAULT 50,
  meta_visitas integer DEFAULT 80,
  activo boolean DEFAULT true,
  created_at timestamp with time zone DEFAULT now()
);

-- plantillas_mensajes
CREATE TABLE IF NOT EXISTS public.plantillas_mensajes (
  id uuid DEFAULT uuid_generate_v4() NOT NULL,
  barberia_id uuid,
  evento text NOT NULL,
  mensaje text NOT NULL,
  activo boolean DEFAULT true,
  created_at timestamp with time zone DEFAULT now()
);

-- reservas
CREATE TABLE IF NOT EXISTS public.reservas (
  id uuid DEFAULT uuid_generate_v4() NOT NULL,
  barberia_id uuid,
  nombre_cliente text NOT NULL,
  whatsapp_cliente text,
  email_cliente text,
  fecha date NOT NULL,
  hora time without time zone NOT NULL,
  servicio text,
  barbero_nombre text,
  estado text DEFAULT 'Confirmada'::text,
  procesado boolean DEFAULT false,
  notas text,
  fuente text DEFAULT 'Manual'::text,
  created_at timestamp with time zone DEFAULT now(),
  cumpleanos_cliente date,
  oculto_profesional boolean DEFAULT false NOT NULL
);

-- servicios
CREATE TABLE IF NOT EXISTS public.servicios (
  id uuid DEFAULT uuid_generate_v4() NOT NULL,
  barberia_id uuid,
  nombre text NOT NULL,
  precio numeric DEFAULT 0,
  duracion_min integer DEFAULT 30,
  comision_pct numeric DEFAULT 50,
  activo boolean DEFAULT true,
  created_at timestamp with time zone DEFAULT now(),
  foto_url text,
  descripcion text
);

-- vip_historial
CREATE TABLE IF NOT EXISTS public.vip_historial (
  id uuid DEFAULT uuid_generate_v4() NOT NULL,
  barberia_id uuid,
  cliente_id uuid,
  nivel text NOT NULL,
  beneficio text,
  fecha_ganado date DEFAULT CURRENT_DATE,
  fecha_expira date,
  canjeado boolean DEFAULT false,
  fecha_canje date,
  msg_enviado boolean DEFAULT false,
  created_at timestamp with time zone DEFAULT now()
);

-- visitas
CREATE TABLE IF NOT EXISTS public.visitas (
  id uuid DEFAULT uuid_generate_v4() NOT NULL,
  barberia_id uuid,
  cliente_id uuid,
  barbero_id uuid,
  barbero_nombre text,
  servicio text,
  valor numeric DEFAULT 0,
  fecha date NOT NULL,
  hora time without time zone,
  metodo_pago text DEFAULT 'Efectivo'::text,
  fuente text DEFAULT 'Presencial'::text,
  notas text,
  created_at timestamp with time zone DEFAULT now(),
  estado text DEFAULT 'Atendida'::text NOT NULL,
  comision_monto numeric,
  oculto_profesional boolean DEFAULT false NOT NULL
);


-- =============================================================================
-- 2. CONSTRAINTS
-- Primarias, únicas, checks y foráneas.
-- =============================================================================

-- alianza_canjes.alianza_canjes_barberia_id_fkey
ALTER TABLE public.alianza_canjes ADD CONSTRAINT alianza_canjes_barberia_id_fkey FOREIGN KEY (barberia_id) REFERENCES barberias(id);

-- alianza_canjes.alianza_canjes_codigo_id_fkey
ALTER TABLE public.alianza_canjes ADD CONSTRAINT alianza_canjes_codigo_id_fkey FOREIGN KEY (codigo_id) REFERENCES alianza_codigos(id);

-- alianza_canjes.alianza_canjes_pkey
ALTER TABLE public.alianza_canjes ADD CONSTRAINT alianza_canjes_pkey PRIMARY KEY (id);

-- alianza_codigos.alianza_codigos_alianza_id_fkey
ALTER TABLE public.alianza_codigos ADD CONSTRAINT alianza_codigos_alianza_id_fkey FOREIGN KEY (alianza_id) REFERENCES alianzas(id);

-- alianza_codigos.alianza_codigos_barberia_id_fkey
ALTER TABLE public.alianza_codigos ADD CONSTRAINT alianza_codigos_barberia_id_fkey FOREIGN KEY (barberia_id) REFERENCES barberias(id);

-- alianza_codigos.alianza_codigos_cliente_id_fkey
ALTER TABLE public.alianza_codigos ADD CONSTRAINT alianza_codigos_cliente_id_fkey FOREIGN KEY (cliente_id) REFERENCES clientes(id);

-- alianza_codigos.alianza_codigos_codigo_key
ALTER TABLE public.alianza_codigos ADD CONSTRAINT alianza_codigos_codigo_key UNIQUE (codigo);

-- alianza_codigos.alianza_codigos_pkey
ALTER TABLE public.alianza_codigos ADD CONSTRAINT alianza_codigos_pkey PRIMARY KEY (id);

-- alianza_codigos.alianza_codigos_tipo_check
ALTER TABLE public.alianza_codigos ADD CONSTRAINT alianza_codigos_tipo_check CHECK ((tipo = ANY (ARRAY['cliente'::text, 'generico'::text])));

-- alianzas.alianzas_barberia_id_fkey
ALTER TABLE public.alianzas ADD CONSTRAINT alianzas_barberia_id_fkey FOREIGN KEY (barberia_id) REFERENCES barberias(id);

-- alianzas.alianzas_nivel_minimo_id_fkey
ALTER TABLE public.alianzas ADD CONSTRAINT alianzas_nivel_minimo_id_fkey FOREIGN KEY (nivel_minimo_id) REFERENCES niveles_vip(id) ON DELETE SET NULL;

-- alianzas.alianzas_pkey
ALTER TABLE public.alianzas ADD CONSTRAINT alianzas_pkey PRIMARY KEY (id);

-- barberias.barberias_creado_por_fkey
ALTER TABLE public.barberias ADD CONSTRAINT barberias_creado_por_fkey FOREIGN KEY (creado_por) REFERENCES auth.users(id);

-- barberias.barberias_pkey
ALTER TABLE public.barberias ADD CONSTRAINT barberias_pkey PRIMARY KEY (id);

-- barbero_servicios.barbero_servicios_barberia_id_fkey
ALTER TABLE public.barbero_servicios ADD CONSTRAINT barbero_servicios_barberia_id_fkey FOREIGN KEY (barberia_id) REFERENCES barberias(id) ON DELETE CASCADE;

-- barbero_servicios.barbero_servicios_barbero_id_fkey
ALTER TABLE public.barbero_servicios ADD CONSTRAINT barbero_servicios_barbero_id_fkey FOREIGN KEY (barbero_id) REFERENCES barberos(id) ON DELETE CASCADE;

-- barbero_servicios.barbero_servicios_barbero_id_servicio_id_key
ALTER TABLE public.barbero_servicios ADD CONSTRAINT barbero_servicios_barbero_id_servicio_id_key UNIQUE (barbero_id, servicio_id);

-- barbero_servicios.barbero_servicios_pkey
ALTER TABLE public.barbero_servicios ADD CONSTRAINT barbero_servicios_pkey PRIMARY KEY (id);

-- barbero_servicios.barbero_servicios_servicio_id_fkey
ALTER TABLE public.barbero_servicios ADD CONSTRAINT barbero_servicios_servicio_id_fkey FOREIGN KEY (servicio_id) REFERENCES servicios(id) ON DELETE CASCADE;

-- barberos.barberos_auth_user_id_fkey
ALTER TABLE public.barberos ADD CONSTRAINT barberos_auth_user_id_fkey FOREIGN KEY (auth_user_id) REFERENCES auth.users(id) ON DELETE SET NULL;

-- barberos.barberos_auth_user_id_key
ALTER TABLE public.barberos ADD CONSTRAINT barberos_auth_user_id_key UNIQUE (auth_user_id);

-- barberos.barberos_barberia_id_fkey
ALTER TABLE public.barberos ADD CONSTRAINT barberos_barberia_id_fkey FOREIGN KEY (barberia_id) REFERENCES barberias(id) ON DELETE CASCADE;

-- barberos.barberos_pkey
ALTER TABLE public.barberos ADD CONSTRAINT barberos_pkey PRIMARY KEY (id);

-- bloqueos_profesional.bloqueos_profesional_barberia_id_fkey
ALTER TABLE public.bloqueos_profesional ADD CONSTRAINT bloqueos_profesional_barberia_id_fkey FOREIGN KEY (barberia_id) REFERENCES barberias(id);

-- bloqueos_profesional.bloqueos_profesional_dia_semana_check
ALTER TABLE public.bloqueos_profesional ADD CONSTRAINT bloqueos_profesional_dia_semana_check CHECK (((dia_semana >= 0) AND (dia_semana <= 6)));

-- bloqueos_profesional.bloqueos_profesional_pkey
ALTER TABLE public.bloqueos_profesional ADD CONSTRAINT bloqueos_profesional_pkey PRIMARY KEY (id);

-- bloqueos_profesional.bloqueos_profesional_profesional_id_fkey
ALTER TABLE public.bloqueos_profesional ADD CONSTRAINT bloqueos_profesional_profesional_id_fkey FOREIGN KEY (profesional_id) REFERENCES barberos(id);

-- bloqueos_profesional.bloqueos_profesional_tipo_check
ALTER TABLE public.bloqueos_profesional ADD CONSTRAINT bloqueos_profesional_tipo_check CHECK ((tipo = ANY (ARRAY['puntual'::text, 'dia_completo'::text, 'recurrente'::text])));

-- clientes.clientes_barberia_id_fkey
ALTER TABLE public.clientes ADD CONSTRAINT clientes_barberia_id_fkey FOREIGN KEY (barberia_id) REFERENCES barberias(id) ON DELETE CASCADE;

-- clientes.clientes_pkey
ALTER TABLE public.clientes ADD CONSTRAINT clientes_pkey PRIMARY KEY (id);

-- costos.costos_barberia_id_fkey
ALTER TABLE public.costos ADD CONSTRAINT costos_barberia_id_fkey FOREIGN KEY (barberia_id) REFERENCES barberias(id) ON DELETE CASCADE;

-- costos.costos_pkey
ALTER TABLE public.costos ADD CONSTRAINT costos_pkey PRIMARY KEY (id);

-- horario_negocio.horario_colacion_coherente
ALTER TABLE public.horario_negocio ADD CONSTRAINT horario_colacion_coherente CHECK ((((hora_colacion_inicio IS NULL) AND (hora_colacion_fin IS NULL)) OR ((hora_colacion_inicio IS NOT NULL) AND (hora_colacion_fin IS NOT NULL) AND (hora_colacion_inicio < hora_colacion_fin))));

-- horario_negocio.horario_negocio_barberia_id_dia_semana_key
ALTER TABLE public.horario_negocio ADD CONSTRAINT horario_negocio_barberia_id_dia_semana_key UNIQUE (barberia_id, dia_semana);

-- horario_negocio.horario_negocio_barberia_id_fkey
ALTER TABLE public.horario_negocio ADD CONSTRAINT horario_negocio_barberia_id_fkey FOREIGN KEY (barberia_id) REFERENCES barberias(id);

-- horario_negocio.horario_negocio_dia_semana_check
ALTER TABLE public.horario_negocio ADD CONSTRAINT horario_negocio_dia_semana_check CHECK (((dia_semana >= 0) AND (dia_semana <= 6)));

-- horario_negocio.horario_negocio_pkey
ALTER TABLE public.horario_negocio ADD CONSTRAINT horario_negocio_pkey PRIMARY KEY (id);

-- inventario.inventario_barberia_id_fkey
ALTER TABLE public.inventario ADD CONSTRAINT inventario_barberia_id_fkey FOREIGN KEY (barberia_id) REFERENCES barberias(id) ON DELETE CASCADE;

-- inventario.inventario_pkey
ALTER TABLE public.inventario ADD CONSTRAINT inventario_pkey PRIMARY KEY (id);

-- movimientos_stock.movimientos_stock_barberia_id_fkey
ALTER TABLE public.movimientos_stock ADD CONSTRAINT movimientos_stock_barberia_id_fkey FOREIGN KEY (barberia_id) REFERENCES barberias(id) ON DELETE CASCADE;

-- movimientos_stock.movimientos_stock_pkey
ALTER TABLE public.movimientos_stock ADD CONSTRAINT movimientos_stock_pkey PRIMARY KEY (id);

-- movimientos_stock.movimientos_stock_producto_id_fkey
ALTER TABLE public.movimientos_stock ADD CONSTRAINT movimientos_stock_producto_id_fkey FOREIGN KEY (producto_id) REFERENCES inventario(id) ON DELETE CASCADE;

-- niveles_vip.niveles_vip_barberia_id_fkey
ALTER TABLE public.niveles_vip ADD CONSTRAINT niveles_vip_barberia_id_fkey FOREIGN KEY (barberia_id) REFERENCES barberias(id);

-- niveles_vip.niveles_vip_barberia_id_orden_key
ALTER TABLE public.niveles_vip ADD CONSTRAINT niveles_vip_barberia_id_orden_key UNIQUE (barberia_id, orden);

-- niveles_vip.niveles_vip_pkey
ALTER TABLE public.niveles_vip ADD CONSTRAINT niveles_vip_pkey PRIMARY KEY (id);

-- perfiles.perfiles_barberia_id_fkey
ALTER TABLE public.perfiles ADD CONSTRAINT perfiles_barberia_id_fkey FOREIGN KEY (barberia_id) REFERENCES barberias(id) ON DELETE CASCADE;

-- perfiles.perfiles_id_fkey
ALTER TABLE public.perfiles ADD CONSTRAINT perfiles_id_fkey FOREIGN KEY (id) REFERENCES auth.users(id) ON DELETE CASCADE;

-- perfiles.perfiles_pkey
ALTER TABLE public.perfiles ADD CONSTRAINT perfiles_pkey PRIMARY KEY (id);

-- plantillas_mensajes.plantillas_mensajes_barberia_id_fkey
ALTER TABLE public.plantillas_mensajes ADD CONSTRAINT plantillas_mensajes_barberia_id_fkey FOREIGN KEY (barberia_id) REFERENCES barberias(id) ON DELETE CASCADE;

-- plantillas_mensajes.plantillas_mensajes_pkey
ALTER TABLE public.plantillas_mensajes ADD CONSTRAINT plantillas_mensajes_pkey PRIMARY KEY (id);

-- reservas.reservas_barberia_id_fkey
ALTER TABLE public.reservas ADD CONSTRAINT reservas_barberia_id_fkey FOREIGN KEY (barberia_id) REFERENCES barberias(id) ON DELETE CASCADE;

-- reservas.reservas_pkey
ALTER TABLE public.reservas ADD CONSTRAINT reservas_pkey PRIMARY KEY (id);

-- servicios.servicios_barberia_id_fkey
ALTER TABLE public.servicios ADD CONSTRAINT servicios_barberia_id_fkey FOREIGN KEY (barberia_id) REFERENCES barberias(id) ON DELETE CASCADE;

-- servicios.servicios_pkey
ALTER TABLE public.servicios ADD CONSTRAINT servicios_pkey PRIMARY KEY (id);

-- vip_historial.vip_historial_barberia_id_fkey
ALTER TABLE public.vip_historial ADD CONSTRAINT vip_historial_barberia_id_fkey FOREIGN KEY (barberia_id) REFERENCES barberias(id) ON DELETE CASCADE;

-- vip_historial.vip_historial_cliente_id_fkey
ALTER TABLE public.vip_historial ADD CONSTRAINT vip_historial_cliente_id_fkey FOREIGN KEY (cliente_id) REFERENCES clientes(id) ON DELETE CASCADE;

-- vip_historial.vip_historial_pkey
ALTER TABLE public.vip_historial ADD CONSTRAINT vip_historial_pkey PRIMARY KEY (id);

-- visitas.visitas_barberia_id_fkey
ALTER TABLE public.visitas ADD CONSTRAINT visitas_barberia_id_fkey FOREIGN KEY (barberia_id) REFERENCES barberias(id) ON DELETE CASCADE;

-- visitas.visitas_barbero_id_fkey
ALTER TABLE public.visitas ADD CONSTRAINT visitas_barbero_id_fkey FOREIGN KEY (barbero_id) REFERENCES perfiles(id) ON DELETE SET NULL;

-- visitas.visitas_cliente_id_fkey
ALTER TABLE public.visitas ADD CONSTRAINT visitas_cliente_id_fkey FOREIGN KEY (cliente_id) REFERENCES clientes(id) ON DELETE SET NULL;

-- visitas.visitas_pkey
ALTER TABLE public.visitas ADD CONSTRAINT visitas_pkey PRIMARY KEY (id);


-- =============================================================================
-- 3. ÍNDICES
-- Solo los que no respaldan un constraint.
-- =============================================================================

-- alianza_codigos_unico_por_cliente
CREATE UNIQUE INDEX alianza_codigos_unico_por_cliente ON public.alianza_codigos USING btree (alianza_id, cliente_id) WHERE (tipo = 'cliente'::text);


-- =============================================================================
-- 4. FUNCIONES Y RPCs
-- Incluye las security definer que expone PostgREST.
-- =============================================================================

-- auth_barberia_id
CREATE OR REPLACE FUNCTION public.auth_barberia_id()
 RETURNS uuid
 LANGUAGE sql
 STABLE SECURITY DEFINER
AS $function$
  select barberia_id from perfiles where id = auth.uid()
$function$
;

-- auth_barbero_id
CREATE OR REPLACE FUNCTION public.auth_barbero_id()
 RETURNS uuid
 LANGUAGE sql
 STABLE SECURITY DEFINER
AS $function$
  select id from barberos where auth_user_id = auth.uid() and activo = true
$function$
;

-- auth_rol
CREATE OR REPLACE FUNCTION public.auth_rol()
 RETURNS text
 LANGUAGE sql
 STABLE SECURITY DEFINER
AS $function$
  select rol from perfiles where id = auth.uid()
$function$
;

-- buscar_o_crear_cliente_club
CREATE OR REPLACE FUNCTION public.buscar_o_crear_cliente_club(p_barberia_id uuid, p_reserva_id uuid)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_cliente_id uuid;
  v_reserva reservas%rowtype;
begin
  select * into v_reserva
  from reservas
  where id = p_reserva_id and barberia_id = p_barberia_id;
  if not found then
    raise exception 'Reserva no encontrada para este negocio';
  end if;
  select id into v_cliente_id
  from clientes
  where barberia_id = p_barberia_id and whatsapp = v_reserva.whatsapp_cliente
  limit 1;
  if v_cliente_id is not null then
    return v_cliente_id;
  end if;
  insert into clientes (barberia_id, nombre, whatsapp, cumpleanos, canal, fecha_registro)
  values (
    p_barberia_id, v_reserva.nombre_cliente, v_reserva.whatsapp_cliente,
    v_reserva.cumpleanos_cliente, 'Reserva Web', v_reserva.fecha
  )
  returning id into v_cliente_id;
  return v_cliente_id;
end;
$function$
;

-- crear_reserva_publica
CREATE OR REPLACE FUNCTION public.crear_reserva_publica(p_barberia_id uuid, p_nombre_cliente text, p_whatsapp_cliente text, p_fecha date, p_hora time without time zone, p_email_cliente text DEFAULT NULL::text, p_cumpleanos_cliente date DEFAULT NULL::date, p_servicio text DEFAULT NULL::text, p_barbero_nombre text DEFAULT NULL::text, p_notas text DEFAULT NULL::text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_id uuid;
begin
  insert into reservas (
    barberia_id, nombre_cliente, whatsapp_cliente, email_cliente,
    cumpleanos_cliente, fecha, hora, servicio, barbero_nombre,
    estado, procesado, notas, fuente
  ) values (
    p_barberia_id, p_nombre_cliente, p_whatsapp_cliente, p_email_cliente,
    p_cumpleanos_cliente, p_fecha, p_hora, p_servicio,
    coalesce(p_barbero_nombre, 'Por asignar'),
    'Confirmada', false, p_notas, 'Web propia'
  ) returning id into v_id;
  return v_id;
end;
$function$
;

-- crear_reserva_publica_club
CREATE OR REPLACE FUNCTION public.crear_reserva_publica_club(p_barberia_id uuid, p_cliente_id uuid, p_fecha date, p_hora time without time zone, p_servicio text DEFAULT NULL::text, p_barbero_nombre text DEFAULT NULL::text, p_notas text DEFAULT NULL::text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_id uuid;
  v_cliente clientes%rowtype;
begin
  select * into v_cliente
  from clientes
  where id = p_cliente_id and barberia_id = p_barberia_id;
  if not found then
    raise exception 'Cliente no encontrado para este negocio';
  end if;
  insert into reservas (
    barberia_id, nombre_cliente, whatsapp_cliente, email_cliente,
    cumpleanos_cliente, fecha, hora, servicio, barbero_nombre,
    estado, procesado, notas, fuente
  ) values (
    p_barberia_id,
    trim(v_cliente.nombre || ' ' || coalesce(v_cliente.apellido, '')),
    v_cliente.whatsapp, v_cliente.email, v_cliente.cumpleanos,
    p_fecha, p_hora, p_servicio,
    coalesce(p_barbero_nombre, 'Por asignar'),
    'Confirmada', false, p_notas, 'Club VIP'
  ) returning id into v_id;
  return v_id;
end;
$function$
;

-- generar_codigo_alianza
CREATE OR REPLACE FUNCTION public.generar_codigo_alianza()
 RETURNS text
 LANGUAGE plpgsql
AS $function$
declare
  v_chars text := 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';
  v_codigo text;
begin
  v_codigo := '';
  for i in 1..8 loop
    v_codigo := v_codigo || substr(v_chars, floor(random() * length(v_chars))::int + 1, 1);
  end loop;
  return v_codigo;
end;
$function$
;

-- generar_codigo_generico_publico
CREATE OR REPLACE FUNCTION public.generar_codigo_generico_publico(p_barberia_id uuid, p_alianza_id uuid)
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_codigo text;
begin
  if not exists (select 1 from alianzas where id = p_alianza_id and barberia_id = p_barberia_id and activo = true) then
    raise exception 'Alianza inválida';
  end if;

  loop
    begin
      v_codigo := generar_codigo_alianza();
      insert into alianza_codigos (barberia_id, alianza_id, cliente_id, tipo, codigo)
        values (p_barberia_id, p_alianza_id, null, 'generico', v_codigo);
      return v_codigo;
    exception when unique_violation then
      -- colisión de código global (rarísima) — reintenta con uno nuevo.
    end;
  end loop;
end;
$function$
;

-- get_barberia_id
CREATE OR REPLACE FUNCTION public.get_barberia_id()
 RETURNS uuid
 LANGUAGE sql
 SECURITY DEFINER
AS $function$
  select barberia_id from perfiles where id = auth.uid();
$function$
;

-- get_club_vip_historial_publico
CREATE OR REPLACE FUNCTION public.get_club_vip_historial_publico(p_barberia_id uuid, p_cliente_id uuid)
 RETURNS TABLE(id uuid, cliente_id uuid, barberia_id uuid, nivel text, beneficio text, fecha_ganado timestamp with time zone, fecha_expira timestamp with time zone, canjeado boolean)
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select id, cliente_id, barberia_id, nivel, beneficio, fecha_ganado, fecha_expira, canjeado
  from vip_historial
  where cliente_id = p_cliente_id
    and barberia_id = p_barberia_id
  order by fecha_ganado desc;
$function$
;

-- get_club_vip_publico
CREATE OR REPLACE FUNCTION public.get_club_vip_publico(p_barberia_id uuid, p_cliente_id uuid)
 RETURNS TABLE(cliente_id uuid, barberia_id uuid, nombre text, total_visitas bigint, nivel text)
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  with base as (
    select
      c.id as cliente_id,
      c.barberia_id,
      c.nombre,
      count(v.id) as total_visitas
    from clientes c
    left join visitas v on v.cliente_id = c.id
    where c.id = p_cliente_id
      and c.barberia_id = p_barberia_id
    group by c.id, c.barberia_id, c.nombre
  )
  select
    base.cliente_id,
    base.barberia_id,
    base.nombre,
    base.total_visitas,
    coalesce(
      (
        select nv.nombre
        from niveles_vip nv
        where nv.barberia_id = base.barberia_id
          and nv.visitas_minimas <= base.total_visitas
        order by nv.orden desc
        limit 1
      ),
      'Sin nivel'
    ) as nivel
  from base;
$function$
;

-- handle_new_user
CREATE OR REPLACE FUNCTION public.handle_new_user()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
begin
  insert into perfiles (id, nombre, rol)
  values (
    new.id,
    coalesce(new.raw_user_meta_data->>'nombre', new.email),
    coalesce(new.raw_user_meta_data->>'rol', 'dueno')
  )
  on conflict (id) do nothing;
  return new;
end;
$function$
;

-- mi_agenda_buscar_cliente
CREATE OR REPLACE FUNCTION public.mi_agenda_buscar_cliente(p_query text)
 RETURNS TABLE(id uuid, nombre text, whatsapp text)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select c.id, c.nombre, c.whatsapp
  from clientes c
  where c.barberia_id = auth_barberia_id()
    and auth_barbero_id() is not null
    and (c.nombre ilike '%' || p_query || '%' or c.whatsapp ilike '%' || p_query || '%')
  order by c.nombre
  limit 15
$function$
;

-- mi_agenda_cancelar_cita
CREATE OR REPLACE FUNCTION public.mi_agenda_cancelar_cita(p_id uuid, p_tipo text)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_barbero_id uuid := auth_barbero_id();
  v_nombre text;
  v_barberia uuid := auth_barberia_id();
  v_rows int;
begin
  if v_barbero_id is null then
    raise exception 'No autorizado';
  end if;
  select nombre into v_nombre from barberos where id = v_barbero_id;

  if p_tipo = 'reserva' then
    update reservas set estado = 'Cancelada'
      where id = p_id and barberia_id = v_barberia and barbero_nombre = v_nombre;
  elsif p_tipo = 'visita' then
    update visitas set estado = 'Cancelada'
      where id = p_id and barberia_id = v_barberia and barbero_nombre = v_nombre;
  else
    raise exception 'Tipo inválido';
  end if;

  get diagnostics v_rows = row_count;
  return v_rows > 0;
end;
$function$
;

-- mi_agenda_citas
CREATE OR REPLACE FUNCTION public.mi_agenda_citas(p_fecha date)
 RETURNS TABLE(id uuid, tipo text, fecha date, hora time without time zone, servicio text, estado text, procesado boolean, nombre_cliente text, whatsapp_cliente text, valor numeric, comision_monto numeric, notas text)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_barbero_id uuid := auth_barbero_id();
  v_nombre text;
  v_barberia uuid := auth_barberia_id();
begin
  if v_barbero_id is null then
    return;
  end if;
  select nombre into v_nombre from barberos where barberos.id = v_barbero_id;

  return query
  select r.id, 'reserva'::text, r.fecha, r.hora, r.servicio, r.estado, r.procesado,
         r.nombre_cliente, r.whatsapp_cliente, null::numeric, null::numeric, r.notas
  from reservas r
  where r.barberia_id = v_barberia and r.barbero_nombre = v_nombre
    and r.fecha = p_fecha and r.oculto_profesional = false
    and r.procesado = false
  union all
  select v.id, 'visita'::text, v.fecha, v.hora, v.servicio, v.estado, true,
         c.nombre, c.whatsapp, v.valor, v.comision_monto, v.notas
  from visitas v
  left join clientes c on c.id = v.cliente_id
  where v.barberia_id = v_barberia and v.barbero_nombre = v_nombre
    and v.fecha = p_fecha and v.oculto_profesional = false
  order by 4;
end;
$function$
;

-- mi_agenda_comisiones
CREATE OR REPLACE FUNCTION public.mi_agenda_comisiones(p_desde date DEFAULT NULL::date, p_hasta date DEFAULT NULL::date)
 RETURNS TABLE(fecha date, servicio text, valor numeric, comision_monto numeric, estado text)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select v.fecha, v.servicio, v.valor, v.comision_monto, v.estado
  from visitas v
  where v.barberia_id = auth_barberia_id()
    and v.barbero_nombre = (select nombre from barberos where id = auth_barbero_id())
    and auth_barbero_id() is not null
    and (p_desde is null or v.fecha >= p_desde)
    and (p_hasta is null or v.fecha <= p_hasta)
  order by v.fecha desc
$function$
;

-- mi_agenda_crear_reserva
CREATE OR REPLACE FUNCTION public.mi_agenda_crear_reserva(p_nombre_cliente text, p_whatsapp_cliente text, p_fecha date, p_hora time without time zone, p_servicio text DEFAULT NULL::text, p_notas text DEFAULT NULL::text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_barbero_id uuid := auth_barbero_id();
  v_nombre text;
  v_barberia uuid := auth_barberia_id();
  v_id uuid;
begin
  if v_barbero_id is null then
    raise exception 'No autorizado';
  end if;
  select nombre into v_nombre from barberos where id = v_barbero_id;

  insert into reservas (
    barberia_id, nombre_cliente, whatsapp_cliente, fecha, hora,
    servicio, barbero_nombre, estado, procesado, notas, fuente
  ) values (
    v_barberia, p_nombre_cliente, p_whatsapp_cliente, p_fecha, p_hora,
    p_servicio, v_nombre, 'Confirmada', false, p_notas, 'Mi Agenda'
  ) returning id into v_id;

  return v_id;
end;
$function$
;

-- mi_agenda_eliminar_cita
CREATE OR REPLACE FUNCTION public.mi_agenda_eliminar_cita(p_id uuid, p_tipo text)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_barbero_id uuid := auth_barbero_id();
  v_nombre text;
  v_barberia uuid := auth_barberia_id();
  v_rows int;
begin
  if v_barbero_id is null then
    raise exception 'No autorizado';
  end if;
  select nombre into v_nombre from barberos where id = v_barbero_id;

  if p_tipo = 'reserva' then
    update reservas set oculto_profesional = true
      where id = p_id and barberia_id = v_barberia and barbero_nombre = v_nombre;
  elsif p_tipo = 'visita' then
    update visitas set oculto_profesional = true
      where id = p_id and barberia_id = v_barberia and barbero_nombre = v_nombre;
  else
    raise exception 'Tipo inválido';
  end if;

  get diagnostics v_rows = row_count;
  return v_rows > 0;
end;
$function$
;

-- mi_agenda_procesar_pago
CREATE OR REPLACE FUNCTION public.mi_agenda_procesar_pago(p_reserva_id uuid, p_metodo_pago text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_barbero_id uuid := auth_barbero_id();
  v_nombre text;
  v_puede boolean;
  v_barberia uuid := auth_barberia_id();
  v_reserva reservas%rowtype;
  v_cliente_id uuid;
  v_precio numeric;
  v_comision_pct numeric;
  v_modo_comision text;
  v_iva_pct numeric;
  v_base numeric;
  v_comision_monto numeric;
  v_visita_id uuid;
begin
  if v_barbero_id is null then
    raise exception 'No autorizado';
  end if;

  select nombre, puede_procesar_pagos, comision_pct
    into v_nombre, v_puede, v_comision_pct
    from barberos where barberos.id = v_barbero_id;

  if not coalesce(v_puede, false) then
    raise exception 'No tenés permiso para procesar pagos. Pedile al dueño que lo active en Config → Equipo.';
  end if;

  select * into v_reserva from reservas
    where id = p_reserva_id and barberia_id = v_barberia and barbero_nombre = v_nombre;
  if not found then
    raise exception 'Reserva no encontrada';
  end if;
  if v_reserva.procesado then
    raise exception 'Esta reserva ya fue procesada';
  end if;

  select c.id into v_cliente_id from clientes c
    where c.barberia_id = v_barberia and c.whatsapp = v_reserva.whatsapp_cliente;
  if v_cliente_id is null then
    insert into clientes (barberia_id, nombre, whatsapp, cumpleanos, canal, fecha_registro)
    values (v_barberia, v_reserva.nombre_cliente, v_reserva.whatsapp_cliente, v_reserva.cumpleanos_cliente, 'Reserva Web', v_reserva.fecha)
    returning id into v_cliente_id;
  end if;

  select precio into v_precio from servicios where barberia_id = v_barberia and nombre = v_reserva.servicio;
  v_precio := coalesce(v_precio, 0);
  v_comision_pct := coalesce(v_comision_pct, 50);

  select modo_comision, iva_pct into v_modo_comision, v_iva_pct from barberias where id = v_barberia;
  if v_modo_comision = 'neto_iva' then
    v_base := v_precio - (v_precio * coalesce(v_iva_pct, 19) / (100 + coalesce(v_iva_pct, 19)));
  else
    v_base := v_precio;
  end if;
  v_comision_monto := round(v_base * v_comision_pct / 100);

  insert into visitas (
    barberia_id, cliente_id, barbero_nombre, servicio, valor, fecha, hora,
    fuente, estado, comision_monto, metodo_pago
  ) values (
    v_barberia, v_cliente_id, v_nombre, v_reserva.servicio, v_precio, v_reserva.fecha, v_reserva.hora,
    'Reserva', 'Atendida', v_comision_monto, p_metodo_pago
  ) returning id into v_visita_id;

  update reservas set procesado = true, estado = 'Atendida' where id = p_reserva_id;

  return v_visita_id;
end;
$function$
;

-- obtener_codigo_alianza_publico
CREATE OR REPLACE FUNCTION public.obtener_codigo_alianza_publico(p_barberia_id uuid, p_cliente_id uuid, p_alianza_id uuid)
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_codigo text;
begin
  if not exists (select 1 from clientes where id = p_cliente_id and barberia_id = p_barberia_id) then
    raise exception 'Cliente inválido';
  end if;
  if not exists (select 1 from alianzas where id = p_alianza_id and barberia_id = p_barberia_id and activo = true) then
    raise exception 'Alianza inválida';
  end if;

  select codigo into v_codigo from alianza_codigos
    where alianza_id = p_alianza_id and cliente_id = p_cliente_id and tipo = 'cliente';
  if found then
    return v_codigo;
  end if;

  loop
    begin
      v_codigo := generar_codigo_alianza();
      insert into alianza_codigos (barberia_id, alianza_id, cliente_id, tipo, codigo)
        values (p_barberia_id, p_alianza_id, p_cliente_id, 'cliente', v_codigo);
      return v_codigo;
    exception when unique_violation then
      -- colisión de código global (rarísima) o llamada concurrente duplicada
      -- para el mismo cliente+alianza (el índice parcial la frena) — en ese
      -- segundo caso ya existe la fila, así que la traemos y listo.
      select codigo into v_codigo from alianza_codigos
        where alianza_id = p_alianza_id and cliente_id = p_cliente_id and tipo = 'cliente';
      if found then
        return v_codigo;
      end if;
    end;
  end loop;
end;
$function$
;

-- obtener_plantilla_publica
CREATE OR REPLACE FUNCTION public.obtener_plantilla_publica(p_barberia_id uuid, p_evento text)
 RETURNS text
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select mensaje from plantillas_mensajes
  where barberia_id = p_barberia_id and evento = p_evento and activo = true
  limit 1
$function$
;

-- validar_codigo_alianza_negocio
CREATE OR REPLACE FUNCTION public.validar_codigo_alianza_negocio(p_alianza_id uuid, p_codigo text)
 RETURNS timestamp with time zone
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_barberia uuid := auth_barberia_id();
  v_codigo_id uuid;
  v_activo boolean;
  v_fecha timestamptz;
begin
  if v_barberia is null then
    raise exception 'No autorizado';
  end if;

  select id, activo into v_codigo_id, v_activo from alianza_codigos
    where codigo = upper(trim(p_codigo))
      and alianza_id = p_alianza_id
      and barberia_id = v_barberia
      and tipo = 'generico'
      -- alianza desactivada cae en "not found" (Código inválido), nunca en
      -- la rama de "ya fue usado" — esa distinción es una cortesía para el
      -- staff autenticado, no algo que corresponda mezclar con el estado
      -- de la alianza.
      and exists (select 1 from alianzas a where a.id = p_alianza_id and a.barberia_id = v_barberia and a.activo = true);

  if not found then
    raise exception 'Código inválido';
  end if;
  if not v_activo then
    raise exception 'Este código ya fue usado';
  end if;

  update alianza_codigos set activo = false where id = v_codigo_id;
  insert into alianza_canjes (codigo_id, barberia_id) values (v_codigo_id, v_barberia)
    returning fecha into v_fecha;

  return v_fecha;
end;
$function$
;

-- validar_codigo_alianza_publico
CREATE OR REPLACE FUNCTION public.validar_codigo_alianza_publico(p_barberia_id uuid, p_alianza_id uuid, p_codigo text)
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_codigo_id uuid;
  v_cliente_id uuid;
  v_nombre text;
begin
  select id, cliente_id into v_codigo_id, v_cliente_id from alianza_codigos
    where codigo = upper(trim(p_codigo))
      and alianza_id = p_alianza_id
      and barberia_id = p_barberia_id
      and tipo = 'cliente'
      and activo = true
      -- alianza desactivada cae acá también (mismo "not found"), nunca en
      -- una rama de error aparte, para no filtrarle esa distinción a
      -- alguien que esté probando códigos al azar.
      and exists (select 1 from alianzas a where a.id = p_alianza_id and a.barberia_id = p_barberia_id and a.activo = true);

  if not found then
    raise exception 'Código inválido';
  end if;

  select split_part(trim(nombre), ' ', 1) into v_nombre from clientes where id = v_cliente_id;

  insert into alianza_canjes (codigo_id, barberia_id) values (v_codigo_id, p_barberia_id);

  return v_nombre;
end;
$function$
;


-- =============================================================================
-- 5. VISTAS
-- =============================================================================

-- reservas_disponibilidad
CREATE OR REPLACE VIEW public.reservas_disponibilidad AS  SELECT id,
    barberia_id,
    fecha,
    hora,
    barbero_nombre,
    procesado
   FROM reservas;


-- =============================================================================
-- 6. ROW LEVEL SECURITY
-- Activarlo ANTES de crear las políticas.
--
-- Las 19 tablas van con ENABLE y NINGUNA con FORCE, y eso último es a
-- propósito: sin FORCE, el dueño de la tabla (postgres) no evalúa RLS, que
-- es lo que permite que las RPC `security definer` —crear_reserva_publica y
-- las otras dos puertas públicas de reserva— escriban en `reservas` sin que
-- las políticas las bloqueen. Agregar FORCE a una tabla rompe ese bypass.
-- =============================================================================

-- alianza_canjes
ALTER TABLE public.alianza_canjes ENABLE ROW LEVEL SECURITY;

-- alianza_codigos
ALTER TABLE public.alianza_codigos ENABLE ROW LEVEL SECURITY;

-- alianzas
ALTER TABLE public.alianzas ENABLE ROW LEVEL SECURITY;

-- barberias
ALTER TABLE public.barberias ENABLE ROW LEVEL SECURITY;

-- barbero_servicios
ALTER TABLE public.barbero_servicios ENABLE ROW LEVEL SECURITY;

-- barberos
ALTER TABLE public.barberos ENABLE ROW LEVEL SECURITY;

-- bloqueos_profesional
ALTER TABLE public.bloqueos_profesional ENABLE ROW LEVEL SECURITY;

-- clientes
ALTER TABLE public.clientes ENABLE ROW LEVEL SECURITY;

-- costos
ALTER TABLE public.costos ENABLE ROW LEVEL SECURITY;

-- horario_negocio
ALTER TABLE public.horario_negocio ENABLE ROW LEVEL SECURITY;

-- inventario
ALTER TABLE public.inventario ENABLE ROW LEVEL SECURITY;

-- movimientos_stock
ALTER TABLE public.movimientos_stock ENABLE ROW LEVEL SECURITY;

-- niveles_vip
ALTER TABLE public.niveles_vip ENABLE ROW LEVEL SECURITY;

-- perfiles
ALTER TABLE public.perfiles ENABLE ROW LEVEL SECURITY;

-- plantillas_mensajes
ALTER TABLE public.plantillas_mensajes ENABLE ROW LEVEL SECURITY;

-- reservas
ALTER TABLE public.reservas ENABLE ROW LEVEL SECURITY;

-- servicios
ALTER TABLE public.servicios ENABLE ROW LEVEL SECURITY;

-- vip_historial
ALTER TABLE public.vip_historial ENABLE ROW LEVEL SECURITY;

-- visitas
ALTER TABLE public.visitas ENABLE ROW LEVEL SECURITY;


-- =============================================================================
-- 7. POLÍTICAS RLS
-- =============================================================================

-- alianza_canjes.alianza_canjes_select_own
CREATE POLICY alianza_canjes_select_own ON public.alianza_canjes AS PERMISSIVE FOR SELECT TO public USING ((barberia_id = auth_barberia_id()));

-- alianza_codigos.alianza_codigos_delete_own
CREATE POLICY alianza_codigos_delete_own ON public.alianza_codigos AS PERMISSIVE FOR DELETE TO public USING ((barberia_id = auth_barberia_id()));

-- alianza_codigos.alianza_codigos_select_own
CREATE POLICY alianza_codigos_select_own ON public.alianza_codigos AS PERMISSIVE FOR SELECT TO public USING ((barberia_id = auth_barberia_id()));

-- alianza_codigos.alianza_codigos_update_own
CREATE POLICY alianza_codigos_update_own ON public.alianza_codigos AS PERMISSIVE FOR UPDATE TO public USING ((barberia_id = auth_barberia_id())) WITH CHECK ((barberia_id = auth_barberia_id()));

-- alianzas.alianzas_delete_own
CREATE POLICY alianzas_delete_own ON public.alianzas AS PERMISSIVE FOR DELETE TO public USING (((barberia_id = auth_barberia_id()) AND (auth_rol() = 'dueno'::text)));

-- alianzas.alianzas_insert_own
CREATE POLICY alianzas_insert_own ON public.alianzas AS PERMISSIVE FOR INSERT TO public WITH CHECK (((barberia_id = auth_barberia_id()) AND (auth_rol() = 'dueno'::text)));

-- alianzas.alianzas_select_public
CREATE POLICY alianzas_select_public ON public.alianzas AS PERMISSIVE FOR SELECT TO public USING (true);

-- alianzas.alianzas_update_own
CREATE POLICY alianzas_update_own ON public.alianzas AS PERMISSIVE FOR UPDATE TO public USING (((barberia_id = auth_barberia_id()) AND (auth_rol() = 'dueno'::text))) WITH CHECK (((barberia_id = auth_barberia_id()) AND (auth_rol() = 'dueno'::text)));

-- barberias.barberias_insert_new
CREATE POLICY barberias_insert_new ON public.barberias AS PERMISSIVE FOR INSERT TO public WITH CHECK (((auth.uid() IS NOT NULL) AND (creado_por = auth.uid())));

-- barberias.barberias_select_public
CREATE POLICY barberias_select_public ON public.barberias AS PERMISSIVE FOR SELECT TO public USING (true);

-- barberias.barberias_update_own
CREATE POLICY barberias_update_own ON public.barberias AS PERMISSIVE FOR UPDATE TO public USING (((id = auth_barberia_id()) AND (auth_rol() = 'dueno'::text))) WITH CHECK (((id = auth_barberia_id()) AND (auth_rol() = 'dueno'::text)));

-- barbero_servicios.barbero_servicios_delete_own
CREATE POLICY barbero_servicios_delete_own ON public.barbero_servicios AS PERMISSIVE FOR DELETE TO public USING (((barberia_id = auth_barberia_id()) AND (auth_rol() = 'dueno'::text)));

-- barbero_servicios.barbero_servicios_insert_own
CREATE POLICY barbero_servicios_insert_own ON public.barbero_servicios AS PERMISSIVE FOR INSERT TO public WITH CHECK (((barberia_id = auth_barberia_id()) AND (auth_rol() = 'dueno'::text)));

-- barbero_servicios.barbero_servicios_select_public
CREATE POLICY barbero_servicios_select_public ON public.barbero_servicios AS PERMISSIVE FOR SELECT TO public USING (true);

-- barbero_servicios.barbero_servicios_update_own
CREATE POLICY barbero_servicios_update_own ON public.barbero_servicios AS PERMISSIVE FOR UPDATE TO public USING (((barberia_id = auth_barberia_id()) AND (auth_rol() = 'dueno'::text))) WITH CHECK (((barberia_id = auth_barberia_id()) AND (auth_rol() = 'dueno'::text)));

-- barberos.barberos_delete_own
CREATE POLICY barberos_delete_own ON public.barberos AS PERMISSIVE FOR DELETE TO public USING (((barberia_id = auth_barberia_id()) AND (auth_rol() = 'dueno'::text)));

-- barberos.barberos_insert_own
CREATE POLICY barberos_insert_own ON public.barberos AS PERMISSIVE FOR INSERT TO public WITH CHECK (((barberia_id = auth_barberia_id()) AND (auth_rol() = 'dueno'::text)));

-- barberos.barberos_select_public
CREATE POLICY barberos_select_public ON public.barberos AS PERMISSIVE FOR SELECT TO public USING (true);

-- barberos.barberos_update_own
CREATE POLICY barberos_update_own ON public.barberos AS PERMISSIVE FOR UPDATE TO public USING (((barberia_id = auth_barberia_id()) AND (auth_rol() = 'dueno'::text))) WITH CHECK (((barberia_id = auth_barberia_id()) AND (auth_rol() = 'dueno'::text)));

-- bloqueos_profesional.bloqueos_delete_own
CREATE POLICY bloqueos_delete_own ON public.bloqueos_profesional AS PERMISSIVE FOR DELETE TO public USING (((barberia_id = auth_barberia_id()) AND (auth_rol() = 'dueno'::text)));

-- bloqueos_profesional.bloqueos_insert_own
CREATE POLICY bloqueos_insert_own ON public.bloqueos_profesional AS PERMISSIVE FOR INSERT TO public WITH CHECK (((barberia_id = auth_barberia_id()) AND (auth_rol() = 'dueno'::text)));

-- bloqueos_profesional.bloqueos_select_public
CREATE POLICY bloqueos_select_public ON public.bloqueos_profesional AS PERMISSIVE FOR SELECT TO public USING (true);

-- bloqueos_profesional.bloqueos_update_own
CREATE POLICY bloqueos_update_own ON public.bloqueos_profesional AS PERMISSIVE FOR UPDATE TO public USING (((barberia_id = auth_barberia_id()) AND (auth_rol() = 'dueno'::text))) WITH CHECK (((barberia_id = auth_barberia_id()) AND (auth_rol() = 'dueno'::text)));

-- clientes.clientes_own
CREATE POLICY clientes_own ON public.clientes AS PERMISSIVE FOR ALL TO public USING (((barberia_id = auth_barberia_id()) AND (auth_rol() = 'dueno'::text))) WITH CHECK (((barberia_id = auth_barberia_id()) AND (auth_rol() = 'dueno'::text)));

-- costos.costos_own
CREATE POLICY costos_own ON public.costos AS PERMISSIVE FOR ALL TO public USING (((barberia_id = auth_barberia_id()) AND (auth_rol() = 'dueno'::text))) WITH CHECK (((barberia_id = auth_barberia_id()) AND (auth_rol() = 'dueno'::text)));

-- horario_negocio.horario_negocio_delete_own
CREATE POLICY horario_negocio_delete_own ON public.horario_negocio AS PERMISSIVE FOR DELETE TO public USING (((barberia_id = auth_barberia_id()) AND (auth_rol() = 'dueno'::text)));

-- horario_negocio.horario_negocio_insert_own
CREATE POLICY horario_negocio_insert_own ON public.horario_negocio AS PERMISSIVE FOR INSERT TO public WITH CHECK (((barberia_id = auth_barberia_id()) AND (auth_rol() = 'dueno'::text)));

-- horario_negocio.horario_negocio_select_public
CREATE POLICY horario_negocio_select_public ON public.horario_negocio AS PERMISSIVE FOR SELECT TO public USING (true);

-- horario_negocio.horario_negocio_update_own
CREATE POLICY horario_negocio_update_own ON public.horario_negocio AS PERMISSIVE FOR UPDATE TO public USING (((barberia_id = auth_barberia_id()) AND (auth_rol() = 'dueno'::text))) WITH CHECK (((barberia_id = auth_barberia_id()) AND (auth_rol() = 'dueno'::text)));

-- inventario.inventario_own
CREATE POLICY inventario_own ON public.inventario AS PERMISSIVE FOR ALL TO public USING (((barberia_id = auth_barberia_id()) AND (auth_rol() = 'dueno'::text))) WITH CHECK (((barberia_id = auth_barberia_id()) AND (auth_rol() = 'dueno'::text)));

-- movimientos_stock.movimientos_stock_own
CREATE POLICY movimientos_stock_own ON public.movimientos_stock AS PERMISSIVE FOR ALL TO public USING (((barberia_id = auth_barberia_id()) AND (auth_rol() = 'dueno'::text))) WITH CHECK (((barberia_id = auth_barberia_id()) AND (auth_rol() = 'dueno'::text)));

-- niveles_vip.niveles_vip_delete_own
CREATE POLICY niveles_vip_delete_own ON public.niveles_vip AS PERMISSIVE FOR DELETE TO public USING (((barberia_id = auth_barberia_id()) AND (auth_rol() = 'dueno'::text)));

-- niveles_vip.niveles_vip_insert_own
CREATE POLICY niveles_vip_insert_own ON public.niveles_vip AS PERMISSIVE FOR INSERT TO public WITH CHECK (((barberia_id = auth_barberia_id()) AND (auth_rol() = 'dueno'::text)));

-- niveles_vip.niveles_vip_select_public
CREATE POLICY niveles_vip_select_public ON public.niveles_vip AS PERMISSIVE FOR SELECT TO public USING (true);

-- niveles_vip.niveles_vip_update_own
CREATE POLICY niveles_vip_update_own ON public.niveles_vip AS PERMISSIVE FOR UPDATE TO public USING (((barberia_id = auth_barberia_id()) AND (auth_rol() = 'dueno'::text))) WITH CHECK (((barberia_id = auth_barberia_id()) AND (auth_rol() = 'dueno'::text)));

-- perfiles.perfiles_insert_own
CREATE POLICY perfiles_insert_own ON public.perfiles AS PERMISSIVE FOR INSERT TO public WITH CHECK (((id = auth.uid()) AND ((rol <> 'dueno'::text) OR ((EXISTS ( SELECT 1
   FROM barberias b
  WHERE ((b.id = perfiles.barberia_id) AND (b.creado_por = auth.uid())))) AND (NOT (EXISTS ( SELECT 1
   FROM perfiles p2
  WHERE ((p2.barberia_id = p2.barberia_id) AND (p2.rol = 'dueno'::text)))))))));

-- perfiles.perfiles_select_own
CREATE POLICY perfiles_select_own ON public.perfiles AS PERMISSIVE FOR SELECT TO public USING ((id = auth.uid()));

-- perfiles.perfiles_update_own
CREATE POLICY perfiles_update_own ON public.perfiles AS PERMISSIVE FOR UPDATE TO public USING ((id = auth.uid())) WITH CHECK ((id = auth.uid()));

-- plantillas_mensajes.plantillas_mensajes_own
CREATE POLICY plantillas_mensajes_own ON public.plantillas_mensajes AS PERMISSIVE FOR ALL TO public USING (((barberia_id = auth_barberia_id()) AND (auth_rol() = 'dueno'::text))) WITH CHECK (((barberia_id = auth_barberia_id()) AND (auth_rol() = 'dueno'::text)));

-- reservas.reservas_delete_own
CREATE POLICY reservas_delete_own ON public.reservas AS PERMISSIVE FOR DELETE TO public USING (((barberia_id = auth_barberia_id()) AND (auth_rol() = 'dueno'::text)));

-- reservas.reservas_insert_own
CREATE POLICY reservas_insert_own ON public.reservas AS PERMISSIVE FOR INSERT TO public WITH CHECK (((barberia_id = auth_barberia_id()) AND (auth_rol() = 'dueno'::text)));

-- reservas.reservas_select_own
CREATE POLICY reservas_select_own ON public.reservas AS PERMISSIVE FOR SELECT TO public USING (((barberia_id = auth_barberia_id()) AND (auth_rol() = 'dueno'::text)));

-- reservas.reservas_update_own
CREATE POLICY reservas_update_own ON public.reservas AS PERMISSIVE FOR UPDATE TO public USING (((barberia_id = auth_barberia_id()) AND (auth_rol() = 'dueno'::text))) WITH CHECK (((barberia_id = auth_barberia_id()) AND (auth_rol() = 'dueno'::text)));

-- servicios.servicios_delete_own
CREATE POLICY servicios_delete_own ON public.servicios AS PERMISSIVE FOR DELETE TO public USING (((barberia_id = auth_barberia_id()) AND (auth_rol() = 'dueno'::text)));

-- servicios.servicios_insert_own
CREATE POLICY servicios_insert_own ON public.servicios AS PERMISSIVE FOR INSERT TO public WITH CHECK (((barberia_id = auth_barberia_id()) AND (auth_rol() = 'dueno'::text)));

-- servicios.servicios_select_public
CREATE POLICY servicios_select_public ON public.servicios AS PERMISSIVE FOR SELECT TO public USING (true);

-- servicios.servicios_update_own
CREATE POLICY servicios_update_own ON public.servicios AS PERMISSIVE FOR UPDATE TO public USING (((barberia_id = auth_barberia_id()) AND (auth_rol() = 'dueno'::text))) WITH CHECK (((barberia_id = auth_barberia_id()) AND (auth_rol() = 'dueno'::text)));

-- vip_historial.vip_historial_own
CREATE POLICY vip_historial_own ON public.vip_historial AS PERMISSIVE FOR ALL TO public USING (((barberia_id = auth_barberia_id()) AND (auth_rol() = 'dueno'::text))) WITH CHECK (((barberia_id = auth_barberia_id()) AND (auth_rol() = 'dueno'::text)));

-- visitas.visitas_own
CREATE POLICY visitas_own ON public.visitas AS PERMISSIVE FOR ALL TO public USING (((barberia_id = auth_barberia_id()) AND (auth_rol() = 'dueno'::text))) WITH CHECK (((barberia_id = auth_barberia_id()) AND (auth_rol() = 'dueno'::text)));


-- =============================================================================
-- 8. PERMISOS DE TABLA
-- Agrupados por tabla y rol. RLS filtra las filas; esto abre la puerta.
-- =============================================================================

GRANT DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON public.alianza_canjes TO anon;
GRANT DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON public.alianza_canjes TO authenticated;
GRANT DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON public.alianza_canjes TO service_role;
GRANT DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON public.alianza_codigos TO anon;
GRANT DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON public.alianza_codigos TO authenticated;
GRANT DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON public.alianza_codigos TO service_role;
GRANT DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON public.alianzas TO anon;
GRANT DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON public.alianzas TO authenticated;
GRANT DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON public.alianzas TO service_role;
GRANT DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON public.barberias TO anon;
GRANT DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON public.barberias TO authenticated;
GRANT DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON public.barberias TO service_role;
GRANT DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON public.barbero_servicios TO anon;
GRANT DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON public.barbero_servicios TO authenticated;
GRANT DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON public.barbero_servicios TO service_role;
GRANT DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON public.barberos TO anon;
GRANT DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON public.barberos TO authenticated;
GRANT DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON public.barberos TO service_role;
GRANT DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON public.bloqueos_profesional TO anon;
GRANT DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON public.bloqueos_profesional TO authenticated;
GRANT DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON public.bloqueos_profesional TO service_role;
GRANT DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON public.clientes TO anon;
GRANT DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON public.clientes TO authenticated;
GRANT DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON public.clientes TO service_role;
GRANT DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON public.costos TO anon;
GRANT DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON public.costos TO authenticated;
GRANT DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON public.costos TO service_role;
GRANT DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON public.horario_negocio TO anon;
GRANT DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON public.horario_negocio TO authenticated;
GRANT DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON public.horario_negocio TO service_role;
GRANT DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON public.inventario TO anon;
GRANT DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON public.inventario TO authenticated;
GRANT DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON public.inventario TO service_role;
GRANT DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON public.movimientos_stock TO anon;
GRANT DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON public.movimientos_stock TO authenticated;
GRANT DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON public.movimientos_stock TO service_role;
GRANT DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON public.niveles_vip TO anon;
GRANT DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON public.niveles_vip TO authenticated;
GRANT DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON public.niveles_vip TO service_role;
GRANT DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON public.perfiles TO anon;
GRANT DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE ON public.perfiles TO authenticated;
GRANT DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON public.perfiles TO service_role;
GRANT DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON public.plantillas_mensajes TO anon;
GRANT DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON public.plantillas_mensajes TO authenticated;
GRANT DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON public.plantillas_mensajes TO service_role;
GRANT DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON public.reservas TO anon;
GRANT DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON public.reservas TO authenticated;
GRANT DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON public.reservas TO service_role;
GRANT DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON public.reservas_disponibilidad TO anon;
GRANT DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON public.reservas_disponibilidad TO authenticated;
GRANT DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON public.reservas_disponibilidad TO service_role;
GRANT DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON public.servicios TO anon;
GRANT DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON public.servicios TO authenticated;
GRANT DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON public.servicios TO service_role;
GRANT DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON public.vip_historial TO anon;
GRANT DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON public.vip_historial TO authenticated;
GRANT DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON public.vip_historial TO service_role;
GRANT DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON public.visitas TO anon;
GRANT DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON public.visitas TO authenticated;
GRANT DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON public.visitas TO service_role;


-- =============================================================================
-- CÓMO SE REGENERA ESTE ARCHIVO
--
-- No se edita a mano. Se pega la consulta de abajo en el SQL Editor de
-- Supabase, se baja el resultado con "Download CSV" y se rearma el archivo
-- agrupando por la columna `seccion`, en ese mismo orden.
--
-- No hace falta instalar nada: el DDL lo emite Postgres con las funciones
-- pg_get_constraintdef / pg_get_indexdef / pg_get_functiondef /
-- pg_get_triggerdef, no está reconstruido a mano. Lo único que se ensambla
-- son las columnas del CREATE TABLE, que salen de pg_attribute porque es
-- donde están bien los defaults, las columnas generadas y las identity.
--
-- Los permisos salen uno por privilegio (~419 filas) y acá se agrupan por
-- tabla y rol para que sean legibles. Es el mismo efecto.
--
-- Si algún día hay extensiones nuevas, la sección 0 se saca de:
--   select extname, extversion from pg_extension order by extname;
--
-- La sección de RLS mira DOS flags, no uno: `relrowsecurity` (ENABLE) y
-- `relforcerowsecurity` (FORCE). La primera versión de esta consulta solo
-- miraba el primero, y el hueco apareció al verificar
-- migration_reservas_insert_own.sql: FORCE hace que RLS se evalúe también
-- para el DUEÑO de la tabla, y por lo tanto que las funciones
-- `security definer` dejen de bypasear las políticas. Como todas las RPC
-- públicas dependen de ese bypass, una tabla con FORCE activo rompería el
-- flujo de reservas entero, y el dump anterior no lo habría mostrado.
-- Hoy son 0 tablas, así que la salida no cambia — cambia que ahora se vería.
--
-- -----------------------------------------------------------------------------
/*
with cols as (
  select c.relname::text as tabla,
    string_agg(
      '  ' || quote_ident(a.attname) || ' ' || format_type(a.atttypid, a.atttypmod)
      || case
           when a.attgenerated = 's' then ' GENERATED ALWAYS AS (' || pg_get_expr(ad.adbin, ad.adrelid) || ') STORED'
           when a.attidentity = 'a' then ' GENERATED ALWAYS AS IDENTITY'
           when a.attidentity = 'd' then ' GENERATED BY DEFAULT AS IDENTITY'
           when ad.adbin is not null then ' DEFAULT ' || pg_get_expr(ad.adbin, ad.adrelid)
           else '' end
      || case when a.attnotnull then ' NOT NULL' else '' end,
      E',\n' order by a.attnum) as cuerpo
  from pg_class c
  join pg_namespace n on n.oid = c.relnamespace
  join pg_attribute a on a.attrelid = c.oid and a.attnum > 0 and not a.attisdropped
  left join pg_attrdef ad on ad.adrelid = c.oid and ad.adnum = a.attnum
  where n.nspname = 'public' and c.relkind = 'r'
  group by c.relname
)
select * from (
  select 1 as seccion, 'TIPOS'::text as bloque, t.typname::text as objeto,
    'CREATE TYPE public.' || quote_ident(t.typname) || ' AS ENUM (' ||
    string_agg(quote_literal(e.enumlabel), ', ' order by e.enumsortorder) || ');' as ddl
  from pg_type t join pg_enum e on e.enumtypid = t.oid
  join pg_namespace n on n.oid = t.typnamespace
  where n.nspname = 'public' group by t.typname

  union all select 2, 'SECUENCIAS', sequencename::text,
    'CREATE SEQUENCE IF NOT EXISTS public.' || quote_ident(sequencename) ||
    ' AS ' || data_type::text || ' START WITH ' || start_value::text ||
    ' INCREMENT BY ' || increment_by::text ||
    case when max_value is null then ' NO MAXVALUE' else ' MAXVALUE ' || max_value::text end ||
    case when cycle then ' CYCLE' else ' NO CYCLE' end || ';'
  from pg_sequences where schemaname = 'public'

  union all select 3, 'TABLAS', tabla,
    'CREATE TABLE IF NOT EXISTS public.' || quote_ident(tabla) || E' (\n' || cuerpo || E'\n);'
  from cols

  union all select 4, 'CONSTRAINTS', rel.relname::text || '.' || con.conname::text,
    'ALTER TABLE public.' || quote_ident(rel.relname) ||
    ' ADD CONSTRAINT ' || quote_ident(con.conname) || ' ' || pg_get_constraintdef(con.oid) || ';'
  from pg_constraint con
  join pg_class rel on rel.oid = con.conrelid
  join pg_namespace n on n.oid = rel.relnamespace
  where n.nspname = 'public' and con.contype in ('p','u','c','f')

  union all select 5, 'INDICES', ic.relname::text, pg_get_indexdef(i.indexrelid) || ';'
  from pg_index i
  join pg_class ic on ic.oid = i.indexrelid
  join pg_class tc on tc.oid = i.indrelid
  join pg_namespace n on n.oid = tc.relnamespace
  where n.nspname = 'public'
    and not exists (select 1 from pg_constraint c where c.conindid = i.indexrelid)

  union all select 6, 'FUNCIONES', p.proname::text, pg_get_functiondef(p.oid) || ';'
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public' and p.prokind in ('f','p')
    and not exists (select 1 from pg_depend d where d.objid = p.oid and d.deptype = 'e')

  union all select 7, 'VISTAS', viewname::text,
    'CREATE OR REPLACE VIEW public.' || quote_ident(viewname::text) || ' AS ' || definition
  from pg_views where schemaname = 'public'

  union all select 8, 'TRIGGERS', c.relname::text || '.' || t.tgname::text,
    pg_get_triggerdef(t.oid) || ';'
  from pg_trigger t join pg_class c on c.oid = t.tgrelid
  join pg_namespace n on n.oid = c.relnamespace
  where n.nspname = 'public' and not t.tgisinternal

  union all select 9, 'RLS', c.relname::text,
    concat_ws(E'\n',
      case when c.relrowsecurity
           then 'ALTER TABLE public.' || quote_ident(c.relname) || ' ENABLE ROW LEVEL SECURITY;' end,
      case when c.relforcerowsecurity
           then 'ALTER TABLE public.' || quote_ident(c.relname) || ' FORCE ROW LEVEL SECURITY;' end)
  from pg_class c join pg_namespace n on n.oid = c.relnamespace
  where n.nspname = 'public' and c.relkind = 'r'
    and (c.relrowsecurity or c.relforcerowsecurity)

  union all select 10, 'POLITICAS', tablename::text || '.' || policyname::text,
    'CREATE POLICY ' || quote_ident(policyname::text) ||
    ' ON public.' || quote_ident(tablename::text) ||
    ' AS ' || permissive || ' FOR ' || cmd ||
    ' TO ' || array_to_string(roles, ', ') ||
    coalesce(' USING (' || qual || ')', '') ||
    coalesce(' WITH CHECK (' || with_check || ')', '') || ';'
  from pg_policies where schemaname = 'public'

  union all select 11, 'GRANTS', table_name::text || '.' || grantee::text,
    'GRANT ' || privilege_type::text || ' ON public.' || quote_ident(table_name::text) ||
    ' TO ' || quote_ident(grantee::text) || ';'
  from information_schema.role_table_grants
  where table_schema = 'public' and grantee in ('anon','authenticated','service_role')
) t
order by seccion, objeto;
*/
