-- =============================================================================
-- MI AGENDA: métricas del profesional y comisiones con desglose de honorarios.
-- · mi_agenda_metricas(): citas por día (mes anterior + este), meta, días que el
--   negocio cierra y citas agendadas que quedan del mes. El navegador arma con
--   eso los cuadros de color (mes / semana / ayer / meta). Todo sale de los
--   datos: el profesional no carga nada.
-- · mi_agenda_comisiones_detalle(): lo mismo que mi_agenda_comisiones más la
--   propina y el desglose de honorarios que congeló cada visita (retención que
--   le toca al profesional y líquido), para mostrar por día qué recibe y qué
--   retiene el SII.
-- Solo ven lo propio: todo se filtra por auth_barbero_id().
-- =============================================================================

create or replace function public.mi_agenda_metricas()
returns jsonb
language plpgsql stable security definer set search_path to 'public'
as $$
declare
  v_b barberos%rowtype;
  v_bar barberias%rowtype;
  v_hoy date := (now() at time zone 'America/Santiago')::date;
  v_ini date := date_trunc('month', (now() at time zone 'America/Santiago')::date - interval '1 month')::date;
  v_fin_mes date := (date_trunc('month', (now() at time zone 'America/Santiago')::date) + interval '1 month')::date;
  v_cerrados jsonb;
begin
  select * into v_b from barberos where id = auth_barbero_id();
  if not found then return null; end if;
  select * into v_bar from barberias where id = v_b.barberia_id;

  -- Mismo criterio que el panel (horarioDeSuc): la fila del día de su sucursal;
  -- sin fila, solo el domingo cuenta como cerrado.
  select coalesce(jsonb_agg(d.dia), '[]'::jsonb) into v_cerrados
  from generate_series(0, 6) as d(dia)
  where coalesce(
    (select h.cerrado from horario_negocio h
      where h.barberia_id = v_b.barberia_id and h.dia_semana = d.dia
        and (v_b.sucursal_id is null or h.sucursal_id is null or h.sucursal_id = v_b.sucursal_id)
      order by (h.sucursal_id = v_b.sucursal_id) desc nulls last limit 1),
    d.dia = 0);

  return jsonb_build_object(
    'hoy', v_hoy,
    'meta', coalesce(v_b.meta_citas, 80),
    'usa_honorarios', coalesce(v_bar.usa_honorarios, false),
    'cerrados', v_cerrados,
    'citas', (select coalesce(jsonb_object_agg(x.fecha, x.n), '{}'::jsonb) from (
        select v.fecha, count(*) as n from visitas v
         where v.barberia_id = v_b.barberia_id and v.barbero_nombre = v_b.nombre
           and v.fecha between v_ini and v_hoy and coalesce(v.estado, '') <> 'Cancelada'
         group by v.fecha) x),
    'agendadas', (select count(*) from reservas r
         where r.barberia_id = v_b.barberia_id and r.barbero_nombre = v_b.nombre
           and r.fecha >= v_hoy and r.fecha < v_fin_mes
           and not coalesce(r.procesado, false) and coalesce(r.estado, '') <> 'Cancelada')
  );
end;
$$;
revoke all on function public.mi_agenda_metricas() from public, anon;
grant execute on function public.mi_agenda_metricas() to authenticated;

create or replace function public.mi_agenda_comisiones_detalle(p_desde date default null, p_hasta date default null)
returns table(tipo text, fecha date, servicio text, valor numeric, comision_monto numeric, estado text,
              propina numeric, retencion_profesional numeric, liquido_profesional numeric, retencion_pct numeric)
language sql stable security definer set search_path to 'public'
as $$
  select 'servicio'::text, v.fecha, v.servicio, v.valor, v.comision_monto, v.estado,
         coalesce(v.propina, 0), v.retencion_profesional, v.liquido_profesional, v.retencion_pct
  from visitas v
  where v.barberia_id = auth_barberia_id()
    and v.barbero_nombre = (select b.nombre from barberos b where b.id = auth_barbero_id())
    and auth_barbero_id() is not null
    and (p_desde is null or v.fecha >= p_desde)
    and (p_hasta is null or v.fecha <= p_hasta)
  union all
  select 'producto'::text, cp.fecha, coalesce(i.nombre, 'Producto'), cp.valor, cp.comision_monto, 'Vendido'::text,
         0::numeric, null::numeric, null::numeric, null::numeric
  from cobro_productos cp
  left join inventario i on i.id = cp.producto_id
  where cp.barberia_id = auth_barberia_id()
    and cp.barbero_nombre = (select b.nombre from barberos b where b.id = auth_barbero_id())
    and auth_barbero_id() is not null
    and (p_desde is null or cp.fecha >= p_desde)
    and (p_hasta is null or cp.fecha <= p_hasta)
  order by 2 desc
$$;
revoke all on function public.mi_agenda_comisiones_detalle(date, date) from public, anon;
grant execute on function public.mi_agenda_comisiones_detalle(date, date) to authenticated;
