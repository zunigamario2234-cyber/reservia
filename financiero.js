// Módulo financiero v2 (panel del dueño). Solo se muestra si barberias.financiero_v2 = true.
// Todo el cálculo de plata vive en la base (funciones fin_*); acá solo se pide, se muestra y se exporta.
(function(){
  'use strict';
  const $ = id => document.getElementById(id);
  const esc = s => (s==null?'':String(s)).replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'})[c]);
  const money = n => '$' + (Math.round(Number(n)||0)).toLocaleString('es-CL');
  const hoyChile = () => (typeof ahoraEnChile==='function' ? ahoraEnChile().fecha : new Date().toISOString().slice(0,10));
  const MODELOS = {
    A: 'A · El negocio vende y paga comisión',
    B: 'B · El profesional vende por su cuenta (arrienda el sillón)',
    C: 'C · Mixto, con configuración tributaria validada'
  };
  const MEDIOS_SIN_CAJA = 'Gift card';

  const F = { tab:'caja', desde:null, hasta:null, suc:'', prof:'', modelo:'', lineas:[], ready:false, liqActual:null };
  window.FIN = F;

  function sinFondos(){ return !S.barberia || !S.barberia.financiero_v2; }
  function esDueno(){ return S.perfil && S.perfil.rol === 'dueno'; }
  async function rpc(nombre, args){
    const { data, error } = await sb.rpc(nombre, args || {});
    if (error) throw new Error(error.message || 'Error');
    return data;
  }
  function falla(e){ notify((e && e.message ? e.message : 'No se pudo completar'), 'err'); }

  // ── Visibilidad ────────────────────────────────────────────────────────────
  window.finAplicarVisibilidad = function(){
    const on = !!(S.barberia && S.barberia.financiero_v2) && esDueno();
    document.querySelectorAll('.fin-only').forEach(n => { n.style.display = on ? '' : 'none'; });
    const card = $('imp-fin-card');
    if (card) {
      card.style.display = esDueno() ? '' : 'none';
      const act = !!(S.barberia && S.barberia.financiero_v2);
      $('imp-fin-estado').textContent = act ? 'Activado' : 'Desactivado';
      $('imp-fin-btn').textContent = act ? 'Desactivar' : 'Activar módulo financiero nuevo';
    }
  };
  window.finAlternarActivacion = async function(){
    const nuevo = !S.barberia.financiero_v2;
    const msg = nuevo
      ? 'Se activa el cálculo nuevo de comisiones, boletas y liquidaciones. Los cobros anteriores no cambian. ¿Continuar?'
      : 'Se desactiva el módulo. Los datos ya guardados se conservan. ¿Continuar?';
    if (!window.confirm(msg)) return;
    const { error } = await sb.from('barberias').update({ financiero_v2: nuevo }).eq('id', S.barberia.id);
    if (error) return falla(error);
    S.barberia.financiero_v2 = nuevo;
    finAplicarVisibilidad();
    notify(nuevo ? 'Módulo financiero activado ✓' : 'Módulo financiero desactivado');
  };

  // ── Entrada y filtros ──────────────────────────────────────────────────────
  window.renderFinanciero = async function(){
    if (sinFondos()) { nav('impuestos'); return; }
    if (!F.ready) {
      const h = hoyChile();
      F.desde = h.slice(0,8) + '01'; F.hasta = h;
      F.ready = true;
    }
    $('fin-desde').value = F.desde; $('fin-hasta').value = F.hasta;
    const sucs = (S.sucursales || []).filter(x => x.activa !== false);
    $('fin-suc').innerHTML = '<option value="">Todas las sucursales</option>' + sucs.map(x => `<option value="${x.id}">${esc(x.nombre)}</option>`).join('');
    $('fin-suc').parentElement.style.display = sucs.length > 1 ? '' : 'none';
    $('fin-suc').value = F.suc;
    const pros = (S.barberos || []).map(b => b.nombre);
    $('fin-prof').innerHTML = '<option value="">Todos los profesionales</option>' + [...new Set(pros)].map(n => `<option value="${esc(n)}">${esc(n)}</option>`).join('');
    $('fin-prof').value = F.prof;
    $('fin-modelo').value = F.modelo;
    finTab(F.tab, true);
  };
  window.finFiltrar = function(){
    F.desde = $('fin-desde').value; F.hasta = $('fin-hasta').value;
    F.suc = $('fin-suc').value; F.prof = $('fin-prof').value; F.modelo = $('fin-modelo').value;
    if (F.desde && F.hasta && F.hasta < F.desde) { notify('La fecha final es anterior a la inicial', 'err'); return; }
    finTab(F.tab, true);
  };
  window.finPreset = function(p){
    const h = hoyChile(); const y = h.slice(0,4), m = h.slice(0,7);
    if (p === 'hoy') { F.desde = h; F.hasta = h; }
    if (p === 'mes') { F.desde = m + '-01'; F.hasta = h; }
    if (p === 'mesant') { const a = sumarMes(m, -1); const [ay, am] = a.split('-').map(Number); F.desde = a + '-01'; F.hasta = a + '-' + String(new Date(ay, am, 0).getDate()).padStart(2,'0'); }
    if (p === 'anio') { F.desde = y + '-01-01'; F.hasta = h; }
    $('fin-desde').value = F.desde; $('fin-hasta').value = F.hasta;
    finTab(F.tab, true);
  };
  window.finTab = function(tab, forzar){
    F.tab = tab;
    document.querySelectorAll('#fin-tabs .tab').forEach(t => t.classList.toggle('active', t.dataset.t === tab));
    ['caja','ventas','trib','liq','cfg'].forEach(t => { const el = $('fin-t-' + t); if (el) el.style.display = t === tab ? '' : 'none'; });
    $('fin-filtros').style.display = tab === 'cfg' ? 'none' : 'flex';
    $('fin-modelo-box').style.display = tab === 'trib' || tab === 'liq' ? 'none' : '';
    const r = { caja: finCaja, ventas: finVentas, trib: finTrib, liq: finLiq, cfg: finCfg }[tab];
    if (r) r().catch(falla);
  };

  // ── Datos base: líneas del período con devoluciones ya descontadas ─────────
  async function cargarLineas(){
    let q = sb.from('cobro_lineas_netas').select('*').gte('fecha_cobro', F.desde).lte('fecha_cobro', F.hasta).order('fecha_cobro', { ascending: false }).limit(5000);
    if (F.suc) q = q.eq('sucursal_id', F.suc);
    if (F.prof) q = q.eq('barbero_nombre', F.prof);
    if (F.modelo) q = q.eq('modelo', F.modelo);
    const { data, error } = await q;
    if (error) throw new Error(error.message);
    F.lineas = (data || []).filter(l => l.estado_conciliacion !== 'anulado');
    return F.lineas;
  }
  const sum = (arr, f) => arr.reduce((a, x) => a + (Number(f(x)) || 0), 0);
  const nombreSuc = id => { const s = (S.sucursales || []).find(x => x.id === id); return s ? s.nombre : '—'; };
  function tarjeta(label, valor, sub, cls){
    return `<div class="mc"><div class="mc-label">${label}</div><div class="mc-val ${cls || ''}">${valor}</div>${sub ? `<div class="mc-sub">${sub}</div>` : ''}</div>`;
  }
  function tabla(cols, filas, vacio){
    if (!filas.length) return `<div class="empty">${vacio || 'Sin movimientos en este período'}</div>`;
    return `<div class="tbl-wrap"><table><thead><tr>${cols.map(c => `<th${c.r ? ' style="text-align:right"' : ''}>${c.t}</th>`).join('')}</tr></thead><tbody>${
      filas.map(f => `<tr>${f.map((v, i) => `<td${cols[i].r ? ' style="text-align:right"' : ''}>${v}</td>`).join('')}</tr>`).join('')
    }</tbody></table></div>`;
  }

  // ── 1. Caja ────────────────────────────────────────────────────────────────
  // Lo que realmente entró: precio final + propina − abono previo (ese ya había entrado antes).
  // Gift card: se vende como ingreso propio pero no entra plata a caja al canjearla.
  async function finCaja(){
    const L = await cargarLineas();
    const conCaja = L.filter(l => l.estado_conciliacion !== 'sin_caja');
    const entro = sum(conCaja, l => l.precio_final_neto - l.abono_previo + l.propina);
    const propinas = sum(L, l => l.propina);
    const aProf = sum(L.filter(l => l.clasificacion_tributaria === 'ingreso_propio'), l => l.profesional_neto);
    const terceros = sum(L.filter(l => l.clasificacion_tributaria === 'tercero'), l => l.profesional_neto);
    const negocio = sum(L, l => l.establecimiento_neto);
    const devuelto = sum(L, l => l.devuelto);
    $('fin-caja-cards').innerHTML =
      tarjeta('Entró a caja', money(entro), 'Cobros del período, sin gift cards', 'gold') +
      tarjeta('Plata del negocio', money(negocio), 'Parte del establecimiento') +
      tarjeta('Por pagar a profesionales', money(aProf + terceros), 'Comisiones y ventas de terceros') +
      tarjeta('Propinas (fondos de terceros)', money(propinas), 'Pasan por caja; no son ingreso del negocio') +
      tarjeta('Devoluciones', money(devuelto), 'Ya descontadas de las partes') +
      tarjeta('Gift cards canjeadas', money(sum(L.filter(l => l.estado_conciliacion === 'sin_caja'), l => l.precio_final_neto)), 'Venta propia sin entrada a caja');
    const porMedio = {};
    L.forEach(l => {
      const m = l.metodo_pago || 'Sin medio';
      const o = porMedio[m] || (porMedio[m] = { n: 0, caja: 0, abono: 0, prop: 0 });
      o.n++; o.abono += Number(l.abono_previo) || 0; o.prop += Number(l.propina) || 0;
      o.caja += l.estado_conciliacion === 'sin_caja' ? 0 : (l.precio_final_neto - l.abono_previo + l.propina);
    });
    const filas = Object.entries(porMedio).sort((a, b) => b[1].caja - a[1].caja).map(([m, o]) => [esc(m), o.n, money(o.abono), money(o.prop), money(o.caja)]);
    $('fin-caja-medios').innerHTML = tabla([{t:'Medio de pago'},{t:'Movimientos',r:1},{t:'Abonos previos',r:1},{t:'Propinas',r:1},{t:'Entró a caja',r:1}], filas);
    F.exportCaja = { cab: ['Medio de pago','Movimientos','Abonos previos','Propinas','Entró a caja'], filas: Object.entries(porMedio).map(([m, o]) => [m, o.n, o.abono, o.prop, o.caja]) };
    const pend = L.filter(l => l.estado_conciliacion === 'pendiente').length;
    $('fin-caja-nota').textContent = pend ? `${pend} movimiento(s) todavía sin conciliar con el banco o el POS.` : 'Todos los movimientos del período están conciliados o no pasan por caja.';
  }

  // ── 2. Ventas comerciales ──────────────────────────────────────────────────
  async function finVentas(){
    const L = await cargarLineas();
    $('fin-ventas-cards').innerHTML =
      tarjeta('Ventas (precio final)', money(sum(L, l => l.precio_final_neto)), L.length + ' líneas', 'gold') +
      tarjeta('Descuentos dados', money(sum(L, l => l.descuento))) +
      tarjeta('Parte profesionales', money(sum(L, l => l.profesional_neto))) +
      tarjeta('Parte del negocio', money(sum(L, l => l.establecimiento_neto)));
    const filas = L.map(l => [
      l.fecha_cobro, esc(nombreSuc(l.sucursal_id)), esc(l.barbero_nombre || '—'),
      (l.tipo === 'producto' ? '📦 Producto' : esc(l.servicio || 'Servicio')),
      money(l.precio_original), money(l.descuento), money(l.precio_final_neto),
      l.pct_aplicado == null ? '—' : l.pct_aplicado + '%' + (l.regla_version ? ' (v' + l.regla_version + ')' : ' (antigua)'),
      money(l.profesional_neto), money(l.establecimiento_neto), l.modelo
    ]);
    $('fin-ventas-tabla').innerHTML = tabla([{t:'Fecha'},{t:'Sucursal'},{t:'Profesional'},{t:'Detalle'},{t:'Precio',r:1},{t:'Descuento',r:1},{t:'Final',r:1},{t:'%'},{t:'Profesional',r:1},{t:'Negocio',r:1},{t:'Modelo'}], filas);
    F.exportVentas = { cab: ['Fecha','Sucursal','Profesional','Tipo','Detalle','Precio original','Descuento','Precio final neto','Devuelto','% aplicado','Versión regla','Profesional','Negocio','Propina','Medio de pago','Modelo','Clasificación'],
      filas: L.map(l => [l.fecha_cobro, nombreSuc(l.sucursal_id), l.barbero_nombre || '', l.tipo, l.servicio || '', l.precio_original, l.descuento, l.precio_final_neto, l.devuelto, l.pct_aplicado, l.regla_version, l.profesional_neto, l.establecimiento_neto, l.propina, l.metodo_pago || '', l.modelo, l.clasificacion_tributaria]) };
  }
  window.finDevolver = async function(lineaId){
    const monto = Number(window.prompt('Monto a devolver (en pesos)'));
    if (!monto || monto <= 0) return;
    const motivo = window.prompt('Motivo de la devolución');
    if (!motivo) return;
    try { await rpc('fin_devolver', { p_linea: lineaId, p_monto: monto, p_motivo: motivo, p_medio: null, p_clave: 'dev-' + lineaId + '-' + monto + '-' + Date.now() }); notify('Devolución registrada ✓'); finTab('ventas', true); }
    catch (e) { falla(e); }
  };

  // ── 3. Tributación ─────────────────────────────────────────────────────────
  async function finTrib(){
    const mes = F.hasta.slice(0, 7);
    $('fin-trib-mes').textContent = mes;
    const ruts = await rutsDelNegocio();
    const sel = $('fin-trib-rut');
    const prev = sel.value;
    sel.innerHTML = '<option value="">Todos los RUT</option>' + ruts.map(r => `<option value="${esc(r)}">${esc(r)}</option>`).join('');
    sel.value = ruts.includes(prev) ? prev : '';
    const reaj = Number($('fin-trib-reaj').value) || 0;
    const iva = await rpc('fin_iva_mes', { p_mes: mes, p_reajuste_pct: reaj, p_rut: sel.value || null });
    const r = Array.isArray(iva) ? iva[0] : iva;
    $('fin-trib-cards').innerHTML =
      tarjeta('IVA débito', money(r.iva_debito), 'Solo ventas propias y arriendos') +
      tarjeta('IVA crédito', money(r.iva_credito), 'IVA de gastos') +
      tarjeta('Remanente anterior', money(r.remanente_anterior), reaj ? 'Reajustado: ' + money(r.remanente_reajustado) : 'Sin reajuste') +
      tarjeta(r.iva_a_pagar > 0 ? 'IVA a pagar' : 'Remanente a favor', money(r.iva_a_pagar > 0 ? r.iva_a_pagar : r.remanente_nuevo), r.iva_a_pagar > 0 ? 'F29 del mes' : 'Pasa al mes siguiente', 'gold');
    // Documentos
    const { data: docs, error } = await sb.from('documentos_tributarios').select('*').order('created_at', { ascending: false }).limit(300);
    if (error) throw new Error(error.message);
    const pend = (docs || []).filter(d => d.estado === 'pendiente' || d.estado === 'fallido');
    $('fin-docs-aviso').innerHTML = pend.length
      ? `<div style="background:#d9770618;border:1px solid #d9770644;border-radius:8px;padding:10px 12px;font-size:12px;margin-bottom:10px">${pend.length} documento(s) sin folio verificado. El sistema no emite boletas ante el SII: emítelas en el SII y registra aquí el folio.</div>` : '';
    const filas = (docs || []).map(d => [
      d.fecha_emision || '—', ({boleta_honorarios:'Boleta de honorarios',boleta_ventas:'Boleta de ventas',factura:'Factura',nota_credito:'Nota de crédito',otro:'Otro'})[d.tipo] || d.tipo,
      esc(d.folio || '—'), esc(d.rut_emisor), esc(d.rut_receptor || '—'), money(d.honorarios_brutos),
      d.retencion ? money(d.retencion) + ' (' + d.retencion_pct + '%)' : (d.ppm ? 'PPM ' + money(d.ppm) : '—'),
      `<span class="badge" style="background:${d.estado === 'emitido' ? '#16a34a22' : '#d9770622'}">${d.estado}${d.verificado_manual ? ' ✓' : ''}</span>` + (d.advertencia ? ' ⚠' : ''),
      d.estado === 'pendiente' || d.estado === 'fallido' ? `<button class="btn btn-ghost btn-sm" onclick="finDocFolio('${d.id}')">Poner folio</button>` : ''
    ]);
    $('fin-docs-tabla').innerHTML = tabla([{t:'Fecha'},{t:'Tipo'},{t:'Folio'},{t:'RUT emisor'},{t:'RUT receptor'},{t:'Honorarios',r:1},{t:'Retención / PPM'},{t:'Estado'},{t:''}], filas, 'Aún no registras documentos');
    F.exportTrib = { cab: ['Mes','IVA débito','IVA crédito','Remanente anterior','Remanente reajustado','IVA a pagar','Remanente nuevo','RUT'], filas: [[mes, r.iva_debito, r.iva_credito, r.remanente_anterior, r.remanente_reajustado, r.iva_a_pagar, r.remanente_nuevo, sel.value || 'Todos']] };
    F.exportDocs = { cab: ['Fecha','Tipo','Folio','RUT emisor','RUT receptor','Honorarios brutos','Retención %','Retención','PPM %','PPM','Responsable del impuesto','Subsidio del negocio','Estado','Verificado a mano'],
      filas: (docs || []).map(d => [d.fecha_emision || '', d.tipo, d.folio || '', d.rut_emisor, d.rut_receptor || '', d.honorarios_brutos, d.retencion_pct, d.retencion, d.ppm_pct, d.ppm, d.responsable_impuesto || '', d.subsidio_negocio, d.estado, d.verificado_manual ? 'sí' : 'no']) };
    // Ejemplo informativo de PPM: no se resta de nada.
    const L = await cargarLineas();
    const hon = sum(L.filter(l => l.tipo === 'servicio'), l => l.profesional_neto);
    $('fin-trib-nota').textContent = `Honorarios brutos de profesionales en el período: ${money(hon)}. El PPM del profesional es informativo y nunca se descuenta dos veces.`;
  }
  async function rutsDelNegocio(){
    const set = new Set();
    if (S.barberia.rut) set.add(S.barberia.rut);
    (S.sucursales || []).forEach(s => { if (s.rut) set.add(s.rut); });
    return [...set];
  }
  window.finCerrarMes = async function(){
    const mes = F.hasta.slice(0, 7);
    if (!window.confirm('Se guarda el IVA de ' + mes + ' y su remanente pasa al mes siguiente. ¿Cerrar el mes?')) return;
    try { await rpc('fin_iva_cerrar_mes', { p_mes: mes, p_reajuste_pct: Number($('fin-trib-reaj').value) || 0 }); notify('Mes cerrado ✓'); finTab('trib', true); }
    catch (e) { falla(e); }
  };
  window.finDocFolio = async function(id){
    const folio = window.prompt('Folio de la boleta emitida en el SII');
    if (!folio || !folio.trim()) return;
    const fecha = window.prompt('Fecha de emisión (AAAA-MM-DD)', hoyChile());
    if (!fecha) return;
    const { error } = await sb.from('documentos_tributarios').update({ folio: folio.trim(), fecha_emision: fecha, estado: 'emitido', verificado_manual: true }).eq('id', id);
    if (error) return falla(error);
    notify('Folio registrado ✓'); finTab('trib', true);
  };
  window.finAbrirDoc = function(liqId, monto){
    $('fd-liq').value = liqId || '';
    $('fd-tipo').value = 'boleta_honorarios';
    $('fd-emisor').value = ''; $('fd-receptor').value = S.barberia.rut || '';
    $('fd-retiene').value = 'si'; $('fd-monto').value = monto || '';
    $('fd-fecha').value = hoyChile(); $('fd-folio').value = ''; $('fd-ppm').value = '10'; $('fd-subsidio').value = '0';
    finDocRetiene();
    openM('m-fin-doc');
  };
  window.finDocRetiene = function(){
    const ret = $('fd-retiene').value === 'si';
    $('fd-ppm-box').style.display = ret ? 'none' : '';
    $('fd-ret-info').textContent = ret
      ? 'El receptor es una empresa: retiene el impuesto (15,25% en 2026, 16% en 2027, 17% en 2028 según la fecha del documento).'
      : 'El receptor es una persona: no hay retención. El profesional paga su PPM.';
  };
  window.finGuardarDoc = async function(){
    try {
      await rpc('fin_documento_registrar', {
        p_tipo: $('fd-tipo').value, p_rut_emisor: $('fd-emisor').value.trim(), p_rut_receptor: $('fd-receptor').value.trim() || null,
        p_receptor_retiene: $('fd-retiene').value === 'si', p_honorarios: Number($('fd-monto').value) || 0,
        p_fecha_emision: $('fd-fecha').value || null, p_folio: $('fd-folio').value.trim() || null,
        p_ppm_pct: $('fd-retiene').value === 'si' ? null : (Number($('fd-ppm').value) || 0),
        p_subsidio: Number($('fd-subsidio').value) || 0, p_liquidacion: $('fd-liq').value || null
      });
      closeM('m-fin-doc'); notify('Documento registrado ✓');
      if (F.tab === 'trib') finTab('trib', true); else if (F.liqActual) finVerLiq(F.liqActual);
    } catch (e) { falla(e); }
  };

  // ── 4. Liquidaciones ───────────────────────────────────────────────────────
  async function finLiq(){
    let q = sb.from('liquidaciones').select('*').order('created_at', { ascending: false }).limit(200);
    if (F.prof) q = q.eq('barbero_nombre', F.prof);
    const { data, error } = await q;
    if (error) throw new Error(error.message);
    const L = (data || []).filter(l => l.hasta >= F.desde && l.desde <= F.hasta);
    const filas = L.map(l => {
      const pend = Number(l.total_a_transferir) + Number(l.ajustes) - Number(l.total_transferido);
      return [esc(l.barbero_nombre), l.desde + ' → ' + l.hasta, l.servicios_n, money(l.honorarios_brutos), money(l.comision_productos), money(l.propinas), money(l.total_a_transferir + Number(l.ajustes)), money(l.total_transferido), money(pend),
        `<span class="badge" style="background:${l.estado === 'pagada' ? '#16a34a22' : '#d9770622'}">${({emitida:'Emitida',pagada_parcial:'Pago parcial',pagada:'Pagada',anulada:'Anulada'})[l.estado]}</span>`,
        `<button class="btn btn-ghost btn-sm" onclick="finVerLiq('${l.id}')">Abrir</button>`];
    });
    $('fin-liq-tabla').innerHTML = tabla([{t:'Profesional'},{t:'Período'},{t:'Servicios',r:1},{t:'Honorarios',r:1},{t:'Prod.',r:1},{t:'Propinas',r:1},{t:'A transferir',r:1},{t:'Transferido',r:1},{t:'Pendiente',r:1},{t:'Estado'},{t:''}], filas, 'Aún no hay liquidaciones en este período');
    F.exportLiq = { cab: ['Profesional','Desde','Hasta','Servicios','Total cobrado','Honorarios brutos','Comisión productos','Propinas','Anticipos','Retenciones','PPM estimado (informativo)','Ajustes','A transferir','Transferido','Estado'],
      filas: L.map(l => [l.barbero_nombre, l.desde, l.hasta, l.servicios_n, l.total_cobrado, l.honorarios_brutos, l.comision_productos, l.propinas, l.anticipos, l.retenciones_aplicadas, l.ppm_estimado, l.ajustes, l.total_a_transferir, l.total_transferido, l.estado]) };
  }
  window.finNuevaLiq = function(){
    $('fl-prof').innerHTML = (S.barberos || []).map(b => `<option value="${esc(b.nombre)}">${esc(b.nombre)}</option>`).join('');
    if (F.prof) $('fl-prof').value = F.prof;
    $('fl-desde').value = F.desde; $('fl-hasta').value = F.hasta; $('fl-ppm').value = '10';
    openM('m-fin-liq');
  };
  window.finCrearLiq = async function(){
    try {
      const id = await rpc('fin_liquidacion_crear', { p_barbero: $('fl-prof').value, p_desde: $('fl-desde').value, p_hasta: $('fl-hasta').value, p_ppm_pct: Number($('fl-ppm').value) || 0 });
      closeM('m-fin-liq'); notify('Liquidación creada ✓'); finTab('liq', true); finVerLiq(id);
    } catch (e) { falla(e); }
  };
  window.finVerLiq = async function(id){
    F.liqActual = id;
    try {
      const { data: l, error } = await sb.from('liquidaciones').select('*').eq('id', id).single();
      if (error) throw error;
      const [{ data: pagos }, { data: ajustes }, base, { data: arr }] = await Promise.all([
        sb.from('liquidacion_pagos').select('*').eq('liquidacion_id', id).order('created_at'),
        sb.from('liquidacion_ajustes').select('*').eq('liquidacion_id', id).order('created_at'),
        rpc('fin_liquidacion_base_boleta', { p_liq: id }),
        sb.from('arriendos_sillon').select('*').eq('barbero_nombre', l.barbero_nombre).is('liquidacion_id', null).neq('estado', 'anulado')
      ]);
      const b = Array.isArray(base) ? base[0] : base;
      const total = Number(l.total_a_transferir) + Number(l.ajustes);
      const pend = total - Number(l.total_transferido);
      $('fl-det-titulo').textContent = 'Liquidación de ' + l.barbero_nombre;
      const fila = (a, v, cls) => `<tr><td>${a}</td><td style="text-align:right;${cls || ''}">${v}</td></tr>`;
      $('fl-det').innerHTML =
        `<div style="font-size:12px;color:var(--text3);margin-bottom:8px">${l.desde} → ${l.hasta} · ${l.servicios_n} servicios</div>` +
        `<div class="tbl-wrap"><table><tbody>` +
        fila('Total cobrado a clientes', money(l.total_cobrado)) +
        fila('Honorarios por servicios', money(l.honorarios_brutos)) +
        fila('Comisión por venta de productos', money(l.comision_productos)) +
        fila('Propinas (fondos de terceros, fuera de la boleta)', money(l.propinas)) +
        fila('− Retenciones aplicadas', money(l.retenciones_aplicadas)) +
        fila('− Anticipos', money(l.anticipos)) +
        fila('± Ajustes', money(l.ajustes)) +
        fila('<b>Total a transferir</b>', '<b>' + money(total) + '</b>') +
        fila('Ya transferido', money(l.total_transferido)) +
        fila('<b>Pendiente</b>', '<b>' + money(pend) + '</b>', 'color:#d4a853') +
        fila('PPM estimado (solo informativo)', money(l.ppm_estimado), 'color:var(--text3)') +
        `</tbody></table></div>` +
        `<div style="font-size:12px;margin:10px 0">Monto sugerido para la boleta de honorarios: <b>${money(b.monto_boleta)}</b> (${b.incluye_productos ? 'incluye' : 'no incluye'} la comisión de productos; las propinas nunca van en la boleta).</div>` +
        (pagos && pagos.length ? '<div style="font-size:12px;margin-top:8px"><b>Pagos</b><br>' + pagos.map(p => `${p.fecha} · ${money(p.monto)} · ${esc(p.medio || '')} ${esc(p.comprobante || '')}`).join('<br>') + '</div>' : '') +
        (ajustes && ajustes.length ? '<div style="font-size:12px;margin-top:8px"><b>Ajustes</b><br>' + ajustes.map(a => `${money(a.monto)} · ${esc(a.motivo)}`).join('<br>') + '</div>' : '') +
        (arr && arr.length ? '<div style="font-size:12px;margin-top:8px"><b>Arriendos de sillón pendientes</b><br>' + arr.map(a => `${a.periodo}: ${money(a.monto_neto + a.iva)} <button class="btn btn-ghost btn-sm" onclick="finDescontarArriendo('${a.id}')">Descontar</button>`).join('<br>') + '</div>' : '');
      $('fl-pagar-monto').value = pend > 0 ? pend : '';
      $('fl-acciones').style.display = l.estado === 'anulada' ? 'none' : '';
      $('fl-btn-doc').onclick = () => { closeM('m-fin-liqdet'); finAbrirDoc(id, b.monto_boleta); };
      openM('m-fin-liqdet');
    } catch (e) { falla(e); }
  };
  window.finPagarLiq = async function(){
    const monto = Number($('fl-pagar-monto').value);
    if (!monto || monto <= 0) return notify('Indica el monto a transferir', 'err');
    try {
      await rpc('fin_liquidacion_pagar', { p_liq: F.liqActual, p_monto: monto, p_medio: $('fl-pagar-medio').value, p_comprobante: $('fl-pagar-comp').value.trim() || null, p_clave: 'pago-' + F.liqActual + '-' + monto + '-' + Date.now() });
      notify('Pago registrado ✓'); $('fl-pagar-comp').value = ''; finVerLiq(F.liqActual); finTab('liq', true);
    } catch (e) { falla(e); }
  };
  window.finAjustarLiq = async function(){
    const monto = Number($('fl-aj-monto').value), motivo = $('fl-aj-motivo').value.trim();
    if (!monto) return notify('Indica el monto del ajuste (negativo descuenta)', 'err');
    if (!motivo) return notify('Falta el motivo del ajuste', 'err');
    try { await rpc('fin_liquidacion_ajustar', { p_liq: F.liqActual, p_monto: monto, p_motivo: motivo }); $('fl-aj-monto').value = ''; $('fl-aj-motivo').value = ''; notify('Ajuste guardado ✓'); finVerLiq(F.liqActual); finTab('liq', true); }
    catch (e) { falla(e); }
  };
  window.finDescontarArriendo = async function(idArr){
    try { await rpc('fin_arriendo_descontar', { p_arriendo: idArr, p_liq: F.liqActual }); notify('Arriendo descontado ✓'); finVerLiq(F.liqActual); finTab('liq', true); }
    catch (e) { falla(e); }
  };

  // ── 5. Configuración ───────────────────────────────────────────────────────
  async function finCfg(){
    const b = S.barberia;
    $('fc-modelo-actual').textContent = MODELOS[b.modelo_comercial || 'A'] + ' (desde ' + (b.modelo_vigente_desde || '—') + ')';
    $('fc-modelo-nuevo').value = b.modelo_comercial || 'A';
    $('fc-desde').value = hoyChile(); $('fc-motivo').value = '';
    $('fc-rut').value = b.rut || ''; $('fc-razon').value = b.razon_social || '';
    $('fc-validada').checked = !!b.config_tributaria_validada;
    $('fc-validada-info').textContent = b.config_tributaria_validada ? 'Validada por ' + (b.config_validada_por || '—') + (b.config_validada_at ? ' el ' + b.config_validada_at.slice(0, 10) : '') : 'Sin validar. El modelo C no se puede activar hasta validarla.';
    $('fc-prod-boleta').checked = b.comision_producto_en_boleta !== false;
    const sucs = (S.sucursales || []);
    $('fc-sucs').innerHTML = sucs.map(s => `<div class="fr"><div class="fg"><label>RUT de ${esc(s.nombre)} (vacío = el del negocio)</label><input id="fc-suc-${s.id}" type="text" value="${esc(s.rut || '')}" placeholder="${esc(b.rut || '76.000.000-0')}" onchange="finGuardarRutSuc('${s.id}')"></div></div>`).join('');
    const { data: reglas } = await sb.from('reglas_distribucion').select('*').order('created_at', { ascending: false });
    const alc = { negocio: 'Todo el negocio', profesional: 'Un profesional', servicio: 'Un servicio', profesional_servicio: 'Profesional + servicio' };
    $('fc-reglas').innerHTML = tabla([{t:'Alcance'},{t:'Quién / qué'},{t:'% profesional',r:1},{t:'Base'},{t:'Versión',r:1},{t:'Vigente desde'}],
      (reglas || []).map(r => [alc[r.alcance], esc([r.barbero_nombre, r.servicio_nombre].filter(Boolean).join(' · ') || '—'), r.pct_profesional + '%', r.base === 'neto' ? 'Neto (sin IVA)' : 'Precio final', 'v' + r.version, r.vigente_desde]),
      'Sin reglas nuevas: se usa la comisión de cada profesional como hasta ahora');
    $('fc-regla-prof').innerHTML = '<option value="">—</option>' + (S.barberos || []).map(x => `<option value="${esc(x.nombre)}">${esc(x.nombre)}</option>`).join('');
    $('fc-regla-desde').value = hoyChile();
    finReglaAlcance();
    const { data: arr } = await sb.from('arriendos_sillon').select('*').order('periodo', { ascending: false }).limit(50);
    $('fc-arr-prof').innerHTML = (S.barberos || []).map(x => `<option value="${esc(x.nombre)}">${esc(x.nombre)}</option>`).join('');
    $('fc-arr-mes').value = mesActual();
    $('fc-arr-lista').innerHTML = tabla([{t:'Período'},{t:'Profesional'},{t:'Neto',r:1},{t:'IVA',r:1},{t:'Estado'}], (arr || []).map(a => [a.periodo, esc(a.barbero_nombre), money(a.monto_neto), money(a.iva), a.estado]), 'Sin arriendos registrados');
  }
  window.finReglaAlcance = function(){
    const a = $('fc-regla-alc').value;
    $('fc-regla-prof-box').style.display = a === 'profesional' || a === 'profesional_servicio' ? '' : 'none';
    $('fc-regla-serv-box').style.display = a === 'servicio' || a === 'profesional_servicio' ? '' : 'none';
  };
  window.finCrearRegla = async function(){
    const alc = $('fc-regla-alc').value;
    const pct = Number($('fc-regla-pct').value);
    if (isNaN(pct) || pct < 0 || pct > 100) return notify('El porcentaje debe estar entre 0 y 100', 'err');
    try {
      await rpc('fin_regla_crear', { p_alcance: alc, p_barbero: (alc === 'profesional' || alc === 'profesional_servicio') ? $('fc-regla-prof').value : null, p_servicio: (alc === 'servicio' || alc === 'profesional_servicio') ? $('fc-regla-serv').value.trim() : null, p_pct: pct, p_base: $('fc-regla-base').value, p_desde: $('fc-regla-desde').value });
      notify('Regla creada ✓ (rige desde la fecha indicada; lo anterior no cambia)'); finCfg();
    } catch (e) { falla(e); }
  };
  window.finCambiarModelo = async function(){
    try {
      await rpc('fin_cambiar_modelo', { p_modelo: $('fc-modelo-nuevo').value, p_desde: $('fc-desde').value, p_motivo: $('fc-motivo').value });
      const { data } = await sb.from('barberias').select('*').eq('id', S.barberia.id).single(); if (data) S.barberia = data;
      notify('Modelo actualizado ✓'); finCfg();
    } catch (e) { falla(e); }
  };
  window.finGuardarDatos = async function(){
    const upd = { rut: $('fc-rut').value.trim() || null, razon_social: $('fc-razon').value.trim() || null, comision_producto_en_boleta: $('fc-prod-boleta').checked };
    const { error } = await sb.from('barberias').update(upd).eq('id', S.barberia.id);
    if (error) return falla(error);
    Object.assign(S.barberia, upd); notify('Guardado ✓');
  };
  window.finValidarConfig = async function(){
    const v = $('fc-validada').checked;
    if (v && !($('fc-rut').value.trim())) { $('fc-validada').checked = false; return notify('Ingresa el RUT del negocio antes de validar', 'err'); }
    const upd = { config_tributaria_validada: v, config_validada_por: v ? (S.perfil.nombre || S.perfil.email || 'dueño') : null, config_validada_at: v ? new Date().toISOString() : null, rut: $('fc-rut').value.trim() || null, razon_social: $('fc-razon').value.trim() || null };
    const { error } = await sb.from('barberias').update(upd).eq('id', S.barberia.id);
    if (error) { $('fc-validada').checked = !v; return falla(error); }
    Object.assign(S.barberia, upd); notify(v ? 'Configuración validada ✓' : 'Validación quitada'); finCfg();
  };
  window.finGuardarRutSuc = async function(id){
    const v = $('fc-suc-' + id).value.trim() || null;
    const { error } = await sb.from('sucursales').update({ rut: v }).eq('id', id);
    if (error) return falla(error);
    const s = (S.sucursales || []).find(x => x.id === id); if (s) s.rut = v; notify('RUT de la sucursal guardado ✓');
  };
  window.finCrearArriendo = async function(){
    const neto = Number($('fc-arr-monto').value);
    if (!neto || neto <= 0) return notify('Indica el monto neto del arriendo', 'err');
    const ivaPct = Number(S.barberia.iva_pct != null ? S.barberia.iva_pct : 19);
    const { error } = await sb.from('arriendos_sillon').insert({ barberia_id: S.barberia.id, barbero_nombre: $('fc-arr-prof').value, periodo: $('fc-arr-mes').value, monto_neto: neto, iva: Math.floor(neto * ivaPct / 100 + 0.5) });
    if (error) return falla(error);
    $('fc-arr-monto').value = ''; notify('Arriendo registrado ✓'); finCfg();
  };

  // ── Exportación (CSV y Excel) ──────────────────────────────────────────────
  const EXPORTS = { caja: ['exportCaja'], ventas: ['exportVentas'], trib: ['exportTrib', 'exportDocs'], liq: ['exportLiq'] };
  const NOMBRES = { caja: 'Caja', ventas: 'Ventas', trib: 'Tributacion', liq: 'Liquidaciones' };
  const NOMBRES_HOJA = { exportCaja: 'Caja', exportVentas: 'Ventas', exportTrib: 'IVA', exportDocs: 'Documentos', exportLiq: 'Liquidaciones' };
  function celdaCSV(v){ const s = v == null ? '' : String(v); return /[";\n\r]/.test(s) ? '"' + s.replace(/"/g, '""') + '"' : s; }
  window.finExportar = function(formato){
    const tab = F.tab; const claves = EXPORTS[tab]; if (!claves) return;
    const sets = claves.map(k => ({ k, d: F[k] })).filter(x => x.d && x.d.filas);
    if (!sets.length) return notify('No hay datos para exportar', 'err');
    const nombre = `Reservia_${NOMBRES[tab]}_${F.desde}_a_${F.hasta}`;
    if (formato === 'xlsx') {
      const wb = XLSX.utils.book_new();
      sets.forEach(x => XLSX.utils.book_append_sheet(wb, XLSX.utils.aoa_to_sheet([x.d.cab, ...x.d.filas]), NOMBRES_HOJA[x.k]));
      XLSX.writeFile(wb, nombre + '.xlsx');
    } else {
      const x = sets[0].d; // el CSV lleva la primera hoja; el Excel trae todas
      const txt = '﻿' + [x.cab, ...x.filas].map(f => f.map(celdaCSV).join(';')).join('\r\n');
      const url = URL.createObjectURL(new Blob([txt], { type: 'text/csv;charset=utf-8' }));
      const a = document.createElement('a'); a.href = url; a.download = nombre + '.csv'; document.body.appendChild(a); a.click(); a.remove(); setTimeout(() => URL.revokeObjectURL(url), 1000);
    }
  };
})();
