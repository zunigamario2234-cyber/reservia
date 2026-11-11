// Mercado Pago Point en la app: configuración (dueño) y botón «Cobrar con Point» en la caja.
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
 const api=[]; let estados=[]; let cobrarResp={ok:true,orderId:'ORD0000000001'}; let cancelarResp={ok:true,cancelado:true};
 async function nueva(rol){
  const s=await sesion(rol); const p=s.p;
  await p.route('**/api/mp-point',async r=>{ const b=JSON.parse(r.request().postData()||'{}'); api.push({...b,auth:r.request().headers()['authorization']});
    let out={ok:true};
    if(b.accion==='cobrar') out=cobrarResp; else if(b.accion==='estado') out=estados.shift()||{ok:true,estado:'esperando'}; else if(b.accion==='cancelar') out=cancelarResp;
    else if(b.accion==='conectar') out={ok:true,conectado:true,token_final:'ABCD'};
    else if(b.accion==='terminales') out={ok:true,terminales:[{id:'NEWLAND_N950__N950NCB801293324',nombre:'N950 · …3324',modo:'STANDALONE'}],elegida:null};
    else if(b.accion==='elegir_terminal') out={ok:true,terminal_nombre:'N950 · …3324',activo:true,reiniciar:true};
    await r.fulfill({status:out.ok===false?400:200,contentType:'application/json',body:JSON.stringify(out)}); });
  await p.evaluate(()=>{ window.pointEspera=()=>new Promise(r=>setTimeout(r,15)); window.confirm=()=>true; });
  return s;
 }
 const abrir=async p=>{ await p.evaluate(()=>abrirCobro('r1')); await p.waitForTimeout(250); };
 const vis=(p,id)=>p.evaluate(i=>{const e=document.getElementById(i);return !!e&&getComputedStyle(e).display!=='none';},id);

 // ── Caja ──
 let s=await nueva('dueno'); let p=s.p;
 await abrir(p);
 ok('sin Point activo: el bloque no aparece',!(await vis(p,'cob-point')),null);
 await p.evaluate(()=>closeM('m-cobro'));
 await p.evaluate(()=>{ POINT={conectado:true,activo:true,terminal_elegida:true,terminal_nombre:'N950 · …3324',token_final:'ABCD'}; });
 await abrir(p);
 ok('con Point activo aparece el bloque con la terminal',await vis(p,'cob-point')&&/N950/.test(await p.textContent('#cob-point-nombre')),null);
 ok('el botón muestra el monto a cobrar',/12\.000/.test(await p.textContent('#cob-point-btn')),await p.textContent('#cob-point-btn'));
 await p.evaluate(()=>{ COBRO_CTX.gift={codigo:'GC-X',saldo:5000}; cobroRecalcular(); });
 ok('con gift card el bloque se oculta',!(await vis(p,'cob-point')),null);
 await p.evaluate(()=>{ COBRO_CTX.gift=null; cobroRecalcular(); });
 ok('sin gift card vuelve a aparecer',await vis(p,'cob-point'),null);

 // Pago aprobado con débito: registra solo
 estados=[{ok:true,estado:'esperando'},{ok:true,estado:'en_terminal'},{ok:true,estado:'pagado',metodo:'Débito',monto:12000}];
 const antes=s.rpcs.length;
 await p.evaluate(()=>cobrarConPoint());
 await p.waitForFunction(()=>!document.getElementById('m-cobro').classList.contains('open'),null,{timeout:8000}).catch(()=>{});
 const c=api.find(x=>x.accion==='cobrar');
 ok('manda el monto entero y una clave única al servidor',c&&c.monto===12000&&/^[0-9a-f-]{36}$/.test(c.clave)&&/^Bearer /.test(c.auth),c);
 const reg=s.rpcs.slice(antes).find(r=>r.n==='registrar_cobro_conjunto');
 ok('al pagar registra el cobro solo, con método Débito y el total',reg&&reg.body.p_metodo_pago==='Débito'&&reg.body.p_total_declarado===12000,reg);
 ok('el modal se cierra tras registrar',!(await p.evaluate(()=>document.getElementById('m-cobro').classList.contains('open'))),null);
 ok('no queda un cobro en curso',await p.evaluate(()=>POINT_RUN===null),null);

 // Crédito
 estados=[{ok:true,estado:'pagado',metodo:'Crédito',monto:12000}]; api.length=0;
 await abrir(p); const a2=s.rpcs.length;
 await p.evaluate(()=>cobrarConPoint()); await p.waitForTimeout(600);
 const reg2=s.rpcs.slice(a2).find(r=>r.n==='registrar_cobro_conjunto');
 ok('pago con crédito se registra como Crédito',reg2&&reg2.body.p_metodo_pago==='Crédito',reg2);

 // Cancelar
 estados=[{ok:true,estado:'esperando'},{ok:true,estado:'esperando'},{ok:true,estado:'esperando'},{ok:true,estado:'esperando'}]; api.length=0;
 await abrir(p);
 await p.evaluate(()=>{ window.pointEspera=()=>new Promise(r=>setTimeout(r,150)); });
 await p.evaluate(()=>{ cobrarConPoint(); });
 await p.waitForTimeout(250);
 ok('mientras espera: se ve el estado y el botón cancelar, y no se puede registrar a mano',await vis(p,'cob-point-estado')&&await vis(p,'cob-point-cancel')&&await p.evaluate(()=>document.getElementById('cob-btn').disabled),null);
 ok('mientras espera: el botón Cobrar con Point se oculta (no se envían dos cobros)',!(await vis(p,'cob-point-btn')),null);
 await p.evaluate(()=>pointCancelarCobro()); await p.waitForTimeout(300);
 ok('cancelar manda la orden a cancelar',api.some(x=>x.accion==='cancelar'&&x.orderId==='ORD0000000001'),api);
 ok('tras cancelar se puede volver a cobrar',await vis(p,'cob-point-btn')&&!(await p.evaluate(()=>document.getElementById('cob-btn').disabled)),null);

 // Expira
 estados=[{ok:true,estado:'expirado'}]; await p.evaluate(()=>{ window.pointEspera=()=>new Promise(r=>setTimeout(r,15)); });
 await p.evaluate(()=>cobrarConPoint()); await p.waitForTimeout(400);
 ok('orden vencida: avisa y deja reintentar sin registrar nada',/venci/.test(await p.textContent('#cob-point-msg'))&&await vis(p,'cob-point-btn'),await p.textContent('#cob-point-msg'));
 // Error del servidor al crear
 cobrarResp={ok:false,error:'La terminal ya tiene un cobro pendiente.'};
 await p.evaluate(()=>cobrarConPoint()); await p.waitForTimeout(300);
 ok('error al crear la orden: muestra el motivo y deja reintentar',/pendiente/.test(await p.textContent('#cob-point-msg'))&&await vis(p,'cob-point-btn'),await p.textContent('#cob-point-msg'));
 cobrarResp={ok:true,orderId:'ORD0000000001'};

 // Monto cambiado durante la espera: no registra solo
 estados=[{ok:true,estado:'esperando'},{ok:true,estado:'esperando'}]; api.length=0;
 await p.evaluate(()=>{ window.pointEspera=()=>new Promise(r=>setTimeout(r,120)); });
 const a3=s.rpcs.length;
 await p.evaluate(()=>{ cobrarConPoint(); });
 await p.waitForTimeout(60);
 await p.evaluate(()=>{ document.getElementById('cob-final').value=9000; cobroPrecioEditado(); });
 estados=[{ok:true,estado:'pagado',metodo:'Débito',monto:12000}];
 await p.waitForTimeout(500);
 ok('si el monto de la caja cambió tras enviar, NO registra solo',!s.rpcs.slice(a3).some(r=>r.n==='registrar_cobro_conjunto')&&/cambió/.test(await p.textContent('#cob-point-msg')),await p.textContent('#cob-point-msg'));
 ok('sin errores de JS (dueño)',s.errs.length===0,s.errs);
 await s.b.close();

 // ── Configuración ──
 s=await nueva('dueno'); p=s.p; api.length=0;
 await p.evaluate(()=>{ POINT={conectado:false,activo:false}; nav('config'); pintarPointConfig(); });
 await p.waitForTimeout(200);
 ok('el dueño ve la pestaña Terminal Point',await vis(p,'tab-point'),null);
 await p.evaluate(()=>switchTab(document.getElementById('tab-point'),'cfg-point'));
 ok('sin conectar: pide el token y no muestra la terminal',await vis(p,'pt-paso-conectar')&&!(await vis(p,'pt-paso-conectado')),null);
 ok('el campo del token es de tipo contraseña',await p.evaluate(()=>document.getElementById('pt-token').type)==='password',null);
 await p.fill('#pt-token','APP_USR-1234567890-secreto-ABCD');
 await p.evaluate(()=>{ window.loadPointConfig=async()=>{ POINT={conectado:true,activo:false,terminal_elegida:false,token_final:'ABCD'}; }; });
 await p.evaluate(()=>pointConectar()); await p.waitForTimeout(300);
 ok('conectar manda el token al servidor',api.some(x=>x.accion==='conectar'&&x.token==='APP_USR-1234567890-secreto-ABCD'),api);
 ok('tras conectar, el campo queda vacío y se ve solo el final del token',await p.inputValue('#pt-token')===''&&/ABCD/.test(await p.textContent('#pt-cuenta'))&&!(await p.content()).includes('secreto-ABCD'),await p.textContent('#pt-cuenta'));
 ok('sin terminal elegida, el interruptor está bloqueado',await p.evaluate(()=>document.getElementById('pt-activo').disabled),null);
 await p.evaluate(()=>pointBuscarTerminales()); await p.waitForTimeout(250);
 ok('lista las terminales',/N950/.test(await p.evaluate(()=>document.getElementById('pt-terminal').innerHTML)),null);
 await p.evaluate(()=>{ window.loadPointConfig=async()=>{ POINT={conectado:true,activo:true,terminal_elegida:true,terminal_nombre:'N950 · …3324',token_final:'ABCD'}; }; });
 await p.evaluate(()=>pointElegirTerminal()); await p.waitForTimeout(300);
 ok('elegir la terminal la deja activa',api.some(x=>x.accion==='elegir_terminal')&&await p.evaluate(()=>document.getElementById('pt-activo').checked),api);
 ok('sin errores de JS (config)',s.errs.length===0,s.errs);
 await s.b.close();

 // ── Otros roles ──
 s=await nueva('recepcion'); p=s.p;
 await p.evaluate(()=>{ POINT={conectado:true,activo:true,terminal_elegida:true,terminal_nombre:'N950',token_final:null}; nav('config'); pintarPointConfig(); });
 ok('recepción NO ve la pestaña de configuración de Point',!(await vis(p,'tab-point')),null);
 ok('recepción no ve datos del token en la pantalla',(await p.textContent('#pt-cuenta')).trim()===''&&await p.evaluate(()=>POINT.token_final===null),null);
 await s.b.close();

 console.log(res.join('\n')); console.log(res.filter(x=>x.startsWith('FALLO')).length?'HAY FALLOS':'TODO OK ('+res.length+')');
 process.exit(res.some(r=>r.startsWith('FALLO'))?1:0);
})().catch(e=>{console.error('ERROR',e);process.exit(1);});
