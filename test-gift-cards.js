// Prueba de punta a punta: gift cards, íconos de origen y confirmación por WhatsApp (panel).
// Corre contra un Supabase simulado. Uso: NODE_PATH=$(npm root -g) node test-gift-cards.js  (con el servidor en :8765)
const { chromium } = require('playwright'); const fs=require('fs');
const REF='dqoqykngmtxtvbokxbzp', BID='b0000000-0000-0000-0000-000000000001', UID='u0000000-0000-0000-0000-000000000001';
const hoy=new Date().toLocaleDateString('en-CA',{timeZone:'America/Santiago'});
const ayer=new Date(Date.now()-3*86400000).toLocaleDateString('en-CA',{timeZone:'America/Santiago'});
const T={
 perfiles:[{id:UID,barberia_id:BID,nombre:'Mario',rol:'dueno',email:'m@x.cl'}],
 barberias:[{id:BID,nombre:'Essentials Studio',rubro:'barberia',modo_tema:'oscuro',intervalo_min:30,iva_pct:19}],
 clientes:[{id:'c1',barberia_id:BID,nombre:'Juan',apellido:'Pérez',whatsapp:'+56912345671',created_at:'2026-10-01T10:00:00Z'}],
 servicios:[{id:'s1',barberia_id:BID,nombre:'Corte clásico',precio:12000,duracion_min:30,activo:true,orden:1},{id:'s2',barberia_id:BID,nombre:'Corte + barba',precio:18000,duracion_min:60,activo:true,orden:2}],
 barberos:[{id:'b1',barberia_id:BID,nombre:'Mario',activo:true}],
 horario_negocio:[], bloqueos_profesional:[],
 visitas:[{id:'v1',barberia_id:BID,fecha:hoy,hora:'10:00',cliente_id:'c1',barbero_nombre:'Mario',servicio:'Corte clásico',valor:12000,estado:'Atendida',fuente:'Reserva'}],
 reservas:[
  {id:'r1',barberia_id:BID,fecha:hoy,hora:'11:00',nombre_cliente:'Luis',whatsapp_cliente:'+56911111111',barbero_nombre:'Mario',servicio:'Corte clásico',estado:'Pendiente',procesado:false,fuente:'Web propia'},
  {id:'r2',barberia_id:BID,fecha:hoy,hora:'12:00',nombre_cliente:'Ana',whatsapp_cliente:'+56922222222',barbero_nombre:'Mario',servicio:'Corte + barba',estado:'Confirmada',procesado:false,fuente:'Club VIP'},
  {id:'r3',barberia_id:BID,fecha:hoy,hora:'13:00',nombre_cliente:'Beto',whatsapp_cliente:'+56933333333',barbero_nombre:'Mario',servicio:'Corte clásico',estado:'Pendiente',procesado:false,fuente:'Mi Agenda'},
  {id:'r4',barberia_id:BID,fecha:hoy,hora:'14:00',nombre_cliente:'Caro',whatsapp_cliente:'+56944444444',barbero_nombre:'Mario',servicio:'Corte clásico',estado:'Pendiente',procesado:false,fuente:'Manual'}],
 gift_cards:[
  {id:'g1',barberia_id:BID,codigo:'GC-AAAA-BBBB',servicio:'Corte clásico',valor:12000,estado:'Activa',created_at:'2026-11-01T10:00:00Z'},
  {id:'g2',barberia_id:BID,codigo:'GC-USED-USED',servicio:'Corte clásico',valor:12000,estado:'Canjeada',created_at:'2026-11-01T10:00:00Z'},
  {id:'g3',barberia_id:BID,codigo:'GC-VENC-VENC',servicio:'Corte clásico',valor:12000,estado:'Activa',vence:ayer,created_at:'2026-10-01T10:00:00Z'},
  {id:'g4',barberia_id:BID,codigo:'GC-BARB-BARB',servicio:'Corte + barba',valor:18000,estado:'Activa',created_at:'2026-11-01T10:00:00Z'}],
};
const res=[]; const ok=(n,c,extra)=>{res.push((c?'OK    ':'FALLO ')+n+(c?'':'  -> '+JSON.stringify(extra)));};
(async()=>{
 const b=await chromium.launch(); const p=await b.newPage({viewport:{width:1360,height:900}});
 const errs=[]; p.on('pageerror',e=>errs.push(e.message));
 let rpcs=[]; const updates=[]; let popup=null;
 await p.addInitScript(([ref,uid])=>{ try{ localStorage.setItem('sb-'+ref+'-auth-token',JSON.stringify({access_token:'x.y.z',refresh_token:'r',expires_at:Math.floor(Date.now()/1000)+36000,expires_in:36000,token_type:'bearer',user:{id:uid,email:'m@x.cl',aud:'authenticated',role:'authenticated',app_metadata:{},user_metadata:{}}})); }catch(e){} window.__opened=[]; window.open=function(u){window.__opened.push(u);return {focus(){}}}; },[REF,UID]);
 await p.route(/^https:\/\/(cdn\.jsdelivr\.net|cdnjs\.cloudflare\.com|unpkg\.com)\//, r=>{const u=r.request().url(); const m=/supabase-js/.test(u)?'/tmp/cdn/node_modules/@supabase/supabase-js/dist/umd/supabase.js':/chart/i.test(u)?'/tmp/cdn/node_modules/chart.js/dist/chart.umd.js':null; return m&&fs.existsSync(m)?r.fulfill({status:200,contentType:'application/javascript',body:fs.readFileSync(m)}):r.fulfill({status:200,contentType:'application/javascript',body:''});});
 await p.route(/supabase\.co\/(rest|auth|storage)\//, async r=>{
   const req=r.request(); const u=req.url(); const t=(u.match(/\/rest\/v1\/(?:rpc\/)?([a-z_]+)/)||[])[1];
   const one=(req.headers()['accept']||'').includes('pgrst.object')||/maybeSingle/.test('');
   const json=(o,st=200,h={})=>r.fulfill({status:st,contentType:'application/json',headers:h,body:JSON.stringify(o)});
   if(/\/auth\/v1\/user/.test(u)) return json({id:UID,email:'m@x.cl'});
   if(/\/rest\/v1\/rpc\//.test(u)){
     const body=req.postData()?JSON.parse(req.postData()):{}; rpcs.push({n:t,body});
     if(t==='crear_gift_card') return json({id:'gnew',barberia_id:BID,codigo:'GC-NEW1-NEW2',servicio:body.p_servicio,valor:12000,estado:'Activa',para_nombre:body.p_para_nombre,de_nombre:body.p_de_nombre,vence:body.p_vence});
     if(t==='registrar_cobro_conjunto') return json('cobro-1');
     if(t==='gift_card_consultar') return json(T.gift_cards.filter(g=>g.codigo===body.p_codigo));
     if(t==='listar_recepcion') return json([]);
     return json([]);
   }
   if(req.method()!=='GET'){ updates.push({t,m:req.method(),body:req.postData(),u}); return json([],204); }
   let rows=(T[t]||[]).slice();
   const m=u.match(/codigo=eq\.([^&]+)/); if(m) rows=rows.filter(x=>x.codigo===decodeURIComponent(m[1]));
   const acc=req.headers()['accept']||'';
   if(/pgrst\.object/.test(acc)) return rows[0]?json(rows[0]):json({code:'PGRST116',message:'no rows'},406);
   json(rows,200,{'content-range':'0-'+Math.max(rows.length-1,0)+'/'+rows.length});
 });
 await p.goto('http://localhost:8765/app.html');
 await p.waitForFunction(()=>document.getElementById('loading-screen')&&document.getElementById('loading-screen').style.display==='none',null,{timeout:15000}).catch(()=>res.push('FALLO no cargó el panel'));
 await p.waitForTimeout(500);

 // ── Pantalla Gift cards
 await p.evaluate(()=>nav('gift')); await p.waitForTimeout(300);
 const filas=await p.$$eval('#t-gift tr',a=>a.map(x=>x.innerText.replace(/\s+/g,' ')));
 ok('lista 4 gift cards',filas.length===4,filas);
 ok('la vencida se ve como Vencida',filas.some(f=>/GC-VENC-VENC.*Vencida/.test(f)),filas);
 ok('activas = 2 (la vencida no cuenta)',(await p.textContent('#g-activas')).trim()==='2');
 ok('por canjear suma 30.000',/30\.000/.test(await p.textContent('#g-pendiente')),await p.textContent('#g-pendiente'));
 await p.fill('#q-gift','barb'); await p.evaluate(()=>renderGiftCards());
 ok('buscar filtra',(await p.$$('#t-gift tr')).length===1);
 await p.fill('#q-gift',''); await p.selectOption('#f-gift-estado','Canjeada');
 ok('filtro por estado',(await p.$$('#t-gift tr')).length===1);
 await p.selectOption('#f-gift-estado','');
 await p.screenshot({path:'/tmp/gift_lista.png'});

 // ── Crear
 await p.click('text=+ Nueva gift card'); await p.waitForTimeout(200);
 await p.click('#gift-btn');
 ok('sin servicio no llama a la base',!rpcs.some(r=>r.n==='crear_gift_card'));
 await p.selectOption('#gift-servicio','Corte clásico'); await p.fill('#gift-para','Pedro'); await p.fill('#gift-de','Ana');
 await p.click('#gift-btn'); await p.waitForTimeout(400);
 const c=rpcs.find(r=>r.n==='crear_gift_card');
 ok('crear_gift_card recibe servicio y nombres',c&&c.body.p_servicio==='Corte clásico'&&c.body.p_para_nombre==='Pedro'&&c.body.p_de_nombre==='Ana',c);
 ok('muestra el código generado',(await p.textContent('#gift-codigo')).trim()==='GC-NEW1-NEW2');
 await p.screenshot({path:'/tmp/gift_codigo.png'});
 await p.click('#m-gift >> text=Cerrar');

 // ── Cobro con gift card
 async function abrir(id){ await p.evaluate(i=>abrirCobro(i),id); await p.waitForTimeout(250); }
 async function aplicar(cod){ await p.fill('#cob-gift-codigo',cod); await p.click('#cob-gift-btn'); await p.waitForTimeout(300); return (await p.textContent('#cob-gift-msg')).trim(); }
 await abrir('r1');
 let m=await aplicar('gc-aaaa-bbbb');
 ok('código válido (en minúsculas) se acepta',/válida/.test(m),m);
 ok('método queda Gift card y bloqueado',await p.$eval('#cob-metodo',e=>e.value==='Gift card'&&e.disabled));
 await p.screenshot({path:'/tmp/gift_cobro.png'});
 await p.click('#cob-btn'); await p.waitForTimeout(400);
 const cb=rpcs.filter(r=>r.n==='registrar_cobro_conjunto').pop();
 ok('el cobro envía p_gift_codigo normalizado',cb&&cb.body.p_gift_codigo==='GC-AAAA-BBBB',cb&&cb.body);
 ok('el método enviado es Gift card',cb&&cb.body.p_metodo_pago==='Gift card',cb&&cb.body);

 await abrir('r1'); m=await aplicar('GC-USED-USED'); ok('canjeada se rechaza',/ya fue canjeada/.test(m),m);
 ok('...y no queda aplicada',await p.$eval('#cob-metodo',e=>!e.disabled));
 m=await aplicar('GC-VENC-VENC'); ok('vencida se rechaza',/venció/.test(m),m);
 m=await aplicar('GC-NOPE-NOPE'); ok('inexistente se rechaza',/no existe/.test(m),m);
 m=await aplicar('GC-BARB-BARB'); ok('de otro servicio se rechaza',/es para «Corte \+ barba»/.test(m),m);
 m=await aplicar(''); ok('vacío pide el código',/Escribe el código/.test(m),m);
 // quitar
 await p.fill('#cob-gift-codigo','GC-AAAA-BBBB'); await p.click('#cob-gift-btn'); await p.waitForTimeout(250);
 await p.click('#cob-gift-btn'); await p.waitForTimeout(150);
 ok('quitar devuelve el método de pago',await p.$eval('#cob-metodo',e=>!e.disabled&&e.value==='Efectivo'));
 const n0=rpcs.filter(r=>r.n==='registrar_cobro_conjunto').length;
 await p.click('#cob-btn'); await p.waitForTimeout(400);
 const cb2=rpcs.filter(r=>r.n==='registrar_cobro_conjunto').pop();
 ok('cobro normal no manda código',rpcs.filter(r=>r.n==='registrar_cobro_conjunto').length===n0+1&&cb2.body.p_gift_codigo===null,cb2&&cb2.body);
 await abrir('r2'); // otro cobro: el estado de gift no se arrastra
 ok('abrir otro cobro limpia el código',await p.$eval('#cob-gift-codigo',e=>e.value===''&&!e.disabled));
 await p.evaluate(()=>closeM('m-cobro'));

 // ── Agenda: íconos de origen
 await p.evaluate(()=>nav('agenda')); await p.waitForTimeout(500);
 const tips=await p.$$eval('.cal-block .ag-origen',a=>a.map(x=>x.title));
 ok('4 íconos de origen en los bloques',tips.length===4,tips);
 ok('cada origen con su texto',['web','app del club','profesional','panel'].every(w=>tips.some(t=>t.toLowerCase().includes(w))),tips);
 ok('la cita ya cobrada (visita) no lleva ícono',await p.$$eval('.cal-block[data-tipo="cita"] .ag-origen,.cal-block[data-tipo="visita"] .ag-origen',a=>a.length===0));
 ok('leyenda con 4 símbolos',(await p.$$('#ag-leyenda .ag-origen')).length===4);
 await p.screenshot({path:'/tmp/agenda_origen.png'});

 // ── Abrir una reserva => botón de confirmación por WhatsApp
 await p.evaluate(()=>abrirEditarReserva('r1')); await p.waitForTimeout(250);
 ok('el modal muestra el origen',/web/i.test(await p.textContent('#r-origen')),await p.textContent('#r-origen'));
 ok('el botón de confirmación está visible',await p.isVisible('#r-btn-wa'));
 await p.click('#r-btn-wa'); await p.waitForTimeout(300);
 const op=await p.evaluate(()=>window.__opened);
 ok('abre wa.me al número de la reserva',op.length===1&&/wa\.me\/56911111111/.test(op[0]),op);
 const txt=op[0]?decodeURIComponent(op[0].split('text=')[1]||''):'';
 ok('el mensaje trae nombre, fecha, hora y servicio',/Luis/.test(txt)&&txt.includes(hoy)&&/11:00/.test(txt)&&/Corte clásico/.test(txt),txt);
 await p.screenshot({path:'/tmp/modal_reserva.png'});
 await p.evaluate(()=>closeM('m-reserva'));
 // nueva reserva: sin botón
 await p.evaluate(()=>openM('m-reserva')); await p.waitForTimeout(150);
 ok('reserva nueva no muestra el botón ni el origen',!(await p.isVisible('#r-btn-wa'))&&!(await p.isVisible('#r-origen')));
 await p.evaluate(()=>closeM('m-reserva'));
 // cita (visita)
 await p.evaluate(()=>abrirEditarCita('v1')); await p.waitForTimeout(250);
 ok('la cita cobrada también tiene botón de confirmación',await p.isVisible('#v-btn-wa'));
 await p.evaluate(()=>{window.__opened=[];}); await p.click('#v-btn-wa'); await p.waitForTimeout(250);
 const op2=await p.evaluate(()=>window.__opened);
 ok('abre wa.me al cliente de la cita',op2.length===1&&/wa\.me\/56912345671/.test(op2[0]),op2);
 await p.evaluate(()=>closeM('m-cita')); await p.evaluate(()=>openM('m-cita')); await p.waitForTimeout(150);
 ok('cita nueva no muestra el botón',!(await p.isVisible('#v-btn-wa')));
 // sin plantilla activa => texto por defecto (S.plantillas vacío en el mock)
 ok('sin plantilla usa mensaje por defecto',/confirmada/.test(txt),txt);
 // Reservas tabla
 await p.evaluate(()=>nav('reservas')); await p.waitForTimeout(250);
 ok('tabla de reservas con íconos',(await p.$$('#t-reservas .ag-origen')).length===4);

 ok('sin errores de página',errs.length===0,errs);
 console.log(res.join('\n')); console.log(res.filter(x=>x.startsWith('FALLO')).length+' fallos de '+res.length);
 await b.close();
})();
