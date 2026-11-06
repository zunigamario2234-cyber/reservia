// Inventario: editar producto (nombre, stock, precios) y menú lateral alcanzable en pantallas bajas.
const { chromium } = require('playwright'); const fs=require('fs');
const REF='dqoqykngmtxtvbokxbzp', BID='b0000000-0000-0000-0000-000000000001', UID='u0000000-0000-0000-0000-000000000001';
const hoy=new Date().toLocaleDateString('en-CA',{timeZone:'America/Santiago'});
function datos(rol){ return {
 perfiles:[{id:UID,barberia_id:BID,nombre:rol==='recepcion'?'María':'Mario',rol,sucursal_id:rol==='recepcion'?'su2':null}],
 barberias:[{id:BID,slug:'essentials-studio',nombre:'Essentials Studio',rubro:'barberia',modo_tema:'oscuro',intervalo_min:30,iva_pct:19}],
 clientes:[{id:'c1',barberia_id:BID,nombre:'Juan',apellido:'Pérez',whatsapp:'+56912345671',created_at:'2026-10-01T10:00:00Z'}],
 servicios:[{id:'s1',barberia_id:BID,nombre:'Corte clásico',precio:12000,duracion_min:30,activo:true,orden:1}],
 barberos:[{id:'b1',barberia_id:BID,nombre:'Mario',slug:'mario',activo:true,sucursal_id:'su1',whatsapp:'+56911111111',comision_pct:50},{id:'b2',barberia_id:BID,nombre:'Felipe',slug:'felipe',activo:true,sucursal_id:'su2',whatsapp:'+56922222222',comision_pct:50}]
 ,sucursales:[{id:'su1',barberia_id:BID,nombre:'Centro',slug:'centro',direccion:'Av 1',activa:true,orden:0},{id:'su2',barberia_id:BID,nombre:'Norte',slug:'norte',direccion:'Av 2',activa:true,orden:1}],
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
 const {p,b,errs,reqs}=await sesion('dueno');
 const gets=[]; p.on('request',r=>{ if(r.method()==='GET') gets.push(decodeURIComponent(r.url())); });
 const writes=[]; p.on('request',r=>{ if(/sucursales/.test(r.url())&&r.method()!=='GET') writes.push({m:r.method(),u:r.url(),b:JSON.parse(r.postData()||'null')}); });
 const sw=await p.evaluate(()=>{const s=document.getElementById('suc-switch');return{vis:s.style.display!=='none',opts:[...s.options].map(o=>o.textContent)}});
 ok('dueño ve el selector con todas las sucursales',sw.vis&&sw.opts.join('|')==='Todas las sucursales|Centro|Norte',sw);
 await p.selectOption('#suc-switch','su2'); await p.waitForTimeout(700);
 ok('filtrar pide reservas, visitas y profesionales solo de esa sucursal',['reservas','visitas','barberos'].every(t=>gets.some(g=>g.includes('/rest/v1/'+t+'?')&&g.includes('sucursal_id=eq.su2'))),gets.filter(g=>/sucursal_id/.test(g)));
 ok('recuerda la elección',await p.evaluate(()=>localStorage.getItem('suc-'+S.barberia.id))==='su2');
 await p.selectOption('#suc-switch',''); await p.waitForTimeout(500);
 ok('"Todas" vuelve a pedir sin filtro',await p.evaluate(()=>S.sucFiltro===null));
 // link corto
 const links=await p.evaluate(()=>({neg:linkReserva(),pro:linkReserva({profId:'b2'}),suc:linkReserva({sucId:'su2'})}));
 ok('link del negocio corto',/\/reservar\/essentials-studio$/.test(links.neg),links);
 ok('link del profesional: negocio + profesional',/\/reservar\/essentials-studio\/felipe$/.test(links.pro),links);
 ok('link de sucursal',/\/reservar\/essentials-studio\?sucursal=norte$/.test(links.suc),links);
 // config
 await p.evaluate(()=>nav('config')); await p.waitForTimeout(300);
 await p.evaluate(()=>switchTab([...document.querySelectorAll('.tab')].find(t=>t.textContent.trim()==='Sucursales'),'cfg-suc')); await p.waitForTimeout(200);
 const cfg=await p.evaluate(()=>document.getElementById('suc-lista').innerText+'|'+document.getElementById('suc-general').innerText);
 ok('lista sucursales con su link',/Centro/.test(cfg)&&/Norte/.test(cfg)&&/reservar\/essentials-studio/.test(cfg),cfg);
 await p.evaluate(()=>abrirSucursal()); await p.evaluate(()=>guardarSucursal()); await p.waitForTimeout(200);
 ok('no guarda sin nombre',writes.length===0,writes);
 await p.fill('#su-nombre','Sur'); await p.fill('#su-dir','Av 3');
 await p.evaluate(()=>guardarSucursal()); await p.waitForTimeout(300);
 ok('crea sucursal para el negocio',writes[0]&&writes[0].m==='POST'&&writes[0].b.nombre==='Sur'&&writes[0].b.barberia_id===BID&&writes[0].b.direccion==='Av 3',writes);
 await p.evaluate(()=>abrirSucursal('su1')); await p.evaluate(()=>{document.getElementById('su-activa').checked=false;}); await p.evaluate(()=>guardarSucursal()); await p.waitForTimeout(200);
 ok('desactivar una deja funcionando',writes.some(w=>w.m==='PATCH'&&w.b.activa===false),writes);
 // profesional: selector de sucursal
 await p.evaluate(()=>{ S.sucursales.forEach(s=>s.activa=true); editarProfesional('b2'); }); await p.waitForTimeout(200);
 const ps=await p.evaluate(()=>({vis:document.getElementById('ba-suc-fg').style.display!=='none',val:document.getElementById('ba-suc').value}));
 ok('al editar un profesional se ve su sucursal',ps.vis&&ps.val==='su2',ps);
 ok('sin errores de página',errs.length===0,errs); await b.close();
 // recepción
 const r=await sesion('recepcion');
 const rv=await r.p.evaluate(()=>({sw:document.getElementById('suc-switch').style.display,et:document.getElementById('suc-etiqueta').innerText}));
 ok('recepción no tiene selector, ve su sucursal',rv.sw==='none'&&/Norte/.test(rv.et),rv);
 ok('recepción sin errores',r.errs.length===0,r.errs); await r.b.close();
 console.log(res.join('\n')); console.log(res.filter(x=>x.startsWith('FALLO')).length+' fallos de '+res.length);
})();
