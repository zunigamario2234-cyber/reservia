// Prueba e2e del Club: modificar una reserva (sin poder cancelarla) y del
// correo a los profesionales. Corre con: node test-club-modificar.js
// (requiere un servidor estático en :8765 y playwright).
const { chromium } = require('playwright'); const fs = require('fs');
const BID='b0000000-0000-0000-0000-000000000001', CID='c0000000-0000-0000-0000-000000000001', RID='11111111-1111-1111-1111-111111111111';
const res=[]; const ok=(n,c,x)=>res.push((c?'OK    ':'FALLO ')+n+(c?'':'  -> '+JSON.stringify(x)));
(async()=>{
 const b=await chromium.launch(); const p=await b.newPage({viewport:{width:420,height:900}});
 const errs=[]; p.on('pageerror',e=>errs.push(e.message));
 const rpcs=[], posts=[];
 const manana=new Date(Date.now()+864e5*3).toLocaleDateString('en-CA',{timeZone:'America/Santiago'});
 await p.route(/^https:\/\/(cdn\.jsdelivr\.net|cdnjs\.cloudflare\.com|unpkg\.com)\//, r=>{const u=r.request().url(); const m=/supabase-js/.test(u)?'/tmp/cdn/node_modules/@supabase/supabase-js/dist/umd/supabase.js':null; return m&&fs.existsSync(m)?r.fulfill({status:200,contentType:'application/javascript',body:fs.readFileSync(m)}):r.fulfill({status:200,contentType:'application/javascript',body:''});});
 await p.route('**/api/avisar-modificacion-reserva',r=>{posts.push(JSON.parse(r.request().postData()));r.fulfill({status:200,contentType:'application/json',body:'{"ok":true}'});});
 await p.route('**/api/enviar-confirmacion',r=>r.fulfill({status:200,contentType:'application/json',body:'{"ok":true}'}));
 await p.route(/supabase\.co\/rest\//, async r=>{
  const req=r.request(), u=req.url(); const json=(o,st=200)=>r.fulfill({status:st,contentType:'application/json',headers:{'content-range':'0-0/1'},body:JSON.stringify(o)});
  const t=(u.match(/\/rest\/v1\/(?:rpc\/)?([a-z_]+)/)||[])[1];
  if(/\/rest\/v1\/rpc\//.test(u)){ const body=req.postData()?JSON.parse(req.postData()):{}; rpcs.push({n:t,body});
   if(t==='get_club_vip_publico') return json([{ok:true,cliente_id:CID,nombre:'Matías',visitas:3,nivel:null,barberia:{id:BID,nombre:'Essentials',whatsapp:'+56912345678'}}]);
   if(t==='get_proximas_reservas_club') return json([{id:RID,fecha:manana,hora:'10:00:00',servicio:'Corte',profesional:'MARIO'}]);
   if(t==='modificar_reserva_club') return json(RID);
   return json([]); }
  const T={servicios:[{id:'s1',barberia_id:BID,nombre:'Corte',precio:10000,duracion_min:30,activo:true},{id:'s2',barberia_id:BID,nombre:'Barba',precio:8000,duracion_min:30,activo:true}],
   barberos:[{id:'p1',barberia_id:BID,nombre:'MARIO',activo:true},{id:'p2',barberia_id:BID,nombre:'FELIPE',activo:true}],
   horario_negocio:[],bloqueos_profesional:[],reservas_disponibilidad:[{hora:'10:00:00',barbero_nombre:'MARIO',duracion_min:30},{hora:'11:00:00',barbero_nombre:'MARIO',duracion_min:30}]};
  json(T[t]||[]); });
 await p.goto('http://localhost:8765/club.html?id='+BID+'&cliente='+CID);
 await p.waitForTimeout(1200);
 await p.evaluate(()=>cambiarTabTop('mis')); await p.waitForTimeout(500);
 const html=await p.innerHTML('#mis-reservas');
 ok('usa la RPC con id',rpcs.some(r=>r.n==='get_proximas_reservas_club'));
 ok('hay botón Modificar',/Modificar/.test(html));
 ok('NO hay botón de cancelar ni eliminar',!/cancelar|eliminar|anular|borrar/i.test(html),html.slice(0,300));
 await p.click('text=Modificar día, hora o profesional'); await p.waitForTimeout(900);
 ok('abre el flujo en modo modificar (banner)',await p.isVisible('#r-modo-modificar')&&/Modificando tu reserva/.test(await p.textContent('#r-modo-modificar')));
 ok('cae directo en Fecha y hora',await p.$eval('#r-sc-3',e=>e.classList.contains('active')));
 const mario10=await p.$$eval('#r-lista-horarios .horario-btn',a=>a.filter(x=>x.textContent.trim()==='10:00').map(x=>x.disabled));
 ok('su propio horario actual NO queda bloqueado',mario10[0]===false,mario10);
 const mario11=await p.$$eval('#r-lista-horarios .horario-btn',a=>a.filter(x=>x.textContent.trim()==='11:00').map(x=>x.disabled));
 ok('un horario ocupado por otra reserva sí queda bloqueado',mario11[0]===true,mario11);
 await p.click('#r-lista-horarios .horario-btn:text-is("12:00")'); await p.click('#r-btn-s3'); await p.waitForTimeout(200);
 ok('el resumen muestra el "Antes"',/Antes/.test(await p.textContent('#r-resumen-reserva')));
 ok('el botón dice Guardar cambios',/Guardar cambios/.test(await p.textContent('#r-btn-confirmar')));
 await p.click('#r-btn-confirmar'); await p.waitForTimeout(700);
 const m=rpcs.find(r=>r.n==='modificar_reserva_club');
 ok('llama a modificar_reserva_club con la reserva y el cliente',m&&m.body.p_reserva_id===RID&&m.body.p_cliente_id===CID&&m.body.p_hora==='12:00'&&m.body.p_barbero_nombre==='MARIO',m);
 ok('NO crea una reserva nueva',!rpcs.some(r=>r.n==='crear_reserva_publica_club'));
 ok('avisa al servidor para mandar los correos',posts.length===1&&posts[0].reservaId===RID,posts);
 ok('muestra "Reserva modificada"',/modificada/i.test(await p.textContent('#r-success-title')));
 ok('sin errores de página',errs.length===0,errs);
 console.log(res.join('\n')); console.log(res.filter(x=>x.startsWith('FALLO')).length+' fallos de '+res.length);
 await b.close();
})();
