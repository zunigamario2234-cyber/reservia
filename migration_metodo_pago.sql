-- Métodos de pago al procesar una reserva (Efectivo/Transferencia/Débito/
-- Crédito — mismas 4 opciones que ya existen en "Registrar cita" manual,
-- reutilizadas acá, no una lista nueva) + permiso opcional para que un
-- profesional procese pagos desde Mi Agenda (pensado para negocios donde
-- el dueño es también quien atiende).
--
-- La columna visitas.metodo_pago YA EXISTE (se usa hoy en el modal manual
-- "Registrar/editar cita" de app.html) — no hace falta agregarla, esta
-- migración solo la completa desde el flujo de "Pagar" una reserva.
--
-- Ejecutar UNA VEZ, completo, en el SQL Editor de Supabase.

-- ═══════════════════════════════════════════════════════════════
-- (1) Columna nueva en barberos
-- ═══════════════════════════════════════════════════════════════

alter table barberos add column if not exists puede_procesar_pagos boolean not null default false;

-- ═══════════════════════════════════════════════════════════════
-- (2) RPC de Mi Agenda: procesar el pago de una reserva propia.
-- security definer, resuelve la identidad del profesional únicamente por
-- auth.uid() (mismo molde que el resto de mi_agenda_*) y replica EXACTO el
-- cálculo de comisión de calcularComision() en app.html: base = valor
-- completo si barberias.modo_comision='total', o valor menos el IVA
-- incluido (usando barberias.iva_pct) si es 'neto_iva'.
-- ═══════════════════════════════════════════════════════════════

create or replace function mi_agenda_procesar_pago(p_reserva_id uuid, p_metodo_pago text)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
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

  -- Cliente: buscar por whatsapp en la barbería, crear si no existe —
  -- mismo criterio que procesarReserva() en app.html.
  select c.id into v_cliente_id from clientes c
    where c.barberia_id = v_barberia and c.whatsapp = v_reserva.whatsapp_cliente;
  if v_cliente_id is null then
    insert into clientes (barberia_id, nombre, whatsapp, cumpleanos, canal, fecha_registro)
    values (v_barberia, v_reserva.nombre_cliente, v_reserva.whatsapp_cliente, v_reserva.cumpleanos_cliente, 'Reserva Web', v_reserva.fecha)
    returning id into v_cliente_id;
  end if;

  -- Precio del servicio, por nombre, en la barbería (igual que procesarReserva()).
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
$$;

revoke all on function mi_agenda_procesar_pago(uuid,text) from public;
grant execute on function mi_agenda_procesar_pago(uuid,text) to authenticated;
