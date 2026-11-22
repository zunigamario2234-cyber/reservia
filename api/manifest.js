// Vercel Serverless Function: GET /api/manifest?app=agenda|panel&b=<barberia_id>
//
// Manifest de la app instalable con el NOMBRE y el LOGO del negocio, para que al
// "Agregar a inicio" el ícono sea el del local y no el de Reservia.
//  · app=agenda -> Mi Agenda del profesional (/mi-agenda.html)
//  · app=panel  -> Panel del dueño (/app.html)
// Solo lee datos públicos del negocio (nombre, logo, color). Sin b o sin logo,
// devuelve el manifest de siempre con el ícono de Reservia.
const { supabaseGet } = require('./_lib/resend');

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const HEX = /^#[0-9a-f]{6}$/i;
const APPS = {
  agenda: { url: '/mi-agenda.html', sufijo: 'Agenda', icono: '/mi-agenda-icon', nombre: 'Mi Agenda' },
  panel: { url: '/app.html', sufijo: 'Panel', icono: '/panel-icon', nombre: 'Reservia' }
};

module.exports = async function handler(req, res) {
  const q = req.query || {};
  const app = APPS[q.app] || APPS.agenda;
  let negocio = null;
  if (q.b && UUID.test(String(q.b))) {
    try {
      const filas = await supabaseGet(`barberias?id=eq.${q.b}&select=nombre,logo_url,color_marca,color_fondo_marca,modo_tema`);
      negocio = filas[0] || null;
    } catch (e) { negocio = null; }
  }
  const logo = negocio && /^https:\/\//i.test(negocio.logo_url || '') ? negocio.logo_url : null;
  const nombre = (negocio && negocio.nombre) ? String(negocio.nombre).slice(0, 40) : null;
  const fondo = negocio && HEX.test(negocio.color_fondo_marca || '') ? negocio.color_fondo_marca
              : (negocio && negocio.modo_tema === 'claro' ? '#ffffff' : '#08090d');
  const iconos = logo
    ? [{ src: logo, sizes: '192x192', type: 'image/png', purpose: 'any' },
       { src: logo, sizes: '512x512', type: 'image/png', purpose: 'any' }]
    : [{ src: app.icono + '-192.png', sizes: '192x192', type: 'image/png' },
       { src: app.icono + '-512.png', sizes: '512x512', type: 'image/png' }];
  res.setHeader('Content-Type', 'application/manifest+json; charset=utf-8');
  res.setHeader('Cache-Control', 'public, max-age=300');
  res.status(200).send(JSON.stringify({
    id: app.url + (q.b ? '?b=' + q.b : ''),
    name: nombre ? `${nombre} · ${app.sufijo}` : app.nombre,
    short_name: nombre ? nombre.slice(0, 12) : app.nombre,
    start_url: app.url,
    scope: app.url,
    display: 'standalone',
    orientation: 'portrait',
    background_color: fondo,
    theme_color: fondo,
    icons: iconos
  }));
};
