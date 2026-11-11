// Ficha del cliente dentro de la reserva: historial completo, profesional y notas.
const { chromium } = require('playwright'); const fs=require('fs');
const REF='dqoqykngmtxtvbokxbzp', BID='b0000000-0000-0000-0000-000000000001', UID='u0000000-0000-0000-0000-000000000001';
const hoy=new Date().toLocaleDateString('en-CA',{timeZone:'America/Santiago'});
function datos(rol){ return {
 perfiles:[{id:UID,barberia_id:BID,nombre:rol==='recepcion'?'María':'Mario',rol,sucursal_id:rol==='recepcion'?'su2':null}],
 barberias:[{id:BID,slug:'essentials-studio',nombre:'Essentials Studio',rubro:'Barbería / Peluquería / Centro de estética',club_vip_activo:globalThis.CLUB_T,modo_tema:'oscuro',intervalo_min:30,iva_pct:19}],
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
 const s=await sesion('dueno'); const p=s.p;
 const patches=[]; p.on('request',r=>{ if(/\/clientes/.test(r.url())&&r.method()==='PATCH') patches.push(JSON.parse(r.postData()||'null')); });
 await p.evaluate(()=>{
  const B=S.barberia.id;
  S.clientes=[
   {id:'cA',barberia_id:B,nombre:'Juan',apellido:'Pérez',whatsapp:'+56 9 8754 2136',notas:'Alérgico al mentol',barbero_preferido:'Mario'},
   {id:'cB',barberia_id:B,nombre:'Pedro',apellido:'Soto',whatsapp:'+56 9 1111 2222',notas:'<img src=x onerror="window.__xss=1">'},
   {id:'cC',barberia_id:B,nombre:'Nuevo',apellido:'Cliente',whatsapp:'+56 9 5555 6666',notas:''}];
  S.visitas=[
   {id:'v1',barberia_id:B,cliente_id:'cA',fecha:'2026-10-01',hora:'10:00:00',barbero_nombre:'Felipe',servicio:'Corte',valor:12000,estado:'Atendida',notas:'Pidió degradé'},
   {id:'v2',barberia_id:B,cliente_id:'cA',fecha:'2026-10-15',hora:'11:00:00',barbero_nombre:'Felipe',servicio:'Corte',valor:12000,estado:'Atendida'},
   {id:'v3',barberia_id:B,cliente_id:'cA',fecha:'2026-10-25',hora:'12:00:00',barbero_nombre:'Mario',servicio:'Barba',valor:8000,estado:'Atendida'},
   {id:'v9',barberia_id:B,cliente_id:'cB',fecha:'2026-10-20',hora:'12:00:00',barbero_nombre:'Mario',servicio:'Corte',valor:12000,estado:'Atendida'}];
  const man=new Date(Date.now()+86400000).toISOString().slice(0,10);
  S.reservas=[
   {id:'rA',barberia_id:B,fecha:man,hora:'16:00',nombre_cliente:'Juan Pérez',whatsapp_cliente:'987542136',barbero_nombre:'Felipe',servicio:'Corte',estado:'Confirmada',procesado:false,notas:'Viene con su hijo'},
   {id:'rB',barberia_id:B,fecha:'2026-09-10',hora:'10:00',nombre_cliente:'Juan Pérez',whatsapp_cliente:'+56987542136',barbero_nombre:'Mario',servicio:'Corte',estado:'Cancelada',procesado:false},
   {id:'rC',barberia_id:B,fecha:'2026-10-01',hora:'10:00',nombre_cliente:'Juan Pérez',whatsapp_cliente:'+56987542136',barbero_nombre:'Felipe',servicio:'Corte',estado:'Atendida',procesado:true},
   {id:'rD',barberia_id:B,fecha:'2026-10-02',hora:'10:00',nombre_cliente:'Pedro Soto',whatsapp_cliente:'+56911112222',barbero_nombre:'Mario',servicio:'Corte',estado:'No asistió',procesado:false},
   {id:'rE',barberia_id:B,fecha:man,hora:'17:00',nombre_cliente:'Nuevo Cliente',whatsapp_cliente:'+56955556666',barbero_nombre:'Mario',servicio:'Corte',estado:'Pendiente',procesado:false}];
 });
 const vis=id=>p.evaluate(i=>{const e=document.getElementById(i);return !!e&&getComputedStyle(e).display!=='none';},id);

 // Editar una reserva de Juan
 await p.evaluate(()=>abrirEditarReserva('rA')); await p.waitForTimeout(250);
 ok('la reserva muestra el botón con el nombre del cliente',await vis('r-ficha-bar')&&/Juan Pérez/.test(await p.textContent('#r-ficha-btn')),await p.textContent('#r-ficha-btn'));
 const resumen=await p.textContent('#r-ficha-resumen');
 ok('resumen: 3 atenciones, última, y con quién se atiende más',/3 atenciones/.test(resumen)&&/2026-10-25/.test(resumen)&&/Felipe.*2 de 3/.test(resumen),resumen);
 ok('resumen: próxima reserva y cancelaciones',/próxima reserva/.test(resumen)&&/1 cancelación/.test(resumen),resumen);
 ok('la nota del cliente se ve ya en la reserva',await vis('r-ficha-nota')&&/Alérgico al mentol/.test(await p.textContent('#r-ficha-nota')),null);

 // Abrir la ficha
 await p.click('#r-ficha-btn'); await p.waitForTimeout(250);
 ok('se abre la ficha',await p.evaluate(()=>!!document.getElementById('m-ficha-cliente')),null);
 ok('la ficha queda ENCIMA del modal de la reserva',await p.evaluate(()=>+document.getElementById('m-ficha-cliente').style.zIndex>+document.getElementById('m-reserva').style.zIndex),null);
 const filas=await p.evaluate(()=>[...document.querySelectorAll('#m-ficha-cliente tbody tr')].map(r=>r.innerText.replace(/\s+/g,' ')));
 ok('historial: 3 atenciones + reserva futura + cancelada = 5 filas (sin duplicar la cobrada, sin otros clientes)',filas.length===5,filas);
 ok('historial: muestra profesional y estado',filas.some(f=>/Felipe/.test(f)&&/Confirmada/.test(f))&&filas.some(f=>/Cancelada/.test(f))&&filas.some(f=>/Mario/.test(f)&&/Barba/.test(f)),filas);
 ok('historial: muestra la nota de la atención y la de la reserva',filas.some(f=>/Pidió degradé/.test(f))&&filas.some(f=>/Viene con su hijo/.test(f)),filas);
 ok('historial: la más reciente primero',/Confirmada/.test(filas[0])&&/Cancelada/.test(filas[4]),filas);
 ok('la nota del cliente aparece editable en la ficha',await p.inputValue('#fc-notas')==='Alérgico al mentol',null);

 // Guardar nota
 await p.fill('#fc-notas','Alérgico al mentol. Le gusta el silencio.');
 await p.evaluate(()=>guardarNotaCliente('cA')); await p.waitForTimeout(300);
 ok('guardar nota: actualiza solo la ficha del cliente',patches.length===1&&patches[0].notas==='Alérgico al mentol. Le gusta el silencio.',patches);
 ok('guardar nota: se refleja en la reserva abierta',/silencio/.test(await p.textContent('#r-ficha-nota')),null);
 ok('guardar nota: confirma en pantalla',/Guardada/.test(await p.textContent('#fc-notas-msg')),null);
 await p.evaluate(()=>document.getElementById('m-ficha-cliente').remove());
 await p.evaluate(()=>closeM('m-reserva'));

 // Cliente sin historial
 await p.evaluate(()=>abrirEditarReserva('rE')); await p.waitForTimeout(200);
 ok('cliente sin historial: dice que es primera vez',await vis('r-ficha-bar')&&/Primera vez|próxima reserva/.test(await p.textContent('#r-ficha-resumen'))&&!(await vis('r-ficha-nota')),await p.textContent('#r-ficha-resumen'));
 await p.evaluate(()=>closeM('m-reserva'));

 // Nueva reserva: aparece al elegir cliente del buscador; no hay residuo del anterior
 await p.evaluate(()=>openM('m-reserva')); await p.waitForTimeout(150);
 ok('reserva nueva: sin cliente no hay botón',!(await vis('r-ficha-bar')),null);
 await p.evaluate(()=>selClienteReserva('cA')); await p.waitForTimeout(150);
 ok('reserva nueva: al elegir un cliente aparece su ficha',await vis('r-ficha-bar')&&/Juan/.test(await p.textContent('#r-ficha-btn')),null);
 await p.fill('#r-wsp','+56 9 1111 2222'); await p.evaluate(()=>{document.getElementById('r-cliente-id').value='';reservaFichaActualizar();});
 ok('si cambia el WhatsApp, la ficha pasa al cliente que corresponde',/Pedro/.test(await p.textContent('#r-ficha-btn')),await p.textContent('#r-ficha-btn'));
 await p.fill('#r-wsp','+56 9 0000 0000'); await p.evaluate(()=>{document.getElementById('r-cliente-id').value='';reservaFichaActualizar();});
 ok('WhatsApp desconocido: se oculta',!(await vis('r-ficha-bar')),null);
 await p.evaluate(()=>closeM('m-reserva'));

 // XSS en notas
 await p.evaluate(()=>{ verCliente('cB'); }); await p.waitForTimeout(200);
 ok('las notas con HTML no se ejecutan (ficha)',await p.evaluate(()=>window.__xss!==1&&!document.querySelector('#m-ficha-cliente img')),null);
 await p.evaluate(()=>document.getElementById('m-ficha-cliente').remove());
 await p.evaluate(()=>abrirEditarReserva('rD')); await p.waitForTimeout(200);
 ok('las notas con HTML no se ejecutan (reserva)',await p.evaluate(()=>window.__xss!==1&&!document.querySelector('#r-ficha-nota img')),null);
 ok('sin errores de JS',s.errs.length===0,s.errs);
 await s.b.close();
 console.log(res.join('\n')); console.log(res.filter(x=>x.startsWith('FALLO')).length?'HAY FALLOS':'TODO OK ('+res.length+')'); process.exit(res.some(r=>r.startsWith('FALLO'))?1:0);
})().catch(e=>{console.error('ERROR',e);process.exit(1);});
