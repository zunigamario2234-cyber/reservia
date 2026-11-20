// Reparto de un cobro en boletas. Puro: sin red ni base, se prueba aparte.
//
// Entra lo que la base ya tiene registrado del cobro (visitas y productos) y la
// configuración del negocio; sale la lista de boletas a pedir. Nunca inventa
// montos: todo sale de `valor` (bruto con IVA, ya descontado, SIN propina) y
// de `comision_monto`, que la RPC de cobro dejó congelados.
//
// La propina no va en ninguna boleta (decisión del dueño, ver reservia.md del
// módulo financiero): `valor` ya viene sin ella.

const DETALLE_MAX = 80;

// Lo que le corresponde al profesional, en BRUTO, de una visita.
// comision_monto se calcula sobre el neto cuando modo_comision = 'neto_iva'
// (ver mi_agenda_procesar_pago): para repartir lo que pagó el cliente hay que
// llevarla a bruto. Con 'total' ya está sobre el bruto.
function parteProfesional(visita, negocio) {
  const valor = Math.max(0, Math.round(Number(visita.valor) || 0));
  const com = Math.max(0, Number(visita.comision_monto) || 0);
  const iva = Number(negocio.iva_pct ?? 19);
  const bruto = negocio.modo_comision === 'neto_iva' ? Math.round(com * (100 + iva) / 100) : Math.round(com);
  return Math.min(valor, bruto);
}

function medioPago(metodo) {
  const m = String(metodo || '').toLowerCase();
  if (!m) return null;
  if (m.includes('efectivo')) return 'EFECTIVO';
  if (m.includes('transfer')) return 'TRANSFERENCIA';
  if (/d[eé]bito|cr[eé]dito|tarjeta|point|getnet|pos|electr/.test(m)) return 'PAGO_ELECTRONICO';
  if (m.includes('cheque')) return 'CHEQUE';
  return 'OTRO';
}

function detalleDe(textos) {
  const unicos = [...new Set(textos.map(t => String(t || '').trim()).filter(Boolean))];
  const s = unicos.join(', ') || 'Servicios';
  return s.length > DETALLE_MAX ? s.slice(0, DETALLE_MAX - 1) + '…' : s;
}

// origen: { tipo: 'cobro' | 'visita', id }
// negocio: fila de barberias (boletas_*, modo_comision, iva_pct)
// barberos: filas de barberos del negocio (id, nombre, boletas_emisor_ref, boletas_tipo_dte)
// visitas, productos: lo registrado en ese cobro
function repartir({ origen, negocio, barberos, visitas, productos }) {
  const vivas = (visitas || []).filter(v => v && v.estado !== 'Cancelada');
  const prods = productos || [];
  const tipoLocal = Number(negocio.boletas_tipo_dte) || 39;
  const porId = new Map((barberos || []).map(b => [b.id, b]));
  const ref = `${origen.tipo}:${origen.id}`;

  const local = { monto: 0, textos: [] };
  const profes = new Map(); // barbero_id -> { monto, textos, barbero }

  for (const v of vivas) {
    const valor = Math.max(0, Math.round(Number(v.valor) || 0));
    if (!valor) continue;
    const b = v.barbero_id ? porId.get(v.barbero_id) : null;
    const emite = negocio.boletas_modo === 'dos' && b && String(b.boletas_emisor_ref || '').trim();
    if (!emite) { local.monto += valor; local.textos.push(v.servicio); continue; }
    const parte = parteProfesional(v, negocio);
    if (parte > 0) {
      const p = profes.get(b.id) || { monto: 0, textos: [], barbero: b };
      p.monto += parte; p.textos.push(v.servicio);
      profes.set(b.id, p);
    }
    if (valor - parte > 0) { local.monto += valor - parte; local.textos.push(v.servicio); }
  }
  for (const p of prods) {
    const valor = Math.max(0, Math.round(Number(p.valor) || 0));
    if (!valor) continue;
    local.monto += valor; local.textos.push(p.nombre || 'Productos');
  }

  const medio = medioPago((vivas[0] && vivas[0].metodo_pago) || (prods[0] && prods[0].metodo_pago));
  const salida = [];
  for (const [id, p] of profes) {
    const tipo = Number(p.barbero.boletas_tipo_dte) || tipoLocal;
    salida.push({
      emisor: 'profesional', barbero_id: id, emisor_ref: String(p.barbero.boletas_emisor_ref).trim(),
      tipo_dte: tipo, monto_total: p.monto, detalle: detalleDe(p.textos), medio_pago: medio,
      llave: `${ref}|profesional|${id}|${tipo}`
    });
  }
  if (local.monto > 0) {
    salida.unshift({
      emisor: 'local', barbero_id: null, emisor_ref: negocio.boletas_emisor_ref ? String(negocio.boletas_emisor_ref).trim() : null,
      tipo_dte: tipoLocal, monto_total: local.monto, detalle: detalleDe(local.textos), medio_pago: medio,
      llave: `${ref}|local|-|${tipoLocal}`
    });
  }
  return salida;
}

module.exports = { repartir, parteProfesional, medioPago, detalleDe };
