// Links cortos /reservar/<negocio>/<profesional> y elección de sucursal en la página pública.
const { chromium } = require('playwright'); const fs=require('fs');
const BID='b0000000-0000-4000-8000-000000000001', S1='50000000-0000-4000-8000-000000000001', S2='50000000-0000-4000-8000-000000000002';
const res=[]; const ok=(n,c,x)=>res.push((c?'OK    ':'FALLO ')+n+(c?'':'  -> '+JSON.stringify(x)));
const html=fs.readFileSync('reservar.html','utf8');
function T(multi){ return {
  barberias:{id:BID,nombre:'Essentials Studio',slug:'essentials-studio',modo_tema:'oscuro',intervalo_min:30},
  servicios:[{id:'sv1',barberia_id:BID,nombre:'Corte',precio:12000,duracion_min:30,activo:true},{id:'sv2',barberia_id:BID,nombre:'Barba',precio:8000,duracion_min:20,activo:true}],
  barberos:[{id:'p1',barberia_id:BID,nombre:'Felipe',slug:'felipe',activo:true,sucursal_id:S1},{id:'p2',barberia_id:BID,nombre:'Mario',slug:'mario',activo:true,sucursal_id:multi?S2:S1}],
  barbero_servicios:[{barberia_id:BID,barbero_id:'p1',servicio_id:'sv1',activo:true},{barberia_id:BID,barbero_id:'p2',servicio_id:'sv1',activo:true},{barberia_id:BID,barbero_id:'p2',servicio_id:'sv2',activo:true}],
  sucursales:multi?[{id:S1,barberia_id:BID,nombre:'Centro',slug:'centro',direccion:'Av. 1',activa:true,orden:0},{id:S2,barberia_id:BID,nombre:'Norte',slug:'norte',direccion:'Av. 2',activa:true,orden:1}]:[{id:S1,barberia_id:BID,nombre:'Principal',slug:'principal',activa:true,orden:0}] }; }
async function abrir(url,multi){
  const b=await chromium.launch(); const p=await b.newPage({viewport:{width:390,height:900}}); const errs=[],reqs=[]; p.on('pageerror',e=>errs.push(e.message));
  const t=T(multi);
  await p.route(/^https:\/\/(cdn\.jsdelivr\.net|cdnjs\.cloudflare\.com|unpkg\.com)\//, r=>{const u=r.request().url();r.fulfill({path:/supabase-js/.test(u)?'/tmp/cdn/node_modules/@supabase/supabase-js/dist/umd/supabase.js':'/dev/null',contentType:'application/javascript'});});
  await p.route(/localhost:8765\/reservar\/[^.]*$/, r=>r.fulfill({status:200,contentType:'text/html',body:html}));
  await p.route(/supabase\.co\/(rest|auth)\//, r=>{const u=r.request().url();const tb=(u.match(/\/rest\/v1\/([a-z_]+)/)||[])[1]; reqs.push(decodeURIComponent(u.split('/rest/v1/')[1]||''));
    const v=t[tb]===undefined?[]:t[tb]; const acc=r.request().headers()['accept']||'';
    if(/pgrst\.object/.test(acc)) return r.fulfill({status:200,contentType:'application/json',body:JSON.stringify(Array.isArray(v)?v[0]:v)});
    r.fulfill({status:200,contentType:'application/json',body:JSON.stringify(Array.isArray(v)?v:[v])});});
  await p.goto(url); await p.waitForTimeout(900); return {p,b,errs,reqs}; }
(async()=>{
 // 1. link del negocio
 let t=await abrir('http://localhost:8765/reservar/essentials-studio',false);
 ok('resuelve el negocio por su nombre en la ruta',t.reqs.some(r=>/^barberias\?select=id&slug=eq\.essentials-studio/.test(r)),t.reqs.slice(0,3));
 ok('carga servicios y profesionales del negocio',await t.p.evaluate(()=>B.servicios.length===2&&B.profesionals.length===2));
 ok('sin errores de página',t.errs.length===0,t.errs); await t.b.close();
 // 2. link del profesional
 t=await abrir('http://localhost:8765/reservar/essentials-studio/felipe',false);
 const pr=await t.p.evaluate(()=>({sel:SEL.profesional&&SEL.profesional.nombre,banner:document.getElementById('prof-preselec').innerText}));
 ok('preselecciona al profesional del link',pr.sel==='Felipe'&&/Felipe/.test(pr.banner),pr);
 await t.b.close();
 // 3. mayúsculas y tildes en la ruta no rompen
 t=await abrir('http://localhost:8765/reservar/Essentials-Studio/FELIPE',false);
 ok('la ruta no distingue mayúsculas',await t.p.evaluate(()=>SEL.profesional&&SEL.profesional.nombre)==='Felipe'); await t.b.close();
 // 4. link viejo sigue valiendo
 t=await abrir('http://localhost:8765/reservar.html?id='+BID+'&profesional=p2',false);
 ok('el link largo antiguo sigue funcionando',await t.p.evaluate(()=>SEL.profesional&&SEL.profesional.nombre)==='Mario'); await t.b.close();
 // 5. una sola sucursal: no se ve selector
 t=await abrir('http://localhost:8765/reservar/essentials-studio',false);
 ok('con una sucursal no aparece el selector',await t.p.evaluate(()=>document.getElementById('suc-picker').style.display==='none')); await t.b.close();
 // 6. dos sucursales: hay que elegir
 t=await abrir('http://localhost:8765/reservar/essentials-studio',true);
 let v=await t.p.evaluate(()=>({pick:document.getElementById('suc-picker').innerText,srv:document.getElementById('lista-servicios').innerText}));
 ok('ofrece elegir sucursal',/Centro/.test(v.pick)&&/Norte/.test(v.pick),v);
 ok('no muestra servicios hasta elegir',/Elige primero la sucursal/.test(v.srv),v);
 await t.p.evaluate(()=>selSucursal('50000000-0000-4000-8000-000000000002'));
 v=await t.p.evaluate(()=>({srv:document.getElementById('lista-servicios').innerText,pros:profesionalesDeSucursal().map(b=>b.nombre)}));
 ok('Norte: solo el profesional de esa sucursal',JSON.stringify(v.pros)==='["Mario"]',v);
 ok('Norte: servicios que ese profesional hace',/Corte/.test(v.srv)&&/Barba/.test(v.srv),v);
 await t.p.evaluate(()=>selSucursal('50000000-0000-4000-8000-000000000001'));
 v=await t.p.evaluate(()=>({srv:document.getElementById('lista-servicios').innerText,pros:profesionalesDeSucursal().map(b=>b.nombre)}));
 ok('Centro: solo Felipe y sin Barba (nadie allí la hace)',JSON.stringify(v.pros)==='["Felipe"]'&&/Corte/.test(v.srv)&&!/Barba/.test(v.srv),v);
 ok('sin errores de página',t.errs.length===0,t.errs); await t.b.close();
 // 7. link de sucursal por slug y link de profesional de otra sucursal
 t=await abrir('http://localhost:8765/reservar/essentials-studio?sucursal=norte',true);
 v=await t.p.evaluate(()=>({suc:SEL.sucursal,lock:B.sucLocked,txt:document.getElementById('suc-picker').innerText}));
 ok('?sucursal=slug la fija y muestra su nombre',v.suc==='50000000-0000-4000-8000-000000000002'&&v.lock&&/Norte/.test(v.txt),v); await t.b.close();
 t=await abrir('http://localhost:8765/reservar/essentials-studio/mario',true);
 ok('link de un profesional fija su sucursal',await t.p.evaluate(()=>SEL.sucursal)==='50000000-0000-4000-8000-000000000002'); await t.b.close();
 console.log(res.join('\n')); console.log(res.filter(x=>x.startsWith('FALLO')).length+' fallos de '+res.length);
})();
