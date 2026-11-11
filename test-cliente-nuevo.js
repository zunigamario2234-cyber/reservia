// Marca «Nuevo» para quien reserva por primera vez (agenda, lista de reservas, reserva, aviso en vivo).
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
 const man=await p.evaluate(()=>new Date(Date.now()+86400000).toISOString().slice(0,10));
 await p.evaluate((man)=>{
  const B=S.barberia.id;
  S.clientes=[
   {id:'cA',barberia_id:B,nombre:'Juan',apellido:'Pérez',whatsapp:'+56 9 8754 2136'},
   {id:'cC',barberia_id:B,nombre:'Nuevo',apellido:'Cliente',whatsapp:'+56 9 5555 6666'}];
  S.visitas=[{id:'v1',barberia_id:B,cliente_id:'cA',fecha:'2026-10-01',hora:'10:00:00',barbero_nombre:'Mario',servicio:'Corte',valor:12000,estado:'Atendida'}];
  const R=(id,hora,nom,w,est,extra)=>({id,barberia_id:B,fecha:man,hora,nombre_cliente:nom,whatsapp_cliente:w,barbero_nombre:'Mario',servicio:'Corte clásico',estado:est||'Pendiente',procesado:false,...(extra||{})});
  S.reservas=[
   R('rA','10:00','Juan Pérez','987542136','Confirmada'),
   R('rE','11:00','Nuevo Cliente','+56955556666'),
   R('rF','12:00','Desconocido Uno','+56 9 7777 8888'),
   R('rG','13:00','Desconocido Uno','+56977778888'),
   R('rH','14:00','Zeta','+56 9 3333 4444','Cancelada'),
   R('rI','15:00','Atendido Antes','+56 9 2222 1111','Atendida',{procesado:true}),
   R('rJ',null,'Sin Hora Nuevo','+56 9 6666 0000')];
  document.getElementById('ag-fecha').value=man; renderAgenda(); renderReservas();
 },man);
 await p.waitForTimeout(250);
 const tag=id=>p.evaluate(i=>{const b=document.querySelector('.cal-block[data-id="'+i+'"]');return b?!!b.querySelector('.tag-nuevo'):null;},id);
 ok('agenda: cliente conocido (con atenciones) NO lleva marca',(await tag('rA'))===false,await tag('rA'));
 ok('agenda: cliente con ficha pero sin atenciones lleva «Nuevo»',(await tag('rE'))===true,await tag('rE'));
 ok('agenda: quien no tiene ficha y reserva por primera vez lleva «Nuevo»',(await tag('rF'))===true,await tag('rF'));
 ok('agenda: su segunda reserva (misma persona, otro formato de WhatsApp) no se marca',(await tag('rG'))===false,await tag('rG'));
 ok('agenda: reserva cancelada no se marca',(await tag('rH'))===false,await tag('rH'));
 ok('agenda: reserva ya atendida no se marca',(await tag('rI'))!==true,await tag('rI'));
 ok('agenda: la marca dice «Nuevo»',/Nuevo/.test(await p.evaluate(()=>document.querySelector('.cal-block[data-id="rE"] .tag-nuevo').textContent)),null);
 ok('agenda: sin hora también se marca',await p.evaluate(()=>/Nuevo/.test(document.getElementById('agenda-sinhora').innerText)),null);
 ok('lista de reservas: marca solo a los nuevos',await p.evaluate(()=>{const f=[...document.querySelectorAll('#t-reservas tr')];const t=id=>f.find(r=>r.innerHTML.includes("abrirCobro('"+id+"')")||r.innerHTML.includes("enviarConfirm('"+id+"')"));return !!t('rE').querySelector('.tag-nuevo')&&!t('rA').querySelector('.tag-nuevo')&&!!t('rF').querySelector('.tag-nuevo');}),null);

 // Modal
 const vis=id=>p.evaluate(i=>{const e=document.getElementById(i);return !!e&&getComputedStyle(e).display!=='none';},id);
 await p.evaluate(()=>abrirEditarReserva('rE')); await p.waitForTimeout(200);
 ok('modal: cliente nuevo con ficha muestra el aviso',await vis('r-ficha-nuevo')&&await vis('r-ficha-btn'),null);
 await p.evaluate(()=>closeM('m-reserva'));
 await p.evaluate(()=>abrirEditarReserva('rA')); await p.waitForTimeout(200);
 ok('modal: cliente conocido no muestra el aviso',!(await vis('r-ficha-nuevo')),null);
 await p.evaluate(()=>closeM('m-reserva'));
 await p.evaluate(()=>abrirEditarReserva('rF')); await p.waitForTimeout(200);
 ok('modal: persona sin ficha muestra el aviso y no ofrece ficha',await vis('r-ficha-bar')&&await vis('r-ficha-nuevo')&&!(await vis('r-ficha-btn')),null);
 await p.evaluate(()=>closeM('m-reserva'));
 await p.evaluate(()=>openM('m-reserva')); await p.waitForTimeout(150);
 ok('reserva nueva vacía: sin aviso',!(await vis('r-ficha-bar')),null);
 await p.fill('#r-wsp','+56 9 1234 0000'); await p.waitForTimeout(100);
 ok('reserva nueva: WhatsApp desconocido → «cliente nuevo»',await vis('r-ficha-nuevo'),null);
 await p.fill('#r-wsp','+56 9 8754 2136'); await p.waitForTimeout(100);
 ok('reserva nueva: WhatsApp de un cliente conocido → sin aviso de nuevo',!(await vis('r-ficha-nuevo'))&&await vis('r-ficha-btn'),null);
 await p.evaluate(()=>closeM('m-reserva'));

 // Aviso en vivo
 await p.evaluate(()=>avisarReservaNueva({id:'rZ',nombre_cliente:'Alguien',whatsapp_cliente:'+56 9 0000 1111',fecha:'2026-12-01',hora:'10:00',estado:'Pendiente',fuente:'Web propia'}));
 ok('aviso en vivo: anuncia «cliente nuevo» si no lo conocemos',/cliente nuevo/.test(await p.textContent('#aviso-reserva')),await p.textContent('#aviso-reserva'));
 await p.evaluate(()=>avisarReservaNueva({id:'rY',nombre_cliente:'Juan Pérez',whatsapp_cliente:'+56 9 8754 2136',fecha:'2026-12-01',hora:'10:00',estado:'Pendiente',fuente:'Web propia'}));
 ok('aviso en vivo: no lo dice de un cliente conocido',!/cliente nuevo/.test(await p.textContent('#aviso-reserva')),await p.textContent('#aviso-reserva'));

 // La marca desaparece al atender
 await p.evaluate(()=>{ const r=S.reservas.find(x=>x.id==='rE'); r.procesado=true; r.estado='Atendida'; S.reservas=[...S.reservas]; renderAgenda(); });
 ok('al atenderlo ya no se marca',(await tag('rE'))!==true,await tag('rE'));
 ok('sin errores de JS',s.errs.length===0,s.errs);
 await s.b.close();
 console.log(res.join('\n')); console.log(res.filter(x=>x.startsWith('FALLO')).length?'HAY FALLOS':'TODO OK ('+res.length+')'); process.exit(res.some(r=>r.startsWith('FALLO'))?1:0);
})().catch(e=>{console.error('ERROR',e);process.exit(1);});
