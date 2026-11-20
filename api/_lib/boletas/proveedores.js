// Proveedores de boletas electrónicas. Todos cumplen la misma forma:
//
//   emitir(boleta)    → resultado
//   consultar(boleta) → resultado   (solo los que responden después: Boleteados)
//
//   resultado = { estado, folio?, pdf_url?, proveedor_ref?, error? }
//   estado:
//     'emitida'     el SII la tiene. Definitivo.
//     'en_proceso'  el proveedor la aceptó y avisará (webhook) o se consulta después.
//     'rechazada'   no se va a emitir así: datos inválidos, emisor no autorizado… Definitivo.
//     'error'       falla pasajera (red, proveedor caído): se reintenta.
//     'desconocido' no sabemos si quedó emitida: se reintenta con la MISMA
//                   Idempotency-Key, que el proveedor reconoce y no duplica.
//
// `boleta` es la fila de la tabla boletas. Su idem_key viaja como
// Idempotency-Key en toda llamada que pueda emitir.
//
// Las claves de API viven solo en variables de entorno de Vercel. Nunca se
// devuelven ni se escriben en logs ni en la tabla.

const crypto = require('crypto');

function textoError(data, status) {
  const e = data && (data.error || data.errors);
  const msg = (e && (e.message || e.code || (Array.isArray(e) && e[0] && (e[0].message || e[0].code)))) ||
              (data && (data.message || data.code)) || '';
  return String(msg || `HTTP ${status}`).slice(0, 300);
}

// 408/409/425/429 y 5xx: vale la pena reintentar. El resto de 4xx: no.
function esPasajero(status) { return status === 408 || status === 409 || status === 425 || status === 429 || status >= 500; }

async function llamar(url, opciones) {
  let r;
  try { r = await fetch(url, opciones); } catch (e) { return { red: true, status: 0, data: null }; }
  let data = null;
  try { data = await r.json(); } catch (e) { data = null; }
  return { red: false, status: r.status, ok: r.ok, data };
}

// ── Simulado: no toca el SII. Para probar el flujo de punta a punta. ─────────
const simulado = {
  nombre: 'simulado',
  async emitir(b) {
    // Folio estable por boleta: reintentar la misma devuelve el mismo folio,
    // igual que un proveedor real con idempotencia.
    const n = parseInt(crypto.createHash('sha256').update(String(b.idem_key)).digest('hex').slice(0, 6), 16) % 90000 + 10000;
    return { estado: 'emitida', folio: 'SIM-' + n, pdf_url: null, proveedor_ref: 'sim-' + b.idem_key };
  },
  async consultar(b) { return { estado: b.estado === 'emitida' ? 'emitida' : 'error', error: 'Simulado sin consulta' }; }
};

// ── Emisso Connect (emite por E-Boleta del SII) ──────────────────────────────
// Documentación: https://connect.emisso.ai/docs/emitir/boletas
// Dos llamadas por boleta: previsualizar (devuelve previewRef, vence a los 15
// min) y emitir con Idempotency-Key. Una boleta = una línea con su total.
// No hay ambiente de pruebas: todo lo que se emite es real.
const emisso = {
  nombre: 'emisso',
  async emitir(b) {
    const key = process.env.EMISSO_API_KEY;
    const base = (process.env.EMISSO_URL || 'https://connect.emisso.ai').replace(/\/$/, '');
    if (!key) return { estado: 'error', error: 'Falta EMISSO_API_KEY en el servidor.' };
    if (!b.emisor_ref) return { estado: 'rechazada', error: 'El emisor no tiene conexión de Emisso configurada.' };
    const headers = {
      Authorization: `Bearer ${key}`,
      'X-Connect-Connection': b.emisor_ref,
      'Content-Type': 'application/json'
    };
    const candidato = { tipoDte: String(b.tipo_dte), montoTotal: b.monto_total };
    if (b.detalle) candidato.detalle = String(b.detalle).slice(0, 80);
    if (b.medio_pago) candidato.medioPagoCodigo = b.medio_pago;

    const pre = await llamar(`${base}/api/v1/tools/sii.boleta.previsualizar/execute`, {
      method: 'POST', headers, body: JSON.stringify({ input: { candidato } })
    });
    if (pre.red) return { estado: 'error', error: 'No pudimos comunicarnos con Emisso.' };
    if (!pre.ok) return { estado: esPasajero(pre.status) ? 'error' : 'rechazada', error: 'Emisso (vista previa): ' + textoError(pre.data, pre.status) };
    const previewRef = pre.data && pre.data.data && pre.data.data.previewRef;
    if (!previewRef) return { estado: 'error', error: 'Emisso no devolvió previewRef.' };

    const em = await llamar(`${base}/api/v1/tools/sii.boleta.emitir/execute`, {
      method: 'POST', headers: { ...headers, 'Idempotency-Key': String(b.idem_key) },
      body: JSON.stringify({ input: { previewRef } })
    });
    // Se cortó la red DESPUÉS de mandar la emisión: no sabemos si quedó.
    if (em.red) return { estado: 'desconocido', error: 'Se perdió la conexión con Emisso al emitir.' };
    if (!em.ok) {
      const t = textoError(em.data, em.status);
      if (/connection_busy/.test(t) || esPasajero(em.status)) return { estado: 'desconocido', error: 'Emisso: ' + t };
      return { estado: 'rechazada', error: 'Emisso: ' + t };
    }
    const r = (em.data && em.data.data && em.data.data.resultado) || {};
    if (r.estado === 'emitida') return { estado: 'emitida', folio: r.folio ? String(r.folio) : null, pdf_url: r.pdfUrl || null, proveedor_ref: r.folio ? `${r.tipoDte || b.tipo_dte}-${r.folio}` : null };
    if (r.estado === 'rechazada') return { estado: 'rechazada', error: 'El SII rechazó la boleta (Emisso).' };
    return { estado: 'desconocido', error: 'Emisso respondió resultado desconocido.' };
  },
  // Emisso responde en la misma llamada; "desconocido" se resuelve volviendo a
  // emitir con la misma Idempotency-Key.
  async consultar(b) { return this.emitir(b); }
};

// ── Boleteados (plataforma propia, solución de mercado) ──────────────────────
// Contrato de la API v1 de Boleteados (la define el mismo proyecto):
//   POST {BOLETEADOS_URL}/v1/boletas      Idempotency-Key: <uuid>
//     { emisor_id, tipo_dte, monto_total, detalle, medio_pago, referencia,
//       receptor: { nombre, correo }, enviar_correo: false }
//   → 201/200 { id, estado: 'en_cola'|'enviada'|'aceptada'|'rechazada', folio?, pdf_url?, error? }
//   GET  {BOLETEADOS_URL}/v1/boletas/{id} → misma forma
// Reservia manda el correo al cliente, por eso enviar_correo: false.
function desdeBoleteados(d) {
  const est = d && d.estado;
  if (est === 'aceptada') return { estado: 'emitida', folio: d.folio ? String(d.folio) : null, pdf_url: d.pdf_url || null, proveedor_ref: d.id || null };
  if (est === 'rechazada') return { estado: 'rechazada', error: String(d.error || 'El SII rechazó la boleta.').slice(0, 300), proveedor_ref: d.id || null };
  if (est === 'en_cola' || est === 'enviada') return { estado: 'en_proceso', proveedor_ref: d.id || null, folio: d.folio ? String(d.folio) : null };
  return { estado: 'desconocido', error: 'Respuesta de Boleteados sin estado.', proveedor_ref: (d && d.id) || null };
}

const boleteados = {
  nombre: 'boleteados',
  async emitir(b) {
    const key = process.env.BOLETEADOS_API_KEY;
    const base = (process.env.BOLETEADOS_URL || '').replace(/\/$/, '');
    if (!key || !base) return { estado: 'error', error: 'Faltan BOLETEADOS_URL o BOLETEADOS_API_KEY en el servidor.' };
    if (!b.emisor_ref) return { estado: 'rechazada', error: 'El emisor no tiene id de Boleteados configurado.' };
    const r = await llamar(`${base}/v1/boletas`, {
      method: 'POST',
      headers: { Authorization: `Bearer ${key}`, 'Idempotency-Key': String(b.idem_key), 'Content-Type': 'application/json' },
      body: JSON.stringify({
        emisor_id: b.emisor_ref, tipo_dte: b.tipo_dte, monto_total: b.monto_total,
        detalle: b.detalle || null, medio_pago: b.medio_pago || null, referencia: b.llave,
        receptor: { nombre: b.cliente_nombre || null, correo: b.cliente_correo || null },
        enviar_correo: false
      })
    });
    if (r.red) return { estado: 'desconocido', error: 'Se perdió la conexión con Boleteados.' };
    if (!r.ok) return { estado: esPasajero(r.status) ? 'desconocido' : 'rechazada', error: 'Boleteados: ' + textoError(r.data, r.status) };
    return desdeBoleteados(r.data);
  },
  async consultar(b) {
    if (!b.proveedor_ref) return this.emitir(b);
    const key = process.env.BOLETEADOS_API_KEY;
    const base = (process.env.BOLETEADOS_URL || '').replace(/\/$/, '');
    if (!key || !base) return { estado: 'error', error: 'Faltan BOLETEADOS_URL o BOLETEADOS_API_KEY en el servidor.' };
    const r = await llamar(`${base}/v1/boletas/${encodeURIComponent(b.proveedor_ref)}`, { headers: { Authorization: `Bearer ${key}` } });
    if (r.red || !r.ok) return { estado: b.estado === 'en_proceso' ? 'en_proceso' : 'error', proveedor_ref: b.proveedor_ref, error: 'No pudimos consultar Boleteados.' };
    return desdeBoleteados(r.data);
  },
  // Firma del webhook: X-Boleteados-Firma: t=<unix>,v1=<hex>
  // v1 = HMAC-SHA256(BOLETEADOS_WEBHOOK_SECRET, "<t>.<id>.<estado>.<folio>")
  // Se firma sobre campos y no sobre el cuerpo crudo porque Vercel ya entrega
  // el JSON parseado. Se rechaza si t tiene más de 5 minutos.
  firmaValida(cabecera, cuerpo, ahora = Date.now()) {
    const secreto = process.env.BOLETEADOS_WEBHOOK_SECRET;
    if (!secreto || !cabecera || !cuerpo) return false;
    const m = /t=(\d+),v1=([0-9a-f]{64})/i.exec(String(cabecera));
    if (!m) return false;
    const t = Number(m[1]);
    if (!Number.isFinite(t) || Math.abs(ahora / 1000 - t) > 300) return false;
    const base = `${t}.${cuerpo.id || ''}.${cuerpo.estado || ''}.${cuerpo.folio || ''}`;
    const esperado = crypto.createHmac('sha256', secreto).update(base).digest('hex');
    const a = Buffer.from(esperado, 'hex'), b = Buffer.from(m[2].toLowerCase(), 'hex');
    return a.length === b.length && crypto.timingSafeEqual(a, b);
  },
  desdeBoleteados
};

const PROVEEDORES = { simulado, emisso, boleteados };
function proveedor(nombre) { return Object.prototype.hasOwnProperty.call(PROVEEDORES, nombre) ? PROVEEDORES[nombre] : null; }

module.exports = { proveedor, PROVEEDORES };
