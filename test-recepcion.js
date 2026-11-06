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
 // ───────── Recepción
 let {p,b,errs,reqs}=await sesion('recepcion');
 ok('etiqueta de rol Recepción',(await p.textContent('#sb-rol')).trim()==='Recepción');
 const visibles=await p.$$eval('.nav-item',a=>a.filter(x=>x.offsetParent!==null).map(x=>x.dataset.page));
 ok('solo ve agenda, reservas y caja',JSON.stringify(visibles.sort())===JSON.stringify(['agenda','caja','reservas']),visibles);
 ok('arranca en la agenda',await p.$eval('#p-agenda',e=>e.classList.contains('active')));
 await p.evaluate(()=>nav('dashboard')); ok('nav(dashboard) lo manda a la agenda',await p.$eval('#p-agenda',e=>e.classList.contains('active')));
 await p.evaluate(()=>nav('config')); ok('nav(config) lo manda a la agenda',await p.$eval('#p-agenda',e=>e.classList.contains('active')));
 ok('no ve el botón + Cita',!(await p.isVisible('.topbar button[onclick*="m-cita"]')));
 ok('lee inventario_recepcion (sin costos), no inventario',reqs.includes('get:inventario_recepcion')&&!reqs.includes('get:inventario'),reqs);
 await p.evaluate(()=>nav('reservas')); await p.waitForTimeout(200);
 ok('en Reservas no hay botón de borrar',(await p.$$('#t-reservas .btn-danger')).length===0);
 await p.evaluate(()=>abrirEditarReserva('r1')); await p.waitForTimeout(200);
 ok('en la reserva no hay "Eliminar reserva"',!(await p.isVisible('#r-btn-eliminar')));
 ok('pero sí "Enviar confirmación" y "Cobrar"',await p.isVisible('#r-btn-wa')&&await p.isVisible('#r-btn-pagar'));
 await p.evaluate(()=>closeM('m-reserva'));
 // Caja
 await p.evaluate(()=>nav('caja')); await p.waitForTimeout(300);
 const cards=await p.$$eval('#caja-cards .mc',a=>a.map(x=>x.innerText.replace(/\s+/g,' ')));
 ok('vendido hoy = 56.000 (cancelada y día antiguo no cuentan)',/Vendido hoy \$56\.000/i.test(cards[0]),cards);
 ok('propinas = 1.000',/\$1\.000/.test(cards[1]),cards);
 ok('dinero recibido = 45.000 (sin gift card)',/\$45\.000/.test(cards[2]),cards);
 const mets=await p.$$eval('#caja-metodos .mc',a=>a.map(x=>x.innerText.replace(/\s+/g,' ')));
 ok('efectivo = 22.000 (12.000 + propina 1.000 + producto 9.000)',mets.some(m=>/^Efectivo \$22\.000/i.test(m)),mets);
 ok('débito = 18.000',mets.some(m=>/^Débito \$18\.000/i.test(m)),mets);
 ok('gift card = 12.000 listada aparte',mets.some(m=>/^Gift card \$12\.000/i.test(m)),mets);
 ok('producto sin método va a "Sin método"',mets.some(m=>/^Sin método \$5\.000/i.test(m)),mets);
 ok('5 movimientos',(await p.$$('#t-caja tr')).length===5);
 await p.fill('#caja-fondo','20000'); await p.fill('#caja-contado','42000');
 ok('esperado = fondo + efectivo = 42.000',/42\.000/.test(await p.inputValue('#caja-esperado')));
 ok('cuadra',/Cuadra/.test(await p.textContent('#caja-dif')));
 await p.fill('#caja-contado','41000'); ok('faltan 1.000',/Faltan \$1\.000/.test(await p.textContent('#caja-dif')),await p.textContent('#caja-dif'));
 await p.fill('#caja-contado','43500'); ok('sobran 1.500',/Sobran \$1\.500/.test(await p.textContent('#caja-dif')));
 await p.evaluate(()=>renderCaja()); ok('el cuadre se recuerda al recargar la pantalla',(await p.inputValue('#caja-fondo'))==='20000'&&(await p.inputValue('#caja-contado'))==='43500');
 await p.screenshot({path:'/tmp/caja.png'});
 await p.click('text=+ Venta de productos'); await p.waitForTimeout(300);
 ok('la venta de productos abre el cobro',await p.$eval('#m-cobro',e=>e.classList.contains('open')));
 ok('sin errores de página (recepción)',errs.length===0,errs);
 await b.close();

 // ───────── Dueño
 ({p,b,errs,reqs,rpcs}=await sesion('dueno'));
 ok('dueño ve el menú completo',(await p.$$eval('.nav-item',a=>a.filter(x=>x.offsetParent!==null).length))>=10);
 ok('dueño lee inventario real',reqs.includes('get:inventario'));
 await p.evaluate(()=>nav('caja')); await p.waitForTimeout(250);
 ok('dueño también ve la caja (solo hoy)',/\$56\.000/.test(await p.textContent('#caja-cards')));
 await p.evaluate(()=>nav('profesionals')); await p.waitForTimeout(400);
 ok('Equipo lista la cuenta de Recepción',/Ana Caja/.test(await p.textContent('#l-recepcion')));
 await p.click('text=+ Crear cuenta de Recepción'); await p.waitForTimeout(200);
 await p.click('#rec-btn'); ok('sin nombre no avanza',/Falta el nombre/.test(await p.textContent('#rec-alert')));
 await p.fill('#rec-nombre','Pía'); await p.fill('#rec-email','Pia@Correo.cl');
 await p.click('#rec-btn'); await p.waitForTimeout(600);
 const orden=reqs.filter(x=>/invitar_recepcion|signup|reclamar_recepcion|cancelar/.test(x)).join('>');
 ok('flujo: invitar → registrar → reclamar',orden.endsWith('rpc:invitar_recepcion>signup>rpc:reclamar_recepcion'),orden);
 ok('el correo viaja en minúsculas',rpcs.find(r=>r.n==='invitar_recepcion')?.body.p_email==='pia@correo.cl');
 ok('muestra los datos de acceso',/pia@correo\.cl/.test(await p.textContent('#rec-datos')));
 await p.screenshot({path:'/tmp/rec_modal.png'});
 const wa=await p.evaluate(()=>{ const o=[]; window.abrirWA=(n,m)=>o.push([n,m]);
   S.barberia.link_reviews='https://g.page/r/abc/review';
   S.encuestas=[{id:'e1',cliente_id:'c1',visita_id:'v1',puntaje:5,respondida_at:'2026-11-05T10:00:00Z',vista_at:null,enviada_at:'2026-11-05T09:00:00Z'}];
   S.plantillas=[{evento:'Pedir reseña',activo:true,mensaje:'Hola {nombre} {reviews}'}];
   renderEncuestas(); const hay=!!document.querySelector('#l-enc-resp [onclick*=pedirResenaWA]');
   pedirResenaWA('e1'); return {hay,o}; });
 ok('4-5★ ofrece "Pedir reseña en Google"',wa.hay,wa);
 ok('el mensaje lleva el link de Google',wa.o.length===1&&/g\.page\/r\/abc\/review/.test(wa.o[0][1])&&/Juan/.test(wa.o[0][1]),wa.o);
 ok('link inválido se rechaza, g.page se acepta',await p.evaluate(()=>!normalizarLinkResenas('https://evil.com/x').ok&&normalizarLinkResenas('g.page/r/a/review').ok));
 const av=await p.evaluate(()=>{ avisarReservaNueva({nombre_cliente:'Pedro',servicio:'Corte clásico',fecha:'2026-11-07',hora:'10:00:00',fuente:'Web propia'}); const e=document.getElementById('aviso-reserva'); return {show:e.classList.contains('show'),txt:e.textContent,boton:!!document.getElementById('btn-sonido-aviso')}; });
 ok('reserva nueva muestra el aviso con cliente y servicio',av.show&&/Pedro/.test(av.txt)&&/Corte clásico/.test(av.txt)&&av.boton,av);
 await p.click('#btn-sonido-aviso'); ok('el botón silencia los avisos',(await p.textContent('#btn-sonido-aviso')).trim()==='🔕');
 await p.click('#btn-sonido-aviso'); ok('y los reactiva',(await p.textContent('#btn-sonido-aviso')).trim()==='🔔');
 const pc=await p.evaluate(async()=>{ await pintarPush(); const e=document.getElementById('push-card'); return {vis:e.style.display!=='none',txt:e.textContent}; });
 ok('el dueño ve la tarjeta de avisos push',pc.vis&&/avisos/i.test(pc.txt),pc);
 ok('el service worker de push existe y maneja push y clic',await p.evaluate(async()=>{ const t=await (await fetch('/panel-sw.js')).text(); return /addEventListener\('push'/.test(t)&&/notificationclick/.test(t); }));
 ok('el manifest del panel es instalable',await p.evaluate(async()=>{ const m=await (await fetch('/panel-manifest.json')).json(); return m.display==='standalone'&&m.start_url==='/app.html'&&m.icons.length>=2; }));
 ok('sin errores de página (dueño)',errs.length===0,errs);
 await b.close();

 // ───────── Registro falla => se cancela la invitación
 ({p,b,errs,reqs,rpcs}=await sesion('dueno',true));
 await p.evaluate(()=>nav('profesionals')); await p.waitForTimeout(300);
 await p.click('text=+ Crear cuenta de Recepción'); await p.fill('#rec-nombre','Pía'); await p.fill('#rec-email','pia@correo.cl');
 await p.click('#rec-btn'); await p.waitForTimeout(600);
 ok('si el registro falla se cancela la invitación',reqs.includes('rpc:cancelar_invitacion_recepcion')&&!reqs.includes('rpc:reclamar_recepcion'),reqs);
 ok('y se muestra el error',/already registered|Error/.test(await p.textContent('#rec-alert')));
 await b.close();

 console.log(res.join('\n')); console.log(res.filter(x=>x.startsWith('FALLO')).length+' fallos de '+res.length);
})();
