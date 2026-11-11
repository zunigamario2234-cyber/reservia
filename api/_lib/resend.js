// Código compartido entre las funciones serverless que envían correo (Resend).
// Archivos/carpetas que empiezan con "_" dentro de /api no se publican como
// endpoints en Vercel — solo se pueden importar desde otras funciones.

// La URL sale de env var para que cada entorno de Vercel apunte a su propia
// base. El fallback existe solo para que este cambio no dependa de configurar
// el dashboard antes del deploy: hoy no hay más entorno que producción.
//
// CUANDO EXISTA STAGING, HAY QUE SACAR EL FALLBACK. Deja de ser una comodidad
// y pasa a ser una trampa: un preview sin la env var definida escribiría en la
// base de la barbería real sin avisar. Es el mismo motivo por el que las
// páginas no llevan credenciales de producción como respaldo. Mientras tanto,
// avisa en los logs para que el día que pase quede rastro.
const SUPABASE_URL = process.env.SUPABASE_URL || 'https://dqoqykngmtxtvbokxbzp.supabase.co';
if (!process.env.SUPABASE_URL) {
  console.warn('SUPABASE_URL no está definida en el entorno; usando la de producción por defecto.');
}
// Las funciones serverless usan la service_role key, nunca la anon key: con
// RLS activado, la anon key solo ve los datos del negocio dueño de cada fila
// (o nada, si nadie inició sesión), pero estas funciones necesitan leer la
// reserva/visita puntual que el navegador les pasó por id, sea de quien sea.
// Es tráfico servidor-a-servidor de confianza; esta key nunca llega al navegador.
const SUPABASE_SERVICE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
const RESEND_FROM = process.env.RESEND_FROM || 'Reservia <no-responder@mireservia.cl>';

async function supabaseGet(path) {
  if (!SUPABASE_SERVICE_KEY) {
    throw new Error('SUPABASE_SERVICE_ROLE_KEY no configurada en el servidor');
  }
  const res = await fetch(`${SUPABASE_URL}/rest/v1/${path}`, {
    headers: { apikey: SUPABASE_SERVICE_KEY, Authorization: `Bearer ${SUPABASE_SERVICE_KEY}` }
  });
  if (!res.ok) throw new Error(`Supabase ${path} respondió ${res.status}`);
  return res.json();
}

// Escribe con la service_role key, igual que supabaseGet lee con ella. Se usa
// para marcar en la base lo que la función serverless ya hizo — por ejemplo
// que una encuesta se envió — porque eso no lo puede escribir el navegador:
// diría "la mandé" sin que nadie lo verifique.
//
// `path` lleva su propio filtro PostgREST (ej. 'encuestas?id=eq.<uuid>'). Se
// exige que traiga un `=eq.` o algún filtro: un PATCH sin where en PostgREST
// actualiza LA TABLA ENTERA, y ese error no avisa, solo destruye.
async function supabasePatch(path, body) {
  if (!SUPABASE_SERVICE_KEY) {
    throw new Error('SUPABASE_SERVICE_ROLE_KEY no configurada en el servidor');
  }
  if (!/[?&][a-z_]+=(eq|in|is)\./i.test(path)) {
    throw new Error(`supabasePatch sin filtro: "${path}" actualizaría la tabla entera`);
  }
  const res = await fetch(`${SUPABASE_URL}/rest/v1/${path}`, {
    method: 'PATCH',
    headers: {
      apikey: SUPABASE_SERVICE_KEY,
      Authorization: `Bearer ${SUPABASE_SERVICE_KEY}`,
      'Content-Type': 'application/json',
      Prefer: 'return=representation'
    },
    body: JSON.stringify(body)
  });
  if (!res.ok) {
    const detalle = await res.text();
    throw new Error(`Supabase PATCH ${path} respondió ${res.status}: ${detalle}`);
  }
  return res.json();
}

async function enviarEmail({ to, subject, html, replyTo }) {
  if (!process.env.RESEND_API_KEY) {
    throw new Error('RESEND_API_KEY no configurada en el servidor');
  }
  const resendRes = await fetch('https://api.resend.com/emails', {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${process.env.RESEND_API_KEY}`,
      'Content-Type': 'application/json'
    },
    body: JSON.stringify({ from: RESEND_FROM, to: [to], subject, html, ...(replyTo ? { reply_to: replyTo } : {}) })
  });
  if (!resendRes.ok) {
    const detalle = await resendRes.text();
    throw new Error(`Resend respondió ${resendRes.status}: ${detalle}`);
  }
}

// Inserta una fila con la service_role key. Devuelve la fila creada.
async function supabasePost(path, body) {
  if (!SUPABASE_SERVICE_KEY) {
    throw new Error('SUPABASE_SERVICE_ROLE_KEY no configurada en el servidor');
  }
  const res = await fetch(`${SUPABASE_URL}/rest/v1/${path}`, {
    method: 'POST',
    headers: {
      apikey: SUPABASE_SERVICE_KEY,
      Authorization: `Bearer ${SUPABASE_SERVICE_KEY}`,
      'Content-Type': 'application/json',
      Prefer: 'return=representation'
    },
    body: JSON.stringify(body)
  });
  if (!res.ok) {
    const detalle = await res.text();
    throw new Error(`Supabase POST ${path} respondió ${res.status}: ${detalle}`);
  }
  return res.json();
}

function escaparHtml(s) {
  return (s == null ? '' : String(s)).replace(/[&<>"']/g, c => ({
    '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;'
  })[c]);
}

// Wrapper visual compartido: encabezado con el logo y el nombre del negocio,
// sobre una tarjeta blanca. Lo usan los tres endpoints que mandan correo.
//
// ⚠ DOS COSAS QUE EL HTML DE CORREO NO PERDONA, y que explican por qué esto no
// se escribe como una página normal:
//
//  1. MUCHOS CLIENTES BLOQUEAN LAS IMÁGENES por defecto — Outlook entre ellos.
//     Por eso el logo va ADEMÁS del nombre en texto, nunca en su lugar: con las
//     imágenes bloqueadas, el correo tiene que seguir diciendo de quién es.
//
//     Y por eso el `alt` va VACÍO, que es lo contrario de lo que uno escribe
//     por reflejo. El logo es decorativo: el nombre ya está al lado, en texto.
//     Con el nombre en el alt pasaban dos cosas, las dos malas — bloqueado, el
//     texto quedaba recortado dentro del cuadro de 44px ("Essent…") pegado al
//     nombre entero, que se lee como algo roto; y un lector de pantalla
//     anunciaba el negocio dos veces seguidas. Comprobado renderizando el
//     correo con la imagen bloqueada el 2026-09-16.
//
//  2. `linear-gradient` NO EXISTE en Outlook, que ignora la propiedad entera y
//     deja la celda sin fondo: texto blanco sobre blanco, ilegible. Por eso
//     `background` lleva primero un color sólido y después el degradado —
//     quien entiende el segundo lo pisa, quien no, se queda con el primero.
//     Es un respaldo, no una redundancia.
//
// Y todo va en tablas con estilos en línea por lo mismo: el CSS de <head> y el
// layout moderno se caen en la mitad de los clientes de correo.
// ── Tema del dueño en los correos ────────────────────────────────────
// Los correos se ven como la app de cada negocio: mismas superficies, texto y
// acento que deriva tema.js (la misma función que usan el panel y las páginas
// públicas, con el contraste ya calculado). Un negocio sin tema propio sigue
// recibiendo el correo de siempre. Cualquier fallo del tema cae a ese correo:
// un correo transaccional nunca debe dejar de salir por un color.
const CAMPOS_TEMA = 'color_marca,modo_tema,color_fondo_logo,color_fondo_marca';
let TEMA_JS = null;
try { TEMA_JS = require('../../tema.js'); } catch (e) { console.error('tema.js no disponible para los correos:', e.message); }

function temaDeNegocio(n) {
  if (!TEMA_JS || !n) return null;
  try {
    return TEMA_JS.derivarSuperficies({
      modo: n.modo_tema === 'claro' ? 'claro' : 'oscuro',
      colorMarca: n.color_marca, colorFondoLogo: n.color_fondo_logo, colorFondoMarca: n.color_fondo_marca
    });
  } catch (e) { console.error('No se pudo derivar el tema del negocio:', e.message); return null; }
}

// Lee el negocio con los campos que pide el correo MÁS los del tema. Si la
// columna color_fondo_marca todavía no existe, reintenta sin ella.
async function negocioParaEmail(filtro, campos) {
  try {
    return await supabaseGet(`barberias?${filtro}&select=${campos},${CAMPOS_TEMA}`);
  } catch (e) {
    return await supabaseGet(`barberias?${filtro}&select=${campos},color_marca,modo_tema,color_fondo_logo`);
  }
}

// Los contenidos de cada correo traen sus grises fijos. Con tema se
// reemplazan por los colores calculados, que ya cumplen contraste.
function aplicarTemaAContenido(html, t, oscuro) {
  const caja = oscuro ? t['--portada-fondo'] : t['--fondo'];
  const mapa = {
    '111': t['--texto'], '222': t['--texto'],
    '333': t['--texto-suave'], '444': t['--texto-suave'], '555': t['--texto-suave'], '666': t['--texto-suave'],
    '888': t['--texto-debil'], '999': t['--texto-debil'],
    'f4f4f7': caja, 'f7f7fa': caja
  };
  return String(html)
    .replace(/background:linear-gradient\(135deg,#7c6af7,#5b8def\)/gi, `background:${t['--acento']}`)
    .replace(/color:#fff;text-decoration:none/gi, `color:${t['--texto-sobre-acento']};text-decoration:none`)
    .replace(/#([0-9a-f]{3}|[0-9a-f]{6})(?![0-9a-f])/gi, (m, h) => mapa[h.toLowerCase()] || m);
}

function emailShell({ nombreNegocio, contenidoHtml, logoUrl, negocio }) {
  const nombre = escaparHtml(nombreNegocio);
  // Solo se acepta http(s): un `logo_url` con javascript: o data: no tiene
  // sentido acá y no vale la pena dejarlo pasar a un correo.
  const logo = logoUrl && /^https?:\/\//i.test(logoUrl) ? escaparHtml(logoUrl) : '';
  const t = temaDeNegocio(negocio);
  const oscuro = !!t && TEMA_JS.modoDeFondoMarca(t['--fondo']) === 'oscuro';
  const pagina = t ? t['--fondo'] : '#f4f4f7';
  const tarjeta = t ? t['--tarjeta'] : '#ffffff';
  const cabeza = t ? `background:${t['--acento']}` : 'background:#6f5cf0;background:linear-gradient(135deg,#7c6af7,#5b8def)';
  const textoCabeza = t ? t['--texto-sobre-acento'] : '#ffffff';
  const fondoLogo = t ? t['--fondo-logo'] : '#ffffff';
  const cuerpo = t ? aplicarTemaAContenido(contenidoHtml, t, oscuro) : contenidoHtml;
  return `<!DOCTYPE html>
<html lang="es">
<body style="margin:0;padding:0;background:${pagina};font-family:system-ui,-apple-system,sans-serif">
  <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="background:${pagina};padding:32px 16px">
    <tr><td align="center">
      <table role="presentation" width="480" cellpadding="0" cellspacing="0" style="background:${tarjeta};border-radius:12px;overflow:hidden;max-width:100%">
        <tr><td style="${cabeza};padding:24px 32px">
          <table role="presentation" cellpadding="0" cellspacing="0"><tr>
            ${logo ? `<td style="padding-right:12px;vertical-align:middle">
              <img src="${logo}" alt="" width="44" height="44"
                   style="display:block;width:44px;height:44px;border-radius:8px;object-fit:cover;background:${fondoLogo}">
            </td>` : ''}
            <td style="vertical-align:middle">
              <span style="color:${textoCabeza};font-size:18px;font-weight:700">${nombre}</span>
            </td>
          </tr></table>
        </td></tr>
        <tr><td style="padding:32px">
          ${cuerpo}
        </td></tr>
      </table>
    </td></tr>
  </table>
</body>
</html>`;
}

module.exports = { SUPABASE_URL, supabaseGet, supabasePatch, supabasePost, enviarEmail, emailShell, escaparHtml, negocioParaEmail, temaDeNegocio };
