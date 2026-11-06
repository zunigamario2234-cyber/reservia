// Inventario: editar producto (nombre, stock, precios) y menú lateral alcanzable en pantallas bajas.
const { chromium } = require('playwright'); const fs=require('fs');
const REF='dqoqykngmtxtvbokxbzp', BID='b0000000-0000-0000-0000-000000000001', UID='u0000000-0000-0000-0000-000000000001';
const hoy=new Date().toLocaleDateString('en-CA',{timeZone:'America/Santiago'});
function datos(rol){ return {
 perfiles:[{id:UID,barberia_id:BID,nombre:rol==='recepcion'?'María':'Mario',rol}],
 barberias:[{id:BID,nombre:'Essentials Studio',rubro:'barberia',modo_tema:'oscuro',intervalo_min:30,iva_pct:19}],
 clientes:[{id:'c1',barberia_id:BID,nombre:'Juan',apellido:'Pérez',whatsapp:'+56912345671',created_at:'2026-10-01T10:00:00Z'}],
 servicios:[{id:'s1',barberia_id:BID,nombre:'Corte clásico',precio:12000,duracion_min:30,activo:true,orden:1}],
 barberos:[{id:'b1',barberia_id:BID,nombre:'Mario',activo:true}],
 horario_negocio:[], bloqueos_profesional:[],
 visitas:[
  {id:'v1',barberia_id:BID,fecha:hoy,hora:'10:00',cliente_id:'c1',barbero_nombre:'Mario',servicio:'Corte clásico',valor:12000,propina:1000,metodo_pago:'Efectivo',estado:'Atendida'},
  {id:'v2',barberia_id:BID,fecha:hoy,hora:'11:00',cliente_id:'c1',barbero_nombre:'Mario',servicio:'Corte clásico',valor:18000,propina:0,metodo_pago:'Débito',estado:'Atendida'},
  {id:'v3',barberia_id:BID,fecha:hoy,hora:'12:00',cliente_id:'c1',barbero_nombre:'Mario',servicio:'Corte clásico',valor:12000,propina:0,metodo_pago:'Gift card',estado:'Atendida'},
  {id:'v4',barberia_id:BID,fecha:hoy,hora:'13:00',cliente_id:'c1',barbero_nombre:'Mario',servicio:'Corte clásico',valor:15000,propina:0,metodo_pago:'Efectivo',estado:'Cancelada'},
  {id:'v5',barberia_id:BID,fecha:'2026-01-05',hora:'13:00',cliente_id:'c1',barbero_nombre:'Mario',servicio:'Corte clásico',valor:99000,propina:0,metodo_pago:'Efectivo',estado:'Atendida'}],
 cobro_productos:[
  {id:'p1',cobro_id:'k1',barberia_id:BID,producto_id:'i1',barbero_nombre:'Mario',cantidad:1,valor:9000,fecha:hoy,created_at:new Date().toISOString(),metodo_pago:'Efectivo'},
  {id:'p2',cobro_id:'k2',barberia_id:BID,producto_id:'i1',barbero_nombre:'Mario',cantidad:2,valor:5000,fecha:hoy,created_at:new Date().toISOString(),metodo_pago:null}],
 reservas:[{id:'r1',barberia_id:BID,fecha:hoy,hora:'15:00',nombre_cliente:'Luis',whatsapp_cliente:'+56911111111',barbero_nombre:'Mario',servicio:'Corte clásico',estado:'Pendiente',procesado:false,fuente:'Web propia'}],
 anticipos_profesional:[{id:'an1',barberia_id:BID,barbero_nombre:'Mario',fecha:hoy,monto:5000,nota:'adelanto'},{id:'an2',barberia_id:BID,barbero_nombre:'Mario',fecha:'2026-01-05',monto:9999,nota:'viejo'}],
 inventario:[{id:'i1',barberia_id:BID,codigo:'SH-1',nombre:'Shampoo',stock:5,stock_min:1,stock_max:10,costo_unitario:3000,precio_venta:9000}],
 inventario_recepcion:[{id:'i1',barberia_id:BID,codigo:'SH-1',nombre:'Shampoo',stock:5,precio_venta:9000}],
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
 const writes=[]; p.on('request',r=>{ if(/anticipos_profesional/.test(r.url())&&r.method()!=='GET') writes.push({m:r.method(),u:r.url(),b:JSON.parse(r.postData()||'{}')}); });
 p.on('dialog',d=>d.accept());
 await p.evaluate(()=>{ nav('reportes'); }); await p.waitForTimeout(300);
 await p.evaluate(()=>{ const t=[...document.querySelectorAll('.tab')].find(x=>/Profesional/i.test(x.textContent)); if(t) t.click(); }); await p.waitForTimeout(200);
 await p.evaluate(()=>{ repProfRango('mes'); }); await p.waitForTimeout(300);
 const card=await p.evaluate(()=>document.getElementById('rep-anticipos').innerText);
 ok('lista anticipos del período',/adelanto/.test(card)&&/\$5\.000/.test(card),card);
 ok('no muestra anticipos de otro período',!/9\.999/.test(card)&&!/viejo/.test(card));
 const tabla=await p.evaluate(()=>document.getElementById('rep-tabla-prof').innerText);
 ok('tabla muestra anticipo y a transferir',/− \$5\.000/.test(tabla),tabla);
 // Mario: servicios 12000+18000+12000(gift)... comisión según config; verificamos aritmética: total - 5000
 const nums=await p.evaluate(()=>{const tr=document.querySelector('#rep-tabla-prof tr');const g=l=>tr.querySelector('[data-label="'+l+'"]').textContent;return{tot:g('Total a pagarle'),ant:g('Anticipos'),tr:g('A transferir')}});
 const n=x=>+x.replace(/[^0-9-]/g,'').replace(/^-?/,'')||0; const tot=n(nums.tot),tr=n(nums.tr);
 ok('a transferir = total − anticipos',tot-5000===tr,nums);
 // alta
 await p.evaluate(()=>abrirAnticipo()); await p.waitForTimeout(200);
 const pre=await p.evaluate(()=>({prof:document.getElementById('an-prof').value,f:document.getElementById('an-fecha').value,t:document.getElementById('an-titulo').textContent}));
 ok('modal de alta con fecha de hoy',pre.f===hoy&&/Anotar/.test(pre.t),pre);
 await p.evaluate(()=>guardarAnticipo()); await p.waitForTimeout(200);
 ok('no guarda sin monto',writes.length===0,writes);
 await p.fill('#an-monto','3000'); await p.fill('#an-nota','segundo');
 await p.evaluate(()=>guardarAnticipo()); await p.waitForTimeout(300);
 const w=writes[0]; ok('inserta con negocio, profesional y monto',w&&w.m==='POST'&&w.b.barberia_id===BID&&w.b.monto===3000&&w.b.barbero_nombre==='Mario'&&w.b.nota==='segundo',writes);
 // editar
 await p.evaluate(()=>abrirAnticipo('an1')); await p.waitForTimeout(100);
 const ed=await p.evaluate(()=>({m:document.getElementById('an-monto').value,t:document.getElementById('an-titulo').textContent}));
 ok('editar precarga',ed.m==='5000'&&/Editar/.test(ed.t),ed);
 await p.fill('#an-monto','6000'); await p.evaluate(()=>guardarAnticipo()); await p.waitForTimeout(300);
 const pa=writes.find(x=>x.m==='PATCH'); ok('edita con PATCH',pa&&pa.b.monto===6000&&/id=eq\.an1/.test(pa.u),writes);
 await p.evaluate(()=>borrarAnticipo('an1')); await p.waitForTimeout(300);
 ok('borra con DELETE',writes.some(x=>x.m==='DELETE'&&/id=eq\.an1/.test(x.u)),writes);
 await p.evaluate(()=>{ S.barberia.usa_honorarios=true; repProfRango('mes'); }); await p.waitForTimeout(300);
 const hon=await p.evaluate(()=>document.getElementById('rep-honorarios').innerText);
 ok('honorarios: anticipo y "A transferir" por profesional',/Anticipos ya entregados/.test(hon)&&/A transferir a Mario/.test(hon),hon);
 ok('honorarios: total a transferir a profesionales',/Total a transferir a profesionales/.test(hon),hon);
 ok('sin errores de página',errs.length===0,errs); await b.close();
 // recepción no ve el apartado
 const r2=await sesion('recepcion'); 
 ok('recepción no carga anticipos',!r2.reqs.includes('get:anticipos_profesional'),r2.reqs.filter(x=>/antic/.test(x)));
 await r2.b.close();
 console.log(res.join('\n')); console.log(res.filter(x=>x.startsWith('FALLO')).length+' fallos de '+res.length);
})();
