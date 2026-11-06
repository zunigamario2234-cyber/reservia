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
 reservas:[{id:'ra1',barberia_id:BID,fecha:hoy,hora:'16:00',nombre_cliente:'Pedro Abono',whatsapp_cliente:'+56922222222',barbero_nombre:'Mario',servicio:'Corte clásico',estado:'Pendiente de abono',procesado:false,abono_estado:'Por confirmar',abono_monto:4000,abono_comprobante:BID+'/ra1/tok-1.png',abono_vence_at:new Date(Date.now()+30*60000).toISOString()},{id:'ra2',barberia_id:BID,fecha:hoy,hora:'17:00',nombre_cliente:'Sara Espera',whatsapp_cliente:'+56933333333',barbero_nombre:'Mario',servicio:'Corte clásico',estado:'Pendiente de abono',procesado:false,abono_estado:'Pendiente',abono_monto:4000,abono_vence_at:new Date(Date.now()+20*60000).toISOString()},{id:'r1',barberia_id:BID,fecha:hoy,hora:'15:00',nombre_cliente:'Luis',whatsapp_cliente:'+56911111111',barbero_nombre:'Mario',servicio:'Corte clásico',estado:'Pendiente',procesado:false,fuente:'Web propia'}],
 abono_config:[{barberia_id:BID,activo:true,tipo:'porcentaje',valor:30,retencion_min:45,exige_comprobante:false,club_exento:true,banco:'Banco Estado',tipo_cuenta:'Cuenta RUT',numero_cuenta:'999',titular:'Essentials SpA',rut:'76.1-7'}],
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
 const {p,b,errs,rpcs,reqs}=await sesion('dueno');
 const mails=[]; p.on('request',r=>{ if(/enviar-confirmacion/.test(r.url())) mails.push(JSON.parse(r.postData()||'{}')); });
 const upserts=[]; p.on('request',r=>{ if(/abono_config/.test(r.url())&&r.method()!=='GET') upserts.push(JSON.parse(r.postData()||'{}')); });
 await p.evaluate(()=>nav('config')); await p.waitForTimeout(300);
 await p.evaluate(()=>switchTab([...document.querySelectorAll('.tab')].find(t=>/Abono/.test(t.textContent)),'cfg-abono')); await p.waitForTimeout(300);
 const v=await p.evaluate(()=>({on:document.getElementById('ab-activo').checked,val:document.getElementById('ab-valor').value,ret:document.getElementById('ab-ret').value,ban:document.getElementById('ab-banco').value,det:document.getElementById('ab-detalle').style.display}));
 ok('config precargada',v.on&&v.val==='30'&&v.ret==='45'&&v.ban==='Banco Estado'&&v.det==='',v);
 const retOpts=await p.evaluate(()=>[...document.getElementById('ab-ret').options].map(o=>+o.value));
 ok('retención va de 5 min a 2 h',retOpts[0]===5&&retOpts[retOpts.length-1]===120,retOpts);
 const ej=await p.textContent('#ab-ejemplo'); ok('muestra ejemplo con el cálculo',/abona \$3\.600/.test(ej),ej);
 await p.fill('#ab-ncuenta',''); await p.evaluate(()=>guardarAbonoConfig()); await p.waitForTimeout(200);
 ok('no guarda sin número de cuenta',upserts.length===0,upserts);
 await p.fill('#ab-ncuenta','12345678'); await p.selectOption('#ab-ret','120'); await p.selectOption('#ab-tipo','monto'); await p.fill('#ab-valor','5000');
 await p.evaluate(()=>guardarAbonoConfig()); await p.waitForTimeout(300);
 const u=upserts[0]; ok('guarda config',u&&u.tipo==='monto'&&u.valor===5000&&u.retencion_min===120&&u.numero_cuenta==='12345678',u);
 await p.fill('#ab-valor','0'); await p.evaluate(()=>guardarAbonoConfig()); await p.waitForTimeout(200);
 ok('rechaza abono en cero',upserts.length===1);
 // Reservas: lista de abonos por confirmar
 await p.evaluate(()=>nav('reservas')); await p.waitForTimeout(400);
 const box=await p.evaluate(()=>{const e=document.getElementById('abonos-pendientes');return{vis:e.style.display!=='none',txt:e.innerText}});
 ok('lista abonos por confirmar',box.vis&&/Pedro Abono/.test(box.txt)&&/Sara Espera/.test(box.txt)&&/Subió el comprobante/.test(box.txt)&&/Esperando la transferencia/.test(box.txt),box.txt);
 ok('solo el que subió comprobante tiene "Ver comprobante"',(box.txt.match(/Ver comprobante/g)||[]).length===1);
 const badge=await p.evaluate(()=>{const b=document.getElementById('nav-abono-badge');return b&&b.textContent});
 ok('insignia del menú cuenta 1 por confirmar',badge==='1',badge);
 await p.evaluate(()=>abonoConfirmar('ra1')); await p.waitForTimeout(400);
 ok('confirmar llama a abono_confirmar',rpcs.some(r=>r.n==='abono_confirmar'&&r.body.p_reserva_id==='ra1'),rpcs.map(r=>r.n));
 ok('confirmar manda el correo recién ahora',mails.length===1&&mails[0].reservaId==='ra1',mails);
 p.on('dialog',d=>d.accept('no llegó')); await p.evaluate(()=>abonoRechazar('ra2')); await p.waitForTimeout(400);
 ok('rechazar llama a abono_rechazar con motivo',rpcs.some(r=>r.n==='abono_rechazar'&&r.body.p_reserva_id==='ra2'&&r.body.p_motivo==='no llegó'),rpcs);
 ok('sin errores de página',errs.length===0,errs);
 await b.close();
 // recepción: no ve la config pero sí los abonos
 const r2=await sesion('recepcion'); await r2.p.evaluate(()=>nav('reservas')); await r2.p.waitForTimeout(400);
 ok('recepción ve abonos por confirmar',await r2.p.evaluate(()=>/Pedro Abono/.test(document.getElementById('abonos-pendientes').innerText)));
 ok('recepción sin errores',r2.errs.length===0,r2.errs); await r2.b.close();
 // profesional: no se le muestran los abonos del negocio
 console.log(res.join('\n')); console.log(res.filter(x=>x.startsWith('FALLO')).length+' fallos de '+res.length);
})();
