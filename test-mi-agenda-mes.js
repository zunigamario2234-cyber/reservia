// Mi Agenda: vista Mes con días, nombre, número y servicios; tocar abre el día. node test-mi-agenda-mes.js
const { chromium } = require('playwright'); const fs=require('fs');
const res=[]; const ok=(n,c,x)=>res.push((c?'OK    ':'FALLO ')+n+(c?'':'  -> '+JSON.stringify(x)));
const hoy=new Date().toLocaleDateString('en-CA',{timeZone:'America/Santiago'}); const [Y,M,D]=hoy.split('-').map(Number);
const dm=new Date(Y,M,0).getDate(), pre=hoy.slice(0,7);
const filas=[]; for(let d=1;d<=dm;d++){ const f=pre+'-'+String(d).padStart(2,'0'); filas.push({fecha:f,atendidos:f<=hoy?(d%4):0,agendados:f>=hoy?(d%3):0}); }
let pedidos=[];
(async()=>{
 const b=await chromium.launch(); const p=await b.newPage({viewport:{width:390,height:900},deviceScaleFactor:2}); const errs=[]; p.on('pageerror',e=>errs.push(e.message));
 await p.route(/^https:\/\/(cdn\.jsdelivr\.net|cdnjs\.cloudflare\.com|unpkg\.com)\//, r=>{const m='/tmp/cdn/node_modules/@supabase/supabase-js/dist/umd/supabase.js';return /supabase-js/.test(r.request().url())&&fs.existsSync(m)?r.fulfill({status:200,contentType:'application/javascript',body:fs.readFileSync(m)}):r.fulfill({status:200,contentType:'application/javascript',body:''});});
 await p.route(/supabase\.co\//, r=>{const u=r.request().url(); const json=o=>r.fulfill({status:200,contentType:'application/json',body:JSON.stringify(o)});
   if(/rpc\/mi_agenda_mes/.test(u)){ pedidos.push(r.request().postData()); return json(filas); }
   if(/rpc\/mi_agenda_citas/.test(u)){ pedidos.push('citas:'+r.request().postData()); return json([]); }
   json([]);});
 await p.goto('http://localhost:8765/mi-agenda.html'); await p.waitForTimeout(700);
 await p.evaluate(()=>{ document.getElementById('login-view').style.display='none'; document.getElementById('app-view').style.display=''; PERFIL={barberia_id:'b'}; NEGOCIO_ID='b'; BARBERO={id:'p',nombre:'FELIPE'};
   HORARIO_NEGOCIO=[0,1,2,3,4,5,6].map(i=>({dia_semana:i,cerrado:i===0})); document.getElementById('ag-fecha').value=hoyStr(); });
 await p.evaluate(()=>setVistaAgenda('mes')); await p.waitForTimeout(500);
 const celdas=await p.$$eval('.mes-dia',a=>a.map(x=>x.innerText.replace(/\s+/g,' ').trim()));
 ok('muestra todos los días del mes',celdas.length===dm,celdas.length);
 const d1=new Date(Y,M-1,1).getDay(); const NOM=['dom','lun','mar','mié','jue','vie','sáb'];
 ok('cada día tiene su nombre y número',celdas[0].startsWith(NOM[d1]+' 1'),celdas[0]);
 const i3=2; ok('muestra los servicios del día',/3 ✂|3 📅/.test(celdas[i3])||D<3,celdas[i3]);
 ok('hoy va destacado',await p.$$eval('.mes-dia.hoy',a=>a.length)===1);
 await p.screenshot({path:'/tmp/claude-0/-home-claude/4d67f6db-2749-5f27-9259-d200e700f3a0/scratchpad/miagenda-mes.png',clip:{x:0,y:0,width:390,height:900}});
 pedidos=[];
 await p.click('.mes-dia >> nth=4'); await p.waitForTimeout(500);
 const f5=pre+'-05';
 const st=await p.evaluate(()=>({f:document.getElementById('ag-fecha').value,v:VISTA_AGENDA,mes:document.getElementById('citas-mes').style.display}));
 ok('al tocar un día se abre la agenda de ese día',st.f===f5&&st.v!=='mes'&&st.mes==='none'&&pedidos.some(x=>x.startsWith('citas:')&&x.includes(f5)),{st,pedidos});
 await p.evaluate(()=>setVistaAgenda('mes')); await p.waitForTimeout(300);
 await p.click('button[aria-label="Mes siguiente"]'); await p.waitForTimeout(300);
 ok('se puede pasar al mes siguiente',pedidos.some(x=>/p_desde/.test(x)&&!x.includes(pre+'-01')));
 ok('sin errores de página',errs.length===0,errs);
 console.log(res.join('\n')); console.log(res.filter(x=>x.startsWith('FALLO')).length+' fallos de '+res.length); await b.close();
})();
