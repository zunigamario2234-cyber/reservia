-- 16 pruebas del financiero v2. Corre dentro de una transacción que se revierte sola
-- (el resultado sale en el mensaje del error final). Ejecutar en la RAMA, nunca en producción.
do $test$
declare
  res text := '';
  hoy date := (now() at time zone 'America/Santiago')::date;
  j jsonb; b uuid; u uuid; s uuid; r1 uuid; r2 uuid; c uuid; l record; l2 record; n int; x numeric; p numeric; lid uuid; liq uuid; d1 uuid; d2 uuid; inv uuid; rr record;
begin
  create function pg_temp.ok(p_n text, p_c boolean, p_extra text default '') returns text language sql as
    $f$ select case when p_c then 'OK    ' else 'FALLO ' end || p_n || case when p_c then '' else '  -> ' || p_extra end || E'\n' $f$;
  create function pg_temp.mk(p_modelo text default 'A', p_v2 boolean default true, p_hon boolean default false, p_modo text default 'total', p_rut text default null) returns jsonb language plpgsql as $f$
    declare b uuid := gen_random_uuid(); u uuid := gen_random_uuid(); s uuid := gen_random_uuid();
    begin
      insert into barberias (id, nombre, financiero_v2, usa_honorarios, modo_comision, rut, iva_pct) values (b, 'T-'||left(b::text,6), p_v2, p_hon, p_modo, p_rut, 19);
      if p_modelo <> 'A' then update barberias set modelo_comercial = p_modelo, config_tributaria_validada = true where id = b; end if;
      insert into sucursales (id, barberia_id, nombre) values (s, b, 'Principal');
      insert into perfiles (id, barberia_id, nombre, rol) values (u, b, 'Dueño', 'dueno');
      insert into barberos (barberia_id, nombre, comision_pct, comision_producto_pct, sucursal_id) values (b, 'Ana', 50, 10, s), (b, 'Beto', 50, 10, s);
      perform set_config('request.jwt.claim.sub', u::text, true);
      perform set_config('request.jwt.claims', json_build_object('sub', u, 'role', 'authenticated')::text, true);
      return jsonb_build_object('b', b, 'u', u, 's', s);
    end $f$;
  create function pg_temp.reserva(p_b uuid, p_barbero text, p_valor numeric, p_fecha date default null, p_abono numeric default null, p_serv text default 'Corte') returns uuid language plpgsql as $f$
    declare v_id uuid := gen_random_uuid();
    begin
      insert into reservas (id, barberia_id, nombre_cliente, whatsapp_cliente, fecha, hora, servicio, barbero_nombre, estado, abono_estado, abono_monto)
      values (v_id, p_b, 'Cli', '+569'||floor(random()*90000000+10000000)::text, coalesce(p_fecha, (now() at time zone 'America/Santiago')::date), '10:00', p_serv, p_barbero, 'Confirmada', case when p_abono is null then null else 'Confirmado' end, p_abono);
      return v_id;
    end $f$;
  create function pg_temp.lin(p_r uuid, p_valor numeric, p_prop numeric default 0, p_lista numeric default null, p_dpct numeric default null, p_dmonto numeric default null) returns jsonb language sql as
    $f$ select jsonb_build_object('tipo','reserva','reserva_id',p_r,'valor',p_valor,'propina',p_prop,'precio_lista',p_lista,'descuento_pct',p_dpct,'descuento_monto',p_dmonto) $f$;

  -- 0) interruptor apagado: nada cambia
  j := pg_temp.mk('A', false); b := (j->>'b')::uuid;
  r1 := pg_temp.reserva(b, 'Ana', 17850);
  c := registrar_cobro_conjunto(jsonb_build_array(pg_temp.lin(r1, 17850)), 'Efectivo', 17850);
  select count(*) into n from cobro_lineas where barberia_id = b;
  select comision_monto into x from visitas where barberia_id = b;
  res := res || pg_temp.ok('0. con financiero_v2 apagado no se crea ninguna línea y la comisión antigua no cambia', n = 0 and x = 8925, n||' / '||x);

  -- 1) corte $17.850 repartido 55/45
  j := pg_temp.mk('A'); b := (j->>'b')::uuid;
  perform fin_regla_crear('negocio', null, null, 55, 'bruto', hoy - 30);
  r1 := pg_temp.reserva(b, 'Ana', 17850);
  c := registrar_cobro_conjunto(jsonb_build_array(pg_temp.lin(r1, 17850)), 'Débito', 17850);
  select * into l from cobro_lineas where cobro_id = c;
  res := res || pg_temp.ok('1. $17.850 al 55/45: profesional 9.818 (9.817,5 sube), establecimiento 8.032, suman el total',
     l.participacion_profesional = 9818 and l.participacion_establecimiento = 8032 and l.precio_final = 17850 and l.pct_aplicado = 55 and l.regla_version = 1, row_to_json(l)::text);
  select comision_monto into x from visitas where cobro_id = c;
  res := res || pg_temp.ok('1b. la comisión de la visita sale de la regla nueva y coincide con la línea', x = 9818, x::text);

  -- 2) descuentos 10/15/20 sobre 17.850 (el % es sobre el precio ya descontado)
  j := pg_temp.mk('A'); b := (j->>'b')::uuid;
  perform fin_regla_crear('negocio', null, null, 55, 'bruto', hoy - 30);
  for rr in select * from (values (10, 16065::numeric, 8836::numeric), (15, 15173, 8345), (20, 14280, 7854)) t(dp, final, prof) loop
    r1 := pg_temp.reserva(b, 'Ana', 17850);
    c := registrar_cobro_conjunto(jsonb_build_array(pg_temp.lin(r1, rr.final, 0, 17850, rr.dp, 17850 - rr.final)), 'Efectivo', rr.final);
    select * into l from cobro_lineas where cobro_id = c;
    res := res || pg_temp.ok('2. descuento '||rr.dp||'%: final '||rr.final||', profesional '||rr.prof||' sobre el precio final',
       l.precio_final = rr.final and l.precio_original = 17850 and l.descuento = 17850 - rr.final and l.participacion_profesional = rr.prof and l.participacion_establecimiento = rr.final - rr.prof, row_to_json(l)::text);
  end loop;

  -- 3) propina: aparte, no es venta ni lleva IVA
  j := pg_temp.mk('A'); b := (j->>'b')::uuid;
  r1 := pg_temp.reserva(b, 'Ana', 17850);
  c := registrar_cobro_conjunto(jsonb_build_array(pg_temp.lin(r1, 17850, 2000)), 'Efectivo', 19850);
  select * into l from cobro_lineas where cobro_id = c;
  select iva_debito into x from fin_iva_mes(to_char(hoy,'YYYY-MM'));
  res := res || pg_temp.ok('3. propina $2.000 queda aparte: precio final 17.850 y IVA débito solo de 17.850 (2.850)', l.propina = 2000 and l.precio_final = 17850 and x = 2850, row_to_json(l)::text||' iva='||x);

  -- 4) abono previo
  j := pg_temp.mk('A'); b := (j->>'b')::uuid;
  r1 := pg_temp.reserva(b, 'Ana', 17850, null, 5000);
  c := registrar_cobro_conjunto(jsonb_build_array(pg_temp.lin(r1, 17850)), 'Efectivo', 17850);
  select * into l from cobro_lineas where cobro_id = c;
  res := res || pg_temp.ok('4. abono previo $5.000: la venta cuenta completa (17.850) y en caja entra solo la diferencia (12.850)', l.abono_previo = 5000 and l.precio_final = 17850 and (l.precio_final - l.abono_previo) = 12850, row_to_json(l)::text);

  -- 5) varios servicios y profesionales, cada uno con su regla
  j := pg_temp.mk('A'); b := (j->>'b')::uuid;
  perform fin_regla_crear('negocio', null, null, 50, 'bruto', hoy - 30);
  perform fin_regla_crear('profesional', 'Beto', null, 60, 'bruto', hoy - 30);
  r1 := pg_temp.reserva(b, 'Ana', 10000); r2 := pg_temp.reserva(b, 'Beto', 20000);
  c := registrar_cobro_conjunto(jsonb_build_array(pg_temp.lin(r1, 10000), pg_temp.lin(r2, 20000)), 'Transferencia', 30000);
  select count(*) into n from cobro_lineas where cobro_id = c;
  res := res || pg_temp.ok('5. dos servicios y dos profesionales: Ana 50% (5.000) y Beto 60% por su regla (12.000)', n = 2 and
     (select participacion_profesional from cobro_lineas where cobro_id = c and barbero_nombre = 'Ana') = 5000 and
     (select participacion_profesional from cobro_lineas where cobro_id = c and barbero_nombre = 'Beto') = 12000, n::text);

  -- 6) mixto servicios + productos
  j := pg_temp.mk('A'); b := (j->>'b')::uuid; s := (j->>'s')::uuid;
  inv := gen_random_uuid();
  insert into inventario (id, barberia_id, nombre, stock, costo_unitario, precio_venta, sucursal_id) values (inv, b, 'Cera', 5, 3000, 9000, s);
  r1 := pg_temp.reserva(b, 'Ana', 10000);
  c := registrar_cobro_conjunto(jsonb_build_array(pg_temp.lin(r1, 10000),
        jsonb_build_object('tipo','producto','producto_id',inv,'cantidad',1,'precio_unitario',9000,'valor',9000,'barbero_nombre','Ana')), 'Efectivo', 19000);
  select count(*) into n from cobro_lineas where cobro_id = c;
  select * into l from cobro_lineas where cobro_id = c and tipo = 'producto';
  select stock into x from inventario where id = inv;
  res := res || pg_temp.ok('6. cobro mixto: 2 líneas, el producto paga 10% (900) a quien lo vendió y el stock baja a 4',
     n = 2 and l.participacion_profesional = 900 and l.participacion_establecimiento = 8100 and x = 4, row_to_json(l)::text);

  -- 7) reglas antiguas: comisión sobre total y sobre neto (sin regla nueva se respeta el cálculo de siempre)
  j := pg_temp.mk('A', true, false, 'total'); b := (j->>'b')::uuid;
  r1 := pg_temp.reserva(b, 'Ana', 17850);
  c := registrar_cobro_conjunto(jsonb_build_array(pg_temp.lin(r1, 17850)), 'Efectivo', 17850);
  select * into l from cobro_lineas where cobro_id = c;
  res := res || pg_temp.ok('7a. modo antiguo "total": 50% de 17.850 = 8.925, sin regla nueva (versión 0)', l.participacion_profesional = 8925 and l.regla_version = 0 and l.regla_id is null, row_to_json(l)::text);
  j := pg_temp.mk('A', true, false, 'neto_iva'); b := (j->>'b')::uuid;
  r1 := pg_temp.reserva(b, 'Ana', 17850);
  c := registrar_cobro_conjunto(jsonb_build_array(pg_temp.lin(r1, 17850)), 'Efectivo', 17850);
  select * into l from cobro_lineas where cobro_id = c;
  res := res || pg_temp.ok('7b. modo antiguo "neto": 50% de 15.000 = 7.500', l.participacion_profesional = 7500 and l.base_calculo = 'neto', row_to_json(l)::text);

  -- 8) arriendo de sillón (modelo B): el cobro es dinero de terceros; el IVA propio es solo el arriendo
  j := pg_temp.mk('B'); b := (j->>'b')::uuid;
  r1 := pg_temp.reserva(b, 'Ana', 100000);
  c := registrar_cobro_conjunto(jsonb_build_array(pg_temp.lin(r1, 100000)), 'Efectivo', 100000);
  select * into l from cobro_lineas where cobro_id = c;
  insert into arriendos_sillon (id, barberia_id, barbero_nombre, periodo, monto_neto, iva) values (gen_random_uuid(), b, 'Ana', to_char(hoy,'YYYY-MM'), 50000, 9500) returning id into d1;
  select iva_debito into x from fin_iva_mes(to_char(hoy,'YYYY-MM'));
  res := res || pg_temp.ok('8a. modelo B: la venta es de terceros (profesional 100%, establecimiento 0) y el IVA débito es solo el del arriendo (9.500)',
     l.clasificacion_tributaria = 'tercero' and l.participacion_profesional = 100000 and l.participacion_establecimiento = 0 and x = 9500, row_to_json(l)::text||' iva='||x);
  liq := fin_liquidacion_crear('Ana', hoy - 1, hoy);
  perform fin_arriendo_descontar(d1, liq);
  select fin_liquidacion_pendiente(liq) into x;
  res := res || pg_temp.ok('8b. el arriendo (59.500 con IVA) se descuenta de la liquidación como ajuste: queda 40.500 por transferir', x = 40500, x::text);
  begin perform fin_arriendo_descontar(d1, liq); res := res || pg_temp.ok('8c. el mismo arriendo no se descuenta dos veces', false);
  exception when others then res := res || pg_temp.ok('8c. el mismo arriendo no se descuenta dos veces', sqlerrm like '%ya fue descontado%', sqlerrm); end;

  -- 9) documentos: vender no emite; pendiente/fallido
  j := pg_temp.mk('A'); b := (j->>'b')::uuid;
  r1 := pg_temp.reserva(b, 'Ana', 17850);
  c := registrar_cobro_conjunto(jsonb_build_array(pg_temp.lin(r1, 17850)), 'Efectivo', 17850);
  select count(*) into n from documentos_tributarios where barberia_id = b;
  res := res || pg_temp.ok('9a. cobrar un servicio NO crea ni marca ninguna boleta como emitida', n = 0, n::text);
  d1 := fin_documento_registrar('boleta_honorarios', '11.111.111-1', '76.000.000-0', true, 8000, hoy);
  select estado, verificado_manual into rr from documentos_tributarios where id = d1;
  res := res || pg_temp.ok('9b. sin folio la boleta queda pendiente y sin verificar', rr.estado = 'pendiente' and rr.verificado_manual = false, rr::text);
  update documentos_tributarios set estado = 'fallido' where id = d1;
  begin update documentos_tributarios set estado = 'emitido' where id = d1; res := res || pg_temp.ok('9c. no se puede marcar emitida sin folio ni fecha', false);
  exception when check_violation then res := res || pg_temp.ok('9c. no se puede marcar emitida sin folio ni fecha', true); end;
  d2 := fin_documento_registrar('boleta_honorarios', '11.111.111-1', '76.000.000-0', true, 8000, hoy, 'F-123');
  select estado, verificado_manual, folio into rr from documentos_tributarios where id = d2;
  res := res || pg_temp.ok('9d. con folio manual queda emitida y verificada a mano', rr.estado = 'emitido' and rr.verificado_manual and rr.folio = 'F-123', rr::text);

  -- 10) retención de la empresa vs PPM del profesional; tasa por fecha del documento
  d1 := fin_documento_registrar('boleta_honorarios', '11.111.111-1', '76.000.000-0', true, 100000, '2026-12-20', 'A1');
  d2 := fin_documento_registrar('boleta_honorarios', '11.111.111-1', '76.000.000-0', true, 100000, '2027-01-05', 'A2');
  select retencion into x from documentos_tributarios where id = d1; select retencion into p from documentos_tributarios where id = d2;
  res := res || pg_temp.ok('10a. receptor empresa retiene: 15,25% en 2026 (15.250) y 16% en 2027 (16.000) según la fecha del documento', x = 15250 and p = 16000, x||' / '||p);
  d1 := fin_documento_registrar('boleta_honorarios', '11.111.111-1', '12.345.678-9', false, 100000, hoy, 'P1', 10);
  select retencion, ppm, responsable_impuesto into rr from documentos_tributarios where id = d1;
  res := res || pg_temp.ok('10b. receptor particular: no hay retención; el PPM queda a cargo del profesional (10% configurable)', rr.retencion = 0 and rr.ppm = 10000 and rr.responsable_impuesto = 'emisor_ppm', rr::text);
  d1 := fin_documento_registrar('boleta_honorarios', '11.111.111-1', '76.000.000-0', true, 100000, hoy, 'S1', null, 3000);
  select advertencia into rr from documentos_tributarios where id = d1;
  res := res || pg_temp.ok('10c. si el negocio financia parte del impuesto se registra aparte y se advierte renta adicional', rr.advertencia like '%renta adicional%', coalesce(rr.advertencia,'NULL'));

  -- 11) devoluciones parcial y total
  j := pg_temp.mk('A'); b := (j->>'b')::uuid;
  perform fin_regla_crear('negocio', null, null, 50, 'bruto', hoy - 30);
  r1 := pg_temp.reserva(b, 'Ana', 20000);
  c := registrar_cobro_conjunto(jsonb_build_array(pg_temp.lin(r1, 20000)), 'Efectivo', 20000);
  select id into lid from cobro_lineas where cobro_id = c;
  d1 := fin_devolver(lid, 5000, 'Cliente conforme a medias', 'Efectivo', 'dev-1');
  select * into l from cobro_lineas_netas where id = lid;
  res := res || pg_temp.ok('11a. devolución parcial 5.000: neto 15.000, profesional 7.500, establecimiento 7.500; la línea original no cambia',
     l.precio_final = 20000 and l.precio_final_neto = 15000 and l.profesional_neto = 7500 and l.establecimiento_neto = 7500, row_to_json(l)::text);
  d2 := fin_devolver(lid, 5000, 'Cliente conforme a medias', 'Efectivo', 'dev-1');
  select count(*) into n from devoluciones where cobro_linea_id = lid;
  res := res || pg_temp.ok('11b. reenviar la misma devolución no la duplica', d1 = d2 and n = 1, n::text);
  begin perform fin_devolver(lid, 16000, 'Exceso'); res := res || pg_temp.ok('11c. no se puede devolver más de lo cobrado', false);
  exception when others then res := res || pg_temp.ok('11c. no se puede devolver más de lo cobrado', sqlerrm like '%supera%', sqlerrm); end;
  perform fin_devolver(lid, 15000, 'Devolución del resto');
  select * into l from cobro_lineas_netas where id = lid;
  select iva_debito into x from fin_iva_mes(to_char(hoy,'YYYY-MM'));
  res := res || pg_temp.ok('11d. devolución total: neto 0, profesional 0, y el IVA débito baja a 0', l.precio_final_neto = 0 and l.profesional_neto = 0 and l.establecimiento_neto = 0 and x = 0, row_to_json(l)::text||' iva='||x);

  -- 12) gift card
  j := pg_temp.mk('A'); b := (j->>'b')::uuid;
  insert into gift_cards (barberia_id, codigo, servicio, valor) values (b, 'GC1', 'Corte', 15000);
  r1 := pg_temp.reserva(b, 'Ana', 15000);
  c := registrar_cobro_conjunto(jsonb_build_array(pg_temp.lin(r1, 15000)), 'Efectivo', 15000, 'GC1');
  select * into l from cobro_lineas where cobro_id = c;
  select iva_debito into x from fin_iva_mes(to_char(hoy,'YYYY-MM'));
  res := res || pg_temp.ok('12a. gift card: no entra a caja (sin_caja) pero sí es venta propia con IVA (2.395) al canjearse', l.estado_conciliacion = 'sin_caja' and l.metodo_pago = 'Gift card' and x = 2395, row_to_json(l)::text||' iva='||x);
  r2 := pg_temp.reserva(b, 'Ana', 15000);
  begin perform registrar_cobro_conjunto(jsonb_build_array(pg_temp.lin(r2, 15000)), 'Efectivo', 15000, 'GC1'); res := res || pg_temp.ok('12b. una gift card no se canjea dos veces', false);
  exception when others then res := res || pg_temp.ok('12b. una gift card no se canjea dos veces', sqlerrm like '%ya fue canjeada%', sqlerrm); end;

  -- 13) cambio retroactivo de porcentaje
  j := pg_temp.mk('A'); b := (j->>'b')::uuid;
  d1 := fin_regla_crear('negocio', null, null, 55, 'bruto', hoy - 10);
  r1 := pg_temp.reserva(b, 'Ana', 20000, hoy - 5);
  c := registrar_cobro_conjunto(jsonb_build_array(pg_temp.lin(r1, 20000)), 'Efectivo', 20000);
  d2 := fin_regla_crear('negocio', null, null, 60, 'bruto', hoy);
  r2 := pg_temp.reserva(b, 'Ana', 20000, hoy);
  c := registrar_cobro_conjunto(jsonb_build_array(pg_temp.lin(r2, 20000)), 'Efectivo', 20000);
  select participacion_profesional, regla_version into l from cobro_lineas where fecha_cobro = hoy - 5 and barberia_id = b;
  select participacion_profesional, regla_version into l2 from cobro_lineas where fecha_cobro = hoy and barberia_id = b;
  res := res || pg_temp.ok('13a. al subir el % a 60 desde hoy, el cobro anterior sigue en 55% (11.000, v1) y el nuevo usa 60% (12.000, v2)', l.participacion_profesional = 11000 and l.regla_version = 1 and l2.participacion_profesional = 12000 and l2.regla_version = 2, l::text||' | '||l2::text);
  begin update reglas_distribucion set pct_profesional = 70 where id = d1; res := res || pg_temp.ok('13b. una regla ya creada no se puede editar', false);
  exception when others then res := res || pg_temp.ok('13b. una regla ya creada no se puede editar', sqlerrm like '%versión nueva%', sqlerrm); end;
  begin perform fin_cambiar_modelo('B', hoy - 1, 'retroactivo'); res := res || pg_temp.ok('13c. el modelo comercial no cambia hacia atrás', false);
  exception when others then res := res || pg_temp.ok('13c. el modelo comercial no cambia hacia atrás', sqlerrm like '%retroactiv%', sqlerrm); end;
  begin update barberias set modelo_comercial = 'C', config_tributaria_validada = false where id = b; res := res || pg_temp.ok('13d. el modelo C exige configuración validada', false);
  exception when others then res := res || pg_temp.ok('13d. el modelo C exige configuración validada', sqlerrm like '%validada%', sqlerrm); end;

  -- 14) varias sucursales con el mismo RUT
  j := pg_temp.mk('A', true, false, 'total', '76.111.111-1'); b := (j->>'b')::uuid; s := (j->>'s')::uuid;
  declare s2 uuid := gen_random_uuid(); s3 uuid := gen_random_uuid(); begin
    insert into sucursales (id, barberia_id, nombre) values (s2, b, 'Norte');
    insert into sucursales (id, barberia_id, nombre, rut) values (s3, b, 'Franquicia', '77.222.222-2');
    insert into barberos (barberia_id, nombre, comision_pct, sucursal_id) values (b, 'Carla', 50, s2), (b, 'Dani', 50, s3);
  end;
  r1 := pg_temp.reserva(b, 'Ana', 11900); r2 := pg_temp.reserva(b, 'Carla', 23800);
  c := registrar_cobro_conjunto(jsonb_build_array(pg_temp.lin(r1, 11900), pg_temp.lin(r2, 23800)), 'Efectivo', 35700);
  c := registrar_cobro_conjunto(jsonb_build_array(pg_temp.lin(pg_temp.reserva(b, 'Dani', 11900), 11900)), 'Efectivo', 11900);
  select count(distinct emisor_rut) into n from cobro_lineas where barberia_id = b;
  select iva_debito into x from fin_iva_mes(to_char(hoy,'YYYY-MM'), 0, '76.111.111-1');
  select iva_debito into p from fin_iva_mes(to_char(hoy,'YYYY-MM'), 0, '77.222.222-2');
  res := res || pg_temp.ok('14. dos sucursales heredan el mismo RUT (IVA 1.900+3.800=5.700) y la franquicia con otro RUT se declara aparte (1.900)', n = 2 and x = 5700 and p = 1900, n||' '||x||' '||p);

  -- 15) remanente de crédito fiscal IVA con reajuste
  j := pg_temp.mk('A'); b := (j->>'b')::uuid;
  perform pg_temp.reserva(b, 'Ana', 11900, '2026-09-10');
  c := registrar_cobro_conjunto(jsonb_build_array(pg_temp.lin((select id from reservas where barberia_id = b and fecha = '2026-09-10'), 11900)), 'Efectivo', 11900);
  insert into costos (barberia_id, fecha, descripcion, monto_neto, iva, total) values (b, '2026-09-15', 'Compra', 26316, 5000, 31316);
  perform fin_iva_cerrar_mes('2026-09');
  select * into rr from iva_remanente_libro where barberia_id = b and mes = '2026-09';
  res := res || pg_temp.ok('15a. septiembre: débito 1.900 - crédito 5.000 = remanente 3.100 a favor, sin pagar IVA', rr.iva_debito = 1900 and rr.iva_credito = 5000 and rr.iva_a_pagar = 0 and rr.remanente_nuevo = 3100, rr::text);
  r2 := pg_temp.reserva(b, 'Ana', 59500, '2026-10-10');
  c := registrar_cobro_conjunto(jsonb_build_array(pg_temp.lin(r2, 59500)), 'Efectivo', 59500);
  select * into rr from fin_iva_mes('2026-10', 2);
  res := res || pg_temp.ok('15b. octubre arrastra el remanente reajustado 2% (3.162): débito 9.500 - 3.162 = 6.338 a pagar', rr.remanente_anterior = 3100 and rr.remanente_reajustado = 3162 and rr.iva_a_pagar = 6338 and rr.remanente_nuevo = 0, rr::text);

  -- 16) pago duplicado y corrección
  j := pg_temp.mk('A', true, false); b := (j->>'b')::uuid;
  perform fin_regla_crear('negocio', null, null, 50, 'bruto', hoy - 30);
  r1 := pg_temp.reserva(b, 'Ana', 40000); r2 := pg_temp.reserva(b, 'Ana', 20000);
  c := registrar_cobro_conjunto(jsonb_build_array(pg_temp.lin(r1, 40000, 2000), pg_temp.lin(r2, 20000)), 'Efectivo', 62000);
  insert into anticipos_profesional (barberia_id, barbero_nombre, monto, fecha) values (b, 'Ana', 5000, hoy);
  liq := fin_liquidacion_crear('Ana', hoy - 1, hoy, 10);
  select * into rr from liquidaciones where id = liq;
  res := res || pg_temp.ok('16a. liquidación: 2 servicios, cobrado 60.000, honorarios 30.000, propina 2.000, anticipo 5.000 = 27.000 por transferir; PPM 3.000 solo informativo',
     rr.servicios_n = 2 and rr.total_cobrado = 60000 and rr.honorarios_brutos = 30000 and rr.propinas = 2000 and rr.anticipos = 5000 and rr.total_a_transferir = 27000 and rr.ppm_estimado = 3000, rr::text);
  begin perform fin_liquidacion_crear('Ana', hoy - 1, hoy); res := res || pg_temp.ok('16b. las mismas ventas no se liquidan dos veces', false);
  exception when others then res := res || pg_temp.ok('16b. las mismas ventas no se liquidan dos veces', sqlerrm like '%No hay movimientos%', sqlerrm); end;
  d1 := fin_liquidacion_pagar(liq, 10000, 'Transferencia', 'comp-1', 'pago-A');
  d2 := fin_liquidacion_pagar(liq, 10000, 'Transferencia', 'comp-1', 'pago-A');
  select count(*), sum(monto) into n, x from liquidacion_pagos where liquidacion_id = liq;
  res := res || pg_temp.ok('16c. el mismo pago reenviado (misma clave) no se duplica: queda 1 pago de 10.000', d1 = d2 and n = 1 and x = 10000, n||' '||x);
  begin perform fin_liquidacion_pagar(liq, 20000, 'Transferencia', null, 'pago-B'); res := res || pg_temp.ok('16d. no se paga más de lo pendiente (17.000)', false);
  exception when others then res := res || pg_temp.ok('16d. no se paga más de lo pendiente (17.000)', sqlerrm like '%supera%', sqlerrm); end;
  perform fin_liquidacion_ajustar(liq, -2000, 'Corrección: boleta con error');
  perform fin_liquidacion_pagar(liq, 15000, 'Transferencia', 'comp-2', 'pago-C');
  select estado, total_transferido, ajustes into rr from liquidaciones where id = liq;
  res := res || pg_temp.ok('16e. el ajuste de -2.000 (con motivo) deja 15.000 pendientes; al pagarlos la liquidación queda pagada', rr.estado = 'pagada' and rr.total_transferido = 25000 and rr.ajustes = -2000, rr::text);

  -- invariantes globales
  select count(*) into n from cobro_lineas where participacion_profesional + participacion_establecimiento <> precio_final;
  res := res || pg_temp.ok('Invariante: en todas las líneas profesional + establecimiento = precio final', n = 0, n::text);
  select count(*) into n from (select visita_id from cobro_lineas where visita_id is not null group by 1 having count(*) > 1) q;
  res := res || pg_temp.ok('Invariante: ninguna visita tiene dos líneas (no se duplican ventas)', n = 0, n::text);

  raise exception E'RESULTADOS\n%', res;
end $test$;
