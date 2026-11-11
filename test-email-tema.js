// Los correos siguen el tema de cada negocio (tema.js), con contraste legible.
process.env.SUPABASE_SERVICE_ROLE_KEY='svc'; process.env.RESEND_API_KEY='rk';
const R = require('./api/_lib/resend'); const T = require('./tema.js');
const res=[]; const ok=(n,c,d)=>res.push((c?'OK    ':'FALLO ')+n+(c?'':'  -> '+JSON.stringify(d)));
const contenido = `<p style="margin:0 0 12px;font-size:16px;color:#111">Hola Ana 👋</p>
<p style="margin:0 0 20px;font-size:14px;color:#444;line-height:1.6">Tu reserva</p>
<table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="background:#f4f4f7;border-radius:8px"><tr><td style="padding:16px;font-size:14px;color:#333">Corte</td></tr></table>
<table><tr><td style="border-radius:8px;background:linear-gradient(135deg,#7c6af7,#5b8def)"><a href="x" style="display:inline-block;color:#fff;text-decoration:none">Botón</a></td></tr></table>
<p style="font-size:12px;color:#999">pie</p><p style="color:#e0a850">aviso</p>`;
const base = R.emailShell({ nombreNegocio:'Mi Salón', contenidoHtml:contenido, logoUrl:'https://x.cl/l.png' });
const sinTema = R.emailShell({ nombreNegocio:'Mi Salón', contenidoHtml:contenido, logoUrl:'https://x.cl/l.png', negocio:{ nombre:'x', color_marca:null, modo_tema:'auto', color_fondo_marca:null } });
ok('sin tema el correo es idéntico al de siempre', base===sinTema, null);
ok('sin tema conserva el degradado y los grises', /linear-gradient\(135deg,#7c6af7/.test(sinTema)&&/color:#111/.test(sinTema), null);

const casos = [
 ['solo color de marca (oscuro)', { color_marca:'#2F6B4F', modo_tema:'oscuro' }],
 ['modo claro con color',         { color_marca:'#8A3B62', modo_tema:'claro' }],
 ['fondo verde + acento amarillo',{ color_marca:'#F2C230', modo_tema:'oscuro', color_fondo_marca:'#2F6B4F' }],
 ['fondo gris + acento rojo',     { color_marca:'#C0392B', modo_tema:'claro', color_fondo_marca:'#8A8D91' }],
 ['fondo crema sin acento',       { color_marca:null, modo_tema:'oscuro', color_fondo_marca:'#E8DCC4' }],
 ['fondo negro + acento blanco',  { color_marca:'#FFFFFF', modo_tema:'oscuro', color_fondo_marca:'#111111' }],
];
for (const [nombre, n] of casos) {
  const h = R.emailShell({ nombreNegocio:'Mi Salón', contenidoHtml:contenido, logoUrl:'https://x.cl/l.png', negocio:n });
  const t = R.temaDeNegocio(n);
  ok(nombre+': usa el fondo y la tarjeta del tema', t && h.includes('background:'+t['--fondo']) && h.includes('background:'+t['--tarjeta']), null);
  ok(nombre+': el botón y el encabezado llevan el acento', t && !/#7c6af7|#5b8def/i.test(h) && h.includes(t['--acento']), null);
  ok(nombre+': no queda ningún gris fijo del correo viejo', !/color:#(111|444|333|999)\b/i.test(h) && !/#f4f4f7/i.test(h.replace(/<body[^>]*>/,'')), null);
  // contraste texto/superficie
  const caja = T.modoDeFondoMarca(t['--fondo'])==='oscuro' ? t['--portada-fondo'] : t['--fondo'];
  const pares = [[t['--texto'],t['--tarjeta']],[t['--texto-suave'],caja],[t['--texto-debil'],t['--tarjeta']],[t['--texto-sobre-acento'],t['--acento']]];
  const malos = pares.filter(([a,b])=>T.contrasteHex(a,b)<4.5).map(([a,b])=>a+'/'+b+' '+T.contrasteHex(a,b).toFixed(1));
  ok(nombre+': el texto se lee (≥4,5:1)', malos.length===0, malos);
}
ok('el tema roto no tumba el correo', (()=>{ try { return /Mi Salón/.test(R.emailShell({nombreNegocio:'Mi Salón',contenidoHtml:'<p>x</p>',negocio:{color_marca:'rojo',color_fondo_marca:123}})); } catch(e){ return false; } })(), null);

// negocioParaEmail: reintenta sin la columna nueva
(async()=>{
  const real=global.fetch; const urls=[];
  global.fetch=async(u)=>{ urls.push(String(u)); if(/color_fondo_marca/.test(u)) return {ok:false,status:400,text:async()=>'column does not exist'}; return {ok:true,json:async()=>[{nombre:'N'}]}; };
  const err=console.error; console.error=()=>{};
  let r; try { r = await R.negocioParaEmail('id=eq.1','nombre,logo_url'); } finally { global.fetch=real; console.error=err; }
  ok('sin la columna color_fondo_marca reintenta y el correo sale', r&&r[0].nombre==='N'&&urls.length===2&&!/color_fondo_marca/.test(urls[1]), urls);
  console.log(res.join('\n')); console.log(res.filter(x=>x.startsWith('FALLO')).length+' fallos de '+res.length);
})();
