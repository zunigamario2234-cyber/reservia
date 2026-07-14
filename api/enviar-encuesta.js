// Vercel Serverless Function: POST /api/enviar-encuesta
// Recibe { visitaId }, busca los datos reales en Supabase (nunca confía en
// texto libre del cliente) y envía por Resend el correo con el link a la
// encuesta de satisfacción. RESEND_API_KEY solo vive en el servidor.

const SUPABASE_URL = 'https://dqoqykngmtxtvbokxbzp.supabase.co';
const SUPABASE_KEY = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImRxb3F5a25nbXR4dHZib2t4YnpwIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODI0MTc1NDEsImV4cCI6MjA5Nzk5MzU0MX0.aLjslOdIod_wsdiHN3O7SRlbsM4hOj3nNQTlNTc_rY4';
const RESEND_FROM = process.env.RESEND_FROM || 'onboarding@resend.dev';

async function supabaseGet(path) {
  const res = await fetch(`${SUPABASE_URL}/rest/v1/${path}`, {
    headers: { apikey: SUPABASE_KEY, Authorization: `Bearer ${SUPABASE_KEY}` }
  });
  if (!res.ok) throw new Error(`Supabase ${path} respondió ${res.status}`);
  return res.json();
}

function construirHtml({ nombreCliente, nombreNegocio, link }) {
  return `<!DOCTYPE html>
<html lang="es">
<body style="margin:0;padding:0;background:#f4f4f7;font-family:system-ui,-apple-system,sans-serif">
  <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="background:#f4f4f7;padding:32px 16px">
    <tr><td align="center">
      <table role="presentation" width="480" cellpadding="0" cellspacing="0" style="background:#ffffff;border-radius:12px;overflow:hidden;max-width:100%">
        <tr><td style="background:linear-gradient(135deg,#7c6af7,#5b8def);padding:28px 32px">
          <span style="color:#fff;font-size:18px;font-weight:700">${nombreNegocio}</span>
        </td></tr>
        <tr><td style="padding:32px">
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
          <p style="margin:24px 0 0;font-size:12px;color:#999">Te toma menos de un minuto. ¡Gracias!</p>
        </td></tr>
      </table>
    </td></tr>
  </table>
</body>
</html>`;
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

  if (!process.env.RESEND_API_KEY) {
    res.status(500).json({ ok: false, error: 'RESEND_API_KEY no configurada en el servidor' });
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

    const html = construirHtml({
      nombreCliente: cliente.nombre,
      nombreNegocio: barberia?.nombre || 'tu negocio',
      link
    });

    const resendRes = await fetch('https://api.resend.com/emails', {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${process.env.RESEND_API_KEY}`,
        'Content-Type': 'application/json'
      },
      body: JSON.stringify({
        from: RESEND_FROM,
        to: [cliente.email],
        subject: `¿Cómo fue tu visita a ${barberia?.nombre || 'nosotros'}?`,
        html
      })
    });

    if (!resendRes.ok) {
      const detalle = await resendRes.text();
      res.status(502).json({ ok: false, error: `Resend respondió ${resendRes.status}: ${detalle}` });
      return;
    }

    res.status(200).json({ ok: true });
  } catch (e) {
    res.status(500).json({ ok: false, error: e.message || 'Error interno' });
  }
};
