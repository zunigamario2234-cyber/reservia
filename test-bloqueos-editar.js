// Bloqueos: editar uno existente (tipo, profesional, fecha/día, horas, motivo) desde Configuración y desde la agenda.
const { chromium } = require('playwright'); const fs=require('fs');
const REF='dqoqykngmtxtvbokxbzp', BID='b0000000-0000-0000-0000-000000000001', UID='u0000000-0000-0000-0000-000000000001';
const hoy=new Date().toLocaleDateString('en-CA',{timeZone:'America/Santiago'});
function datos(rol){ return {
 perfiles:[{id:UID,barberia_id:BID,nombre:rol==='recepcion'?'María':'Mario',rol}],
 barberias:[{id:BID,nombre:'Essentials Studio',rubro:'barberia',modo_tema:'oscuro',intervalo_min:30,iva_pct:19}],
 clientes:[{id:'c1',barberia_id:BID,nombre:'Juan',apellido:'Pérez',whatsapp:'+56912345671',created_at:'2026-10-01T10:00:00Z'}],
 servicios:[{id:'s1',barberia_id:BID,nombre:'Corte clásico',precio:12000,duracion_min:30,activo:true,orden:1}],
 barberos:[{id:'b1',barberia_id:BID,nombre:'Mario',activo:true},{id:'b2',barberia_id:BID,nombre:'Felipe',activo:true}],
 horario_negocio:[], bloqueos_profesional:[{id:'k1',barberia_id:BID,profesional_id:'b1',tipo:'dia_completo',fecha:hoy,dia_semana:null,hora_inicio:null,hora_fin:null,motivo:'Trámite',activo:true,created_at:'2026-11-01T10:00:00Z'}],
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
 const patches=[],posts=[]; p.on('request',r=>{ if(/bloqueos_profesional/.test(r.url())){ if(r.method()==='PATCH') patches.push({u:r.url(),b:JSON.parse(r.postData()||'{}')}); if(r.method()==='POST') posts.push(1);} });
 await p.evaluate(()=>{nav('config');}); await p.waitForTimeout(200);
 await p.evaluate(()=>{const t=[...document.querySelectorAll('.tab')].find(x=>/Bloqueos/.test(x.textContent)); t&&t.click();}); await p.waitForTimeout(200);
 ok('hay botón Editar en la tabla',(await p.$$('#t-bloqueos button[title="Editar bloqueo"]')).length===1);
 await p.click('#t-bloqueos button[title="Editar bloqueo"]'); await p.waitForTimeout(200);
 const pre=await p.evaluate(()=>({id:document.getElementById('blq-id').value,t:document.getElementById('m-blq-title').textContent,tipo:document.getElementById('blq-tipo').value,f:document.getElementById('blq-fecha').value,m:document.getElementById('blq-motivo').value,horasVisibles:document.getElementById('blq-fg-horas').style.display!=='none'}));
 ok('modal precargado con el bloqueo',pre.id==='k1'&&/Editar/.test(pre.t)&&pre.tipo==='dia_completo'&&pre.m==='Trámite'&&!pre.horasVisibles,pre);
 // Cambiar de día completo a recurrente (martes 15–17) y de Mario a Felipe
 await p.selectOption('#blq-profesional','b2');
 await p.selectOption('#blq-tipo','recurrente');
 await p.selectOption('#blq-dia-semana','2');
 await p.fill('#blq-hora-inicio','15:00'); await p.fill('#blq-hora-fin','17:00'); await p.fill('#blq-motivo','Clases');
 await p.evaluate(()=>guardarBloqueo()); await p.waitForTimeout(300);
 const pa=patches[0];
 ok('guarda con PATCH al mismo id (no crea otro)',pa&&/id=eq\.k1/.test(pa.u)&&posts.length===0,{patches,posts});
 ok('datos nuevos y fecha vieja limpiada',pa&&pa.b.tipo==='recurrente'&&pa.b.profesional_id==='b2'&&pa.b.dia_semana===2&&pa.b.hora_inicio==='15:00'&&pa.b.hora_fin==='17:00'&&pa.b.fecha===null&&pa.b.motivo==='Clases',pa&&pa.b);
 // De recurrente a puntual: limpia dia_semana
 await p.evaluate(()=>editarBloqueo('k1')); await p.selectOption('#blq-tipo','puntual'); await p.fill('#blq-fecha','2026-12-03'); await p.fill('#blq-hora-inicio','10:00'); await p.fill('#blq-hora-fin','12:00');
 await p.evaluate(()=>guardarBloqueo()); await p.waitForTimeout(300);
 const pb=patches[1]&&patches[1].b;
 ok('a puntual: fecha y horas, sin día de semana',pb&&pb.tipo==='puntual'&&pb.fecha==='2026-12-03'&&pb.dia_semana===null&&pb.hora_inicio==='10:00',pb);
 // Validación: horas al revés no guarda
 await p.evaluate(()=>editarBloqueo('k1')); await p.selectOption('#blq-tipo','puntual'); await p.fill('#blq-fecha','2026-12-03'); await p.fill('#blq-hora-inicio','14:00'); await p.fill('#blq-hora-fin','13:00');
 await p.evaluate(()=>guardarBloqueo()); await p.waitForTimeout(200);
 ok('no guarda horas invertidas',patches.length===2,patches.length);
 await p.evaluate(()=>closeM('m-bloqueo'));
 // "+ Bloqueo" vuelve a abrir vacío
 await p.evaluate(()=>openM('m-bloqueo'));
 const nv=await p.evaluate(()=>({id:document.getElementById('blq-id').value,t:document.getElementById('m-blq-title').textContent}));
 ok('"+ Bloqueo" abre vacío',nv.id===''&&/Agregar/.test(nv.t),nv);
 await p.evaluate(()=>closeM('m-bloqueo'));
 // Desde la agenda: la etiqueta del bloqueo abre el editor
 const html=await p.evaluate(h=>{ S.bloqueos=[{id:'k1',barberia_id:'x',profesional_id:'b1',tipo:'dia_completo',fecha:h,motivo:'Trámite',activo:true}]; return agendaBandasHtml(h,'b1'); },hoy);
 ok('banda de bloqueo en agenda es editable',/editarBloqueo\('k1'\)/.test(html),html.slice(0,300));
 // Varios días seguidos (vacaciones)
 await p.evaluate(()=>{S.bloqueos=[{id:'k1',barberia_id:'x',profesional_id:'b1',tipo:'dia_completo',fecha:'2026-12-01',activo:true}];});
 await p.evaluate(()=>editarBloqueo('k1'));
 await p.selectOption('#blq-tipo','varios_dias');
 const vis=await p.evaluate(()=>({hasta:document.getElementById('blq-fg-hasta').style.display!=='none',horas:document.getElementById('blq-fg-horas').style.display!=='none',lbl:document.getElementById('blq-lbl-fecha').textContent}));
 ok('varios días muestra Desde/Hasta y oculta horas',vis.hasta&&!vis.horas&&/Desde/.test(vis.lbl),vis);
 await p.fill('#blq-fecha','2026-12-10'); await p.fill('#blq-fecha-hasta','2026-12-05'); await p.evaluate(()=>blqResumenDias());
 await p.evaluate(()=>guardarBloqueo()); await p.waitForTimeout(200);
 ok('no guarda hasta antes de desde',patches.length===2,patches.length);
 await p.fill('#blq-fecha-hasta','2026-12-20'); await p.evaluate(()=>blqResumenDias());
 const resu=await p.evaluate(()=>document.getElementById('blq-resumen').textContent);
 ok('resumen cuenta 11 días',/11 días/.test(resu),resu);
 await p.evaluate(()=>guardarBloqueo()); await p.waitForTimeout(300);
 const pv=patches[2]&&patches[2].b;
 ok('se guarda como día completo con fecha_hasta',pv&&pv.tipo==='dia_completo'&&pv.fecha==='2026-12-10'&&pv.fecha_hasta==='2026-12-20'&&pv.hora_inicio===null,pv);
 // Al reabrir, se reconoce como "varios días"; y la tabla lo muestra así
 const re=await p.evaluate(()=>{S.bloqueos=[{id:'k1',barberia_id:'x',profesional_id:'b1',tipo:'dia_completo',fecha:'2026-12-10',fecha_hasta:'2026-12-20',activo:true,motivo:'Vacaciones'}]; renderBloqueos(); editarBloqueo('k1'); return {tipo:document.getElementById('blq-tipo').value,h:document.getElementById('blq-fecha-hasta').value,fila:document.getElementById('t-bloqueos').textContent};});
 ok('reabre como varios días',re.tipo==='varios_dias'&&re.h==='2026-12-20',re);
 ok('tabla dice Varios días y el rango',/Varios días/.test(re.fila)&&/2026-12-10 al 2026-12-20/.test(re.fila),re.fila);
 // De vuelta a un solo día: limpia fecha_hasta
 await p.selectOption('#blq-tipo','dia_completo'); await p.evaluate(()=>guardarBloqueo()); await p.waitForTimeout(300);
 const pu=patches[3]&&patches[3].b;
 ok('volver a día completo borra fecha_hasta',pu&&pu.tipo==='dia_completo'&&pu.fecha_hasta===null,pu);
 await p.evaluate(()=>closeM('m-bloqueo'));
 const band=await p.evaluate(()=>{const B=[{id:'k9',profesional_id:'b1',tipo:'dia_completo',fecha:'2026-12-10',fecha_hasta:'2026-12-20',activo:true,motivo:'Vacaciones'}];
   return ['2026-12-09','2026-12-10','2026-12-15','2026-12-20','2026-12-21'].map(f=>agendaBandas(f,[],B,'b1',540,1200).some(x=>x.tipo==='bloqueo'));});
 ok('agenda del panel bloquea solo dentro del rango',JSON.stringify(band)==='[false,true,true,true,false]',band);
 ok('sin errores de página',errs.length===0,errs);
 console.log(res.join('\n')); console.log(res.filter(x=>/^FALLO/.test(x)).length+' fallos de '+res.length); await b.close();
})();
