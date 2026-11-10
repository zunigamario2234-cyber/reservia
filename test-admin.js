// Panel de administración: acceso, solicitudes, activar Pro, encender/apagar plan.
// Requiere servidor estático en 8765:  python3 -m http.server 8765
const { chromium } = require('playwright');
const res = []; const ok = (n, c, d) => res.push((c ? 'OK    ' : 'FALLO ') + n + (c ? '' : '  -> ' + JSON.stringify(d)));
const stub = (esAdmin, conSesion) => `
window.__rpc=[];
window.__sol=[
 {id:'s1',created_at:'2026-11-10T20:00:00Z',nombre:'Ana Soto',negocio:'Salón <b>Alba</b>',email:'ana@alba.cl',whatsapp:'+56 9 1234 5678',profesionales:'3 a 5',mensaje:'<img src=x onerror=window.__xss=1>',origen:'landing',barberia_id:null,estado:'nueva',notas:null,plan_actual:null},
 {id:'s2',created_at:'2026-11-09T20:00:00Z',nombre:'Luis',negocio:'Norte',email:'luis@norte.cl',whatsapp:'+56911112222',origen:'registro',barberia_id:'b2',estado:'pagada',notas:'ok',plan_actual:'free'},
 {id:'s3',created_at:'2026-11-08T20:00:00Z',nombre:'Eva',negocio:'Vieja',email:'e@v.cl',whatsapp:'+56933334444',origen:'landing',barberia_id:'b3',estado:'activada',notas:'',plan_actual:'pro'}];
window.__neg=[{id:'b1',nombre:'Alba',email:'ana@alba.cl',plan:'free',created_at:'2026-11-10T21:00:00Z'},{id:'b2',nombre:'Norte',email:'luis@norte.cl',plan:'free',created_at:'2026-11-01T21:00:00Z'},{id:'b3',nombre:'Vieja',email:'e@v.cl',plan:'pro',created_at:'2026-10-01T21:00:00Z'}];
window.SUPABASE_URL='x';window.SUPABASE_KEY='y';
window.supabase={createClient:()=>({auth:{
  getSession:async()=>({data:{session:${conSesion}?{user:{id:'u'}}:null}}),
  signInWithPassword:async()=>({error:null}),signOut:async()=>({})},
  rpc:async(n,a)=>{window.__rpc.push([n,a]);
   if(n==='es_admin')return{data:${esAdmin}};
   if(n==='admin_solicitudes')return{data:window.__sol};
   if(n==='admin_negocios')return{data:window.__neg};
   return{data:null,error:null}}})};`;
(async () => {
  const b = await chromium.launch();
  async function abrir(esAdmin, conSesion) {
    const p = await b.newPage({ viewport: { width: 1000, height: 900 } });
    p.errs = []; p.on('pageerror', e => p.errs.push(e.message));
    await p.route('**/cdn.jsdelivr.net/**', r => r.fulfill({ contentType: 'application/javascript', body: stub(esAdmin, conSesion) }));
    await p.route('**/supabase-config.js', r => r.fulfill({ contentType: 'application/javascript', body: '' }));
    await p.goto('http://localhost:8765/admin.html'); await p.waitForTimeout(400);
    return p;
  }
  const rpcs = p => p.evaluate(() => window.__rpc.map(x => x[0] + ':' + JSON.stringify(x[1])));
  const vis = (p, id) => p.evaluate(i => !document.getElementById(i).hidden, id);

  let p = await abrir(false, false);
  ok('sin sesión muestra el ingreso, no el panel', await vis(p, 'v-login') && !(await vis(p, 'v-panel')), null);
  await p.close();
  p = await abrir(false, true);
  ok('una cuenta que no es admin no ve el panel y se le explica', !(await vis(p, 'v-panel')) && /no es de administrador/.test(await p.textContent('#l-err')), null);
  ok('a una cuenta común no se le piden datos', !(await rpcs(p)).some(x => x.startsWith('admin_')), await rpcs(p));
  await p.close();

  p = await abrir(true, true);
  ok('el admin ve el panel', await vis(p, 'v-panel'), null);
  const cards = await p.$$eval('#lista-sol .card', e => e.length);
  ok('«Por atender» muestra nueva + pagada (no la activada)', cards === 2, cards);
  ok('no ejecuta HTML escrito por quien solicita', !(await p.evaluate(() => window.__xss)) && (await p.textContent('#lista-sol')).includes('<b>Alba</b>'), null);
  ok('trae el correo sugerido para vincular', await p.$eval('#lista-sol select', s => s.value) === 'b1', null);
  await p.screenshot({ path: '/tmp/admin-solicitudes.png' });

  // Activar Pro en la solicitud de la landing: vincula y enciende.
  await p.click('#lista-sol .card:nth-child(1) .btn.pri'); await p.waitForTimeout(300);
  let r = await rpcs(p);
  ok('«Activar Pro» enciende el plan del negocio vinculado', r.includes('admin_set_plan:{"p_barberia":"b1","p_plan":"pro"}'), r);
  ok('y marca la solicitud como activada con el negocio', r.some(x => x.startsWith('admin_actualizar_solicitud:') && x.includes('"p_estado":"activada"') && x.includes('"p_barberia":"b1"')), r);

  // Sin negocio vinculado no activa.
  await p.evaluate(() => { document.querySelector('#lista-sol select').value = ''; window.__rpc = []; });
  await p.click('#lista-sol .card:nth-child(1) .btn.pri'); await p.waitForTimeout(150);
  ok('sin negocio vinculado no activa nada y avisa', (await rpcs(p)).length === 0 && /Vincula/.test(await p.textContent('#aviso')), await rpcs(p));

  // Pagada con nota
  await p.evaluate(() => { window.__rpc = []; });
  await p.fill('#lista-sol .card:nth-child(2) textarea', 'transferencia 10/11');
  await p.click('#lista-sol .card:nth-child(2) .btn:has-text("Contactada")'); await p.waitForTimeout(200);
  r = await rpcs(p);
  ok('cambia a «En progreso» guardando la nota', r.some(x => x.includes('"p_estado":"contactada"') && x.includes('transferencia 10/11')), r);

  // Descartar pide confirmación y conserva lo escrito.
  await p.evaluate(() => { window.__rpc = []; });
  await p.fill('#lista-sol .card:nth-child(2) textarea', 'no pagó');
  await p.click('#lista-sol .card:nth-child(2) .btn.peli'); await p.waitForTimeout(100);
  ok('descartar pide un segundo toque', (await rpcs(p)).length === 0 && /Confirmar/.test(await p.textContent('#lista-sol .card:nth-child(2) .btn.peli')), null);
  ok('el segundo toque no borra la nota escrita', await p.inputValue('#lista-sol .card:nth-child(2) textarea') === 'no pagó', null);
  await p.click('#lista-sol .card:nth-child(2) .btn.peli'); await p.waitForTimeout(200);
  ok('confirmado, descarta sin tocar el plan', (await rpcs(p)).some(x => x.includes('"p_estado":"descartada"')) && !(await rpcs(p)).some(x => x.startsWith('admin_set_plan')), await rpcs(p));

  // Negocios: interruptor
  await p.click('[data-vista=negocios]'); await p.waitForTimeout(100);
  ok('lista los negocios con su interruptor Pro', (await p.$$eval('#lista-neg [role=switch]', e => e.map(x => x.getAttribute('aria-checked')))).join() === 'false,false,true', null);
  await p.screenshot({ path: '/tmp/admin-negocios.png' });
  await p.evaluate(() => { window.__rpc = []; });
  await p.click('#lista-neg .card:nth-child(2) [role=switch]'); await p.waitForTimeout(200);
  ok('encender: pasa a Pro', (await rpcs(p)).includes('admin_set_plan:{"p_barberia":"b2","p_plan":"pro"}'), await rpcs(p));
  await p.evaluate(() => { window.__rpc = []; });
  await p.click('#lista-neg .card:nth-child(3) [role=switch]'); await p.waitForTimeout(100);
  ok('apagar pide confirmar antes', (await rpcs(p)).length === 0, await rpcs(p));
  await p.click('#lista-neg .card:nth-child(3) [role=switch]'); await p.waitForTimeout(200);
  ok('apagar confirmado: vuelve a Free', (await rpcs(p)).includes('admin_set_plan:{"p_barberia":"b3","p_plan":"free"}'), await rpcs(p));
  await p.fill('#buscar', 'norte');
  ok('el buscador filtra negocios', await p.$$eval('#lista-neg .card', e => e.length) === 1, null);
  ok('sin errores de página', p.errs.length === 0, p.errs);
  await p.setViewportSize({ width: 390, height: 800 });
  const ov = await p.evaluate(() => document.documentElement.scrollWidth <= document.documentElement.clientWidth);
  ok('en celular no hay scroll lateral', ov, null);
  await b.close();
  console.log(res.join('\n')); console.log(res.filter(x => x.startsWith('FALLO')).length + ' fallos de ' + res.length);
})();
