// Vercel Serverless Function: POST /api/solicitar-plan-pro
//
// Recibe la solicitud del plan Pro (desde la landing o al registrarse), la
// guarda en solicitudes_plan y le avisa por correo al equipo de Reservia, que
// responde con los datos de transferencia. No cobra ni activa nada.
//
// ⚠ ES UN ENDPOINT PÚBLICO: lo llama el navegador de cualquiera, sin sesión.
//  - Valida y recorta todo lo que llega. Nada del body se confía.
//  - NO le manda ningún correo al solicitante: si lo hiciera, cualquiera podría
//    usar este endpoint para enviar correos a direcciones ajenas. El único
//    correo sale hacia SOLICITUDES_EMAIL (variable de entorno, no está en el repo).
//  - Trampa «web» (campo oculto): un bot que la llena recibe un OK y no pasa nada.
//  - Tope por hora y deduplicación por correo, para que no se pueda inundar el buzón.
//  - barberiaId (si viene del registro) se guarda como dato sin verificar: sirve
//    para activar rápido, pero no autoriza nada.

const { supabaseGet, supabasePost, enviarEmail, emailShell, escaparHtml } = require('./_lib/resend');

const MAX_POR_HORA = 30;
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

function texto(v, max) {
  return (v == null ? '' : String(v)).replace(/[\u0000-\u001f\u007f]+/g, ' ').trim().slice(0, max);
}

function limpiar(body) {
  const b = body || {};
  return {
    web: texto(b.web, 50),
    nombre: texto(b.nombre, 80),
    negocio: texto(b.negocio, 100),
    email: texto(b.email, 120).toLowerCase(),
    whatsapp: texto(b.whatsapp, 20),
    profesionales: texto(b.profesionales, 20),
    mensaje: texto(b.mensaje, 500),
    origen: ['landing', 'registro'].includes(b.origen) ? b.origen : 'landing',
    barberia_id: UUID.test(String(b.barberiaId || '')) ? String(b.barberiaId) : null
  };
}

function error(d) {
  if (d.nombre.length < 2) return 'Escribe tu nombre.';
  if (d.negocio.length < 2) return 'Escribe el nombre del negocio.';
  if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(d.email)) return 'Revisa el correo.';
  if (d.whatsapp.replace(/\D/g, '').length < 8) return 'Revisa el número de WhatsApp.';
  return null;
}

function contenido(d) {
  const fila = (k, v) => `<tr><td style="padding:6px 0;color:#666;font-size:13px;width:120px;vertical-align:top">${k}</td>` +
    `<td style="padding:6px 0;color:#111;font-size:14px">${v}</td></tr>`;
  const wa = d.whatsapp.replace(/\D/g, '');
  return `
    <p style="margin:0 0 14px;font-size:16px;color:#111">Alguien pidió el plan Pro</p>
    <table role="presentation" cellpadding="0" cellspacing="0" width="100%">
      ${fila('Nombre', escaparHtml(d.nombre))}
      ${fila('Negocio', escaparHtml(d.negocio))}
      ${fila('Correo', escaparHtml(d.email))}
      ${fila('WhatsApp', `<a href="https://wa.me/${escaparHtml(wa)}">${escaparHtml(d.whatsapp)}</a>`)}
      ${d.profesionales ? fila('Profesionales', escaparHtml(d.profesionales)) : ''}
      ${d.mensaje ? fila('Mensaje', escaparHtml(d.mensaje)) : ''}
      ${fila('Origen', d.origen === 'registro' ? 'Al crear su cuenta' : 'Landing')}
      ${d.barberia_id ? fila('Negocio (id)', escaparHtml(d.barberia_id)) : ''}
    </table>
    <p style="margin:18px 0 0;font-size:13px;color:#666;line-height:1.6">
      Responde a este correo para escribirle: va directo a ${escaparHtml(d.email)}.
      Cuando llegue la transferencia, activa su plan${d.barberia_id ? ' con el id de arriba' : ''}.
    </p>`;
}

module.exports = async function handler(req, res) {
  res.setHeader('Content-Type', 'application/json');
  if (req.method !== 'POST') { res.status(405).json({ ok: false, error: 'Método no permitido' }); return; }

  const d = limpiar(req.body);
  // Trampa: responde como si hubiera funcionado y no hace nada.
  if (d.web) { res.status(200).json({ ok: true }); return; }
  const malo = error(d);
  if (malo) { res.status(400).json({ ok: false, error: malo }); return; }

  try {
    const hace1h = new Date(Date.now() - 3600 * 1000).toISOString();
    const recientes = await supabaseGet(`solicitudes_plan?select=id,email&created_at=gte.${encodeURIComponent(hace1h)}&limit=${MAX_POR_HORA + 1}`);
    if (recientes.length > MAX_POR_HORA) {
      res.status(429).json({ ok: false, error: 'Hay muchas solicitudes ahora. Inténtalo en un rato.' });
      return;
    }
    // La misma persona que insiste: se acepta, pero no se vuelve a avisar.
    if (recientes.some(r => (r.email || '').toLowerCase() === d.email)) {
      res.status(200).json({ ok: true, repetida: true });
      return;
    }

    const { web, ...fila } = d;
    await supabasePost('solicitudes_plan', fila);

    // El aviso por correo es lo que activa el trabajo manual. Si falla, la
    // solicitud ya quedó guardada: se responde OK y el fallo queda en los logs.
    const destino = process.env.SOLICITUDES_EMAIL;
    if (!destino) {
      console.error('SOLICITUDES_EMAIL no está definida: la solicitud se guardó pero no se envió el aviso.');
    } else {
      try {
        await enviarEmail({
          to: destino,
          replyTo: d.email,
          subject: `Plan Pro: ${d.negocio}`,
          html: emailShell({ nombreNegocio: 'Reservia · Solicitud de plan Pro', contenidoHtml: contenido(d) })
        });
      } catch (e) {
        console.error('Solicitud guardada pero el correo falló:', e.message);
      }
    }
    res.status(200).json({ ok: true });
  } catch (e) {
    console.error('solicitar-plan-pro:', e.message);
    res.status(500).json({ ok: false, error: 'No pudimos enviar la solicitud. Inténtalo de nuevo.' });
  }
};
module.exports._limpiar = limpiar;
