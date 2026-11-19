// Vercel Serverless Function: POST /api/enviar-club-bienvenida
//
// Al cobrarse la PRIMERA visita de un cliente, le llega un correo con el link a
// su Club para que lo instale. Recibe { cobroId } (panel del dueño) o
// { visitaId } (Mi Agenda del profesional), igual que /api/enviar-encuesta, y
// resuelve todo en la base: del navegador solo toma ese id.
//
// Manda el correo solo si:
//  · el negocio tiene el Club activo (rubro de barbería/salón y club_vip_activo no apagado),
//  · es la primera visita del cliente (no tiene visitas de otro cobro),
//  · el cliente tiene correo,
//  · no se le había enviado antes (clientes.club_invitado_at, reclamado con un
//    PATCH condicional ANTES de enviar; si el envío falla se libera para reintentar).
// Sin correo no es un error: simplemente no hay a quién escribirle.

const { supabaseGet, supabasePatch, enviarEmail, emailShell, negocioParaEmail, escaparHtml } = require('./_lib/resend');

const RUBRO_VIP = 'Barbería / Peluquería / Centro de estética';
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

function contenido({ nombreCliente, nombreNegocio, link }) {
  const n = escaparHtml(nombreCliente || '');
  const neg = escaparHtml(nombreNegocio || 'nosotros');
  return `
    <p style="margin:0 0 12px;font-size:16px;color:#111">Hola${n ? ' ' + n : ''} 👋</p>
    <p style="margin:0 0 16px;font-size:14px;color:#444;line-height:1.6">
      Gracias por tu primera visita a <strong>${neg}</strong>. Ya tienes tu <strong>Club</strong>:
      ahí ves tus reservas, puedes cambiarlas, reservar de nuevo y mirar la historia de tus visitas y tus cortes.
    </p>
    <table role="presentation" cellpadding="0" cellspacing="0" style="margin:0 0 20px">
      <tr><td style="border-radius:8px;background:linear-gradient(135deg,#7c6af7,#5b8def)">
        <a href="${link}" style="display:inline-block;padding:12px 28px;color:#fff;text-decoration:none;font-size:14px;font-weight:600">Abrir mi Club</a>
      </td></tr>
    </table>
    <p style="margin:0 0 6px;font-size:13px;color:#444;line-height:1.6"><strong>Para tenerlo como aplicación en tu celular:</strong></p>
    <p style="margin:0 0 4px;font-size:13px;color:#444;line-height:1.6">· <strong>iPhone:</strong> abre el link en Safari, toca Compartir y elige «Agregar a inicio».</p>
    <p style="margin:0 0 4px;font-size:13px;color:#444;line-height:1.6">· <strong>Android:</strong> abre el link en Chrome, toca los tres puntos y elige «Instalar aplicación» o «Agregar a pantalla de inicio».</p>
    <p style="margin:20px 0 0;font-size:12px;color:#999">Si el botón no funciona, copia este link: ${link}</p>`;
}

module.exports = async function handler(req, res) {
  res.setHeader('Content-Type', 'application/json');
  if (req.method !== 'POST') { res.status(405).json({ ok: false, error: 'Método no permitido' }); return; }

  const { cobroId, visitaId } = req.body || {};
  const id = cobroId || visitaId;
  if (!id || !UUID.test(String(id))) { res.status(400).json({ ok: false, error: 'Falta cobroId o visitaId válido' }); return; }

  try {
    const visitas = await supabaseGet(
      cobroId
        ? `visitas?cobro_id=eq.${encodeURIComponent(cobroId)}&select=id,barberia_id,cliente_id,cobro_id`
        : `visitas?id=eq.${encodeURIComponent(visitaId)}&select=id,barberia_id,cliente_id,cobro_id`
    );
    if (!visitas.length) { res.status(200).json({ ok: true, enviados: 0, detalle: 'Sin visitas' }); return; }

    const proto = req.headers['x-forwarded-proto'] || 'https';
    const host = req.headers.host;
    const clientesVistos = new Set();
    let enviados = 0;
    const omitidos = [];

    for (const v of visitas) {
      if (!v.cliente_id || clientesVistos.has(v.cliente_id)) continue;
      clientesVistos.add(v.cliente_id);
      let reclamado = false;
      try {
        const [negocios, clientes] = await Promise.all([
          negocioParaEmail(`id=eq.${v.barberia_id}`, 'nombre,logo_url,rubro,club_vip_activo'),
          supabaseGet(`clientes?id=eq.${v.cliente_id}&select=nombre,email,club_invitado_at`)
        ]);
        const negocio = negocios[0], cliente = clientes[0];
        if (!negocio || !cliente) { omitidos.push({ cliente_id: v.cliente_id, motivo: 'no_encontrado' }); continue; }
        if ((negocio.rubro || RUBRO_VIP) !== RUBRO_VIP || negocio.club_vip_activo === false) { omitidos.push({ cliente_id: v.cliente_id, motivo: 'club_inactivo' }); continue; }
        if (cliente.club_invitado_at) { omitidos.push({ cliente_id: v.cliente_id, motivo: 'ya_invitado' }); continue; }
        const correo = (cliente.email || '').trim();
        if (!correo) { omitidos.push({ cliente_id: v.cliente_id, motivo: 'sin_correo' }); continue; }

        // ¿Es la primera visita? Cualquier visita de OTRO cobro (o de otra visita,
        // si no hay cobro) significa que ya venía de antes.
        const filtroOtras = v.cobro_id ? `cobro_id=neq.${v.cobro_id}` : `id=neq.${v.id}`;
        const previas = await supabaseGet(`visitas?cliente_id=eq.${v.cliente_id}&${filtroOtras}&select=id&limit=1`);
        if (previas.length) { omitidos.push({ cliente_id: v.cliente_id, motivo: 'no_es_primera' }); continue; }

        // Reclamo atómico: solo uno gana aunque lleguen dos llamadas a la vez.
        const ganado = await supabasePatch(`clientes?id=eq.${v.cliente_id}&club_invitado_at=is.null`, { club_invitado_at: new Date().toISOString() });
        if (!ganado.length) { omitidos.push({ cliente_id: v.cliente_id, motivo: 'ya_invitado' }); continue; }
        reclamado = true;

        const link = `${proto}://${host}/club.html?id=${encodeURIComponent(v.barberia_id)}&cliente=${encodeURIComponent(v.cliente_id)}`;
        await enviarEmail({
          to: correo,
          subject: `Tu Club de ${negocio.nombre || 'tu barbería'} ya está listo`,
          html: emailShell({
            nombreNegocio: negocio.nombre || 'tu negocio',
            logoUrl: negocio.logo_url,
            negocio,
            contenidoHtml: contenido({ nombreCliente: (cliente.nombre || '').trim().split(/\s+/)[0], nombreNegocio: negocio.nombre, link })
          })
        });
        enviados++;
      } catch (err) {
        // Si se reclamó pero el correo no salió, se libera para que un próximo intento pueda enviarlo.
        if (reclamado) { try { await supabasePatch(`clientes?id=eq.${v.cliente_id}&club_invitado_at=not.is.null`, { club_invitado_at: null }); } catch (_) {} }
        console.error('enviar-club-bienvenida', v.cliente_id, err.message);
        omitidos.push({ cliente_id: v.cliente_id, motivo: 'error', error: err.message });
      }
    }
    res.status(200).json({ ok: true, enviados, omitidos });
  } catch (e) {
    console.error('enviar-club-bienvenida', e.message);
    res.status(500).json({ ok: false, error: e.message || 'Error interno' });
  }
};
