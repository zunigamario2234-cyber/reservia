// Vercel Serverless Function: POST /api/avisar-encuesta-mala
//
// Le avisa por correo al DUEÑO cuando un cliente respondió la encuesta con
// puntaje bajo, para que pueda resolverlo en privado antes de que esa persona
// vaya a Google.
//
// ⚠ QUIÉN LO LLAMA Y POR QUÉ ESO OBLIGA A DESCONFIAR
// Lo llama encuesta.html — o sea, el navegador de un desconocido, desde un
// link sin token. Este endpoint NO puede creerle nada más allá de los dos ids:
// verifica contra la base que la encuesta exista, que esté RESPONDIDA, que el
// puntaje sea realmente bajo y que no se haya avisado antes. El puntaje y el
// comentario que se mandan en el correo salen de la base, nunca del body.
//
// Sin esas verificaciones, cualquiera con el link podría hacer sonar el correo
// del dueño cuantas veces quisiera, o inventarle un comentario.
//
// El `avisada_at` es lo que hace que se avise UNA sola vez: se comprueba antes
// y se marca después.

const { supabaseGet, supabasePatch, enviarEmail, emailShell } = require('./_lib/resend');

// El mismo umbral que usa responder_encuesta_publico para decidir si ofrece el
// link de Google. Vive en dos lados y no hay forma de evitarlo —uno es SQL y
// el otro JavaScript— así que test-encuesta.html compara los dos y falla si se
// separan. Si divergen, habría respuestas que no ofrecen Google NI avisan al
// dueño: caerían en el hueco entre los dos umbrales.
const PUNTAJE_BAJO_MAX = 3;

function escapeHtml(s) {
  return (s == null ? '' : String(s)).replace(/[&<>"']/g, c => ({
    '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;'
  })[c]);
}

function construirContenido({ puntaje, comentario, cliente, whatsapp, servicio, fecha }) {
  const estrellas = '★'.repeat(puntaje) + '☆'.repeat(5 - puntaje);
  return `
    <p style="margin:0 0 6px;font-size:16px;color:#111">Una respuesta que conviene mirar</p>
    <p style="margin:0 0 20px;font-size:24px;color:#e0a850;letter-spacing:2px">${estrellas}
      <span style="font-size:14px;color:#666">(${puntaje} de 5)</span></p>

    <table role="presentation" cellpadding="0" cellspacing="0" width="100%"
           style="background:#f7f7fa;border-radius:8px;margin-bottom:20px">
      <tr><td style="padding:14px 16px;font-size:14px;color:#333;line-height:1.6">
        <strong>${escapeHtml(cliente) || 'Un cliente'}</strong><br>
        <span style="font-size:13px;color:#666">
          ${escapeHtml(servicio) || 'Servicio'}${fecha ? ' · ' + escapeHtml(fecha) : ''}
          ${whatsapp ? '<br>' + escapeHtml(whatsapp) : ''}
        </span>
      </td></tr>
    </table>

    <p style="margin:0 0 6px;font-size:12px;color:#888;text-transform:uppercase;letter-spacing:0.5px">Lo que escribió</p>
    <p style="margin:0 0 20px;font-size:15px;color:#111;line-height:1.65;padding-left:12px;border-left:3px solid #e0a850">
      ${escapeHtml(comentario) || '(sin comentario)'}
    </p>

    <p style="margin:0;font-size:13px;color:#666;line-height:1.6">
      Contactarlo pronto suele ser la diferencia entre una reseña mala y un
      cliente que vuelve.
    </p>`;
}

module.exports = async function handler(req, res) {
  res.setHeader('Content-Type', 'application/json');

  if (req.method !== 'POST') {
    res.status(405).json({ ok: false, error: 'Método no permitido' });
    return;
  }

  const { barberiaId, visitaId } = req.body || {};
  if (!barberiaId || !visitaId) {
    res.status(400).json({ ok: false, error: 'Faltan barberiaId y visitaId' });
    return;
  }

  try {
    // Los DOS ids en el filtro, igual que en las RPC públicas: con uno solo se
    // podría apuntar a la encuesta de otro negocio.
    const encuestas = await supabaseGet(
      `encuestas?barberia_id=eq.${encodeURIComponent(barberiaId)}`
      + `&visita_id=eq.${encodeURIComponent(visitaId)}`
      + `&select=id,puntaje,comentario,cliente_id,respondida_at,avisada_at`
    );
    const e = encuestas[0];

    // Se responde 200 y no 4xx en todos estos casos a propósito: no son
    // errores del cliente que respondió, y devolver códigos distintos le
    // diría a quien sondee el endpoint cuál de las condiciones falló.
    if (!e || !e.respondida_at) {
      res.status(200).json({ ok: true, avisado: false, motivo: 'sin respuesta' });
      return;
    }
    if (e.puntaje == null || e.puntaje > PUNTAJE_BAJO_MAX) {
      res.status(200).json({ ok: true, avisado: false, motivo: 'no es baja' });
      return;
    }
    if (e.avisada_at) {
      res.status(200).json({ ok: true, avisado: false, motivo: 'ya avisado' });
      return;
    }

    const [barberias, clientes, visitas] = await Promise.all([
      supabaseGet(`barberias?id=eq.${encodeURIComponent(barberiaId)}&select=nombre,email,logo_url`),
      e.cliente_id
        ? supabaseGet(`clientes?id=eq.${e.cliente_id}&select=nombre,apellido,whatsapp`)
        : Promise.resolve([]),
      supabaseGet(`visitas?id=eq.${encodeURIComponent(visitaId)}&select=servicio,fecha`)
    ]);

    const negocio = barberias[0];
    const correoDueno = (negocio?.email || '').trim();

    // Sin correo del dueño no hay a dónde avisar. NO se marca avisada_at: si
    // mañana carga su correo en Config, el aviso todavía puede salir. Marcarlo
    // acá lo perdería para siempre.
    if (!correoDueno) {
      res.status(200).json({ ok: true, avisado: false, motivo: 'el negocio no tiene correo cargado' });
      return;
    }

    const c = clientes[0];
    const nombreCliente = [c?.nombre, c?.apellido].filter(Boolean).join(' ');

    await enviarEmail({
      to: correoDueno,
      subject: `${e.puntaje}★ de ${nombreCliente || 'un cliente'} — conviene contactarlo`,
      html: emailShell({
        nombreNegocio: negocio?.nombre || 'tu negocio',
        logoUrl: negocio?.logo_url,
        contenidoHtml: construirContenido({
          puntaje: e.puntaje,
          comentario: e.comentario,
          cliente: nombreCliente,
          whatsapp: c?.whatsapp,
          servicio: visitas[0]?.servicio,
          fecha: visitas[0]?.fecha
        })
      })
    });

    // Después del envío, por lo mismo que en enviar-encuesta: marcarlo antes
    // dejaría el aviso como hecho cuando el correo falló.
    await supabasePatch(`encuestas?id=eq.${e.id}`, { avisada_at: new Date().toISOString() });

    res.status(200).json({ ok: true, avisado: true });
  } catch (err) {
    res.status(500).json({ ok: false, error: err.message || 'Error interno' });
  }
};
