// Vercel Serverless Function: POST /api/enviar-encuesta
//
// Manda la encuesta de satisfacción por correo. Recibe { cobroId } o
// { visitaId }, resuelve TODO en la base y nunca confía en lo que le llega
// del navegador más allá del id.
//
// ⚠ QUIÉN CREA LA FILA: no esta función. Las filas de `encuestas` las crea un
// trigger sobre `visitas` (migration_encuesta_satisfaccion.sql), así que
// existen aunque el cliente no tenga correo. Esta función solo las ENVÍA y
// marca `enviada_at`. Es lo que hace que el ~12% de clientes sin correo no se
// pierda: quedan con enviada_at en null y aparecen en la lista de WhatsApp.
//
// POR QUÉ ACEPTA cobroId ADEMÁS DE visitaId
// Un cobro conjunto puede tener reservas de VARIAS personas distintas — es
// justamente para lo que existe. Una encuesta por cliente, no por cobro. El
// panel manda el cobroId que devuelve registrar_cobro_conjunto(); Mi Agenda
// manda el visitaId que devuelve mi_agenda_procesar_pago().

const { supabaseGet, supabasePatch, enviarEmail, emailShell } = require('./_lib/resend');

function construirContenido({ nombreCliente, servicio, link }) {
  return `
    <p style="margin:0 0 12px;font-size:16px;color:#111">Hola ${nombreCliente || ''} 👋</p>
    <p style="margin:0 0 20px;font-size:14px;color:#444;line-height:1.6">
      ¡Gracias por venir! ${servicio ? `¿Cómo estuvo tu ${servicio}?` : '¿Cómo estuvo tu visita?'}
      Tu opinión nos ayuda a mejorar, y nos toma menos de un minuto.
    </p>
    <table role="presentation" cellpadding="0" cellspacing="0">
      <tr><td style="border-radius:8px;background:linear-gradient(135deg,#7c6af7,#5b8def)">
        <a href="${link}" style="display:inline-block;padding:12px 28px;color:#fff;text-decoration:none;font-size:14px;font-weight:600">Contarles cómo me fue</a>
      </td></tr>
    </table>
    <p style="margin:24px 0 0;font-size:12px;color:#999">Si el botón no funciona, copia este link: ${link}</p>`;
}

module.exports = async function handler(req, res) {
  res.setHeader('Content-Type', 'application/json');

  if (req.method !== 'POST') {
    res.status(405).json({ ok: false, error: 'Método no permitido' });
    return;
  }

  const { cobroId, visitaId } = req.body || {};
  if (!cobroId && !visitaId) {
    res.status(400).json({ ok: false, error: 'Falta cobroId o visitaId' });
    return;
  }

  try {
    // Se parte de `encuestas`, no de `visitas`: la fila solo existe si el
    // trigger la creó, y el trigger ya exigió estado 'Atendida' y cliente_id.
    // Repetir esas condiciones acá sería una segunda copia de la misma regla.
    //
    // enviada_at=is.null evita reenviar: si el dueño cobra, se arrepiente y
    // vuelve a cobrar, el cliente no recibe dos correos.
    const COLUMNAS = 'select=id,barberia_id,visita_id,cliente_id';

    let encuestas;
    if (visitaId) {
      encuestas = await supabaseGet(
        `encuestas?visita_id=eq.${encodeURIComponent(visitaId)}&enviada_at=is.null&${COLUMNAS}`
      );
    } else {
      // PostgREST no hace subconsultas, así que van dos viajes: las visitas de
      // ese cobro, y después sus encuestas.
      const visitas = await supabaseGet(
        `visitas?cobro_id=eq.${encodeURIComponent(cobroId)}&select=id`
      );
      if (!visitas.length) {
        res.status(200).json({ ok: true, enviadas: 0, sin_correo: 0, detalle: 'El cobro no tiene visitas' });
        return;
      }
      const ids = visitas.map(v => v.id).join(',');
      encuestas = await supabaseGet(
        `encuestas?visita_id=in.(${ids})&enviada_at=is.null&${COLUMNAS}`
      );
    }

    if (!encuestas.length) {
      res.status(200).json({ ok: true, enviadas: 0, sin_correo: 0, detalle: 'Nada pendiente de enviar' });
      return;
    }

    const proto = req.headers['x-forwarded-proto'] || 'https';
    const host = req.headers.host;

    let enviadas = 0, sinCorreo = 0;
    const errores = [];

    for (const e of encuestas) {
      try {
        const [clientes, barberias, visitas] = await Promise.all([
          e.cliente_id
            ? supabaseGet(`clientes?id=eq.${e.cliente_id}&select=nombre,email`)
            : Promise.resolve([]),
          supabaseGet(`barberias?id=eq.${e.barberia_id}&select=nombre`),
          supabaseGet(`visitas?id=eq.${e.visita_id}&select=servicio`)
        ]);
        const cliente = clientes[0];
        const correo = (cliente?.email || '').trim();

        // Sin correo NO es un error: es el otro canal. Se marca para que la
        // lista de WhatsApp del panel sepa que le toca a ella, y la fila queda
        // con enviada_at en null hasta que el dueño la mande de verdad.
        if (!correo) {
          sinCorreo++;
          await supabasePatch(`encuestas?id=eq.${e.id}`, { canal: 'whatsapp' });
          continue;
        }

        const link = `${proto}://${host}/encuesta.html`
          + `?b=${encodeURIComponent(e.barberia_id)}&v=${encodeURIComponent(e.visita_id)}`;

        await enviarEmail({
          to: correo,
          subject: `¿Cómo estuvo tu visita a ${barberias[0]?.nombre || 'nosotros'}?`,
          html: emailShell({
            nombreNegocio: barberias[0]?.nombre || 'tu negocio',
            contenidoHtml: construirContenido({
              nombreCliente: cliente?.nombre,
              servicio: visitas[0]?.servicio,
              link
            })
          })
        });

        // Se marca DESPUÉS de que Resend aceptó. Al revés, un fallo del correo
        // dejaría la encuesta como enviada y el cliente nunca la recibiría.
        await supabasePatch(`encuestas?id=eq.${e.id}`, {
          canal: 'email',
          enviada_at: new Date().toISOString()
        });
        enviadas++;
      } catch (err) {
        // Un cobro con varios clientes no puede quedar a medias porque uno
        // tenga el correo mal escrito: se registra y se sigue con los demás.
        errores.push({ visita_id: e.visita_id, error: err.message });
      }
    }

    res.status(200).json({ ok: true, enviadas, sin_correo: sinCorreo, errores });
  } catch (e) {
    res.status(500).json({ ok: false, error: e.message || 'Error interno' });
  }
};
