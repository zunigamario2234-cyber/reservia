// Vercel Serverless Function: POST /api/enviar-confirmacion
// Recibe { reservaId }, busca los datos reales en Supabase (nunca confía en
// texto libre del cliente) y envía por Resend hasta dos correos por reserva:
// la confirmación al cliente y el aviso al profesional. RESEND_API_KEY solo
// vive en el servidor.
//
// Los dos envíos son independientes a propósito: cada uno tiene su try/catch
// y su motivo en la respuesta. El aviso al profesional es funcionalidad nueva
// y no puede, si falla, romper la confirmación al cliente, que ya funcionaba.

const { supabaseGet, enviarEmail, emailShell } = require('./_lib/resend');

// Valor literal que ponen crear_reserva_publica() y crear_reserva_club_vip()
// cuando el cliente no eligió profesional. No es un nombre, es un placeholder:
// no hay a quién avisarle.
const SIN_ASIGNAR = 'Por asignar';

// Escapa texto libre antes de interpolarlo en el HTML del correo. nombre_cliente,
// servicio y notas los escribe el público en reservar.html sin validación, así
// que sin esto un "<" del usuario puede romper el markup del mail.
function esc(v) {
  return String(v == null ? '' : v)
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;');
}

function normalizar(v) {
  return String(v == null ? '' : v).trim().toLowerCase();
}

// Resuelve a qué profesional hay que avisarle a partir de reservas.barbero_nombre,
// que es TEXTO LIBRE y no una FK (deuda conocida, ver migration_mi_agenda.sql (7)).
//
// Reglas, en orden:
//  1. "Por asignar"/vacío -> no hay destinatario, no es un error.
//  2. El match es SIEMPRE normalizado (minúsculas + espacios), porque en
//     producción hay reservas guardadas con distinta capitalización que la
//     ficha del profesional.
//  3. Inactivos quedan fuera: activo=false significa que ya no atiende, y
//     mi-agenda.html ya le bloquea el acceso con el mismo criterio. Se filtran
//     ANTES de evaluar ambigüedad para que un homónimo dado de baja no impida
//     avisarle al que sí trabaja.
//  4. Si quedan DOS o más candidatos, no se envía nada. Con un vínculo por
//     texto no hay forma de desempatar, y equivocarse de persona es peor que
//     no avisar.
//
// Sobre por qué NO se privilegia el match exacto: si en el mismo negocio
// conviven "Mario" y "mario" como dos fichas, que la reserva diga "mario" no
// prueba a cuál se refiere. Todo el motivo por el que existe el match relajado
// es que la capitalización de este sistema no es confiable — así que usarla
// como criterio de desempate justo cuando hay empate sería contradictorio.
// Buscar primero los exactos y cortar ahí hacía que el resolver ni se enterara
// de que existía la otra ficha, y mandaba el correo a una de las dos personas
// al azar.
//
// IMPORTANTE: la lista de barberos que entra acá tiene que venir ya filtrada por
// el barberia_id de la reserva. Estas funciones corren con service_role, que
// bypasea RLS por completo — el scoping por negocio no lo garantiza la base, lo
// garantiza el llamador. Sin eso, dos negocios con un profesional del mismo
// nombre se cruzan los correos.
function resolverProfesional(barberosDelNegocio, barberoNombre) {
  const buscado = normalizar(barberoNombre);
  if (!buscado || buscado === normalizar(SIN_ASIGNAR)) {
    return { motivo: 'sin_profesional_asignado' };
  }

  const candidatos = barberosDelNegocio.filter(b => normalizar(b.nombre) === buscado);
  if (!candidatos.length) return { motivo: 'nombre_no_matchea' };

  // activo !== false (y no "=== true") para que una fila vieja con activo en
  // null no quede excluida sin querer.
  const activos = candidatos.filter(b => b.activo !== false);
  if (!activos.length) return { motivo: 'inactivo' };
  if (activos.length > 1) return { motivo: 'ambiguo' };

  const profesional = activos[0];
  if (!profesional.email) return { motivo: 'sin_email', profesional };
  return { motivo: 'ok', profesional };
}

function construirContenidoCliente({ nombreCliente, fecha, hora, servicio, profesional }) {
  return `
    <p style="margin:0 0 12px;font-size:16px;color:#111">Hola ${esc(nombreCliente)} 👋</p>
    <p style="margin:0 0 20px;font-size:14px;color:#444;line-height:1.6">
      ¡Gracias por reservar con nosotros! Tu cita quedó confirmada:
    </p>
    <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="background:#f4f4f7;border-radius:8px;margin-bottom:20px">
      <tr><td style="padding:16px 20px;font-size:14px;color:#333;line-height:1.9">
        📅 <strong>${esc(fecha)}</strong> a las <strong>${esc(hora)}</strong> hrs<br>
        ✂️ ${esc(servicio || 'Servicio')}${profesional ? ' con ' + esc(profesional) : ''}
      </td></tr>
    </table>
    <p style="margin:0;font-size:12px;color:#999">¡Te esperamos!</p>`;
}

// esRegistroPropio: la reserva la creó el propio profesional desde Mi Agenda,
// así que el correo no le está avisando nada que no sepa — es un comprobante
// para que le quede registro por fuera del panel.
function construirContenidoProfesional({ nombreProfesional, nombreCliente, whatsappCliente, fecha, hora, servicio, esRegistroPropio }) {
  const intro = esRegistroPropio
    ? 'Queda registro de la cita que acabas de agendar:'
    : 'Te agendaron una cita nueva:';
  return `
    <p style="margin:0 0 12px;font-size:16px;color:#111">Hola ${esc(nombreProfesional)} 👋</p>
    <p style="margin:0 0 20px;font-size:14px;color:#444;line-height:1.6">${intro}</p>
    <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="background:#f4f4f7;border-radius:8px;margin-bottom:20px">
      <tr><td style="padding:16px 20px;font-size:14px;color:#333;line-height:1.9">
        📅 <strong>${esc(fecha)}</strong> a las <strong>${esc(hora)}</strong> hrs<br>
        ✂️ ${esc(servicio || 'Servicio')}<br>
        👤 ${esc(nombreCliente || 'Cliente')}${whatsappCliente ? '<br>📱 ' + esc(whatsappCliente) : ''}
      </td></tr>
    </table>
    <p style="margin:0;font-size:12px;color:#999">Puedes ver el detalle completo en Mi Agenda.</p>`;
}

// Respaldo al dueño: solo se usa cuando el lado del negocio no se enteró por
// ningún otro canal. Lleva el motivo real para que el dueño pueda corregir la
// causa (un profesional sin correo cargado, un nombre que no matchea) y no solo
// enterarse de la reserva suelta.
function construirContenidoDueno({ barberoNombre, motivo, nombreCliente, whatsappCliente, fecha, hora, servicio }) {
  const explicacion = {
    sin_profesional_asignado: 'La reserva no tiene profesional asignado.',
    nombre_no_matchea: `La reserva figura a nombre de "${esc(barberoNombre)}", que no coincide con ningún profesional del equipo.`,
    ambiguo: `Hay más de un profesional que coincide con "${esc(barberoNombre)}", así que no se pudo determinar a cuál avisarle.`,
    inactivo: `El profesional "${esc(barberoNombre)}" está marcado como inactivo.`,
    sin_email: `El profesional "${esc(barberoNombre)}" no tiene correo cargado en su ficha.`,
    error_envio: `No se pudo entregar el correo al profesional "${esc(barberoNombre)}".`
  }[motivo] || 'No se pudo avisar al profesional.';

  return `
    <p style="margin:0 0 12px;font-size:16px;color:#111">Nueva reserva sin aviso al profesional</p>
    <p style="margin:0 0 20px;font-size:14px;color:#444;line-height:1.6">${explicacion}<br>Te la reenviamos para que no pase desapercibida.</p>
    <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="background:#f4f4f7;border-radius:8px;margin-bottom:20px">
      <tr><td style="padding:16px 20px;font-size:14px;color:#333;line-height:1.9">
        📅 <strong>${esc(fecha)}</strong> a las <strong>${esc(hora)}</strong> hrs<br>
        ✂️ ${esc(servicio || 'Servicio')}<br>
        👤 ${esc(nombreCliente || 'Cliente')}${whatsappCliente ? '<br>📱 ' + esc(whatsappCliente) : ''}
      </td></tr>
    </table>`;
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

    const barberias = await supabaseGet(`barberias?id=eq.${encodeURIComponent(reserva.barberia_id)}&select=nombre,email`);
    const barberia = barberias[0];
    const nombreNegocio = barberia?.nombre || 'tu negocio';
    const fecha = reserva.fecha;
    const hora = (reserva.hora || '').slice(0, 5);

    // ── Correo al cliente ────────────────────────────────────────────
    const cliente = { sent: false, motivo: 'sin_email' };
    if (reserva.email_cliente) {
      try {
        await enviarEmail({
          to: reserva.email_cliente,
          subject: `Reserva confirmada en ${nombreNegocio}`,
          html: emailShell({
            nombreNegocio,
            contenidoHtml: construirContenidoCliente({
              nombreCliente: reserva.nombre_cliente,
              fecha,
              hora,
              servicio: reserva.servicio,
              profesional: reserva.barbero_nombre === SIN_ASIGNAR ? null : reserva.barbero_nombre
            })
          })
        });
        cliente.sent = true;
        cliente.motivo = 'ok';
      } catch (e) {
        cliente.motivo = 'error_envio';
        cliente.error = e.message;
      }
    }

    // ── Correo al profesional ────────────────────────────────────────
    // El origen se lee de reservas.fuente (lo escriben las RPC server-side),
    // nunca de un parámetro del navegador.
    const esRegistroPropio = reserva.fuente === 'Mi Agenda';
    const profesional = { sent: false, motivo: null };

    // Sin filtrar por activo en la query: se trae el equipo del negocio y el
    // filtro lo hace resolverProfesional(), que así puede distinguir "está
    // inactivo" de "no existe" y devolver un motivo útil.
    const barberosDelNegocio = await supabaseGet(
      `barberos?barberia_id=eq.${encodeURIComponent(reserva.barberia_id)}&select=nombre,email,activo`
    );
    const resuelto = resolverProfesional(barberosDelNegocio, reserva.barbero_nombre);
    profesional.motivo = resuelto.motivo;

    if (resuelto.motivo === 'ok') {
      try {
        await enviarEmail({
          to: resuelto.profesional.email,
          subject: esRegistroPropio
            ? `Registro de cita creada — ${nombreNegocio}`
            : `Te agendaron una cita en ${nombreNegocio}`,
          html: emailShell({
            nombreNegocio,
            contenidoHtml: construirContenidoProfesional({
              nombreProfesional: resuelto.profesional.nombre,
              nombreCliente: reserva.nombre_cliente,
              whatsappCliente: reserva.whatsapp_cliente,
              fecha,
              hora,
              servicio: reserva.servicio,
              esRegistroPropio
            })
          })
        });
        profesional.sent = true;
      } catch (e) {
        profesional.motivo = 'error_envio';
        profesional.error = e.message;
      }
    }

    // ── Respaldo al dueño ────────────────────────────────────────────
    // Solo si el lado del NEGOCIO se quedó sin enterarse. El correo al cliente
    // no cuenta para esto: el cliente ya sabía que reservó.
    //
    // Se excluye a propósito el caso Mi Agenda: ahí la reserva la creó el propio
    // profesional, así que ya está enterado por definición y su correo era un
    // comprobante. Molestar al dueño porque falló un comprobante sería ruido.
    const dueno = { sent: false, motivo: 'no_corresponde' };
    const mismoDestinatarioQueProfesional =
      resuelto.profesional?.email &&
      normalizar(resuelto.profesional.email) === normalizar(barberia?.email);

    if (!profesional.sent && !esRegistroPropio && barberia?.email && !mismoDestinatarioQueProfesional) {
      try {
        await enviarEmail({
          to: barberia.email,
          subject: `Nueva reserva sin avisar en ${nombreNegocio}`,
          html: emailShell({
            nombreNegocio,
            contenidoHtml: construirContenidoDueno({
              barberoNombre: reserva.barbero_nombre,
              motivo: profesional.motivo,
              nombreCliente: reserva.nombre_cliente,
              whatsappCliente: reserva.whatsapp_cliente,
              fecha,
              hora,
              servicio: reserva.servicio
            })
          })
        });
        dueno.sent = true;
        dueno.motivo = 'ok';
      } catch (e) {
        dueno.motivo = 'error_envio';
        dueno.error = e.message;
      }
    }

    res.status(200).json({ ok: true, cliente, profesional, dueno });
  } catch (e) {
    res.status(500).json({ ok: false, error: e.message || 'Error interno' });
  }
};
