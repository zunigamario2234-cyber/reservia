// Vercel Serverless Function: POST /api/avisar-modificacion-reserva
// Recibe { reservaId } cuando un cliente del Club modifica una reserva.
//
// NO confía en nada que venga del navegador sobre QUÉ cambió: lee el último
// cambio sin avisar de reserva_cambios (lo escribe la RPC modificar_reserva_club
// en la base) y lo reclama con un PATCH condicional (avisado_at is null), de
// modo que repetir la llamada no manda correos de nuevo.
//
// Avisa a:
//  · el profesional que ahora tiene la cita (qué cambió: antes → ahora),
//  · el profesional anterior, si el cliente cambió de profesional,
//  · el cliente (confirmación del cambio, si dejó correo),
//  · el dueño, solo como respaldo cuando al profesional nuevo no se le pudo avisar.
// Cada envío es independiente: que uno falle no impide los demás.

const { supabaseGet, supabasePatch, enviarEmail, emailShell, negocioParaEmail } = require('./_lib/resend');
const { resolverProfesional, esc, normalizar } = require('./enviar-confirmacion');

const MESES = ['enero','febrero','marzo','abril','mayo','junio','julio','agosto','septiembre','octubre','noviembre','diciembre'];
const DIAS = ['domingo','lunes','martes','miércoles','jueves','viernes','sábado'];
function fechaLarga(f) {
  const d = new Date(String(f) + 'T12:00:00Z');
  if (isNaN(d)) return String(f || '');
  return `${DIAS[d.getUTCDay()]} ${d.getUTCDate()} de ${MESES[d.getUTCMonth()]}`;
}
// Un reintento si Resend falla de forma pasajera.
async function enviarConReintento(datos) {
  try { await enviarEmail(datos); }
  catch (e) { await new Promise(r => setTimeout(r, 1200)); await enviarEmail(datos); }
}
const hhmm = (h) => String(h || '').slice(0, 5);

// Fila "Antes → Ahora" solo para lo que realmente cambió.
function filaCambio(etiqueta, antes, ahora) {
  if (normalizar(antes) === normalizar(ahora)) {
    return `<tr><td style="padding:4px 0;color:#666;font-size:13px;width:110px">${etiqueta}</td><td style="padding:4px 0;font-size:14px;color:#222">${esc(ahora)}</td></tr>`;
  }
  return `<tr><td style="padding:4px 0;color:#666;font-size:13px;width:110px">${etiqueta}</td><td style="padding:4px 0;font-size:14px;color:#222">
    <span style="color:#999;text-decoration:line-through">${esc(antes)}</span><br><strong>${esc(ahora)}</strong></td></tr>`;
}

function tablaCambio(a, n) {
  return `<table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="background:#f4f4f7;border-radius:8px;margin-bottom:20px">
    <tr><td style="padding:14px 20px">
      <table role="presentation" width="100%" cellpadding="0" cellspacing="0">
        ${filaCambio('📅 Día', fechaLarga(a.fecha), fechaLarga(n.fecha))}
        ${filaCambio('🕐 Hora', hhmm(a.hora) + ' hrs', hhmm(n.hora) + ' hrs')}
        ${filaCambio('✂️ Servicio', a.servicio || 'Servicio', n.servicio || 'Servicio')}
        ${filaCambio('👤 Profesional', a.barbero || '—', n.barbero || '—')}
      </table>
    </td></tr></table>`;
}

function contenidoProfesional({ nombreProfesional, reserva, a, n }) {
  return `
    <p style="margin:0 0 12px;font-size:16px;color:#111">Hola ${esc(nombreProfesional)} 👋</p>
    <p style="margin:0 0 16px;font-size:14px;color:#444;line-height:1.6">
      <strong>${esc(reserva.nombre_cliente || 'Un cliente')}</strong> modificó su cita desde el Club. Quedó así:
    </p>
    ${tablaCambio(a, n)}
    ${reserva.whatsapp_cliente ? `<p style="margin:0 0 8px;font-size:13px;color:#555">📱 ${esc(reserva.whatsapp_cliente)}</p>` : ''}
    <p style="margin:0;font-size:12px;color:#999">Puedes ver el detalle completo en Mi Agenda.</p>`;
}

function contenidoProfesionalAnterior({ nombreProfesional, reserva, a, n }) {
  return `
    <p style="margin:0 0 12px;font-size:16px;color:#111">Hola ${esc(nombreProfesional)} 👋</p>
    <p style="margin:0 0 16px;font-size:14px;color:#444;line-height:1.6">
      <strong>${esc(reserva.nombre_cliente || 'Un cliente')}</strong> cambió su cita a otro profesional.
      <strong>Ya no está en tu agenda</strong>: era el ${esc(fechaLarga(a.fecha))} a las ${esc(hhmm(a.hora))} hrs (${esc(a.servicio || 'Servicio')}).
    </p>
    <p style="margin:0;font-size:12px;color:#999">Ahora la atiende ${esc(n.barbero || '—')}.</p>`;
}

function contenidoCliente({ reserva, a, n, nombreNegocio }) {
  return `
    <p style="margin:0 0 12px;font-size:16px;color:#111">Hola ${esc(reserva.nombre_cliente)} 👋</p>
    <p style="margin:0 0 16px;font-size:14px;color:#444;line-height:1.6">Listo, modificamos tu reserva en ${esc(nombreNegocio)}:</p>
    ${tablaCambio(a, n)}
    <p style="margin:0;font-size:12px;color:#999">¡Te esperamos!</p>`;
}

function contenidoDueno({ motivo, barbero, reserva, a, n }) {
  const explicacion = {
    sin_profesional_asignado: 'La reserva no tiene profesional asignado.',
    nombre_no_matchea: `La reserva figura con "${esc(barbero)}", que no coincide con ningún profesional del equipo.`,
    ambiguo: `Hay más de un profesional que coincide con "${esc(barbero)}".`,
    inactivo: `El profesional "${esc(barbero)}" está marcado como inactivo.`,
    sin_email: `El profesional "${esc(barbero)}" no tiene correo cargado en su ficha.`,
    error_envio: `No se pudo entregar el correo al profesional "${esc(barbero)}".`
  }[motivo] || 'No se pudo avisar al profesional.';
  return `
    <p style="margin:0 0 12px;font-size:16px;color:#111">Un cliente modificó su reserva y el profesional no se enteró</p>
    <p style="margin:0 0 16px;font-size:14px;color:#444;line-height:1.6">${explicacion}<br>
      Cliente: <strong>${esc(reserva.nombre_cliente || 'Cliente')}</strong>${reserva.whatsapp_cliente ? ' · ' + esc(reserva.whatsapp_cliente) : ''}</p>
    ${tablaCambio(a, n)}`;
}

module.exports = async function handler(req, res) {
  res.setHeader('Content-Type', 'application/json');
  if (req.method !== 'POST') { res.status(405).json({ ok: false, error: 'Método no permitido' }); return; }
  const { reservaId } = req.body || {};
  if (!reservaId || !/^[0-9a-f-]{36}$/i.test(String(reservaId))) {
    res.status(400).json({ ok: false, error: 'Falta reservaId' }); return;
  }

  try {
    const pendientes = await supabaseGet(
      `reserva_cambios?reserva_id=eq.${encodeURIComponent(reservaId)}&avisado_at=is.null&select=*&order=created_at.desc&limit=1`);
    const cambio = pendientes[0];
    if (!cambio) { res.status(200).json({ ok: true, motivo: 'sin_cambio_pendiente' }); return; }

    // Reclamo atómico: solo una llamada se queda con el aviso.
    const reclamado = await supabasePatch(
      `reserva_cambios?id=eq.${cambio.id}&avisado_at=is.null`, { avisado_at: new Date().toISOString() });
    if (!reclamado.length) { res.status(200).json({ ok: true, motivo: 'ya_avisado' }); return; }

    const reserva = (await supabaseGet(`reservas?id=eq.${encodeURIComponent(reservaId)}&select=*`))[0];
    if (!reserva) { res.status(404).json({ ok: false, error: 'Reserva no encontrada' }); return; }
    const barberia = (await negocioParaEmail(`id=eq.${encodeURIComponent(reserva.barberia_id)}`, 'nombre,email,logo_url'))[0];
    const nombreNegocio = barberia?.nombre || 'tu negocio';
    const logoUrl = barberia?.logo_url;
    const a = cambio.anterior || {}, n = cambio.nuevo || {};
    const shell = (contenidoHtml) => emailShell({ nombreNegocio, logoUrl, contenidoHtml, negocio: barberia });

    const barberos = await supabaseGet(`barberos?barberia_id=eq.${encodeURIComponent(reserva.barberia_id)}&select=nombre,email,activo`);
    const out = { profesional: { sent: false }, anterior: { sent: false }, cliente: { sent: false }, dueno: { sent: false } };

    // Profesional que ahora tiene la cita.
    const rNuevo = resolverProfesional(barberos, n.barbero);
    out.profesional.motivo = rNuevo.motivo;
    if (rNuevo.motivo === 'ok') {
      try {
        await enviarConReintento({
          to: rNuevo.profesional.email,
          subject: `Una cita fue modificada — ${nombreNegocio}`,
          html: shell(contenidoProfesional({ nombreProfesional: rNuevo.profesional.nombre, reserva, a, n }))
        });
        out.profesional.sent = true;
      } catch (e) { out.profesional.motivo = 'error_envio'; out.profesional.error = e.message; }
    }

    // Profesional anterior, si cambió de persona.
    if (normalizar(a.barbero) !== normalizar(n.barbero)) {
      const rAnt = resolverProfesional(barberos, a.barbero);
      out.anterior.motivo = rAnt.motivo;
      if (rAnt.motivo === 'ok') {
        try {
          await enviarConReintento({
            to: rAnt.profesional.email,
            subject: `Una cita ya no está en tu agenda — ${nombreNegocio}`,
            html: shell(contenidoProfesionalAnterior({ nombreProfesional: rAnt.profesional.nombre, reserva, a, n }))
          });
          out.anterior.sent = true;
        } catch (e) { out.anterior.motivo = 'error_envio'; out.anterior.error = e.message; }
      }
    }

    // Cliente.
    if (reserva.email_cliente) {
      try {
        await enviarConReintento({
          to: reserva.email_cliente,
          subject: `Modificamos tu reserva en ${nombreNegocio}`,
          html: shell(contenidoCliente({ reserva, a, n, nombreNegocio }))
        });
        out.cliente.sent = true;
      } catch (e) { out.cliente.motivo = 'error_envio'; out.cliente.error = e.message; }
    } else { out.cliente.motivo = 'sin_email'; }

    // Respaldo al dueño: solo si el profesional nuevo no recibió el aviso.
    const mismoDestino = rNuevo.profesional?.email && normalizar(rNuevo.profesional.email) === normalizar(barberia?.email);
    if (!out.profesional.sent && barberia?.email && !mismoDestino) {
      try {
        await enviarConReintento({
          to: barberia.email,
          subject: `Reserva modificada sin avisar al profesional — ${nombreNegocio}`,
          html: shell(contenidoDueno({ motivo: out.profesional.motivo, barbero: n.barbero, reserva, a, n }))
        });
        out.dueno.sent = true;
      } catch (e) { out.dueno.motivo = 'error_envio'; out.dueno.error = e.message; }
    }

    if (!out.profesional.sent) console.error('avisar-modificacion: profesional sin aviso', JSON.stringify(out));
    try { await supabasePatch(`reserva_cambios?id=eq.${cambio.id}`, { aviso_resultado: out }); } catch (_) {}
    res.status(200).json({ ok: true, ...out });
  } catch (e) {
    res.status(500).json({ ok: false, error: e.message || 'Error interno' });
  }
};
