// Mi Agenda: el profesional modifica una cita propia (día, hora, servicio). node test-mi-agenda-modificar.js
const { chromium } = require('playwright'); const fs=require('fs');
const res=[]; const ok=(n,c,x)=>res.push((c?'OK    ':'FALLO ')+n+(c?'':'  -> '+JSON.stringify(x)));
const d=new Date(); d.setDate(d.getDate()+((2-d.getDay()+7)%7||7)); const F=d.toISOString().slice(0,10); // próximo martes
const R1='11111111-1111-1111-1111-111111111111';
let rpcMod=null, avisos=[];
(async()=>{
 const b=await chromium.launch(); const p=await b.newPage({viewport:{width:390,height:900}}); const errs=[]; p.on('pageerror',e=>errs.push(e.message));
 await p.route(/^https:\/\/(cdn\.jsdelivr\.net|cdnjs\.cloudflare\.com|unpkg\.com)\//, r=>{const m='/tmp/cdn/node_modules/@supabase/supabase-js/dist/umd/supabase.js';return /supabase-js/.test(r.request().url())&&fs.existsSync(m)?r.fulfill({status:200,contentType:'application/javascript',body:fs.readFileSync(m)}):r.fulfill({status:200,contentType:'application/javascript',body:''});});
 await p.route(/\/api\/avisar-modificacion-reserva/, r=>{ avisos.push(r.request().postData()); r.fulfill({status:200,body:'{}'}); });
 await p.route(/supabase\.co\//, r=>{const u=r.request().url(); const json=o=>r.fulfill({status:200,contentType:'application/json',body:JSON.stringify(o)});
   if(/rpc\/mi_agenda_citas/.test(u)) return json([{id:R1,tipo:'reserva',fecha:F,hora:'11:00:00',servicio:'Corte',estado:'Confirmada',procesado:false,nombre_cliente:'Luis',whatsapp_cliente:'',notas:null}]);
   if(/reservas_disponibilidad/.test(u)) return json([{id:R1,hora:'11:00:00',barbero_nombre:'FELIPE',duracion_min:30},{id:'x',hora:'13:00:00',barbero_nombre:'FELIPE',duracion_min:60}]);
   if(/rpc\/mi_agenda_modificar_reserva/.test(u)){ rpcMod=JSON.parse(r.request().postData()); return json(R1); }
   json([]);});
 await p.goto('http://localhost:8765/mi-agenda.html'); await p.waitForTimeout(700);
 await p.evaluate((F)=>{ document.getElementById('login-view').style.display='none'; document.getElementById('app-view').style.display=''; PERFIL={barberia_id:'b'}; NEGOCIO_ID='b'; BARBERO={id:'p',nombre:'FELIPE'}; NEGOCIO={intervalo_min:30};
   SERVICIOS=[{nombre:'Corte',duracion_min:30},{nombre:'Corte y barba',duracion_min:90}];
   HORARIO_NEGOCIO=[0,1,2,3,4,5,6].map(i=>({dia_semana:i,cerrado:i===0,hora_apertura:'10:00',hora_cierre:'15:00'})); BLOQUEOS=[];
   document.getElementById('ag-fecha').value=F; VISTA_AGENDA='lista'; return cargarAgenda(); },F);
 await p.waitForTimeout(400);
 ok('la cita tiene botón Modificar',await p.isVisible('button:has-text("Modificar")'));
 await p.click('button:has-text("Modificar")'); await p.waitForTimeout(500);
 let horas=await p.$$eval('#mm-hora option',a=>a.map(o=>o.value));
 ok('con Corte (30 min) ofrece horas libres incluida la actual y sin la de 13:00',horas.includes('11:00')&&!horas.includes('13:00')&&!horas.includes('13:30')&&horas.includes('12:30'),horas);
 await p.selectOption('#mm-servicio','Corte y barba'); await p.waitForTimeout(400);
 horas=await p.$$eval('#mm-hora option',a=>a.map(o=>o.value));
 ok('con Corte y barba (90 min) quita las horas que chocarían con 13:00',!horas.includes('12:00')&&!horas.includes('12:30')&&horas.includes('11:30')&&horas.includes('10:00'),horas);
 await p.selectOption('#mm-hora','10:00'); await p.fill('#mm-notas','Llega con su hijo');
 await p.click('#mm-guardar'); await p.waitForTimeout(500);
 ok('guarda con la RPC: día, hora, servicio y nota',rpcMod&&rpcMod.p_reserva_id===R1&&rpcMod.p_fecha===F&&rpcMod.p_hora==='10:00'&&rpcMod.p_servicio==='Corte y barba'&&rpcMod.p_notas==='Llega con su hijo',rpcMod);
 ok('avisa al cliente por correo',avisos.length===1&&avisos[0].includes(R1),avisos);
 ok('cierra el formulario',await p.evaluate(()=>!document.getElementById('m-modificar').classList.contains('open')));
 ok('sin errores de página',errs.length===0,errs);
 console.log(res.join('\n')); console.log(res.filter(x=>x.startsWith('FALLO')).length+' fallos de '+res.length); await b.close();
})();
