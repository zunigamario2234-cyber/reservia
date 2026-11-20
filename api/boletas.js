// Vercel Serverless Function: POST /api/boletas
//
// Boletas electrónicas automáticas al cobrar. Una sola función con varias
// acciones (para no gastar funciones del plan de Vercel):
//   emitir      → pide las boletas de un cobro          (quien cobra; lo llama el panel / Mi Agenda)
//   reintentar  → reintenta las pendientes del negocio  (dueño o recepción; lo llama la pantalla Impuestos)
//   cron        → reintenta las pendientes de todos     (Supabase pg_cron, con X-Cron-Secret)
//   webhook     → Boleteados avisa un cambio de estado   (firmado con HMAC)
//
// EL PROVEEDOR ES INTERCAMBIABLE
// Qué proveedor emite lo dice barberias.boletas_proveedor ('ninguno',
// 'simulado', 'emisso', 'boleteados'). Cada boleta guarda con qué proveedor se
// pidió, así que cambiar de proveedor no deja colgadas las que van en camino.
//
// NUNCA BLOQUEA EL COBRO
// El navegador llama esto SIN await, después de que el cobro ya quedó
// registrado. Si el proveedor o el SII fallan, la boleta queda en la tabla con
// estado 'error' o 'desconocido' y se reintenta sola.
//
// NUNCA DOS VECES LA MISMA BOLETA
//  - Cada boleta tiene una `llave` única por negocio (cobro + emisor + tipo):
//    pedir dos veces el mismo cobro no crea filas nuevas.
//  - Antes de llamar al proveedor la fila se "toma" con un PATCH condicional
//    (estado → 'enviando'): dos llamadas simultáneas no la mandan dos veces.
//  - Su idem_key va como Idempotency-Key: si el proveedor la recibe dos veces,
//    emite una.
//
// SEGURIDAD
//  - Quién llama se verifica con el JWT de la sesión. El negocio sale del
//    perfil de ese usuario, nunca del body.
//  - Las claves de los proveedores viven solo en variables de entorno.

const crypto = require('crypto');
const { SUPABASE_URL, supabaseGet, supabasePatch, enviarEmail, emailShell, escaparHtml, negocioParaEmail } = require('./_lib/resend');
const { repartir } = require('./_lib/boletas/reparto');
const { proveedor } = require('./_lib/boletas/proveedores');

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const REINTENTABLES = ['pendiente', 'error', 'desconocido', 'en_proceso'];
const ESPERA_MIN = [1, 5, 15, 60, 180, 720];
const MAX_INTENTOS = 12;
const CAMPOS_NEGOCIO = 'id,nombre,boletas_proveedor,boletas_modo,boletas_tipo_dte,boletas_emisor_ref,boletas_enviar_correo,modo_comision,iva_pct';
const CAMPOS_BOLETA = 'id,barberia_id,cobro_id,visita_id,origen,emisor,barbero_id,emisor_ref,proveedor,tipo_dte,monto_total,detalle,medio_pago,cliente_nombre,cliente_correo,llave,idem_key,estado,folio,pdf_url,proveedor_ref,error,intentos,correo_enviado_at';

class Falla extends Error { constructor(codigo, mensaje) { super(mensaje); this.codigo = codigo; } }

// ── Base ─────────────────────────────────────────────────────────────────────
// Inserta ignorando las que ya existen (misma llave): eso es lo que hace que
// pedir dos veces el mismo cobro sea inofensivo.
async function insertarBoletas(filas) {
  if (!filas.length) return;
  const key = process.env.SUPABASE_SERVICE_ROLE_KEY;
  const r = await fetch(`${SUPABASE_URL}/rest/v1/boletas?on_conflict=barberia_id,llave`, {
    method: 'POST',
    headers: { apikey: key, Authorization: `Bearer ${key}`, 'Content-Type': 'application/json', Prefer: 'resolution=ignore-duplicates,return=minimal' },
    body: JSON.stringify(filas)
  });
  if (!r.ok) throw new Error(`Supabase POST boletas respondió ${r.status}`);
}

function ahoraIso() { return new Date().toISOString(); }
function enMinutos(min) { return new Date(Date.now() + min * 60000).toISOString(); }

// ── Sesión y permisos (mismo criterio que /api/mp-point) ─────────────────────
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

async function negocioDe(id) {
  const f = await supabaseGet(`barberias?id=eq.${id}&select=${CAMPOS_NEGOCIO}`);
  return f[0] || null;
}

// ── Procesar una boleta ──────────────────────────────────────────────────────
async function procesar(fila) {
  const prov = proveedor(fila.proveedor);
  const anterior = fila.estado;
  // Tomarla: solo si sigue en un estado reintentable. Si otra llamada ya la
  // tomó, el PATCH no devuelve filas y esta la deja tranquila.
  const tomadas = await supabasePatch(
    `boletas?id=eq.${fila.id}&estado=in.(${REINTENTABLES.join(',')})&select=${CAMPOS_BOLETA}`,
    { estado: 'enviando', intentos: (fila.intentos || 0) + 1, updated_at: ahoraIso() }
  );
  const b = tomadas && tomadas[0];
  if (!b) return fila;

  let r;
  if (!prov) r = { estado: 'rechazada', error: `Proveedor desconocido: ${fila.proveedor}` };
  else {
    try {
      // Sin respuesta segura del intento anterior: se consulta (o se reemite
      // con la misma Idempotency-Key, que es lo mismo para el proveedor).
      r = (anterior === 'desconocido' || anterior === 'en_proceso') ? await prov.consultar({ ...b, estado: anterior }) : await prov.emitir(b);
    } catch (e) {
      r = { estado: 'desconocido', error: 'Falla inesperada al llamar al proveedor.' };
    }
  }

  const intentos = b.intentos;
  const cambio = { estado: r.estado, updated_at: ahoraIso(), error: r.error ? String(r.error).slice(0, 300) : null };
  if (r.folio) cambio.folio = r.folio;
  if (r.pdf_url) cambio.pdf_url = r.pdf_url;
  if (r.proveedor_ref) cambio.proveedor_ref = r.proveedor_ref;
  if (r.estado === 'error' || r.estado === 'desconocido' || r.estado === 'en_proceso') {
    const espera = r.estado === 'en_proceso' ? Math.min(60, 2 * intentos) : ESPERA_MIN[Math.min(intentos - 1, ESPERA_MIN.length - 1)];
    cambio.proximo_intento = intentos >= MAX_INTENTOS ? enMinutos(24 * 60) : enMinutos(espera);
  }
  const guardadas = await supabasePatch(`boletas?id=eq.${b.id}&select=${CAMPOS_BOLETA}`, cambio);
  return (guardadas && guardadas[0]) || { ...b, ...cambio };
}

// ── Correo al cliente ────────────────────────────────────────────────────────
// Uno por cobro, cuando todas sus boletas terminaron y al menos una salió.
async function quizasEnviarCorreo(barberiaId, filtroOrigen, negocio) {
  if (!negocio || negocio.boletas_enviar_correo === false) return false;
  const filas = await supabaseGet(`boletas?barberia_id=eq.${barberiaId}&${filtroOrigen}&select=${CAMPOS_BOLETA}&order=created_at`);
  if (!filas.length) return false;
  if (filas.some(f => f.correo_enviado_at)) return false;
  if (filas.some(f => f.estado !== 'emitida' && f.estado !== 'rechazada')) return false;
  const emitidas = filas.filter(f => f.estado === 'emitida');
  const correo = (filas.find(f => f.cliente_correo) || {}).cliente_correo;
  if (!emitidas.length || !correo || !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(correo)) return false;

  const nombres = {};
  const ids = [...new Set(emitidas.map(f => f.barbero_id).filter(Boolean))];
  if (ids.length) (await supabaseGet(`barberos?id=in.(${ids.join(',')})&select=id,nombre`)).forEach(b => { nombres[b.id] = b.nombre; });
  const fmt = n => '$' + Math.round(n).toLocaleString('es-CL');
  const filasHtml = emitidas.map(f => {
    const emisor = f.emisor === 'profesional' ? (nombres[f.barbero_id] || 'Profesional') : negocio.nombre;
    const pdf = f.pdf_url && /^https?:\/\//i.test(f.pdf_url) ? ` · <a href="${escaparHtml(f.pdf_url)}" style="color:#444">Ver PDF</a>` : '';
    return `<tr><td style="padding:8px 0;border-bottom:1px solid #eee;font-size:14px;color:#111">${escaparHtml(emisor)}<br><span style="font-size:12px;color:#666">Boleta ${f.tipo_dte === 41 ? 'exenta' : 'electrónica'} · folio ${escaparHtml(f.folio || '—')}${pdf}</span></td><td style="padding:8px 0;border-bottom:1px solid #eee;font-size:14px;text-align:right;color:#111">${fmt(f.monto_total)}</td></tr>`;
  }).join('');
  const cliente = (filas.find(f => f.cliente_nombre) || {}).cliente_nombre;
  const contenido = `
    <p style="margin:0 0 12px;font-size:16px;color:#111">Hola${cliente ? ' ' + escaparHtml(cliente) : ''},</p>
    <p style="margin:0 0 16px;font-size:14px;color:#444;line-height:1.6">Gracias por tu visita. Aquí ${emitidas.length > 1 ? 'van tus boletas' : 'va tu boleta'} por la atención de hoy.</p>
    <table role="presentation" width="100%" cellpadding="0" cellspacing="0">${filasHtml}</table>
    <p style="margin:16px 0 0;font-size:12px;color:#888">Puedes verificar tus boletas en el sitio del SII o en el enlace de cada PDF.</p>`;
  let neg = null;
  try { neg = (await negocioParaEmail(`id=eq.${barberiaId}`, 'nombre,logo_url'))[0]; } catch (e) { neg = null; }
  await enviarEmail({
    to: correo,
    subject: `${emitidas.length > 1 ? 'Tus boletas' : 'Tu boleta'} de ${negocio.nombre}`,
    html: emailShell({ nombreNegocio: negocio.nombre, contenidoHtml: contenido, logoUrl: neg && neg.logo_url, negocio: neg })
  });
  await supabasePatch(`boletas?id=in.(${filas.map(f => f.id).join(',')})`, { correo_enviado_at: ahoraIso() });
  return true;
}

function filtroDeOrigen(f) { return f.cobro_id ? `cobro_id=eq.${f.cobro_id}` : `visita_id=eq.${f.visita_id}`; }

async function procesarLote(filas) {
  const negocios = new Map();
  const salida = [];
  const origenes = new Map();
  for (const f of filas) {
    const r = await procesar(f);
    salida.push(r);
    origenes.set(`${f.barberia_id}|${filtroDeOrigen(f)}`, f);
  }
  for (const f of origenes.values()) {
    try {
      if (!negocios.has(f.barberia_id)) negocios.set(f.barberia_id, await negocioDe(f.barberia_id));
      await quizasEnviarCorreo(f.barberia_id, filtroDeOrigen(f), negocios.get(f.barberia_id));
    } catch (e) {
      console.error('boletas correo:', String(e.message).slice(0, 200));
    }
  }
  return salida;
}

// Las que quedaron 'enviando' (la función murió a mitad) se tratan como
// 'desconocido': se reintentan con la misma Idempotency-Key.
async function rescatarColgadas(filtroNegocio) {
  const hace = new Date(Date.now() - 10 * 60000).toISOString();
  await supabasePatch(`boletas?estado=eq.enviando&updated_at=lt.${hace}${filtroNegocio}`, { estado: 'desconocido', updated_at: ahoraIso() });
}

async function pendientes(filtroNegocio, limite) {
  await rescatarColgadas(filtroNegocio);
  return supabaseGet(`boletas?estado=in.(${REINTENTABLES.join(',')})&proximo_intento=lte.${ahoraIso()}${filtroNegocio}&select=${CAMPOS_BOLETA}&order=proximo_intento&limit=${limite}`);
}

const vista = f => ({ id: f.id, emisor: f.emisor, barbero_id: f.barbero_id, tipo_dte: f.tipo_dte, monto_total: f.monto_total, estado: f.estado, folio: f.folio || null, pdf_url: f.pdf_url || null, error: f.error || null });

// ── Acciones ─────────────────────────────────────────────────────────────────
const acciones = {
  async emitir(u, body) {
    if (!(await puedeCobrar(u))) throw new Falla(403, 'No tienes permiso para cobrar.');
    const cobroId = body.cobroId, visitaId = body.visitaId;
    if (!(cobroId && UUID.test(cobroId)) && !(visitaId && UUID.test(visitaId))) throw new Falla(400, 'Falta el cobro.');
    const negocio = await negocioDe(u.barberia_id);
    if (!negocio) throw new Falla(404, 'Negocio no encontrado.');
    if (!negocio.boletas_proveedor || negocio.boletas_proveedor === 'ninguno') return { omitido: true, boletas: [] };

    const campos = 'id,valor,comision_monto,barbero_id,barbero_nombre,servicio,metodo_pago,cliente_id,estado,fecha';
    const visitas = cobroId
      ? await supabaseGet(`visitas?cobro_id=eq.${cobroId}&barberia_id=eq.${u.barberia_id}&select=${campos}`)
      : await supabaseGet(`visitas?id=eq.${visitaId}&barberia_id=eq.${u.barberia_id}&select=${campos}`);
    const productos = cobroId
      ? await supabaseGet(`cobro_productos?cobro_id=eq.${cobroId}&barberia_id=eq.${u.barberia_id}&select=valor,cantidad,barbero_nombre`)
      : [];
    if (!visitas.length && !productos.length) throw new Falla(404, 'No encontramos ese cobro en tu negocio.');
    const barberos = await supabaseGet(`barberos?barberia_id=eq.${u.barberia_id}&select=id,nombre,boletas_emisor_ref,boletas_tipo_dte`);

    const origen = cobroId ? { tipo: 'cobro', id: cobroId } : { tipo: 'visita', id: visitaId };
    const specs = repartir({ origen, negocio, barberos, visitas, productos });

    // El cliente del cobro (un cobro conjunto puede ser de varias personas: el
    // correo va al de la primera visita, que es quien pagó en caja).
    let cliente = null;
    const cid = (visitas.find(v => v.cliente_id) || {}).cliente_id;
    if (cid && UUID.test(cid)) cliente = (await supabaseGet(`clientes?id=eq.${cid}&barberia_id=eq.${u.barberia_id}&select=id,nombre,apellido,email`))[0] || null;
    const fecha = (visitas[0] && visitas[0].fecha) || undefined;

    await insertarBoletas(specs.map(s => ({
      barberia_id: u.barberia_id, cobro_id: cobroId || null, visita_id: cobroId ? null : visitaId,
      origen: `${origen.tipo}:${origen.id}`, emisor: s.emisor, barbero_id: s.barbero_id, emisor_ref: s.emisor_ref,
      proveedor: negocio.boletas_proveedor, tipo_dte: s.tipo_dte, monto_total: s.monto_total, detalle: s.detalle,
      medio_pago: s.medio_pago, cliente_id: cliente ? cliente.id : null,
      cliente_nombre: cliente ? [cliente.nombre, cliente.apellido].filter(Boolean).join(' ') : null,
      cliente_correo: cliente && cliente.email ? String(cliente.email).trim() : null,
      llave: s.llave, ...(fecha ? { fecha } : {})
    })));

    const filtro = cobroId ? `cobro_id=eq.${cobroId}` : `visita_id=eq.${visitaId}`;
    const filas = await supabaseGet(`boletas?barberia_id=eq.${u.barberia_id}&${filtro}&select=${CAMPOS_BOLETA}&order=created_at`);
    const porProcesar = filas.filter(f => f.estado === 'pendiente' || f.estado === 'error' || f.estado === 'desconocido');
    const hechas = await procesarLote(porProcesar);
    const porId = new Map(hechas.map(f => [f.id, f]));
    return { boletas: filas.map(f => vista(porId.get(f.id) || f)) };
  },

  async reintentar(u) {
    if (u.rol !== 'dueno' && u.rol !== 'recepcion') throw new Falla(403, 'Solo el dueño o recepción pueden reintentar boletas.');
    const filas = await pendientes(`&barberia_id=eq.${u.barberia_id}`, 10);
    const hechas = await procesarLote(filas);
    return { procesadas: hechas.length, boletas: hechas.map(vista) };
  },

  async cron() {
    const filas = await pendientes('', 25);
    const hechas = await procesarLote(filas);
    return { procesadas: hechas.length };
  },

  async webhook(body, req) {
    const prov = proveedor('boleteados');
    const firma = req.headers && (req.headers['x-boleteados-firma'] || req.headers['X-Boleteados-Firma']);
    if (!prov.firmaValida(firma, body)) throw new Falla(401, 'Firma inválida.');
    const ref = String(body.id || '');
    if (!/^[A-Za-z0-9_-]{4,80}$/.test(ref)) throw new Falla(400, 'Id inválido.');
    const filas = await supabaseGet(`boletas?proveedor=eq.boleteados&proveedor_ref=eq.${encodeURIComponent(ref)}&select=${CAMPOS_BOLETA}`);
    const f = filas[0];
    if (!f) return { ignorado: true };
    if (f.estado === 'emitida' || f.estado === 'rechazada') return { ignorado: true };
    const r = prov.desdeBoleteados(body);
    const cambio = { estado: r.estado === 'desconocido' ? 'en_proceso' : r.estado, updated_at: ahoraIso(), error: r.error || null };
    if (r.folio) cambio.folio = r.folio;
    if (r.pdf_url) cambio.pdf_url = r.pdf_url;
    if (cambio.estado === 'en_proceso') cambio.proximo_intento = enMinutos(5);
    await supabasePatch(`boletas?id=eq.${f.id}`, cambio);
    try { await quizasEnviarCorreo(f.barberia_id, filtroDeOrigen(f), await negocioDe(f.barberia_id)); } catch (e) {
      console.error('boletas correo:', String(e.message).slice(0, 200));
    }
    return { actualizado: true };
  }
};

function secretoIgual(a, b) {
  const x = Buffer.from(String(a || '')), y = Buffer.from(String(b || ''));
  return x.length > 0 && x.length === y.length && crypto.timingSafeEqual(x, y);
}

module.exports = async function handler(req, res) {
  res.setHeader('Content-Type', 'application/json');
  res.setHeader('Cache-Control', 'no-store');
  if (req.method !== 'POST') { res.status(405).json({ ok: false, error: 'Método no permitido' }); return; }
  const b = req.body && typeof req.body === 'object' ? req.body : {};
  try {
    let out;
    if (b.accion === 'webhook') out = await acciones.webhook(b, req);
    else if (b.accion === 'cron') {
      const h = req.headers && (req.headers['x-cron-secret'] || req.headers['X-Cron-Secret']);
      if (!process.env.BOLETAS_CRON_SECRET || !secretoIgual(h, process.env.BOLETAS_CRON_SECRET)) throw new Falla(401, 'No autorizado.');
      out = await acciones.cron();
    } else if (b.accion === 'emitir' || b.accion === 'reintentar') {
      const u = await usuario(req);
      out = await acciones[b.accion](u, b);
    } else { res.status(400).json({ ok: false, error: 'Acción no válida.' }); return; }
    res.status(200).json({ ok: true, ...out });
  } catch (e) {
    if (e instanceof Falla) { res.status(e.codigo).json({ ok: false, error: e.message }); return; }
    console.error('boletas:', b.accion, String(e.message).slice(0, 200));
    res.status(500).json({ ok: false, error: 'No pudimos completar la operación. Inténtalo de nuevo.' });
  }
};
module.exports._procesar = procesar;
