// Vercel Serverless Function: POST /api/enviar-encuesta
// Recibe { visitaId }, busca los datos reales en Supabase (nunca confía en
// texto libre del cliente) y envía por Resend el correo con el link a la
// encuesta de satisfacción. RESEND_API_KEY solo vive en el servidor.

const { supabaseGet, enviarEmail, emailShell } = require('./_lib/resend');

function construirContenido({ nombreCliente, link }) {
  return `
    <p style="margin:0 0 12px;font-size:16px;color:#111">Hola ${nombreCliente || ''} 👋</p>
    <p style="margin:0 0 20px;font-size:14px;color:#444;line-height:1.6">
      ¡Gracias por visitarnos! Nos encantaría saber cómo fue tu experiencia.
      Tu opinión nos ayuda a mejorar.
    </p>
    <table role="presentation" cellpadding="0" cellspacing="0">
      <tr><td style="border-radius:8px;background:linear-gradient(135deg,#7c6af7,#5b8def)">
        <a href="${link}" style="display:inline-block;padding:12px 28px;color:#fff;text-decoration:none;font-size:14px;font-weight:600">Responder encuesta</a>
      </td></tr>
    </table>
    <p style="margin:24px 0 0;font-size:12px;color:#999">Te toma menos de un minuto. ¡Gracias!</p>`;
}

module.exports = async function handler(req, res) {
  res.setHeader('Content-Type', 'application/json');

  if (req.method !== 'POST') {
    res.status(405).json({ ok: false, error: 'Método no permitido' });
    return;
  }

  const { visitaId } = req.body || {};
  if (!visitaId) {
    res.status(400).json({ ok: false, error: 'Falta visitaId' });
    return;
  }

  try {
    const visitas = await supabaseGet(`visitas?id=eq.${encodeURIComponent(visitaId)}&select=*`);
    const visita = visitas[0];
    if (!visita) {
      res.status(404).json({ ok: false, error: 'Visita no encontrada' });
      return;
    }
    if (visita.estado !== 'Atendida') {
      res.status(400).json({ ok: false, error: 'La visita no está marcada como Atendida' });
      return;
    }
    if (!visita.cliente_id) {
      res.status(400).json({ ok: false, error: 'La visita no tiene cliente asociado' });
      return;
    }

    const [clientes, barberias] = await Promise.all([
      supabaseGet(`clientes?id=eq.${encodeURIComponent(visita.cliente_id)}&select=nombre,apellido,email`),
      supabaseGet(`barberias?id=eq.${encodeURIComponent(visita.barberia_id)}&select=nombre`)
    ]);
    const cliente = clientes[0];
    const barberia = barberias[0];

    if (!cliente || !cliente.email) {
      res.status(400).json({ ok: false, error: 'El cliente no tiene correo registrado' });
      return;
    }

    const proto = req.headers['x-forwarded-proto'] || 'https';
    const host = req.headers.host;
    const link = `${proto}://${host}/encuesta.html?visita=${encodeURIComponent(visitaId)}`;

    const html = emailShell({
      nombreNegocio: barberia?.nombre || 'tu negocio',
      contenidoHtml: construirContenido({ nombreCliente: cliente.nombre, link })
    });

    await enviarEmail({
      to: cliente.email,
      subject: `¿Cómo fue tu visita a ${barberia?.nombre || 'nosotros'}?`,
      html
    });

    res.status(200).json({ ok: true });
  } catch (e) {
    res.status(500).json({ ok: false, error: e.message || 'Error interno' });
  }
};
