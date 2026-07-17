// Código compartido entre las funciones serverless que envían correo (Resend).
// Archivos/carpetas que empiezan con "_" dentro de /api no se publican como
// endpoints en Vercel — solo se pueden importar desde otras funciones.

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

async function enviarEmail({ to, subject, html }) {
  if (!process.env.RESEND_API_KEY) {
    throw new Error('RESEND_API_KEY no configurada en el servidor');
  }
  const resendRes = await fetch('https://api.resend.com/emails', {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${process.env.RESEND_API_KEY}`,
      'Content-Type': 'application/json'
    },
    body: JSON.stringify({ from: RESEND_FROM, to: [to], subject, html })
  });
  if (!resendRes.ok) {
    const detalle = await resendRes.text();
    throw new Error(`Resend respondió ${resendRes.status}: ${detalle}`);
  }
}

// Wrapper visual compartido: header con degradado + nombre del negocio + tarjeta blanca.
function emailShell({ nombreNegocio, contenidoHtml }) {
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
          ${contenidoHtml}
        </td></tr>
      </table>
    </td></tr>
  </table>
</body>
</html>`;
}

module.exports = { SUPABASE_URL, SUPABASE_KEY, supabaseGet, enviarEmail, emailShell };
