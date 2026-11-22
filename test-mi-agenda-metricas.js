// Mi Agenda: cuadros de color (mes/semana/ayer/meta) y comisiones con honorarios. node test-mi-agenda-metricas.js
const { chromium } = require('playwright'); const fs=require('fs');
const res=[]; const ok=(n,c,x)=>res.push((c?'OK    ':'FALLO ')+n+(c?'':'  -> '+JSON.stringify(x)));
const SHOT='/tmp/claude-0/-home-claude/4d67f6db-2749-5f27-9259-d200e700f3a0/scratchpad/';
const hoy=new Date().toLocaleDateString('en-CA',{timeZone:'America/Santiago'}); const [Y,M,D]=hoy.split('-').map(Number);
const iso=d=>d.getFullYear()+'-'+String(d.getMonth()+1).padStart(2,'0')+'-'+String(d.getDate()).padStart(2,'0');
const citas={}; for(let i=1;i<=62;i++){ const d=new Date(Y,M-1,D-i); citas[iso(d)]=(d.getMonth()===M-1)?1:3; }
const met={hoy,meta:80,usa_honorarios:true,cerrados:[0],citas,agendadas:4};
const det=[
 {tipo:'servicio',fecha:hoy,servicio:'Corte',valor:15000,comision_monto:6303,estado:'Atendida',propina:1000,retencion_profesional:961,liquido_profesional:5342,retencion_pct:15.25},
 {tipo:'servicio',fecha:hoy,servicio:'Barba',valor:10000,comision_monto:4202,estado:'Atendida',propina:0,retencion_profesional:641,liquido_profesional:3561,retencion_pct:15.25},
 {tipo:'servicio',fecha:hoy,servicio:'Corte',valor:15000,comision_monto:6303,estado:'Cancelada',propina:0,retencion_profesional:961,liquido_profesional:5342,retencion_pct:15.25},
 {tipo:'producto',fecha:hoy,servicio:'Cera',valor:8000,comision_monto:800,estado:'Vendido',propina:0,retencion_profesional:null,liquido_profesional:null,retencion_pct:null}];
(async()=>{
 const b=await chromium.launch(); const p=await b.newPage({viewport:{width:390,height:900},deviceScaleFactor:2}); const errs=[]; p.on('pageerror',e=>errs.push(e.message));
 await p.route(/^https:\/\/(cdn\.jsdelivr\.net|cdnjs\.cloudflare\.com|unpkg\.com)\//, r=>{const m='/tmp/cdn/node_modules/@supabase/supabase-js/dist/umd/supabase.js';return /supabase-js/.test(r.request().url())&&fs.existsSync(m)?r.fulfill({status:200,contentType:'application/javascript',body:fs.readFileSync(m)}):r.fulfill({status:200,contentType:'application/javascript',body:''});});
 await p.route(/supabase\.co\//, r=>{const u=r.request().url(); const json=o=>r.fulfill({status:200,contentType:'application/json',body:JSON.stringify(o)});
   if(/rpc\/mi_agenda_metricas/.test(u)) return json(met);
   if(/rpc\/mi_agenda_comisiones_detalle/.test(u)) return json(det);
   json([]);});
 await p.goto('http://localhost:8765/mi-agenda.html'); await p.waitForTimeout(700);
 await p.evaluate(()=>{ document.getElementById('login-view').style.display='none'; document.getElementById('app-view').style.display=''; PERFIL={barberia_id:'b'}; BARBERO={nombre:'FELIPE'}; });
 await p.evaluate(()=>cargarMetricas()); await p.waitForTimeout(400);
 const t=await p.$$eval('.mt-tile',a=>a.map(x=>({cls:x.className,txt:x.innerText})));
 ok('muestra 4 cuadros',t.length===4,t);
 ok('mes muy por debajo del anterior sale rojo',/rojo/.test(t[0].cls),t[0]);
 ok('la meta atrasada sale roja',/rojo/.test(t[3].cls)&&/\/80/.test(t[3].txt),t[3]);
 const plata=await p.textContent('.mt-plata');
 ok('franja de hoy: comisión, retención, propinas y lo que recibe (sin la cancelada)',/\$11\.305/.test(plata)&&/1\.602/.test(plata)&&/1\.000/.test(plata)&&/\$10\.703/.test(plata),plata);
 await p.click('.mt-tile >> nth=3'); await p.waitForTimeout(150);
 ok('al tocar la meta explica cuánto falta y qué hacer',/por día/.test(await p.textContent('.mt-detalle'))&&/Publica/.test(await p.textContent('.mt-detalle')));
 await p.screenshot({path:SHOT+'miagenda-cuadros.png',clip:{x:0,y:0,width:390,height:520}});
 await p.evaluate(()=>{ cambiarTab('comisiones'); comSetRango('hoy'); }); await p.waitForTimeout(500);
 const v=await p.textContent('#com-resumen');
 ok('Mis ventas separa comisión total, retención y lo que recibe',/Comisión total/.test(v)&&/Retención honorarios \(15,25%\)/.test(v)&&/Lo que recibes/.test(v)&&/10\.703/.test(v),v.slice(0,300));
 ok('Mis ventas muestra el día a día',/Día a día/.test(v)&&/recibes/.test(v));
 await p.screenshot({path:SHOT+'miagenda-ventas.png',fullPage:true});
 // Sin honorarios: no aparece retención
 met.usa_honorarios=false; det.forEach(f=>{f.retencion_profesional=null;});
 await p.evaluate(()=>{ cambiarTab('agenda'); MT_SEL=null; return cargarMetricas(); }); await p.waitForTimeout(300);
 await p.evaluate(()=>cambiarTab('metricas')); await p.waitForTimeout(600); await p.screenshot({path:SHOT+'miagenda-metricas.png',fullPage:true}); ok('pantalla Métricas carga',/Meta del mes/.test(await p.textContent('#met-full')));
 ok('sin modo honorarios no muestra retención',!/Retención/.test(await p.textContent('.mt-plata')));
 ok('sin errores de página',errs.length===0,errs);
 console.log(res.join('\n')); console.log(res.filter(x=>x.startsWith('FALLO')).length+' fallos de '+res.length); await b.close();
})();
