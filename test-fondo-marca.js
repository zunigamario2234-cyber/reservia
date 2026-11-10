// Fondo con el color de la marca: pura (tema.js) y panel.
const { chromium } = require('playwright'); const fs=require('fs');
const REF='dqoqykngmtxtvbokxbzp', BID='b0000000-0000-0000-0000-000000000001', UID='u0000000-0000-0000-0000-000000000001';
const hoy=new Date().toLocaleDateString('en-CA',{timeZone:'America/Santiago'});
function datos(rol){ return {
 perfiles:[{id:UID,barberia_id:BID,nombre:rol==='recepcion'?'María':'Mario',rol,sucursal_id:rol==='recepcion'?'su2':null}],
 barberias:[{id:BID,slug:'essentials-studio',nombre:'Essentials Studio',rubro:'Barbería / Peluquería / Centro de estética',color_marca:globalThis.ACC_T,color_fondo_marca:globalThis.FM_T,modo_tema:'oscuro',intervalo_min:30,iva_pct:19}],
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


const T = require('./tema.js');
const cont = (a, b) => T.contrasteHex(a, b);
(async()=>{
 // ── funciones puras: el contraste se cumple para cualquier color de fondo ──
 const fondos=['#8A8D91','#2F6B4F','#6B1F3A','#E8DCC4','#111111','#F5F5F5','#F2C230','#9CC3E8','#7A7A7A','#3B6EA5','#C0392B','#FFFFFF','#000000'];
 const accs=['#F2C230','#2F6B4F','#6B1F3A',null];
 let malos=[];
 fondos.forEach(f=>accs.forEach(a=>{
   const v=T.derivarSuperficies({modo:'oscuro',colorMarca:a,colorFondoMarca:f});
   const txt=cont(v['--texto'],v['--tarjeta']), txtF=cont(v['--texto'],v['--fondo']), acc=cont(v['--acento'],v['--fondo']), btn=cont(v['--texto-sobre-acento'],v['--acento']);
   if(txt<4.5||txtF<4.5||acc<3||btn<4.5) malos.push([f,a,txt.toFixed(1),txtF.toFixed(1),acc.toFixed(1),btn.toFixed(1)]);
 }));
 ok('texto ≥4,5:1, acento ≥3:1 y botón ≥4,5:1 con 13 fondos × 4 acentos',malos.length===0,malos.slice(0,4));
 ok('el modo lo decide el fondo: verde oscuro → oscuro, crema → claro',T.modoDeFondoMarca('#2F6B4F')==='oscuro'&&T.modoDeFondoMarca('#E8DCC4')==='claro',null);
 const vg=T.derivarSuperficies({modo:'oscuro',colorMarca:'#F2C230',colorFondoMarca:'#2F6B4F'});
 const [r,g,b]=T.rgbDe(vg['--fondo']);
 ok('el fondo sigue siendo verde (no se va a gris)',g>r&&g>b,vg['--fondo']);
 ok('sin fondo de marca todo queda igual que antes',T.derivarSuperficies({modo:'oscuro',colorMarca:null})===null && JSON.stringify(T.derivarSuperficies({modo:'claro',colorMarca:'#2957D6'}))===JSON.stringify(T.derivarSuperficies({modo:'claro',colorMarca:'#2957D6',colorFondoMarca:null})),null);
 ok('un valor inválido de fondo se ignora',T.derivarSuperficies({modo:'oscuro',colorMarca:null,colorFondoMarca:'rojo'})===null,null);
 // sugerencias
 const an2={fondo:null,fondoUniforme:false,fondoTransparente:true,clase:'color',colorRepresentativo:'#2F6B4F',colorMedio:'#2F6B4F',paleta:['#2F6B4F','#F2C230']};
 const sg=T.sugerirFondoMarca(an2).sugerido;
 ok('logo de dos colores: sugiere uno de fondo y el otro de acento',sg&&sg.fondo==='#2F6B4F'&&sg.acento==='#F2C230',sg);
 const an1={fondo:null,fondoUniforme:false,fondoTransparente:true,clase:'color',colorRepresentativo:'#2F6B4F',colorMedio:'#2F6B4F',paleta:['#2F6B4F']};
 ok('logo de un solo color: no sugiere (queda claro/oscuro)',T.sugerirFondoMarca(an1).sugerido===null,null);
 const anG={fondo:'#8A8D91',fondoUniforme:true,fondoTransparente:false,clase:'color',colorRepresentativo:'#C0392B',colorMedio:'#555',paleta:['#C0392B']};
 const sgG=T.sugerirFondoMarca(anG);
 ok('logo con fondo gris: el gris es candidato de fondo y el color su acento',sgG.fondos[0]==='#8A8D91'&&sgG.sugerido&&sgG.sugerido.acento==='#C0392B',sgG);
 ok('logo monocromático sin análisis: no hay candidatos',T.sugerirFondoMarca(null).fondos.length===0,null);

 // ── panel ──
 globalThis.FM_T='#2F6B4F'; globalThis.ACC_T='#F2C230';
 let s=await sesion('dueno'); let p=s.p;
 const esp=T.derivarSuperficies({modo:'oscuro',colorMarca:'#F2C230',colorFondoMarca:'#2F6B4F'});
 const v=await p.evaluate(()=>({bg:document.documentElement.style.getPropertyValue('--bg'),p1:document.documentElement.style.getPropertyValue('--p1'),claro:document.body.classList.contains('panel-claro')}));
 ok('panel con fondo verde: usa ese fondo y el acento amarillo',v.bg===esp['--fondo']&&v.p1===esp['--acento']&&!v.claro,[v,esp['--fondo']]);
 ok('sin errores de página',s.errs.length===0,s.errs);
 await s.b.close();
 globalThis.FM_T='#E8DCC4'; globalThis.ACC_T='#2F6B4F';
 s=await sesion('dueno'); p=s.p;
 ok('fondo crema → el panel pasa solo a modo claro',await p.evaluate(()=>document.body.classList.contains('panel-claro')),null);
 await s.b.close();
 globalThis.FM_T=null; globalThis.ACC_T=null;
 s=await sesion('dueno'); p=s.p;
 ok('sin fondo de marca el panel es el de siempre',await p.evaluate(()=>!document.body.classList.contains('panel-claro')&&document.documentElement.style.getPropertyValue('--bg')===''),null);
 // guardar: va color_fondo_marca
 const patches=[]; p.on('request',r=>{ if(/barberias/.test(r.url())&&r.method()==='PATCH') patches.push(JSON.parse(r.postData()||'null')); });
 await p.evaluate(()=>{ nav('config'); TEMA.color='#F2C230'; temaElegirFondo('#2F6B4F'); });
 await p.waitForTimeout(200);
 ok('al elegir fondo, el modo manual se bloquea y el selector marca la muestra',await p.evaluate(()=>document.getElementById('tema-modo').disabled)&&await p.evaluate(()=>document.querySelectorAll('#tema-fondos button').length>=2),null);
 await p.evaluate(()=>temaGuardar()); await p.waitForTimeout(500);
 ok('guardar envía color_fondo_marca y el modo concreto',patches.some(x=>x&&x.color_fondo_marca==='#2F6B4F'&&x.modo_tema==='oscuro'&&x.color_marca==='#F2C230'),patches);
 await p.evaluate(()=>{ temaElegirFondo(null); }); await p.evaluate(()=>temaGuardar()); await p.waitForTimeout(500);
 ok('«Neutro» guarda null y devuelve el modo manual',patches.some(x=>x&&x.color_fondo_marca===null)&&await p.evaluate(()=>!document.getElementById('tema-modo').disabled),patches);
 await s.b.close();
 console.log(res.join('\n')); console.log(res.filter(x=>x.startsWith('FALLO')).length+' fallos de '+res.length);
})();
