// Vercel Serverless Function: POST /api/enviar-confirmacion
// Recibe { reservaId }, busca los datos reales en Supabase (nunca confía en
// texto libre del cliente) y envía por Resend un email de confirmación de
// reserva. RESEND_API_KEY solo vive en el servidor.

const { supabaseGet, enviarEmail, emailShell } = require('./_lib/resend');

function construirContenido({ nombreCliente, fecha, hora, servicio, profesional }) {
  return `
    <p style="margin:0 0 12px;font-size:16px;color:#111">Hola ${nombreCliente || ''} 👋</p>
    <p style="margin:0 0 20px;font-size:14px;color:#444;line-height:1.6">
      ¡Gracias por reservar con nosotros! Tu cita quedó confirmada:
    </p>
    <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="background:#f4f4f7;border-radius:8px;margin-bottom:20px">
      <tr><td style="padding:16px 20px;font-size:14px;color:#333;line-height:1.9">
        📅 <strong>${fecha}</strong> a las <strong>${hora}</strong> hrs<br>
        ✂️ ${servicio || 'Servicio'}${profesional ? ' con ' + profesional : ''}
      </td></tr>
    </table>
    <p style="margin:0;font-size:12px;color:#999">¡Te esperamos!</p>`;
}

module.exports = async function handler(req, res) {
  res.setHeader('Content-Type', 'application/json');

  if (req.method !== 'POST') {
    res.status(405).json({ ok: false, error: 'Método no permitido' });
    return;
  }

  const { reservaId } = req.body || {};
  if (!reservaId) {
    res.status(400).json({ ok: false, error: 'Falta reservaId' });
    return;
  }

  try {
    const reservas = await supabaseGet(`reservas?id=eq.${encodeURIComponent(reservaId)}&select=*`);
    const reserva = reservas[0];
    if (!reserva) {
      res.status(404).json({ ok: false, error: 'Reserva no encontrada' });
      return;
    }
    if (!reserva.email_cliente) {
      // No hay a quién mandarle el correo: no es un error, simplemente no se envía nada.
      res.status(200).json({ ok: true, sent: false });
      return;
    }

    const barberias = await supabaseGet(`barberias?id=eq.${encodeURIComponent(reserva.barberia_id)}&select=nombre`);
    const barberia = barberias[0];

    const html = emailShell({
      nombreNegocio: barberia?.nombre || 'tu negocio',
      contenidoHtml: construirContenido({
        nombreCliente: reserva.nombre_cliente,
        fecha: reserva.fecha,
        hora: (reserva.hora || '').slice(0, 5),
        servicio: reserva.servicio,
        profesional: reserva.barbero_nombre
      })
    });

    await enviarEmail({
      to: reserva.email_cliente,
      subject: `Reserva confirmada en ${barberia?.nombre || 'nuestro negocio'}`,
      html
    });

    res.status(200).json({ ok: true, sent: true });
  } catch (e) {
    res.status(500).json({ ok: false, error: e.message || 'Error interno' });
  }
};
