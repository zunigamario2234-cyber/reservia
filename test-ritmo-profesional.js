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
 await p.evaluate(()=>nav('profesionals')); await p.waitForTimeout(400);
 const out=await p.evaluate(()=>({cards:[...document.querySelectorAll('#cards-profesionals .card')].map(c=>c.innerText),
   mF:metricasProfesional(S.barberos.find(x=>x.nombre==='FELIPE')),mV:metricasProfesional(S.barberos.find(x=>x.nombre==='VICENTE'))}));
 const cF=out.cards.find(c=>/FELIPE/.test(c))||'', cV=out.cards.find(c=>/VICENTE/.test(c))||'';
 ok('muestra comparación mes, semana y ayer',/mes anterior/.test(cF)&&/semana/i.test(cF)&&/Ayer/.test(cF),cF);
 ok('muestra proyección y agendadas',/cierra el mes en/.test(cF)&&/agendadas/.test(cF)&&out.mF.agendadas===1,out.mF);
 ok('dibuja un gráfico por profesional',(await p.$$('#cards-profesionals svg')).length===2);
 if(D>=5){
   ok('FELIPE (4 por día) va en camino o cumplió',['bien','cumplida'].includes(out.mF.estado),out.mF.estado);
   ok('VICENTE (1 por día) queda en alerta con acciones',out.mV.estado==='alerta'&&/Qué hacer/.test(cV)&&/por día/.test(cV),out.mV.estado);
   ok('compara con el mes anterior al mismo día',out.mV.mesAnt===Math.min(D,28)*3,out.mV.mesAnt);
 }
 ok('sin errores de página',errs.length===0,errs);
 await p.setViewportSize({width:1360,height:1500});
 await p.locator('#cards-profesionals').screenshot({path:'/tmp/claude-0/-home-claude/4d67f6db-2749-5f27-9259-d200e700f3a0/scratchpad/ritmo.png'});
 await p.setViewportSize({width:390,height:1600});
 await p.locator('#cards-profesionals').screenshot({path:'/tmp/claude-0/-home-claude/4d67f6db-2749-5f27-9259-d200e700f3a0/scratchpad/ritmo-movil.png'});
 console.log(res.join('\n')); console.log(res.filter(x=>x.startsWith('FALLO')).length+' fallos de '+res.length); await b.close();
})();
