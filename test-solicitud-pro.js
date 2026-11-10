// Solicitud del plan Pro: endpoint (con fetch simulado), landing y registro.
process.env.SUPABASE_SERVICE_ROLE_KEY = 'svc'; process.env.RESEND_API_KEY = 'rk';
// Requiere un servidor estático en el puerto 8765:  python3 -m http.server 8765
const { chromium } = require('playwright');
const res = []; const ok = (n, c, d) => res.push((c ? 'OK    ' : 'FALLO ') + n + (c ? '' : '  -> ' + JSON.stringify(d)));

async function llamar(handler, { method = 'POST', body, recientes = [], emailFalla = false, destino = 'duenio@ejemplo.cl' }) {
  const calls = []; const real = global.fetch;
  process.env.SUPABASE_SERVICE_ROLE_KEY = 'svc'; process.env.RESEND_API_KEY = 'rk';
  if (destino) process.env.SOLICITUDES_EMAIL = destino; else delete process.env.SOLICITUDES_EMAIL;
  global.fetch = async (url, opt = {}) => {
    calls.push({ url: String(url), method: opt.method || 'GET', body: opt.body ? JSON.parse(opt.body) : null });
    if (/resend\.com/.test(url)) return emailFalla ? { ok: false, status: 500, text: async () => 'x' } : { ok: true, json: async () => ({}) };
    if ((opt.method || 'GET') === 'GET') return { ok: true, json: async () => recientes };
    return { ok: true, json: async () => [{ id: 'n1' }] };
  };
  let status = 200, out = null;
  const r = { setHeader() {}, status(s) { status = s; return r; }, json(o) { out = o; } };
  const err = console.error; console.error = () => {};
  try { await handler({ method, body }, r); } finally { global.fetch = real; console.error = err; }
  return { status, out, calls };
}

(async () => {
  const handler = require('./api/solicitar-plan-pro.js');
  const base = { nombre: 'Ana Soto', negocio: 'Salón Alba', email: 'Ana@Alba.cl', whatsapp: '+56 9 1234 5678', profesionales: '3 a 5', mensaje: '<b>hola</b>', origen: 'landing' };

  let r = await llamar(handler, { method: 'GET' });
  ok('solo acepta POST', r.status === 405, r);
  r = await llamar(handler, { body: { ...base, web: 'spam' } });
  ok('la trampa responde OK sin guardar ni enviar', r.status === 200 && r.calls.length === 0, r);
  r = await llamar(handler, { body: { ...base, email: 'no-es-correo' } });
  ok('correo inválido → 400', r.status === 400 && r.calls.length === 0, r);
  r = await llamar(handler, { body: { ...base, whatsapp: '123' } });
  ok('WhatsApp inválido → 400', r.status === 400, r);
  r = await llamar(handler, { body: { ...base, nombre: '' } });
  ok('sin nombre → 400', r.status === 400, r);

  r = await llamar(handler, { body: { ...base, barberiaId: 'no-uuid' } });
  const ins = r.calls.find(c => c.method === 'POST' && /solicitudes_plan/.test(c.url));
  const mail = r.calls.find(c => /resend\.com/.test(c.url));
  ok('guarda la solicitud con el correo en minúsculas y sin barberia_id inválido', r.status === 200 && ins && ins.body.email === 'ana@alba.cl' && ins.body.barberia_id === null, ins);
  ok('no guarda el campo trampa', ins && !('web' in ins.body), ins);
  ok('el aviso va solo a SOLICITUDES_EMAIL y responde al solicitante', mail && mail.body.to.length === 1 && mail.body.to[0] === 'duenio@ejemplo.cl' && mail.body.reply_to === 'ana@alba.cl', mail);
  ok('el HTML del correo escapa lo que escribió la persona', mail && !/<b>hola<\/b>/.test(mail.body.html) && /&lt;b&gt;hola/.test(mail.body.html), mail && mail.body.html.slice(0, 80));
  ok('no se manda ningún correo al solicitante', r.calls.filter(c => /resend\.com/.test(c.url)).length === 1, r.calls.length);

  const id = '123e4567-e89b-12d3-a456-426614174000';
  r = await llamar(handler, { body: { ...base, origen: 'registro', barberiaId: id } });
  const ins2 = r.calls.find(c => c.method === 'POST' && /solicitudes_plan/.test(c.url));
  const mail2 = r.calls.find(c => /resend\.com/.test(c.url));
  ok('desde el registro guarda el id del negocio y lo muestra en el correo', ins2.body.barberia_id === id && ins2.body.origen === 'registro' && mail2.body.html.includes(id), ins2);

  r = await llamar(handler, { body: base, recientes: [{ id: 'x', email: 'ana@alba.cl' }] });
  ok('el mismo correo dentro de la hora no vuelve a avisar', r.status === 200 && r.out.repetida && !r.calls.some(c => c.method === 'POST'), r);
  r = await llamar(handler, { body: base, recientes: Array.from({ length: 31 }, (_, i) => ({ id: i, email: 'o' + i + '@x.cl' })) });
  ok('más de 30 en una hora → 429', r.status === 429, r);
  r = await llamar(handler, { body: base, emailFalla: true });
  ok('si el correo falla, igual queda guardada y responde OK', r.status === 200 && r.calls.some(c => c.method === 'POST' && /solicitudes_plan/.test(c.url)), r);
  r = await llamar(handler, { body: base, destino: '' });
  ok('sin SOLICITUDES_EMAIL guarda y responde OK', r.status === 200 && !r.calls.some(c => /resend\.com/.test(c.url)), r);

  // ── Landing ──
  const b = await chromium.launch();
  const stubSb = `window.supabase={createClient:()=>({auth:{getSession:async()=>({data:{session:null}})},from:()=>({select:()=>({eq:()=>({maybeSingle:async()=>({data:null})})})})})};`;
  for (const [nombre, w] of [['escritorio', 1360], ['celular', 390]]) {
    const p = await b.newPage({ viewport: { width: w, height: 860 } });
    const errs = []; p.on('pageerror', e => errs.push(e.message));
    await p.route('**/cdn.jsdelivr.net/**', r => r.fulfill({ contentType: 'application/javascript', body: stubSb }));
    await p.goto('http://localhost:8765/index.html'); await p.waitForTimeout(300);
    const ov = await p.evaluate(() => ({ sw: document.documentElement.scrollWidth, cw: document.documentElement.clientWidth }));
    ok('landing en ' + nombre + ' sin scroll horizontal', ov.sw <= ov.cw, ov);
    ok('landing en ' + nombre + ' sin errores de página', errs.length === 0, errs);
    await p.close();
  }
  const p = await b.newPage({ viewport: { width: 1280, height: 900 } });
  const errs = []; p.on('pageerror', e => errs.push(e.message));
  await p.route('**/cdn.jsdelivr.net/**', r => r.fulfill({ contentType: 'application/javascript', body: stubSb }));
  let envio = null, modo = 'ok';
  await p.route('**/api/solicitar-plan-pro', async r => {
    envio = JSON.parse(r.request().postData());
    if (modo === 'ok') await r.fulfill({ contentType: 'application/json', body: '{"ok":true}' });
    else await r.fulfill({ status: 500, contentType: 'application/json', body: '{"ok":false,"error":"No pudimos enviar la solicitud. Inténtalo de nuevo."}' });
  });
  await p.goto('http://localhost:8765/index.html'); await p.waitForTimeout(300);
  await p.click('#abrir-pro'); await p.waitForTimeout(150);
  ok('«Solicitar plan Pro» abre el formulario', await p.evaluate(() => document.getElementById('dlg-pro').open), null);
  await p.click('#p-enviar');
  const e0 = await p.evaluate(() => document.getElementById('p-err').textContent);
  ok('no envía si faltan datos y lo explica', envio === null && /nombre/i.test(e0), e0);
  await p.fill('#p-nombre', 'Ana Soto'); await p.fill('#p-negocio', 'Salón Alba'); await p.fill('#p-wsp', '+56 9 1234 5678'); await p.fill('#p-email', 'ana@alba.cl');
  await p.screenshot({ path: '/tmp/dialogo-pro.png' });
  modo = 'error'; await p.click('#p-enviar'); await p.waitForTimeout(250);
  const e1 = await p.evaluate(() => ({ t: document.getElementById('p-err').textContent, v: getComputedStyle(document.getElementById('p-err')).display, form: document.getElementById('form-pro').style.display }));
  ok('si el servidor falla, muestra el error y deja reintentar', /No pudimos/.test(e1.t) && e1.v === 'block' && e1.form !== 'none', e1);
  modo = 'ok'; await p.click('#p-enviar'); await p.waitForTimeout(250);
  const okv = await p.evaluate(() => ({ ok: getComputedStyle(document.getElementById('p-ok')).display, form: document.getElementById('form-pro').style.display }));
  ok('envío correcto → pantalla de confirmación', okv.ok === 'block' && okv.form === 'none', okv);
  ok('manda los datos del formulario y el origen', envio && envio.nombre === 'Ana Soto' && envio.negocio === 'Salón Alba' && envio.email === 'ana@alba.cl' && envio.origen === 'landing' && envio.web === '', envio);
  await p.click('#p-listo'); await p.waitForTimeout(100);
  ok('«Listo» cierra el diálogo', await p.evaluate(() => !document.getElementById('dlg-pro').open), null);
  // marca
  await p.click('.logos button[data-m=tico]');
  const m = await p.evaluate(() => ({ bg: getComputedStyle(document.getElementById('demo')).getPropertyValue('--m-bg').trim(), n: document.getElementById('demo-nombre').textContent }));
  ok('el ejemplo de marca cambia a modo oscuro con logo blanco', m.bg === '#15181D' && m.n === 'Tico Barber', m);
  ok('landing sin errores de página (con interacciones)', errs.length === 0, errs);
  await p.close();

  // ── Registro: Pro ya no se asigna desde el navegador ──
  async function registrar(plan) {
    const q = await b.newPage({ viewport: { width: 1000, height: 900 } });
    const errs2 = []; q.on('pageerror', e => errs2.push(e.message));
    const stub = `window.__ins=[];window.supabase={createClient:()=>({auth:{getSession:async()=>({data:{session:null}}),signUp:async()=>({data:{user:{id:'u1'}},error:null})},from:(t)=>{const q={insert:(v)=>{window.__ins.push([t,v]);return q},select:()=>q,single:async()=>({data:{id:'b1'},error:null}),then:(a)=>a({error:null})};return q}})};`;
    await q.route('**/cdn.jsdelivr.net/**', r => r.fulfill({ contentType: 'application/javascript', body: stub }));
    let pedido = null;
    await q.route('**/api/solicitar-plan-pro', async r => { pedido = JSON.parse(r.request().postData()); await r.fulfill({ contentType: 'application/json', body: '{"ok":true}' }); });
    await q.goto('http://localhost:8765/ingresar.html#registro'); await q.waitForTimeout(250);
    await q.fill('#r-neg', 'Salón Alba'); await q.fill('#r-wsp', '+56912345678'); await q.evaluate(() => s1());
    await q.fill('#r-nombre', 'Ana Soto'); await q.fill('#r-email', 'ana@alba.cl'); await q.fill('#r-pass', 'secreta1'); await q.fill('#r-pass2', 'secreta1'); await q.evaluate(() => s2());
    if (plan === 'pro') await q.click('.plan:nth-child(2)');
    await q.evaluate(() => { window.location.replace = () => {}; });
    await q.click('#btn-reg'); await q.waitForTimeout(400);
    const barb = await q.evaluate(() => (window.__ins.find(x => x[0] === 'barberias') || [])[1]);
    await q.close();
    return { barb, pedido, errs2 };
  }
  let g = await registrar('free');
  ok('registro Free: cuenta Free y sin solicitud', g.barb && g.barb.plan === 'free' && g.pedido === null && g.errs2.length === 0, g);
  g = await registrar('pro');
  ok('registro Pro: la cuenta nace Free (no se autoasigna Pro)', g.barb && g.barb.plan === 'free', g.barb);
  ok('registro Pro: se envía la solicitud con el id del negocio', g.pedido && g.pedido.origen === 'registro' && g.pedido.barberiaId === 'b1' && g.pedido.email === 'ana@alba.cl', g.pedido);
  await b.close();
  console.log(res.join('\n')); console.log(res.filter(x => x.startsWith('FALLO')).length + ' fallos de ' + res.length);
})();
