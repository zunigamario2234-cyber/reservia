// Vercel Serverless Function: POST /api/mp-point
//
// Integración con la terminal Mercado Pago Point. Una sola función con varias
// acciones (para no gastar funciones del plan de Vercel):
//   estado_config  → ¿hay Point conectado/activo en mi negocio?  (cualquiera del negocio)
//   conectar       → guarda el Access Token del negocio           (solo dueño)
//   terminales     → lista las terminales de la cuenta            (solo dueño)
//   elegir_terminal→ elige la terminal, la pasa a modo PDV y activa (solo dueño)
//   activo         → enciende/apaga el cobro con Point            (solo dueño)
//   desconectar    → borra el token                               (solo dueño)
//   cobrar         → manda el monto a la terminal                 (quien cobra)
//   estado         → consulta si el cliente ya pagó               (quien cobra)
//   cancelar       → cancela un cobro que aún no llegó a la terminal
//
// SEGURIDAD
//  - El Access Token de cada negocio vive solo en la tabla mp_config (sin acceso
//    desde el navegador) y NUNCA se devuelve en una respuesta ni se escribe en logs.
//  - Quién llama se verifica con el JWT de la sesión (Authorization: Bearer ...).
//    El negocio sale del perfil de ese usuario, nunca del body: nadie puede cobrar
//    ni mirar las órdenes de otro negocio.
//  - Montos: enteros en pesos, validados acá; no se confía en lo que diga el navegador
//    más allá del monto que el cajero ve en pantalla.

const { SUPABASE_URL, supabaseGet, supabasePatch, supabasePost, supabaseDelete } = require('./_lib/resend');

const MP = 'https://api.mercadopago.com';
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const ORDER_ID = /^[A-Za-z0-9_-]{6,80}$/;
const MONTO_MAX = 10000000;

class Falla extends Error { constructor(codigo, mensaje) { super(mensaje); this.codigo = codigo; } }

// ── Mercado Pago ─────────────────────────────────────────────────────────────
async function mp(token, metodo, ruta, cuerpo, idem) {
  const headers = { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' };
  if (idem) headers['X-Idempotency-Key'] = idem;
  let r;
  try {
    r = await fetch(MP + ruta, { method: metodo, headers, body: cuerpo ? JSON.stringify(cuerpo) : undefined });
  } catch (e) {
    throw new Falla(502, 'No pudimos comunicarnos con Mercado Pago. Revisa la conexión e inténtalo de nuevo.');
  }
  let data = null;
  try { data = await r.json(); } catch (e) { data = null; }
  return { ok: r.ok, status: r.status, data };
}

function errorMp(r) {
  const errs = r.data && Array.isArray(r.data.errors) ? r.data.errors : [];
  const cod = (errs[0] && (errs[0].code || errs[0].message)) || (r.data && (r.data.code || r.data.error || r.data.message)) || '';
  return String(cod);
}

function mensajeMp(r) {
  const cod = errorMp(r);
  if (r.status === 401) return 'Mercado Pago no aceptó el token. Revisa que sea el Access Token de producción y vuelve a conectarlo.';
  if (/already_queued_order_for_terminal/.test(cod)) return 'La terminal ya tiene un cobro pendiente. Termínalo o cancélalo en la terminal y vuelve a intentar.';
  if (/forbidden_checking_terminal_owner/.test(cod) || r.status === 403) return 'Esa terminal no pertenece a la cuenta de Mercado Pago conectada.';
  if (r.status >= 500) return 'Mercado Pago tuvo un problema. Inténtalo de nuevo en unos segundos.';
  return 'Mercado Pago rechazó la operación' + (cod ? ` (${cod.slice(0, 80)})` : '') + '.';
}

// Resumen NO sensible de cómo informó Mercado Pago el pago (nombres de campos y valores
// cortos del medio de pago). Se guarda en el libro para afinar el reconocimiento de
// débito/crédito con datos reales. Nunca incluye números de tarjeta ni titulares.
function formaDelPago(o, pago) {
  const pm = (pago && pago.payment_method && typeof pago.payment_method === 'object') ? pago.payment_method : {};
  const pmSeguro = {};
  Object.keys(pm).forEach(k => {
    const v = pm[k];
    if (/number|holder|token|name|document|email/i.test(k)) return;
    if (typeof v === 'string' && v.length <= 40) pmSeguro[k] = v;
    else if (typeof v === 'number' || typeof v === 'boolean') pmSeguro[k] = v;
  });
  return {
    payment_method: pmSeguro,
    claves_pago: pago ? Object.keys(pago).slice(0, 40) : [],
    claves_orden: o ? Object.keys(o).slice(0, 40) : [],
    status_detail: String((o && o.status_detail) || '').slice(0, 60)
  };
}

// Estados de la orden de Mercado Pago → los que entiende la pantalla de cobro.
function interpretarOrden(o) {
  const pagos = (o && o.transactions && Array.isArray(o.transactions.payments)) ? o.transactions.payments : [];
  const pago = pagos.find(p => p && p.status === 'processed') || pagos[0] || null;
  const st = String((o && o.status) || '').toLowerCase();
  let estado;
  if (st === 'processed' || (pago && pago.status === 'processed')) estado = 'pagado';
  else if (st === 'at_terminal') estado = 'en_terminal';
  else if (st === 'canceled' || st === 'cancelled') estado = 'cancelado';
  else if (st === 'expired') estado = 'expirado';
  else if (st === 'refunded') estado = 'reembolsado';
  else if (st === 'failed' || st === 'rejected') estado = 'fallido';
  else if (st === 'action_required') estado = 'revisar';
  else estado = 'esperando';
  const pm = (pago && pago.payment_method && typeof pago.payment_method === 'object') ? pago.payment_method : {};
  // Se mira el tipo y el id del medio de pago (ej. debit_card / debmaster) y las cuotas:
  // Mercado Pago no siempre informa el tipo con el mismo nombre.
  const pistas = [pm.type, pm.id, pago && pago.payment_type, pago && pago.payment_method_type]
    .map(x => String(x || '').toLowerCase()).join(' ');
  const cuotas = Number(pm.installments || (pago && pago.installments) || 0);
  const metodo = /deb/.test(pistas) ? 'Débito' : (/cred/.test(pistas) || cuotas > 1 ? 'Crédito' : null);
  const pagado = pago && pago.paid_amount != null ? Math.round(Number(pago.paid_amount)) : null;
  return { estado, metodo, pagado, detalle: String((o && o.status_detail) || ''), forma: formaDelPago(o, pago) };
}

// ── Sesión y permisos ────────────────────────────────────────────────────────
async function usuario(req) {
  const h = (req.headers && (req.headers.authorization || req.headers.Authorization)) || '';
  const jwt = /^Bearer\s+(.+)$/i.exec(h);
  if (!jwt) throw new Falla(401, 'Inicia sesión de nuevo.');
  const key = process.env.SUPABASE_SERVICE_ROLE_KEY;
  if (!key) throw new Falla(500, 'El servidor no está configurado.');
  const r = await fetch(`${SUPABASE_URL}/auth/v1/user`, { headers: { apikey: key, Authorization: `Bearer ${jwt[1]}` } });
  if (!r.ok) throw new Falla(401, 'Inicia sesión de nuevo.');
  const u = await r.json();
  if (!u || !UUID.test(String(u.id || ''))) throw new Falla(401, 'Inicia sesión de nuevo.');
  const perfiles = await supabaseGet(`perfiles?id=eq.${u.id}&select=barberia_id,rol`);
  if (!perfiles[0] || !perfiles[0].barberia_id) throw new Falla(403, 'Tu cuenta no tiene un negocio asociado.');
  return { id: u.id, barberia_id: perfiles[0].barberia_id, rol: perfiles[0].rol };
}

async function puedeCobrar(u) {
  if (u.rol === 'dueno' || u.rol === 'recepcion') return true;
  if (u.rol === 'profesional') {
    const b = await supabaseGet(`barberos?auth_user_id=eq.${u.id}&barberia_id=eq.${u.barberia_id}&select=puede_procesar_pagos`);
    return !!(b[0] && b[0].puede_procesar_pagos);
  }
  return false;
}

async function configDe(barberiaId) {
  const f = await supabaseGet(`mp_config?barberia_id=eq.${barberiaId}&select=*`);
  return f[0] || null;
}

function soloDueno(u) { if (u.rol !== 'dueno') throw new Falla(403, 'Solo el dueño puede configurar Mercado Pago.'); }

// ── Acciones ─────────────────────────────────────────────────────────────────
function terminalNombre(id) {
  // "NEWLAND_N950__N950NCB801293324" → "N950 · …3324": modelo y fin del número de serie.
  const partes = String(id).split('__');
  const modelo = (partes[0] || '').replace(/^[A-Z]+_/, '') || 'Point';
  const serie = partes[1] || partes[0];
  return `${modelo} · …${String(serie).slice(-4)}`;
}

function listaTerminales(data) {
  const arr = (data && data.data && data.data.terminals) || (data && data.terminals) || [];
  return arr.filter(t => t && t.id).map(t => ({
    id: String(t.id),
    nombre: terminalNombre(t.id),
    modo: String(t.operating_mode || '').toUpperCase() || null
  }));
}

const acciones = {
  async estado_config(u) {
    const c = await configDe(u.barberia_id);
    if (!c) return { conectado: false, activo: false };
    return {
      conectado: true,
      activo: !!c.activo && !!c.terminal_id,
      terminal_elegida: !!c.terminal_id,
      terminal_nombre: c.terminal_nombre || null,
      token_final: u.rol === 'dueno' ? String(c.access_token).slice(-4) : null
    };
  },

  async conectar(u, b) {
    soloDueno(u);
    const token = String(b.token || '').trim();
    if (token.length < 20 || /\s/.test(token) || token.length > 400) throw new Falla(400, 'Pega el Access Token completo, sin espacios.');
    const r = await mp(token, 'GET', '/users/me');
    if (!r.ok) throw new Falla(400, mensajeMp(r));
    const mpUser = String((r.data && r.data.id) || '');
    const actual = await configDe(u.barberia_id);
    if (actual) {
      // Otra cuenta de Mercado Pago = otra terminal: se pide elegirla de nuevo.
      const cambia = actual.mp_user_id && mpUser && actual.mp_user_id !== mpUser;
      await supabasePatch(`mp_config?barberia_id=eq.${u.barberia_id}`, {
        access_token: token, mp_user_id: mpUser || null, updated_at: new Date().toISOString(),
        ...(cambia ? { terminal_id: null, terminal_nombre: null, activo: false } : {})
      });
    } else {
      await supabasePost('mp_config', { barberia_id: u.barberia_id, access_token: token, mp_user_id: mpUser || null, activo: false });
    }
    return { conectado: true, cuenta: (r.data && (r.data.nickname || r.data.email)) || null, token_final: token.slice(-4) };
  },

  async terminales(u) {
    soloDueno(u);
    const c = await configDe(u.barberia_id);
    if (!c) throw new Falla(400, 'Primero conecta tu cuenta de Mercado Pago.');
    const r = await mp(c.access_token, 'GET', '/terminals/v1/list');
    if (!r.ok) throw new Falla(502, mensajeMp(r));
    return { terminales: listaTerminales(r.data), elegida: c.terminal_id || null };
  },

  async elegir_terminal(u, b) {
    soloDueno(u);
    const c = await configDe(u.barberia_id);
    if (!c) throw new Falla(400, 'Primero conecta tu cuenta de Mercado Pago.');
    const id = String(b.terminalId || '');
    const r = await mp(c.access_token, 'GET', '/terminals/v1/list');
    if (!r.ok) throw new Falla(502, mensajeMp(r));
    const t = listaTerminales(r.data).find(x => x.id === id);
    if (!t) throw new Falla(400, 'Esa terminal no está en tu cuenta de Mercado Pago.');
    // Para recibir órdenes desde Reservia la terminal tiene que estar en modo PDV.
    if (t.modo !== 'PDV') {
      const m = await mp(c.access_token, 'PATCH', '/terminals/v1/setup', { terminals: [{ id, operating_mode: 'PDV' }] });
      if (!m.ok) throw new Falla(502, 'No pudimos pasar la terminal a modo PDV desde aquí. Hazlo desde la app de Mercado Pago (Tu negocio → Point → Modo integrado). ' + mensajeMp(m));
    }
    await supabasePatch(`mp_config?barberia_id=eq.${u.barberia_id}`, {
      terminal_id: id, terminal_nombre: t.nombre, activo: true, updated_at: new Date().toISOString()
    });
    return { terminal_nombre: t.nombre, activo: true, reiniciar: t.modo !== 'PDV' };
  },

  async activo(u, b) {
    soloDueno(u);
    const c = await configDe(u.barberia_id);
    if (!c) throw new Falla(400, 'Primero conecta tu cuenta de Mercado Pago.');
    if (b.activo && !c.terminal_id) throw new Falla(400, 'Elige primero la terminal.');
    await supabasePatch(`mp_config?barberia_id=eq.${u.barberia_id}`, { activo: !!b.activo, updated_at: new Date().toISOString() });
    return { activo: !!b.activo };
  },

  async desconectar(u) {
    soloDueno(u);
    await supabaseDelete(`mp_config?barberia_id=eq.${u.barberia_id}`);
    return { conectado: false };
  },

  async cobrar(u, b) {
    if (!(await puedeCobrar(u))) throw new Falla(403, 'No tienes permiso para cobrar.');
    const monto = Number(b.monto);
    if (!Number.isInteger(monto) || monto < 1 || monto > MONTO_MAX) throw new Falla(400, 'El monto a cobrar no es válido.');
    const clave = String(b.clave || '');
    if (!UUID.test(clave)) throw new Falla(400, 'Falta la clave del cobro.');
    const c = await configDe(u.barberia_id);
    if (!c || !c.activo || !c.terminal_id) throw new Falla(400, 'El cobro con Point no está activo en este negocio.');
    // Mismo clic (misma clave) reintentado: devuelve la orden que ya se creó.
    const previa = await supabaseGet(`mp_point_ordenes?barberia_id=eq.${u.barberia_id}&external_reference=eq.rsv-${clave}&select=order_id,estado,monto`);
    if (previa[0]) return { orderId: previa[0].order_id, estado: 'esperando', monto: previa[0].monto };
    const ref = `rsv-${clave}`;
    const r = await mp(c.access_token, 'POST', '/v1/orders', {
      type: 'point',
      external_reference: ref,
      expiration_time: 'PT15M',
      transactions: { payments: [{ amount: String(monto) }] },
      config: { point: { terminal_id: c.terminal_id, print_on_terminal: 'no_ticket' } },
      description: 'Cobro Reservia'
    }, clave);
    if (!r.ok || !r.data || !r.data.id) throw new Falla(r.status === 409 ? 409 : 502, mensajeMp(r));
    await supabasePost('mp_point_ordenes', {
      barberia_id: u.barberia_id, order_id: String(r.data.id), external_reference: ref,
      monto, estado: 'created', creado_por: u.id
    });
    return { orderId: String(r.data.id), estado: 'esperando', monto };
  },

  async estado(u, b) {
    if (!(await puedeCobrar(u))) throw new Falla(403, 'No tienes permiso para cobrar.');
    const orderId = String(b.orderId || '');
    if (!ORDER_ID.test(orderId)) throw new Falla(400, 'Orden no válida.');
    const f = await supabaseGet(`mp_point_ordenes?barberia_id=eq.${u.barberia_id}&order_id=eq.${orderId}&select=order_id,monto,estado,metodo`);
    if (!f[0]) throw new Falla(404, 'No encontramos ese cobro.');
    if (f[0].estado === 'pagado') return { estado: 'pagado', metodo: f[0].metodo || null, monto: f[0].monto };
    const c = await configDe(u.barberia_id);
    if (!c) throw new Falla(400, 'El cobro con Point no está configurado.');
    const r = await mp(c.access_token, 'GET', `/v1/orders/${orderId}`);
    if (!r.ok) throw new Falla(502, mensajeMp(r));
    const i = interpretarOrden(r.data);
    // Defensa: un "pagado" con otro monto no se acepta como pago de este cobro.
    if (i.estado === 'pagado' && i.pagado != null && i.pagado !== f[0].monto) {
      return { estado: 'revisar', mensaje: `Mercado Pago cobró $${i.pagado} y se esperaba $${f[0].monto}. Revisa el pago en tu cuenta de Mercado Pago.` };
    }
    if (i.estado !== f[0].estado) {
      await supabasePatch(`mp_point_ordenes?order_id=eq.${orderId}`, {
        estado: i.estado, ...(i.metodo ? { metodo: i.metodo } : {}),
        ...(i.estado === 'pagado' ? { pagado_at: new Date().toISOString(), pago_detalle: i.forma } : {})
      });
    }
    return { estado: i.estado, metodo: i.metodo, monto: f[0].monto };
  },

  async cancelar(u, b) {
    if (!(await puedeCobrar(u))) throw new Falla(403, 'No tienes permiso para cobrar.');
    const orderId = String(b.orderId || '');
    if (!ORDER_ID.test(orderId)) throw new Falla(400, 'Orden no válida.');
    const f = await supabaseGet(`mp_point_ordenes?barberia_id=eq.${u.barberia_id}&order_id=eq.${orderId}&select=estado`);
    if (!f[0]) throw new Falla(404, 'No encontramos ese cobro.');
    const c = await configDe(u.barberia_id);
    if (!c) throw new Falla(400, 'El cobro con Point no está configurado.');
    const r = await mp(c.access_token, 'POST', `/v1/orders/${orderId}/cancel`, null, require('crypto').randomUUID());
    if (r.ok) {
      await supabasePatch(`mp_point_ordenes?order_id=eq.${orderId}`, { estado: 'cancelado' });
      return { cancelado: true };
    }
    // Ya la tomó la terminal: solo se puede cancelar desde el equipo.
    return { cancelado: false, mensaje: 'El cobro ya está en la terminal. Cancélalo desde la terminal.' };
  }
};

module.exports = async function handler(req, res) {
  res.setHeader('Content-Type', 'application/json');
  res.setHeader('Cache-Control', 'no-store');
  if (req.method !== 'POST') { res.status(405).json({ ok: false, error: 'Método no permitido' }); return; }
  const b = req.body && typeof req.body === 'object' ? req.body : {};
  const fn = Object.prototype.hasOwnProperty.call(acciones, b.accion) ? acciones[b.accion] : null;
  if (!fn) { res.status(400).json({ ok: false, error: 'Acción no válida.' }); return; }
  try {
    const u = await usuario(req);
    const out = await fn(u, b);
    res.status(200).json({ ok: true, ...out });
  } catch (e) {
    if (e instanceof Falla) { res.status(e.codigo).json({ ok: false, error: e.message }); return; }
    // Sin e.message completo: podría arrastrar datos de la respuesta de Supabase.
    console.error('mp-point:', b.accion, String(e.message).slice(0, 200));
    res.status(500).json({ ok: false, error: 'No pudimos completar la operación. Inténtalo de nuevo.' });
  }
};
module.exports._interpretarOrden = interpretarOrden;
module.exports._terminalNombre = terminalNombre;
