// Boletas electrónicas: reparto, endpoint /api/boletas y proveedores, con
// Supabase, Resend, Emisso y Boleteados simulados. Correr: node test-boletas.js
process.env.SUPABASE_SERVICE_ROLE_KEY = 'svc'; process.env.SUPABASE_URL = 'https://x.supabase.co';
process.env.RESEND_API_KEY = 're_test'; process.env.EMISSO_API_KEY = 'connect_sk_test';
process.env.BOLETEADOS_URL = 'https://api.boleteados.test'; process.env.BOLETEADOS_API_KEY = 'bol_test';
process.env.BOLETEADOS_WEBHOOK_SECRET = 'whsec_test'; process.env.BOLETAS_CRON_SECRET = 'cron_test';
const crypto = require('crypto');
const { repartir, parteProfesional, medioPago } = require('./api/_lib/boletas/reparto');
const handler = require('./api/boletas.js');

const res = []; const ok = (n, c, d) => res.push((c ? 'OK    ' : 'FALLO ') + n + (c ? '' : '  -> ' + JSON.stringify(d)));

// ── 1. Reparto (puro) ────────────────────────────────────────────────────────
const NEG = { boletas_modo: 'una', boletas_tipo_dte: 39, boletas_emisor_ref: 'conn_local', modo_comision: 'total', iva_pct: 19 };
const BARB = [{ id: 'm1', nombre: 'Mario', boletas_emisor_ref: 'conn_mario', boletas_tipo_dte: null }, { id: 'f1', nombre: 'Felipe', boletas_emisor_ref: null }];
const V1 = { id: 'v1', valor: 15000, comision_monto: 9000, barbero_id: 'm1', servicio: 'Corte y barba', metodo_pago: 'Débito', estado: 'Atendida' };
let r = repartir({ origen: { tipo: 'cobro', id: 'c1' }, negocio: NEG, barberos: BARB, visitas: [V1], productos: [] });
ok('A: una sola boleta del local por el total', r.length === 1 && r[0].emisor === 'local' && r[0].monto_total === 15000 && r[0].emisor_ref === 'conn_local', r);
ok('A: medio de pago débito = PAGO_ELECTRONICO', r[0].medio_pago === 'PAGO_ELECTRONICO', r[0]);
r = repartir({ origen: { tipo: 'cobro', id: 'c1' }, negocio: { ...NEG, boletas_modo: 'dos' }, barberos: BARB, visitas: [V1], productos: [{ valor: 8000 }] });
const loc = r.find(x => x.emisor === 'local'), pro = r.find(x => x.emisor === 'profesional');
ok('B: barbero $9.000 y local $6.000 + producto $8.000', pro && pro.monto_total === 9000 && loc && loc.monto_total === 14000, r);
ok('B: las llaves distinguen emisor', pro.llave === 'cobro:c1|profesional|m1|39' && loc.llave === 'cobro:c1|local|-|39', r);
r = repartir({ origen: { tipo: 'cobro', id: 'c2' }, negocio: { ...NEG, boletas_modo: 'dos' }, barberos: BARB, visitas: [{ ...V1, barbero_id: 'f1' }], productos: [] });
ok('B: profesional sin emisor → su parte va al local', r.length === 1 && r[0].emisor === 'local' && r[0].monto_total === 15000, r);
ok('Comisión sobre neto se lleva a bruto', parteProfesional({ valor: 11900, comision_monto: 5000 }, { modo_comision: 'neto_iva', iva_pct: 19 }) === 5950);
ok('La parte del profesional nunca supera lo cobrado', parteProfesional({ valor: 1000, comision_monto: 5000 }, { modo_comision: 'total' }) === 1000);
r = repartir({ origen: { tipo: 'cobro', id: 'c3' }, negocio: { ...NEG, boletas_modo: 'dos' }, barberos: BARB, visitas: [{ ...V1, comision_monto: 15000 }], productos: [] });
ok('B: si el local no tiene monto, no se emite boleta del local', r.length === 1 && r[0].emisor === 'profesional', r);
r = repartir({ origen: { tipo: 'cobro', id: 'c4' }, negocio: NEG, barberos: BARB, visitas: [{ ...V1, estado: 'Cancelada' }], productos: [] });
ok('Visitas canceladas no generan boleta', r.length === 0, r);
ok('Medios de pago', medioPago('Efectivo') === 'EFECTIVO' && medioPago('Transferencia') === 'TRANSFERENCIA' && medioPago('Gift card') === 'OTRO');

// ── 2. Endpoint con todo simulado ────────────────────────────────────────────
const U_DUENO = 'aaaaaaaa-0000-4000-8000-000000000001', U_PROF = 'aaaaaaaa-0000-4000-8000-000000000002';
const B1 = 'bbbbbbbb-0000-4000-8000-000000000001', B2 = 'bbbbbbbb-0000-4000-8000-000000000002';
const COBRO = 'cccccccc-0000-4000-8000-000000000001', COBRO_B2 = 'cccccccc-0000-4000-8000-000000000002';
const M = 'dddddddd-0000-4000-8000-000000000001', CLI = 'eeeeeeee-0000-4000-8000-000000000001';
const PERFIL = { [U_DUENO]: { barberia_id: B1, rol: 'dueno' }, [U_PROF]: { barberia_id: B1, rol: 'profesional' } };
let DB, LOG;
function reset(neg) {
  LOG = { correos: [], emisso: [], boleteados: [] };
  DB = {
    barberias: [{ id: B1, nombre: 'Essentials Studio', boletas_proveedor: 'simulado', boletas_modo: 'dos', boletas_tipo_dte: 39, boletas_emisor_ref: 'conn_local', boletas_enviar_correo: true, modo_comision: 'total', iva_pct: 19, ...(neg || {}) }],
    barberos: [{ id: M, barberia_id: B1, nombre: 'Mario Zúñiga', boletas_emisor_ref: 'conn_mario', boletas_tipo_dte: null, auth_user_id: U_PROF, puede_procesar_pagos: false }],
    visitas: [
      { id: 'ffffffff-0000-4000-8000-000000000001', cobro_id: COBRO, barberia_id: B1, valor: 15000, comision_monto: 9000, barbero_id: M, servicio: 'Corte y barba', metodo_pago: 'Efectivo', cliente_id: CLI, estado: 'Atendida', fecha: '2026-11-20' },
      { id: 'ffffffff-0000-4000-8000-000000000002', cobro_id: COBRO_B2, barberia_id: B2, valor: 5000, comision_monto: 0, barbero_id: null, servicio: 'Otro', metodo_pago: 'Efectivo', estado: 'Atendida', fecha: '2026-11-20' }
    ],
    cobro_productos: [],
    clientes: [{ id: CLI, barberia_id: B1, nombre: 'Juan', apellido: 'Pérez', email: 'juan@correo.cl' }],
    boletas: []
  };
}
const json = (o, st = 200) => ({ ok: st < 400, status: st, json: async () => o, text: async () => JSON.stringify(o) });
function coincide(row, q) {
  for (const [k, v] of q.entries()) {
    if (['select', 'order', 'limit', 'on_conflict'].includes(k)) continue;
    const [op, ...rest] = v.split('.'); const val = rest.join('.');
    const cell = row[k];
    if (op === 'eq' && String(cell) !== decodeURIComponent(val)) return false;
    if (op === 'in' && !val.replace(/^\(|\)$/g, '').split(',').includes(String(cell))) return false;
    if (op === 'lte' && !(String(cell) <= val)) return false;
    if (op === 'lt' && !(String(cell) < val)) return false;
  }
  return true;
}
let EMISSO_FALLA_RED = false, BOLETEADOS_ESTADO = 'aceptada';
global.fetch = async (url, opt = {}) => {
  const m = (opt.method || 'GET').toUpperCase(); const body = opt.body ? JSON.parse(opt.body) : null; const h = opt.headers || {};
  if (url.includes('/auth/v1/user')) { const t = (h.Authorization || '').replace('Bearer ', ''); return PERFIL[t] ? json({ id: t }) : json({}, 401); }
  if (url.startsWith('https://api.resend.com')) { LOG.correos.push(body); return json({ id: 'em_1' }); }
  if (url.startsWith('https://connect.emisso.ai')) {
    LOG.emisso.push({ url, h, body });
    if (url.includes('previsualizar')) return json({ data: { previewRef: 'pref_' + LOG.emisso.length } });
    if (EMISSO_FALLA_RED) { EMISSO_FALLA_RED = false; throw new Error('socket hang up'); }
    return json({ data: { resultado: { estado: 'emitida', tipoDte: '39', folio: '1287', pdfUrl: 'https://eboleta.s3.amazonaws.com/prod/pdf/x.pdf' } } });
  }
  if (url.startsWith('https://api.boleteados.test')) {
    LOG.boleteados.push({ url, h, body });
    return json({ id: 'bol_' + LOG.boleteados.length, estado: BOLETEADOS_ESTADO, folio: BOLETEADOS_ESTADO === 'aceptada' ? '501' : null }, 201);
  }
  if (url.includes('/rest/v1/')) {
    const p = url.split('/rest/v1/')[1]; const tabla = p.split('?')[0]; const q = new URLSearchParams(p.split('?')[1] || '');
    if (tabla === 'perfiles') { const id = q.get('id').replace('eq.', ''); return json(PERFIL[id] ? [PERFIL[id]] : []); }
    const t = DB[tabla] || [];
    if (m === 'GET') { let out = t.filter(x => coincide(x, q)); if (q.get('limit')) out = out.slice(0, Number(q.get('limit'))); return json(out.map(x => ({ ...x }))); }
    if (m === 'POST') {
      for (const f of (Array.isArray(body) ? body : [body])) {
        if (tabla === 'boletas' && t.some(x => x.barberia_id === f.barberia_id && x.llave === f.llave)) continue;
        t.push({ id: crypto.randomUUID(), idem_key: crypto.randomUUID(), estado: 'pendiente', intentos: 0, proximo_intento: new Date(0).toISOString(), created_at: new Date().toISOString(), updated_at: new Date().toISOString(), correo_enviado_at: null, folio: null, pdf_url: null, proveedor_ref: null, error: null, ...f });
      }
      return json([], 201);
    }
    if (m === 'PATCH') { const hits = t.filter(x => coincide(x, q)); hits.forEach(x => Object.assign(x, body)); return json(hits.map(x => ({ ...x }))); }
  }
  throw new Error('fetch no simulado: ' + url);
};
async function llamar(body, user, headers) {
  let status = 0, out = null;
  const rq = { method: 'POST', body, headers: { ...(user ? { authorization: 'Bearer ' + user } : {}), ...(headers || {}) } };
  await handler(rq, { setHeader() {}, status(s) { status = s; return { json(o) { out = o; } }; } });
  return { status, ...out };
}

(async () => {
  // Simulado, camino B
  reset();
  let a = await llamar({ accion: 'emitir', cobroId: COBRO }, U_DUENO);
  ok('Emitir: responde ok con 2 boletas', a.status === 200 && a.boletas.length === 2, a);
  ok('Emitir: ambas emitidas con folio', a.boletas.every(b => b.estado === 'emitida' && /^SIM-/.test(b.folio)), a.boletas);
  ok('Emitir: montos $6.000 local y $9.000 barbero', a.boletas.find(b => b.emisor === 'local').monto_total === 6000 && a.boletas.find(b => b.emisor === 'profesional').monto_total === 9000, a.boletas);
  ok('Correo al cliente: uno solo, con las 2 boletas', LOG.correos.length === 1 && LOG.correos[0].to[0] === 'juan@correo.cl' && /Tus boletas/.test(LOG.correos[0].subject), LOG.correos);
  const folios = a.boletas.map(b => b.folio).join();
  a = await llamar({ accion: 'emitir', cobroId: COBRO }, U_DUENO);
  ok('Mismo cobro otra vez: no crea boletas nuevas', DB.boletas.length === 2 && a.boletas.length === 2, DB.boletas.length);
  ok('Mismo cobro otra vez: mismos folios, sin segundo correo', a.boletas.map(b => b.folio).join() === folios && LOG.correos.length === 1, LOG.correos.length);

  // Permisos y aislamiento
  a = await llamar({ accion: 'emitir', cobroId: COBRO }, U_PROF);
  ok('Profesional sin permiso de cobro: 403', a.status === 403, a);
  a = await llamar({ accion: 'emitir', cobroId: COBRO_B2 }, U_DUENO);
  ok('Cobro de otro negocio: 404', a.status === 404, a);
  a = await llamar({ accion: 'emitir', cobroId: COBRO });
  ok('Sin sesión: 401', a.status === 401, a);
  reset({ boletas_proveedor: 'ninguno' });
  a = await llamar({ accion: 'emitir', cobroId: COBRO }, U_DUENO);
  ok('Proveedor "ninguno": no emite nada', a.status === 200 && a.omitido === true && DB.boletas.length === 0, a);

  // Emisso
  reset({ boletas_proveedor: 'emisso', boletas_modo: 'una' });
  a = await llamar({ accion: 'emitir', cobroId: COBRO }, U_DUENO);
  const em = LOG.emisso.find(x => x.url.includes('sii.boleta.emitir'));
  ok('Emisso: vista previa con total y tipo', LOG.emisso[0].body.input.candidato.montoTotal === 15000 && LOG.emisso[0].body.input.candidato.tipoDte === '39', LOG.emisso[0]);
  ok('Emisso: conexión del local y Idempotency-Key = idem_key', em.h['X-Connect-Connection'] === 'conn_local' && em.h['Idempotency-Key'] === DB.boletas[0].idem_key, em.h);
  ok('Emisso: queda emitida con folio y PDF', a.boletas[0].estado === 'emitida' && a.boletas[0].folio === '1287' && /^https:/.test(a.boletas[0].pdf_url), a.boletas);
  reset({ boletas_proveedor: 'emisso', boletas_modo: 'una' });
  EMISSO_FALLA_RED = true;
  a = await llamar({ accion: 'emitir', cobroId: COBRO }, U_DUENO);
  ok('Emisso: red cortada al emitir → desconocido (no se sabe si salió)', a.status === 200 && a.boletas[0].estado === 'desconocido', a.boletas);
  ok('El cobro no se bloquea: respondió igual y sin correo', LOG.correos.length === 0);
  const key1 = DB.boletas[0].idem_key; DB.boletas[0].proximo_intento = new Date(0).toISOString();
  a = await llamar({ accion: 'reintentar' }, U_DUENO);
  const emitidos = LOG.emisso.filter(x => x.url.includes('sii.boleta.emitir'));
  ok('Reintento: misma Idempotency-Key, no una nueva', emitidos.length === 2 && emitidos.every(x => x.h['Idempotency-Key'] === key1), emitidos.map(x => x.h['Idempotency-Key']));
  ok('Reintento: queda emitida y sale el correo', DB.boletas[0].estado === 'emitida' && LOG.correos.length === 1, DB.boletas[0]);
  a = await llamar({ accion: 'reintentar' }, U_PROF);
  ok('Reintentar: profesional no puede', a.status === 403, a);

  // Boleteados (asíncrono + webhook)
  reset({ boletas_proveedor: 'boleteados', boletas_modo: 'una' });
  BOLETEADOS_ESTADO = 'en_cola';
  a = await llamar({ accion: 'emitir', cobroId: COBRO }, U_DUENO);
  ok('Boleteados: en cola → en_proceso', a.boletas[0].estado === 'en_proceso' && DB.boletas[0].proveedor_ref === 'bol_1', a.boletas);
  ok('Boleteados: manda emisor, referencia y no pide que ellos envíen correo', LOG.boleteados[0].body.emisor_id === 'conn_local' && LOG.boleteados[0].body.enviar_correo === false && LOG.boleteados[0].h['Idempotency-Key'] === DB.boletas[0].idem_key, LOG.boleteados[0]);
  const cuerpo = { accion: 'webhook', id: 'bol_1', estado: 'aceptada', folio: '777', pdf_url: 'https://boleteados.cl/pdf/777' };
  const t = Math.floor(Date.now() / 1000);
  const firma = crypto.createHmac('sha256', 'whsec_test').update(`${t}.bol_1.aceptada.777`).digest('hex');
  a = await llamar(cuerpo, null, { 'x-boleteados-firma': 'firma-falsa' });
  ok('Webhook con firma inválida: 401 y no cambia nada', a.status === 401 && DB.boletas[0].estado === 'en_proceso', a);
  a = await llamar(cuerpo, null, { 'x-boleteados-firma': `t=${t},v1=${firma}` });
  ok('Webhook válido: queda emitida con folio', a.status === 200 && DB.boletas[0].estado === 'emitida' && DB.boletas[0].folio === '777', DB.boletas[0]);
  ok('Webhook válido: sale el correo', LOG.correos.length === 1, LOG.correos.length);
  const viejo = t - 600, firmaVieja = crypto.createHmac('sha256', 'whsec_test').update(`${viejo}.bol_1.aceptada.777`).digest('hex');
  a = await llamar(cuerpo, null, { 'x-boleteados-firma': `t=${viejo},v1=${firmaVieja}` });
  ok('Webhook con más de 5 minutos: 401', a.status === 401, a);

  // Cron
  a = await llamar({ accion: 'cron' }, null, { 'x-cron-secret': 'otro' });
  ok('Cron sin el secreto correcto: 401', a.status === 401, a);
  a = await llamar({ accion: 'cron' }, null, { 'x-cron-secret': 'cron_test' });
  ok('Cron con secreto: ok', a.status === 200 && typeof a.procesadas === 'number', a);

  console.log(res.join('\n'));
  const f = res.filter(x => x.startsWith('FALLO')).length;
  console.log(`\n${res.length - f}/${res.length} OK`);
  process.exit(f ? 1 : 0);
})();
