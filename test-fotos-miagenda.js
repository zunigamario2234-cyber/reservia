// Prueba: botón de fotos en la agenda del profesional (mi-agenda.html). node test-fotos-miagenda.js
const { chromium } = require('playwright'); const fs=require('fs');
const BID='b0000000-0000-0000-0000-000000000001';
const res=[]; const ok=(n,c,x)=>res.push((c?'OK    ':'FALLO ')+n+(c?'':'  -> '+JSON.stringify(x)));
(async()=>{
 const b=await chromium.launch(); const p=await b.newPage({viewport:{width:420,height:900}});
 const errs=[]; p.on('pageerror',e=>errs.push(e.message)); const rpcs=[];
 await p.route(/^https:\/\/(cdn\.jsdelivr\.net|cdnjs\.cloudflare\.com|unpkg\.com)\//, r=>{const m='/tmp/cdn/node_modules/@supabase/supabase-js/dist/umd/supabase.js';return /supabase-js/.test(r.request().url())&&fs.existsSync(m)?r.fulfill({status:200,contentType:'application/javascript',body:fs.readFileSync(m)}):r.fulfill({status:200,contentType:'application/javascript',body:''});});
 await p.route(/supabase\.co\//, r=>{const u=r.request().url(); const t=(u.match(/\/rest\/v1\/(?:rpc\/)?([a-z_]+)/)||[])[1]; if(t) rpcs.push(t);
   r.fulfill({status:200,contentType:'application/json',headers:{'content-range':'0-0/0'},body:t==='agenda_fotos_cita'?JSON.stringify([{id:'f1',es_actual:true,url:'data:image/gif;base64,R0lGODlhAQABAAAAACw=',fecha:'2026-11-13',hora:'11:00:00',servicio:'Corte',barbero_nombre:'MARIO'}]):'[]'});});
 await p.goto('http://localhost:8765/mi-agenda.html'); await p.waitForTimeout(800);
 await p.evaluate(({BID})=>{
   document.querySelectorAll('body > *').forEach(e=>{});
   if(!document.getElementById('citas-lista')){const d=document.createElement('div');d.id='citas-lista';document.body.appendChild(d);}
   PERFIL={barberia_id:BID}; BARBERO={puede_procesar_pagos:false};
   CITAS_ACTUALES=[{id:'11111111-1111-1111-1111-111111111111',tipo:'reserva',fecha:'2026-11-13',hora:'11:00:00',servicio:'Corte',estado:'Confirmada',procesado:false,nombre_cliente:'Camilo',whatsapp_cliente:'',valor:null,notas:null,cliente_notas:null,fuente:'Manual'},
                   {id:'22222222-2222-2222-2222-222222222222',tipo:'visita',fecha:'2026-11-13',hora:'12:00:00',servicio:'Barba',estado:'Atendida',procesado:true,nombre_cliente:'Luis',whatsapp_cliente:'',valor:8000,notas:null,cliente_notas:null,fuente:null}];
   VISTA_AGENDA='lista'; renderAgendaActual(CITAS_ACTUALES);},{BID});
 const btns=await p.$$eval('#citas-lista button',a=>a.filter(x=>/Fotos del corte/.test(x.textContent)).length);
 ok('cada cita tiene botón de fotos (reserva y visita)',btns===2,btns);
 await p.evaluate(()=>toggleFotosCita('11111111-1111-1111-1111-111111111111')); await p.waitForTimeout(500);
 ok('abre el panel y pide las fotos de la cita',rpcs.includes('agenda_fotos_cita')&&!!(await p.$('.fotos-cita .fc-th img')),rpcs);
 ok('el botón cambia a Ocultar',/Ocultar fotos/.test(await p.textContent('#citas-lista')));
 ok('sin errores de página',errs.length===0,errs);
 console.log(res.join('\n')); console.log(res.filter(x=>x.startsWith('FALLO')).length+' fallos de '+res.length); await b.close();
})();
