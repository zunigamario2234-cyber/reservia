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
 horario_negocio:[
  {id:'h1',barberia_id:BID,sucursal_id:'su1',dia_semana:1,hora_apertura:'09:00',hora_cierre:'13:00',cerrado:false},
  {id:'h2',barberia_id:BID,sucursal_id:'su2',dia_semana:1,hora_apertura:'12:00',hora_cierre:'20:00',cerrado:false,hora_colacion_inicio:'15:00',hora_colacion_fin:'16:00'}], bloqueos_profesional:[],
 costos:[{id:'g1',barberia_id:BID,sucursal_id:'su2',fecha:hoy,descripcion:'Arriendo Norte',tipo:'fijo',categoria:'Arriendo',monto_neto:100000,iva:0,total:100000,created_at:new Date().toISOString()}],
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
 inventario:[{id:'i1',barberia_id:BID,sucursal_id:'su1',codigo:'SH-1',nombre:'Shampoo',stock:5,stock_min:1,stock_max:10,costo_unitario:3000,precio_venta:9000},{id:'i2',barberia_id:BID,sucursal_id:'su2',codigo:'SH-1',nombre:'Shampoo',stock:7,stock_min:1,stock_max:10,costo_unitario:3000,precio_venta:9500}],
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
 const gets=[]; p.on('request',r=>{ if(r.method()==='GET') gets.push(decodeURIComponent(r.url())); });
 const writes=[]; p.on('request',r=>{ if(r.method()!=='GET'&&/rest\/v1\/(horario_negocio|inventario|costos)/.test(r.url())) writes.push({m:r.method(),u:decodeURIComponent(r.url()),b:JSON.parse(r.postData()||'null')}); });
 // horario por sucursal
 await p.evaluate(()=>nav('config')); await p.waitForTimeout(300);
 const h1=await p.evaluate(()=>({vis:document.getElementById('hn-suc-fg').style.display!=='none',suc:S.sucHorario,lun:document.getElementById('hn-cierre-1').value}));
 ok('el dueño elige de qué sucursal es el horario',h1.vis&&h1.suc==='su1'&&h1.lun==='13:00',h1);
 await p.selectOption('#hn-suc','su2'); await p.waitForTimeout(200);
 const h2=await p.evaluate(()=>({ap:document.getElementById('hn-apertura-1').value,ci:document.getElementById('hn-cierre-1').value,col:document.getElementById('hn-colini-1').value}));
 ok('cada sucursal muestra su propio horario',h2.ap==='12:00'&&h2.ci==='20:00'&&h2.col==='15:00',h2);
 await p.evaluate(()=>guardarHorarioNegocio()); await p.waitForTimeout(400);
 const wh=writes.find(w=>/horario_negocio/.test(w.u));
 ok('guardar escribe 7 días de ESA sucursal',wh&&wh.b.length===7&&wh.b.every(x=>x.sucursal_id==='su2')&&/on_conflict=sucursal_id,dia_semana/.test(wh.u),wh&&{u:wh.u,n:wh.b&&wh.b.length});
 // la agenda usa el horario del profesional
 const bandas=await p.evaluate(()=>{ const f='2026-11-09'; return {mario:agendaBandasHtml(f,'b1').includes('Fuera de horario'),felipeIni:/top:0px/.test(agendaBandasHtml(f,'b2'))}; });
 ok('la agenda marca fuera de horario según la sucursal de cada profesional',bandas.mario===true,bandas);
 // inventario y filtro
 await p.selectOption('#suc-switch','su2'); await p.waitForTimeout(700);
 ok('filtrar sucursal pide inventario y gastos de esa sucursal',['inventario','costos'].every(t=>gets.some(g=>g.includes('/rest/v1/'+t+'?')&&g.includes('sucursal_id=eq.su2'))),gets.filter(g=>/sucursal_id/.test(g)));
 await p.selectOption('#suc-switch',''); await p.waitForTimeout(500);
 await p.evaluate(()=>nav('inventario')); await p.waitForTimeout(300);
 const inv=await p.evaluate(()=>document.getElementById('t-inv').innerText);
 ok('en "Todas" cada producto indica su sucursal',/Centro/.test(inv)&&/Norte/.test(inv),inv);
 // producto nuevo en una sucursal
 await p.evaluate(()=>abrirProducto()); await p.fill('#pr-nombre','Cera'); await p.selectOption('#pr-suc','su2'); await p.fill('#pr-cod','CE-1');
 await p.evaluate(()=>guardarProducto()); await p.waitForTimeout(300);
 const wi=writes.find(w=>/inventario/.test(w.u)&&w.m==='POST');
 ok('el producto nuevo queda en la sucursal elegida',wi&&wi.b.sucursal_id==='su2'&&wi.b.nombre==='Cera',writes);
 // gasto
 await p.evaluate(()=>nav('costos')); await p.waitForTimeout(300);
 const gtxt=await p.evaluate(()=>document.getElementById('t-costos').innerText);
 ok('el gasto muestra su sucursal',/Norte/.test(gtxt),gtxt);
 await p.evaluate(()=>openM('m-costo')); await p.fill('#co-desc','Luz'); await p.fill('#co-monto','20000'); await p.selectOption('#co-suc','su1');
 await p.evaluate(()=>guardarCosto()); await p.waitForTimeout(300);
 const wc=writes.find(w=>/costos/.test(w.u)&&w.m==='POST');
 ok('el gasto nuevo se guarda con su sucursal',wc&&wc.b.sucursal_id==='su1'&&wc.b.descripcion==='Luz',writes);
 // venta: productos de la sucursal del profesional
 const vp=await p.evaluate(()=>{ COBRO_CTX={lineas:[],productos:[]}; abrirAgregarProducto(); const s=document.getElementById('cobprod-prof'); s.value='Felipe'; document.getElementById('cobprod-q').value='shampoo'; return productosQueCoinciden('shampoo').map(x=>x.id); });
 ok('al vender, solo salen productos de la sucursal del profesional',JSON.stringify(vp)==='["i2"]',vp);
 ok('sin errores de página',errs.length===0,errs); await b.close();
 // recepción: su sucursal
 const r=await sesion('recepcion');
 const rh=await r.p.evaluate(()=>({suc:S.sucHorario,vis:document.getElementById('hn-suc-fg')?document.getElementById('hn-suc-fg').style.display:'-'}));
 ok('recepción trabaja con el horario de su sucursal',rh.suc==='su2',rh);
 ok('recepción sin errores',r.errs.length===0,r.errs); await r.b.close();
 console.log(res.join('\n')); console.log(res.filter(x=>x.startsWith('FALLO')).length+' fallos de '+res.length);
})();
