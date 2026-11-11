// Mercado Pago Point: endpoint /api/mp-point con Supabase y Mercado Pago simulados.
process.env.SUPABASE_SERVICE_ROLE_KEY = 'svc'; process.env.SUPABASE_URL = 'https://x.supabase.co';
const handler = require('./api/mp-point.js');
const res = []; const ok = (n, c, d) => res.push((c ? 'OK    ' : 'FALLO ') + n + (c ? '' : '  -> ' + JSON.stringify(d)));
const TOKEN = 'APP_USR-1234567890-secreto-ABCD';
const U_DUENO = 'aaaaaaaa-0000-4000-8000-000000000001', U_PROF = 'aaaaaaaa-0000-4000-8000-000000000002', U_PROF_OK = 'aaaaaaaa-0000-4000-8000-000000000003', U_REC = 'aaaaaaaa-0000-4000-8000-000000000004';
const B1 = 'bbbbbbbb-0000-4000-8000-000000000001', B2 = 'bbbbbbbb-0000-4000-8000-000000000002';
const PERFIL = { [U_DUENO]: { barberia_id: B1, rol: 'dueno' }, [U_PROF]: { barberia_id: B1, rol: 'profesional' }, [U_PROF_OK]: { barberia_id: B1, rol: 'profesional' }, [U_REC]: { barberia_id: B1, rol: 'recepcion' } };

let DB, MPLOG, MP;
function reset() {
  DB = { mp_config: [], mp_point_ordenes: [] }; MPLOG = [];
  MP = { me: { status: 200, body: { id: 777, nickname: 'ESSENTIALS' } }, terminales: { status: 200, body: { data: { terminals: [{ id: 'NEWLAND_N950__N950NCB801293324', operating_mode: 'STANDALONE' }] } } },
         crear: { status: 201, body: { id: 'ORD00001111222233334444555566', status: 'created' } },
         orden: { status: 200, body: { id: 'ORD00001111222233334444555566', status: 'created' } },
         cancelar: { status: 200, body: { status: 'canceled' } }, setup: { status: 200, body: {} } };
}
const json = (o, st = 200) => ({ ok: st < 400, status: st, json: async () => o, text: async () => JSON.stringify(o) });
global.fetch = async (url, opt = {}) => {
  const m = (opt.method || 'GET').toUpperCase(); const body = opt.body ? JSON.parse(opt.body) : null;
  if (url.startsWith('https://api.mercadopago.com')) {
    const ruta = url.replace('https://api.mercadopago.com', ''); MPLOG.push({ m, ruta, body, h: opt.headers });
    if (ruta === '/users/me') return json(MP.me.body, MP.me.status);
    if (ruta === '/terminals/v1/list') return json(MP.terminales.body, MP.terminales.status);
    if (ruta === '/terminals/v1/setup') return json(MP.setup.body, MP.setup.status);
    if (ruta === '/v1/orders' && m === 'POST') return json(MP.crear.body, MP.crear.status);
    if (/\/cancel$/.test(ruta)) return json(MP.cancelar.body, MP.cancelar.status);
    if (/^\/v1\/orders\//.test(ruta)) return json(MP.orden.body, MP.orden.status);
  }
  if (url.includes('/auth/v1/user')) {
    const t = (opt.headers.Authorization || '').replace('Bearer ', ''); return PERFIL[t] ? json({ id: t }) : json({}, 401);
  }
  if (url.includes('/rest/v1/')) {
    const p = url.split('/rest/v1/')[1]; const tabla = p.split('?')[0]; const q = new URLSearchParams(p.split('?')[1] || '');
    if (tabla === 'perfiles') { const id = (q.get('id') || '').replace('eq.', ''); return json(PERFIL[id] ? [PERFIL[id]] : []); }
    if (tabla === 'barberos') { const id = (q.get('auth_user_id') || '').replace('eq.', ''); return json(id === U_PROF_OK ? [{ puede_procesar_pagos: true }] : [{ puede_procesar_pagos: false }]); }
    const filtros = [...q.entries()].filter(([k, v]) => /^(eq)\./.test(v));
    const coincide = r => filtros.every(([k, v]) => String(r[k]) === v.replace('eq.', ''));
    if (m === 'GET') return json(DB[tabla].filter(coincide));
    if (m === 'POST') { DB[tabla].push(body); return json([body], 201); }
    if (m === 'PATCH') { DB[tabla].filter(coincide).forEach(r => Object.assign(r, body)); return json([]); }
    if (m === 'DELETE') { DB[tabla] = DB[tabla].filter(r => !coincide(r)); return json([]); }
  }
  throw new Error('fetch no simulado: ' + url);
};
async function llamar(usuario, body, method = 'POST') {
  let st, out; const r = { setHeader() {}, status(c) { st = c; return this; }, json(o) { out = o; } };
  await handler({ method, body, headers: usuario ? { authorization: 'Bearer ' + usuario } : {} }, r); return { st, out };
}
const CLAVE1 = 'cccccccc-0000-4000-8000-000000000001', CLAVE2 = 'cccccccc-0000-4000-8000-000000000002';
const ORD = 'ORD00001111222233334444555566';
const pagoOk = (extra = {}) => ({ id: ORD, status: 'processed', transactions: { payments: [{ id: 'PAY1', status: 'processed', paid_amount: '12000', payment_method: { type: 'debit_card' }, ...extra }] } });

(async () => {
  reset();
  let r = await llamar(U_DUENO, { accion: 'estado_config' }, 'GET'); ok('GET no permitido', r.st === 405, r);
  r = await llamar(null, { accion: 'estado_config' }); ok('sin sesión: 401', r.st === 401, r);
  r = await llamar('token-invalido', { accion: 'estado_config' }); ok('sesión inválida: 401', r.st === 401, r);
  r = await llamar(U_DUENO, { accion: 'borrar_todo' }); ok('acción desconocida: 400', r.st === 400, r);
  r = await llamar(U_DUENO, { accion: 'constructor' }); ok('acción tipo constructor: 400', r.st === 400, r);

  r = await llamar(U_DUENO, { accion: 'estado_config' }); ok('sin config: no conectado', r.out.conectado === false && r.out.activo === false, r);

  // Conectar
  r = await llamar(U_PROF, { accion: 'conectar', token: TOKEN }); ok('profesional no puede conectar', r.st === 403 && DB.mp_config.length === 0, r);
  r = await llamar(U_REC, { accion: 'conectar', token: TOKEN }); ok('recepción no puede conectar', r.st === 403, r);
  r = await llamar(U_DUENO, { accion: 'conectar', token: 'corto' }); ok('token corto: 400', r.st === 400, r);
  r = await llamar(U_DUENO, { accion: 'conectar', token: 'APP_USR con espacios 1234567890123456' }); ok('token con espacios: 400', r.st === 400, r);
  MP.me = { status: 401, body: { message: 'invalid token' } };
  r = await llamar(U_DUENO, { accion: 'conectar', token: TOKEN }); ok('token rechazado por MP: 400 y no guarda', r.st === 400 && /token/i.test(r.out.error) && DB.mp_config.length === 0, r);
  MP.me = { status: 200, body: { id: 777, nickname: 'ESSENTIALS' } };
  r = await llamar(U_DUENO, { accion: 'conectar', token: TOKEN });
  ok('conectar guarda el token en el servidor', r.st === 200 && DB.mp_config.length === 1 && DB.mp_config[0].access_token === TOKEN && DB.mp_config[0].activo === false, r);
  ok('la respuesta NO contiene el token', !JSON.stringify(r.out).includes(TOKEN) && r.out.token_final === 'ABCD', r);
  r = await llamar(U_PROF, { accion: 'estado_config' }); ok('estado_config a profesional: sin token_final, no activo', r.out.conectado === true && r.out.activo === false && r.out.token_final === null && !JSON.stringify(r.out).includes('secreto'), r);

  // Terminales
  r = await llamar(U_PROF, { accion: 'terminales' }); ok('profesional no lista terminales', r.st === 403, r);
  r = await llamar(U_DUENO, { accion: 'terminales' });
  ok('lista terminales con nombre corto y modo', r.st === 200 && r.out.terminales[0].id === 'NEWLAND_N950__N950NCB801293324' && r.out.terminales[0].nombre === 'N950 · …3324' && r.out.terminales[0].modo === 'STANDALONE', r);
  r = await llamar(U_DUENO, { accion: 'elegir_terminal', terminalId: 'OTRA__X' }); ok('terminal ajena: 400', r.st === 400, r);
  r = await llamar(U_DUENO, { accion: 'activo', activo: true }); ok('no activa sin terminal', r.st === 400, r);
  MPLOG.length = 0;
  r = await llamar(U_DUENO, { accion: 'elegir_terminal', terminalId: 'NEWLAND_N950__N950NCB801293324' });
  const setup = MPLOG.find(x => x.ruta === '/terminals/v1/setup');
  ok('elegir terminal en STANDALONE la pasa a PDV', r.st === 200 && setup && setup.m === 'PATCH' && setup.body.terminals[0].operating_mode === 'PDV' && r.out.reiniciar === true, [r, MPLOG]);
  ok('queda activo con la terminal elegida', DB.mp_config[0].activo === true && DB.mp_config[0].terminal_id === 'NEWLAND_N950__N950NCB801293324', DB.mp_config[0]);
  MP.terminales.body.data.terminals[0].operating_mode = 'PDV'; MPLOG.length = 0;
  await llamar(U_DUENO, { accion: 'elegir_terminal', terminalId: 'NEWLAND_N950__N950NCB801293324' });
  ok('si ya está en PDV no vuelve a cambiarla', !MPLOG.some(x => x.ruta === '/terminals/v1/setup'), MPLOG);
  MP.setup = { status: 400, body: { message: 'x' } }; MP.terminales.body.data.terminals[0].operating_mode = 'STANDALONE';
  r = await llamar(U_DUENO, { accion: 'elegir_terminal', terminalId: 'NEWLAND_N950__N950NCB801293324' });
  ok('si no puede pasar a PDV avisa cómo hacerlo a mano', r.st === 502 && /Modo integrado|PDV/.test(r.out.error), r);
  MP.setup = { status: 200, body: {} };

  // Cobrar
  r = await llamar(U_PROF, { accion: 'cobrar', monto: 12000, clave: CLAVE1 }); ok('profesional sin permiso de pagos no cobra', r.st === 403, r);
  r = await llamar(U_PROF_OK, { accion: 'cobrar', monto: 12000, clave: CLAVE1 }); ok('profesional con permiso de pagos sí cobra', r.st === 200, r);
  reset(); DB.mp_config.push({ barberia_id: B1, access_token: TOKEN, terminal_id: 'NEWLAND_N950__N950NCB801293324', terminal_nombre: 'N950 · …3324', activo: true });
  for (const m of [0, -5, 1.5, '12000abc', 99999999, null, NaN]) { r = await llamar(U_DUENO, { accion: 'cobrar', monto: m, clave: CLAVE1 }); ok('monto inválido rechazado: ' + m, r.st === 400 && MPLOG.length === 0, r); }
  r = await llamar(U_DUENO, { accion: 'cobrar', monto: 12000, clave: 'no-uuid' }); ok('clave inválida: 400', r.st === 400, r);
  MPLOG.length = 0;
  r = await llamar(U_REC, { accion: 'cobrar', monto: 12000, clave: CLAVE1 });
  const crea = MPLOG.find(x => x.ruta === '/v1/orders');
  ok('cobrar crea la orden con monto entero en texto, terminal y clave', r.st === 200 && r.out.orderId === ORD && crea.body.type === 'point' && crea.body.transactions.payments[0].amount === '12000' && crea.body.config.point.terminal_id === 'NEWLAND_N950__N950NCB801293324' && crea.h['X-Idempotency-Key'] === CLAVE1 && crea.body.external_reference === 'rsv-' + CLAVE1, [r, crea]);
  ok('external_reference cumple el formato de MP (≤64, letras/números/guion)', /^[A-Za-z0-9-]{1,64}$/.test(crea.body.external_reference), crea.body.external_reference);
  ok('la orden queda en el libro', DB.mp_point_ordenes.length === 1 && DB.mp_point_ordenes[0].monto === 12000 && DB.mp_point_ordenes[0].creado_por === U_REC, DB.mp_point_ordenes);
  MPLOG.length = 0;
  r = await llamar(U_REC, { accion: 'cobrar', monto: 12000, clave: CLAVE1 });
  ok('mismo clic repetido no crea otra orden', r.st === 200 && r.out.orderId === ORD && !MPLOG.length && DB.mp_point_ordenes.length === 1, [r, MPLOG]);
  MP.crear = { status: 409, body: { errors: [{ code: 'already_queued_order_for_terminal' }] } };
  r = await llamar(U_DUENO, { accion: 'cobrar', monto: 5000, clave: CLAVE2 }); ok('terminal ocupada: mensaje claro', r.st === 409 && /pendiente/.test(r.out.error) && DB.mp_point_ordenes.length === 1, r);
  MP.crear = { status: 401, body: {} };
  r = await llamar(U_DUENO, { accion: 'cobrar', monto: 5000, clave: CLAVE2 }); ok('token vencido: mensaje claro', r.st === 502 && /token/i.test(r.out.error), r);
  MP.crear = { status: 201, body: { id: ORD, status: 'created' } };
  DB.mp_config[0].activo = false;
  r = await llamar(U_DUENO, { accion: 'cobrar', monto: 5000, clave: 'cccccccc-0000-4000-8000-000000000009' }); ok('con Point apagado no cobra', r.st === 400, r);
  DB.mp_config[0].activo = true;

  // Estado
  MP.orden = { status: 200, body: { id: ORD, status: 'created' } };
  r = await llamar(U_REC, { accion: 'estado', orderId: ORD }); ok('estado: esperando', r.out.estado === 'esperando', r);
  MP.orden.body = { id: ORD, status: 'at_terminal' };
  r = await llamar(U_REC, { accion: 'estado', orderId: ORD }); ok('estado: en terminal', r.out.estado === 'en_terminal', r);
  MP.orden.body = pagoOk();
  r = await llamar(U_REC, { accion: 'estado', orderId: ORD });
  ok('estado: pagado con débito', r.out.estado === 'pagado' && r.out.metodo === 'Débito' && DB.mp_point_ordenes[0].estado === 'pagado' && DB.mp_point_ordenes[0].pagado_at, [r, DB.mp_point_ordenes]);
  MPLOG.length = 0; MP.orden.body = { id: ORD, status: 'refunded' };
  r = await llamar(U_REC, { accion: 'estado', orderId: ORD }); ok('un pago ya confirmado no vuelve a preguntarse a MP', r.out.estado === 'pagado' && !MPLOG.length, [r, MPLOG]);
  DB.mp_point_ordenes[0].estado = 'created'; delete DB.mp_point_ordenes[0].metodo;
  MP.orden.body = pagoOk({ payment_method: { type: 'credit_card' } });
  r = await llamar(U_REC, { accion: 'estado', orderId: ORD }); ok('estado: pagado con crédito', r.out.estado === 'pagado' && r.out.metodo === 'Crédito', r);
  DB.mp_point_ordenes[0].estado = 'created';
  MP.orden.body = pagoOk({ paid_amount: '9000' });
  r = await llamar(U_REC, { accion: 'estado', orderId: ORD }); ok('monto distinto al cobrado: pide revisar, no da por pagado', r.out.estado === 'revisar' && DB.mp_point_ordenes[0].estado !== 'pagado', r);
  for (const [st, esp] of [['canceled', 'cancelado'], ['expired', 'expirado'], ['failed', 'fallido'], ['action_required', 'revisar'], ['algo_nuevo', 'esperando']]) {
    DB.mp_point_ordenes[0].estado = 'created'; MP.orden.body = { id: ORD, status: st };
    r = await llamar(U_REC, { accion: 'estado', orderId: ORD }); ok('estado MP ' + st + ' → ' + esp, r.out.estado === esp, r);
  }
  r = await llamar(U_REC, { accion: 'estado', orderId: 'ORD_DE_OTRO_NEGOCIO_123' }); ok('orden que no es de mi negocio: 404', r.st === 404, r);
  r = await llamar(U_REC, { accion: 'estado', orderId: '../../x' }); ok('orderId con símbolos raros: 400', r.st === 400, r);
  DB.mp_point_ordenes.push({ barberia_id: B2, order_id: 'ORD_NEGOCIO_DOS_0001', external_reference: 'x', monto: 1000, estado: 'created' });
  r = await llamar(U_REC, { accion: 'estado', orderId: 'ORD_NEGOCIO_DOS_0001' }); ok('no se ve la orden de otro negocio', r.st === 404, r);

  // Cancelar
  r = await llamar(U_REC, { accion: 'cancelar', orderId: ORD }); ok('cancelar ok', r.out.cancelado === true && DB.mp_point_ordenes[0].estado === 'cancelado', r);
  MP.cancelar = { status: 409, body: { errors: [{ code: 'cannot_cancel_order' }] } };
  r = await llamar(U_REC, { accion: 'cancelar', orderId: ORD }); ok('cancelar ya en terminal: indica hacerlo en el equipo', r.out.cancelado === false && /terminal/.test(r.out.mensaje), r);
  r = await llamar(U_REC, { accion: 'cancelar', orderId: 'ORD_NEGOCIO_DOS_0001' }); ok('no cancela órdenes de otro negocio', r.st === 404, r);

  // Activar/apagar y desconectar
  r = await llamar(U_DUENO, { accion: 'activo', activo: false }); ok('dueño apaga Point', r.out.activo === false && DB.mp_config[0].activo === false, r);
  r = await llamar(U_PROF, { accion: 'desconectar' }); ok('profesional no desconecta', r.st === 403 && DB.mp_config.length === 1, r);
  r = await llamar(U_DUENO, { accion: 'desconectar' }); ok('dueño desconecta: se borra el token', DB.mp_config.length === 0, DB.mp_config);
  r = await llamar(U_DUENO, { accion: 'terminales' }); ok('sin config no lista terminales', r.st === 400, r);

  // Otra cuenta de MP resetea terminal
  reset(); DB.mp_config.push({ barberia_id: B1, access_token: 'vieja-vieja-vieja-vieja-1', mp_user_id: '111', terminal_id: 'T__1', terminal_nombre: 'x', activo: true });
  r = await llamar(U_DUENO, { accion: 'conectar', token: TOKEN });
  ok('reconectar con OTRA cuenta de MP borra la terminal y apaga', DB.mp_config[0].terminal_id === null && DB.mp_config[0].activo === false && DB.mp_config[0].access_token === TOKEN, DB.mp_config);

  console.log(res.join('\n')); console.log(res.filter(x => x.startsWith('FALLO')).length ? 'HAY FALLOS' : 'TODO OK (' + res.length + ')');
  process.exit(res.some(x => x.startsWith('FALLO')) ? 1 : 0);
})().catch(e => { console.error('ERROR', e); process.exit(1); });
