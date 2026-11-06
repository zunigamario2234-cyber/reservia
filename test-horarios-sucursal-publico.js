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
  const t=T(multi); t.horario_negocio=[{barberia_id:BID,sucursal_id:S1,dia_semana:1,hora_apertura:'09:00',hora_cierre:'13:00',cerrado:false},{barberia_id:BID,sucursal_id:S2,dia_semana:1,hora_apertura:'12:00',hora_cierre:'20:00',cerrado:false},{barberia_id:BID,sucursal_id:S1,dia_semana:2,hora_apertura:'09:00',hora_cierre:'13:00',cerrado:false},{barberia_id:BID,sucursal_id:S2,dia_semana:2,hora_apertura:'09:00',hora_cierre:'13:00',cerrado:true}];
  await p.route(/^https:\/\/(cdn\.jsdelivr\.net|cdnjs\.cloudflare\.com|unpkg\.com)\//, r=>{const u=r.request().url();r.fulfill({path:/supabase-js/.test(u)?'/tmp/cdn/node_modules/@supabase/supabase-js/dist/umd/supabase.js':'/dev/null',contentType:'application/javascript'});});
  await p.route(/localhost:8765\/reservar\/[^.]*$/, r=>r.fulfill({status:200,contentType:'text/html',body:html}));
  await p.route(/supabase\.co\/(rest|auth)\//, r=>{const u=r.request().url();const tb=(u.match(/\/rest\/v1\/([a-z_]+)/)||[])[1]; reqs.push(decodeURIComponent(u.split('/rest/v1/')[1]||''));
    const v=t[tb]===undefined?[]:t[tb]; const acc=r.request().headers()['accept']||'';
    if(/pgrst\.object/.test(acc)) return r.fulfill({status:200,contentType:'application/json',body:JSON.stringify(Array.isArray(v)?v[0]:v)});
    r.fulfill({status:200,contentType:'application/json',body:JSON.stringify(Array.isArray(v)?v:[v])});});
  await p.goto(url); await p.waitForTimeout(900); return {p,b,errs,reqs}; }
(async()=>{
 const t=await abrir('http://localhost:8765/reservar/essentials-studio',true);
 await t.p.evaluate(()=>selSucursal('50000000-0000-4000-8000-000000000001')); 
 let v=await t.p.evaluate(()=>{SEL.profesional=B.profesionals.find(b=>b.id==='p1'); return {lun:slotsParaDia(1),cierre:cierreDelDia(1),mar:slotsParaDia(2).length}});
 ok('Centro: lunes de 9 a 13',v.lun[0]==='09:00'&&v.cierre===780&&v.mar>0,v);
 await t.p.evaluate(()=>selSucursal('50000000-0000-4000-8000-000000000002'));
 v=await t.p.evaluate(()=>{SEL.profesional=B.profesionals.find(b=>b.id==='p2'); return {lun:slotsParaDia(1),cierre:cierreDelDia(1),mar:slotsParaDia(2).length}});
 ok('Norte: lunes de 12 a 20 y martes cerrado',v.lun[0]==='12:00'&&v.cierre===1200&&v.mar===0,v);
 ok('sin errores',t.errs.length===0,t.errs); await t.b.close();
 console.log(res.join('\n')); console.log(res.filter(x=>x.startsWith('FALLO')).length+' fallos de '+res.length);
})();
