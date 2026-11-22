// Ritmo de cada profesional contra su meta (tarjetas de Profesionales). node test-ritmo-profesional.js
const { chromium } = require('playwright'); const fs=require('fs');
const REF='dqoqykngmtxtvbokxbzp', BID='b0000000-0000-0000-0000-000000000001', UID='u0000000-0000-0000-0000-000000000001';
const hoy=new Date().toLocaleDateString('en-CA',{timeZone:'America/Santiago'});
const [Y,M,D]=hoy.split('-').map(Number);
const f=(y,m,d)=>y+'-'+String(m).padStart(2,'0')+'-'+String(d).padStart(2,'0');
const pm=M===1?12:M-1, py=M===1?Y-1:Y;
const visitas=[]; let n=0;
const add=(nom,y,m,d,k,cli)=>{for(let i=0;i<k;i++) visitas.push({id:'v'+(n++),barberia_id:BID,barbero_nombre:nom,fecha:f(y,m,d),hora:'10:00',cliente_id:cli||('c'+n),valor:12000,propina:0,metodo_pago:'Efectivo',estado:'Atendida',servicio:'Corte'});};
for(let d=1;d<=28;d++){ add('FELIPE',py,pm,d,3); add('VICENTE',py,pm,d,3); }
for(let d=1;d<D;d++){ add('FELIPE',Y,M,d,4); add('VICENTE',Y,M,d,1); }
function datos(rol){ return {
 perfiles:[{id:UID,barberia_id:BID,nombre:'Mario',rol:'dueno',sucursal_id:null}],
 barberias:[{id:BID,slug:'essentials-studio',nombre:'Essentials Studio',rubro:'barberia',modo_tema:'oscuro',intervalo_min:30,iva_pct:19}],
 clientes:[], servicios:[{id:'s1',barberia_id:BID,nombre:'Corte',precio:12000,duracion_min:30,activo:true,orden:1}],
 barberos:[{id:'p1',barberia_id:BID,nombre:'FELIPE',slug:'felipe',activo:true,meta_citas:80,comision_pct:50},{id:'p2',barberia_id:BID,nombre:'VICENTE',slug:'vicente',activo:true,meta_citas:80,comision_pct:50}],
 horario_negocio:[0,1,2,3,4,5,6].map(i=>({id:'h'+i,barberia_id:BID,sucursal_id:null,dia_semana:i,hora_apertura:'10:00',hora_cierre:'20:00',cerrado:i===0})),
 visitas, reservas:[{id:'r1',barberia_id:BID,fecha:hoy,hora:'19:00',nombre_cliente:'Luis',barbero_nombre:'FELIPE',servicio:'Corte',estado:'Pendiente',procesado:false}],
};}
const res=[]; const ok=(n,c,extra)=>{res.push((c?'OK    ':'FALLO ')+n+(c?'':'  -> '+JSON.stringify(extra)));};
async function sesion(rol,signupFalla){
 const T=datos(rol); const reqs=[]; const rpcs=[];
 const b=await chromium.launch(); const p=await b.newPage({viewport:{width:1360,height:900}});
 const errs=[]; p.on('pageerror',e=>errs.push(e.message));
 await p.addInitScript(([ref,uid])=>{ try{ localStorage.setItem('sb-'+ref+'-auth-token',JSON.stringify({access_token:'x.y.z',refresh_token:'r',expires_at:Math.floor(Date.now()/1000)+36000,expires_in:36000,token_type:'bearer',user:{id:uid,email:'m@x.cl',aud:'authenticated',role:'authenticated',app_metadata:{},user_metadata:{}}})); }catch(e){} window.__opened=[]; window.open=function(u){window.__opened.push(u);return {focus(){}}}; },[REF,UID]);
 await p.route(/^https:\/\/(cdn\.jsdelivr\.net|cdnjs\.cloudflare\.com|unpkg\.com)\//, r=>{const u=r.request().url(); const m=/supabase-js/.test(u)?'/tmp/cdn/node_modules/@supabase/supabase-js/dist/umd/supabase.js':/chart/i.test(u)?'/tmp/cdn/node_modules/chart.js/dist/chart.umd.js':null; return m&&fs.existsSync(m)?r.fulfill({status:200,contentType:'application/javascript',body:fs.readFileSync(m)}):r.fulfill({status:200,contentType:'application/javascript',body:''});});
 await p.route(/supabase\.co\/(rest|auth|storage)\//, async r=>{
   const req=r.request(); const u=req.url();
   const json=(o,st=200,h={})=>r.fulfill({status:st,contentType:'application/json',headers:h,body:JSON.stringify(o)});
   if(/\/auth\/v1\/user/.test(u)) return json({id:UID,email:'m@x.cl'});
   if(/\/auth\/v1\/signup/.test(u)){ reqs.push('signup'); if(signupFalla) return json({code:422,msg:'User already registered'},422); return json({access_token:'a.b.c',token_type:'bearer',expires_in:3600,refresh_token:'r',user:{id:'newu',email:'x',aud:'authenticated',role:'authenticated'}}); }
   const t=(u.match(/\/rest\/v1\/(?:rpc\/)?([a-z_]+)/)||[])[1];
   if(/\/rest\/v1\/rpc\//.test(u)){ const body=req.postData()?JSON.parse(req.postData()):{}; rpcs.push({n:t,body}); reqs.push('rpc:'+t);
     if(t==='listar_recepcion') return json([{id:'rx1',nombre:'Ana Caja',email:'ana@x.cl',desde:'2026-11-01T10:00:00Z'}]);
     return json([]); }
   if(req.method()!=='GET'){ return json([],204); }
   reqs.push('get:'+t);
   const rows=(T[t]||[]).slice(); const acc=req.headers()['accept']||'';
   if(/pgrst\.object/.test(acc)) return rows[0]?json(rows[0]):json({code:'PGRST116'},406);
   json(rows,200,{'content-range':'0-'+Math.max(rows.length-1,0)+'/'+rows.length});
 });
 await p.goto('http://localhost:8765/app.html');
 await p.waitForFunction(()=>document.getElementById('loading-screen')&&document.getElementById('loading-screen').style.display==='none',null,{timeout:15000}).catch(()=>res.push('FALLO no cargó el panel ('+rol+')'));
 await p.waitForTimeout(500);
 return {p,b,errs,reqs,rpcs};
}


(async()=>{
 const {p,b,errs}=await sesion('dueno');
 await p.setViewportSize({width:390,height:844});
 await p.evaluate(()=>{ armarNavMovil(); nav('inicio'); }); await p.waitForTimeout(400);
 const r=await p.evaluate(()=>({side:getComputedStyle(document.querySelector('.sidebar')).display,nav:getComputedStyle(document.getElementById('mnav')).display,btns:[...document.querySelectorAll('#mnav button')].map(b=>b.textContent.trim()),
   ini:document.getElementById('mi-inicio').innerText,activo:document.querySelector('#mnav button.on')?.dataset.page,mas:document.querySelectorAll('#m-grid-mas button').length,ancho:document.documentElement.scrollWidth}));
 ok('en el celular se esconde la barra lateral y aparece la barra de abajo',r.side==='none'&&r.nav==='flex',r);
 ok('barra de abajo: Inicio, Agenda, Reservas, Clientes, Más',r.btns.join(',')==='Inicio,Agenda,Reservas,Clientes,Más',r.btns);
 ok('Inicio muestra ventas de hoy, cuadros, agenda de hoy y equipo',/Ventas de hoy/.test(r.ini)&&/Semana/.test(r.ini)&&/Hoy en la agenda/.test(r.ini)&&/Equipo este mes/.test(r.ini)&&/FELIPE/.test(r.ini),r.ini.slice(0,400));
 ok('la reserva pendiente de hoy tiene botón Cobrar',/Luis/.test(r.ini)&&/Cobrar/.test(r.ini));
 ok('Más trae el resto de secciones',r.mas>=8,r.mas);
 ok('sin scroll horizontal',r.ancho<=390,r.ancho);
 await p.screenshot({path:'/tmp/claude-0/-home-claude/4d67f6db-2749-5f27-9259-d200e700f3a0/scratchpad/panel-movil-inicio.png',fullPage:false});
 await p.click('#mnav button[data-page="mas"]'); await p.waitForTimeout(250);
 await p.screenshot({path:'/tmp/claude-0/-home-claude/4d67f6db-2749-5f27-9259-d200e700f3a0/scratchpad/panel-movil-mas.png'});
 await p.click('#m-grid-mas button:has-text("Caja")'); await p.waitForTimeout(300);
 ok('desde Más se abre una sección y se marca Más',await p.evaluate(()=>document.getElementById('p-caja').classList.contains('active')&&!document.getElementById('m-sheet-mas').classList.contains('open')));
 await p.click('.m-plus'); await p.waitForTimeout(200);
 ok('el botón + ofrece nueva reserva y atención',await p.isVisible('#m-sheet-nuevo')&&/Nueva reserva/.test(await p.textContent('#m-sheet-nuevo')));
 await p.click('#m-sheet-nuevo .m-accion >> nth=0'); await p.waitForTimeout(300);
 ok('abre el formulario de reserva',await p.evaluate(()=>document.getElementById('m-reserva').classList.contains('open')));
 await p.evaluate(()=>closeM('m-reserva'));
 for(const pg of ['agenda','reservas','clientes','caja','dashboard']){ await p.evaluate(x=>nav(x),pg); await p.waitForTimeout(300); const w=await p.evaluate(()=>document.documentElement.scrollWidth); ok('sin scroll horizontal en '+pg,w<=392,w); await p.screenshot({path:'/tmp/claude-0/-home-claude/4d67f6db-2749-5f27-9259-d200e700f3a0/scratchpad/panel-movil-'+pg+'.png'}); }
 await p.setViewportSize({width:1360,height:900}); await p.waitForTimeout(200);
 ok('en computador sigue la barra lateral y no aparece la de abajo',await p.evaluate(()=>getComputedStyle(document.querySelector('.sidebar')).display!=='none'&&getComputedStyle(document.getElementById('mnav')).display==='none'));
 await p.click('#btn-app-movil'); await p.waitForTimeout(300);
 const am=await p.evaluate(()=>({txt:document.getElementById('am-cuerpo').innerText,was:[...document.querySelectorAll('#am-cuerpo a.btn-wa')].map(a=>decodeURIComponent(a.href))}));
 ok('en computador, App móvil muestra los dos links con WhatsApp',/ingresar\.html/.test(am.was[0])&&/mi-agenda\.html/.test(am.was[1])&&am.was.length>=2&&/Agregar a inicio/.test(am.was[0]),am);
 await p.screenshot({path:'/tmp/claude-0/-home-claude/4d67f6db-2749-5f27-9259-d200e700f3a0/scratchpad/app-movil-links.png'});
 ok('sin errores de página',errs.length===0,errs);
 console.log(res.join('\n')); console.log(res.filter(x=>x.startsWith('FALLO')).length+' fallos de '+res.length); await b.close();
})();
