// Inventario: editar producto (nombre, stock, precios) y menú lateral alcanzable en pantallas bajas.
const { chromium } = require('playwright'); const fs=require('fs');
const REF='dqoqykngmtxtvbokxbzp', BID='b0000000-0000-0000-0000-000000000001', UID='u0000000-0000-0000-0000-000000000001';
const hoy=new Date().toLocaleDateString('en-CA',{timeZone:'America/Santiago'});
let FLAG=true;
function datos(rol){ return {
 perfiles:[{id:UID,barberia_id:BID,nombre:rol==='recepcion'?'María':'Mario',rol,sucursal_id:rol==='recepcion'?'su2':null}],
 barberias:[{id:BID,slug:'essentials-studio',nombre:'Essentials Studio',rubro:'barberia',modo_tema:'oscuro',intervalo_min:30,iva_pct:19,financiero_v2:FLAG,modelo_comercial:'A',modelo_vigente_desde:'2026-11-01',rut:'76.111.111-1',config_tributaria_validada:false,comision_producto_en_boleta:true}],
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

 cobro_lineas_netas:[
  {id:'l1',barberia_id:BID,sucursal_id:'su1',tipo:'servicio',barbero_nombre:'Mario',servicio:'Corte clásico',precio_original:17850,descuento:0,precio_final:17850,precio_final_neto:17850,devuelto:0,pct_aplicado:55,regla_version:1,participacion_profesional:9818,profesional_neto:9818,establecimiento_neto:8032,propina:2000,abono_previo:0,modelo:'A',clasificacion_tributaria:'ingreso_propio',metodo_pago:'Efectivo',fecha_cobro:hoy,estado_conciliacion:'pendiente'},
  {id:'l2',barberia_id:BID,sucursal_id:'su2',tipo:'servicio',barbero_nombre:'Felipe',servicio:'Barba',precio_original:15000,descuento:0,precio_final:15000,precio_final_neto:15000,devuelto:0,pct_aplicado:50,regla_version:0,participacion_profesional:7500,profesional_neto:7500,establecimiento_neto:7500,propina:0,abono_previo:5000,modelo:'A',clasificacion_tributaria:'ingreso_propio',metodo_pago:'Débito',fecha_cobro:hoy,estado_conciliacion:'conciliado'},
  {id:'l3',barberia_id:BID,sucursal_id:'su1',tipo:'servicio',barbero_nombre:'Mario',servicio:'Corte clásico',precio_original:12000,descuento:0,precio_final:12000,precio_final_neto:12000,devuelto:0,pct_aplicado:50,regla_version:0,participacion_profesional:6000,profesional_neto:6000,establecimiento_neto:6000,propina:0,abono_previo:0,modelo:'A',clasificacion_tributaria:'ingreso_propio',metodo_pago:'Gift card',fecha_cobro:hoy,estado_conciliacion:'sin_caja'}],
 liquidaciones:[{id:'q1',barberia_id:BID,barbero_nombre:'Mario',desde:'2026-11-01',hasta:'2026-11-07',estado:'pagada_parcial',servicios_n:2,total_cobrado:29850,honorarios_brutos:15818,comision_productos:900,propinas:2000,anticipos:0,retenciones_aplicadas:0,ppm_estimado:1582,ajustes:0,total_a_transferir:18718,total_transferido:5000,created_at:'2026-11-07T10:00:00Z'}],
 liquidacion_pagos:[{id:'pg1',liquidacion_id:'q1',monto:5000,medio:'Transferencia',comprobante:'C-1',fecha:'2026-11-07',created_at:'2026-11-07T11:00:00Z'}],
 liquidacion_ajustes:[],
 arriendos_sillon:[],
 documentos_tributarios:[{id:'d1',barberia_id:BID,tipo:'boleta_honorarios',folio:null,fecha_emision:null,rut_emisor:'11.111.111-1',rut_receptor:'76.111.111-1',honorarios_brutos:15818,retencion_pct:15.25,retencion:2412,ppm:0,estado:'pendiente',verificado_manual:false,advertencia:null,created_at:'2026-11-07T12:00:00Z'}],
 reglas_distribucion:[{id:'rg1',barberia_id:BID,alcance:'negocio',pct_profesional:55,base:'bruto',version:1,vigente_desde:'2026-11-01',created_at:'2026-11-01T00:00:00Z'}],
 inventario_recepcion:[{id:'i1',barberia_id:BID,codigo:'SH-1',nombre:'Shampoo',stock:5,precio_venta:9000}],
};}
const DLG=[]; const writesG=[]; const res=[]; const ok=(n,c,extra)=>{res.push((c?'OK    ':'FALLO ')+n+(c?'':'  -> '+JSON.stringify(extra)));};
async function sesion(rol,signupFalla){
 const T=datos(rol); const reqs=[]; const rpcs=[];
 const b=await chromium.launch(); const p=await b.newPage({viewport:{width:1360,height:900}});
 const errs=[]; p.on('pageerror',e=>errs.push(e.message));
 await p.addInitScript(([ref,uid])=>{ try{ localStorage.setItem('sb-'+ref+'-auth-token',JSON.stringify({access_token:'x.y.z',refresh_token:'r',expires_at:Math.floor(Date.now()/1000)+36000,expires_in:36000,token_type:'bearer',user:{id:uid,email:'m@x.cl',aud:'authenticated',role:'authenticated',app_metadata:{},user_metadata:{}}})); }catch(e){} window.__opened=[]; window.open=function(u){window.__opened.push(u);return {focus(){}}}; },[REF,UID]);
 await p.route(/^https:\/\/(cdn\.jsdelivr\.net|cdnjs\.cloudflare\.com|unpkg\.com)\//, r=>{const u=r.request().url(); const m=/supabase-js/.test(u)?'/tmp/cdn/node_modules/@supabase/supabase-js/dist/umd/supabase.js':/chart/i.test(u)?'/tmp/cdn/node_modules/chart.js/dist/chart.umd.js':/xlsx/i.test(u)?'/tmp/cdn/node_modules/xlsx/dist/xlsx.full.min.js':null; return m&&fs.existsSync(m)?r.fulfill({status:200,contentType:'application/javascript',body:fs.readFileSync(m)}):r.fulfill({status:200,contentType:'application/javascript',body:''});});
 await p.route(/supabase\.co\/(rest|auth|storage)\//, async r=>{
   const req=r.request(); const u=req.url();
   const json=(o,st=200,h={})=>r.fulfill({status:st,contentType:'application/json',headers:h,body:JSON.stringify(o)});
   if(/\/auth\/v1\/user/.test(u)) return json({id:UID,email:'m@x.cl'});
   if(/\/auth\/v1\/signup/.test(u)){ reqs.push('signup'); if(signupFalla) return json({code:422,msg:'User already registered'},422); return json({access_token:'a.b.c',token_type:'bearer',expires_in:3600,refresh_token:'r',user:{id:'newu',email:'x',aud:'authenticated',role:'authenticated'}}); }
   const t=(u.match(/\/rest\/v1\/(?:rpc\/)?([a-z_]+)/)||[])[1];
   if(/\/rest\/v1\/rpc\//.test(u)){ const body=req.postData()?JSON.parse(req.postData()):{}; rpcs.push({n:t,body}); reqs.push('rpc:'+t);
     if(t==='listar_recepcion') return json([{id:'rx1',nombre:'Ana Caja',email:'ana@x.cl',desde:'2026-11-01T10:00:00Z'}]);
     if(t==='fin_iva_mes') return json([{iva_debito:5700,iva_credito:2000,remanente_anterior:3100,remanente_reajustado:3162,iva_a_pagar:538,remanente_nuevo:0}]);
     if(t==='fin_liquidacion_base_boleta') return json([{honorarios_servicios:15818,comision_productos:900,monto_boleta:16718,propinas_fuera:2000,incluye_productos:true}]);
     if(t==='fin_liquidacion_crear') return json('q2');
     return json(null); }
   if(req.method()!=='GET'){ if(!/rpc/.test(u)) writesG.push({m:req.method(),u:decodeURIComponent(u),b:req.postData()?JSON.parse(req.postData()):null}); return json([],204); }
   reqs.push('get:'+t);
   const rows=(T[t]||[]).slice(); const acc=req.headers()['accept']||'';
   if(/pgrst\.object/.test(acc)) return rows[0]?json(rows[0]):json({code:'PGRST116'},406);
   json(rows,200,{'content-range':'0-'+Math.max(rows.length-1,0)+'/'+rows.length});
 });
 p.on('dialog',d=>d.accept(d.type()==='prompt'?(DLG.shift()||'x'):undefined)); await p.goto('http://localhost:8765/app.html');
 await p.waitForFunction(()=>document.getElementById('loading-screen')&&document.getElementById('loading-screen').style.display==='none',null,{timeout:15000}).catch(()=>res.push('FALLO no cargó el panel ('+rol+')'));
 await p.waitForTimeout(500);
 return {p,b,errs,reqs,rpcs};
}



(async()=>{
 // 1) módulo apagado: sin menú, con tarjeta para activarlo
 FLAG=false;
 let s=await sesion('dueno');
 let v=await s.p.evaluate(()=>({nav:document.querySelector('.nav-item[data-page="financiero"]').style.display,card:document.getElementById('imp-fin-card').style.display}));
 ok('apagado: no aparece "Financiero" en el menú',v.nav==='none',v);
 await s.p.evaluate(()=>nav('impuestos')); await s.p.waitForTimeout(300);
 const act=await s.p.evaluate(()=>({est:document.getElementById('imp-fin-estado').textContent,card:getComputedStyle(document.getElementById('imp-fin-card')).display}));
 ok('apagado: Impuestos ofrece activarlo',act.est==='Desactivado'&&act.card!=='none',act);
 await s.b.close();
 // recepción nunca lo ve
 FLAG=true; s=await sesion('recepcion');
 v=await s.p.evaluate(()=>getComputedStyle(document.querySelector('.nav-item[data-page="financiero"]')).display);
 ok('recepción no ve "Financiero"',v==='none',v); await s.b.close();

 // 2) módulo prendido
 s=await sesion('dueno'); const {p,errs}=s;
 ok('prendido: aparece en el menú',await p.evaluate(()=>document.querySelector('.nav-item[data-page="financiero"]').style.display!=='none'));
 await p.evaluate(()=>nav('financiero')); await p.waitForTimeout(600);
 const caja=await p.evaluate(()=>[...document.querySelectorAll('#fin-caja-cards .mc')].map(m=>m.querySelector('.mc-label').textContent+'='+m.querySelector('.mc-val').textContent));
 const val=l=>(caja.find(x=>x.startsWith(l))||'').split('=')[1];
 ok('Caja: entró = 17.850+2.000 propina + (15.000-5.000 abono) = $29.850 (la gift card no entra)',val('Entró a caja')==='$29.850',caja);
 ok('Caja: propinas aparte $2.000 y plata del negocio $21.532',val('Propinas')==='$2.000'&&val('Plata del negocio')==='$21.532',caja);
 ok('Caja: por pagar a profesionales $23.318 y gift cards $12.000',val('Por pagar')==='$23.318'&&val('Gift cards')==='$12.000',caja);
 const medios=await p.evaluate(()=>document.getElementById('fin-caja-medios').innerText);
 ok('Caja: separa por medio de pago',/Efectivo/.test(medios)&&/Débito/.test(medios)&&/Gift card/.test(medios),medios);
 // exportar CSV desde Caja
 const [dl]=await Promise.all([p.waitForEvent('download'),p.evaluate(()=>finExportar('csv'))]);
 const csv=fs.readFileSync(await dl.path(),'utf8');
 ok('Exporta CSV con encabezado y nombre con fechas',/Medio de pago;Movimientos/.test(csv)&&/^Reservia_Caja_\d{4}-\d{2}-01_a_/.test(dl.suggestedFilename()),dl.suggestedFilename()+' '+csv.slice(0,80));
 // filtro por profesional llega a la consulta
 const gets=[]; p.on('request',r=>{ if(r.method()==='GET') gets.push(decodeURIComponent(r.url())); });
 await p.selectOption('#fin-prof','Mario'); await p.waitForTimeout(500);
 ok('Filtrar por profesional filtra en la base',gets.some(g=>/cobro_lineas_netas/.test(g)&&/barbero_nombre=eq\.Mario/.test(g)&&/fecha_cobro=gte\./.test(g)),gets.filter(g=>/cobro_lineas_netas/.test(g)));
 await p.selectOption('#fin-prof',''); await p.waitForTimeout(300);
 // ventas
 await p.evaluate(()=>finTab('ventas')); await p.waitForTimeout(500);
 const vt=await p.evaluate(()=>({t:document.getElementById('fin-ventas-tabla').innerText,c:document.getElementById('fin-ventas-cards').innerText}));
 ok('Ventas: muestra % con versión de regla y reparto',/55% \(v1\)/.test(vt.t)&&/50% \(antigua\)/.test(vt.t)&&/\$9\.818/.test(vt.t)&&/\$8\.032/.test(vt.t),vt.t.slice(0,300));
 const [dx]=await Promise.all([p.waitForEvent('download'),p.evaluate(()=>finExportar('xlsx'))]);
 ok('Exporta Excel',/\.xlsx$/.test(dx.suggestedFilename()),dx.suggestedFilename());
 // tributación
 await p.evaluate(()=>finTab('trib')); await p.waitForTimeout(600);
 const tr=await p.evaluate(()=>({c:document.getElementById('fin-trib-cards').innerText,d:document.getElementById('fin-docs-tabla').innerText,a:document.getElementById('fin-docs-aviso').innerText}));
 ok('Tributación: IVA débito, crédito y a pagar',/\$5\.700/.test(tr.c)&&/\$2\.000/.test(tr.c)&&/\$538/.test(tr.c),tr.c);
 ok('Tributación: documento pendiente avisa que no se emite ante el SII',/no emite boletas ante el SII/i.test(tr.a)&&/pendiente/.test(tr.d)&&/15,25|15\.25/.test(tr.d),tr);
 const ivaCall=s.rpcs.filter(r=>r.n==='fin_iva_mes').pop();
 ok('IVA se pide por mes y sin RUT = todos',ivaCall&&/^\d{4}-\d{2}$/.test(ivaCall.body.p_mes)&&ivaCall.body.p_rut===null,ivaCall);
 DLG.push('F-777','2026-11-07'); await p.evaluate(()=>finDocFolio('d1')); await p.waitForTimeout(400);
 const wf=writesG.find(w=>/documentos_tributarios/.test(w.u));
 ok('Poner folio marca emitido y verificado a mano',wf&&wf.b.folio==='F-777'&&wf.b.estado==='emitido'&&wf.b.verificado_manual===true,wf);
 // liquidaciones
 await p.evaluate(()=>finTab('liq')); await p.waitForTimeout(500);
 const lq=await p.evaluate(()=>document.getElementById('fin-liq-tabla').innerText);
 ok('Liquidaciones: lista con pendiente $13.718 y estado',/Pago parcial/.test(lq)&&/\$13\.718/.test(lq),lq);
 await p.evaluate(()=>finVerLiq('q1')); await p.waitForTimeout(500);
 const det=await p.evaluate(()=>document.getElementById('fl-det').innerText);
 ok('Detalle: monto sugerido de boleta $16.718 incluye productos y las propinas quedan fuera',/\$16\.718/.test(det)&&/incluye la comisión de productos/.test(det)&&/nunca van en la boleta/.test(det)&&/fuera de la boleta/.test(det),det);
 await p.fill('#fl-pagar-monto','13718'); await p.evaluate(()=>finPagarLiq()); await p.waitForTimeout(300);
 const pg=s.rpcs.find(r=>r.n==='fin_liquidacion_pagar');
 ok('Pagar envía monto y una clave única (anti duplicado)',pg&&pg.body.p_monto===13718&&/^pago-q1-13718-/.test(pg.body.p_clave),pg);
 await p.fill('#fl-aj-monto','-2000'); await p.fill('#fl-aj-motivo',''); await p.evaluate(()=>finAjustarLiq()); await p.waitForTimeout(200);
 ok('Un ajuste sin motivo no se envía',!s.rpcs.some(r=>r.n==='fin_liquidacion_ajustar'));
 await p.fill('#fl-aj-motivo','Boleta con error'); await p.evaluate(()=>finAjustarLiq()); await p.waitForTimeout(300);
 const aj=s.rpcs.find(r=>r.n==='fin_liquidacion_ajustar');
 ok('Ajuste con motivo se envía',aj&&aj.body.p_monto===-2000&&aj.body.p_motivo==='Boleta con error',aj);
 await p.evaluate(()=>closeM('m-fin-liqdet'));
 // nuevo documento: receptor empresa vs persona
 await p.evaluate(()=>finAbrirDoc('q1',16718)); await p.waitForTimeout(200);
 const d1=await p.evaluate(()=>({ppm:document.getElementById('fd-ppm-box').style.display,inf:document.getElementById('fd-ret-info').textContent}));
 ok('Documento: receptor empresa retiene (sin PPM)',d1.ppm==='none'&&/15,25% en 2026/.test(d1.inf),d1);
 await p.selectOption('#fd-retiene','no');
 const d2=await p.evaluate(()=>({ppm:document.getElementById('fd-ppm-box').style.display,inf:document.getElementById('fd-ret-info').textContent}));
 ok('Documento: receptor persona no retiene, PPM a cargo del profesional',d2.ppm===''&&/PPM/.test(d2.inf),d2);
 await p.fill('#fd-emisor','11.111.111-1'); await p.fill('#fd-receptor','12.345.678-9'); await p.evaluate(()=>finGuardarDoc()); await p.waitForTimeout(300);
 const dc=s.rpcs.find(r=>r.n==='fin_documento_registrar');
 ok('Documento: envía liquidación, PPM y receptor persona, sin folio (queda pendiente)',dc&&dc.body.p_receptor_retiene===false&&dc.body.p_ppm_pct===10&&dc.body.p_liquidacion==='q1'&&dc.body.p_folio===null&&dc.body.p_honorarios===16718,dc);
 // nueva liquidación
 await p.evaluate(()=>finNuevaLiq()); await p.selectOption('#fl-prof','Mario'); await p.evaluate(()=>finCrearLiq()); await p.waitForTimeout(400);
 const lc=s.rpcs.find(r=>r.n==='fin_liquidacion_crear');
 ok('Nueva liquidación pide profesional, período y PPM informativo',lc&&lc.body.p_barbero==='Mario'&&lc.body.p_ppm_pct===10&&/^\d{4}-\d{2}-\d{2}$/.test(lc.body.p_desde),lc);
 // configuración
 await p.evaluate(()=>finTab('cfg')); await p.waitForTimeout(500);
 const cf=await p.evaluate(()=>({m:document.getElementById('fc-modelo-actual').textContent,r:document.getElementById('fc-reglas').innerText,v:document.getElementById('fc-validada-info').textContent,pb:document.getElementById('fc-prod-boleta').checked}));
 ok('Config: muestra modelo A, regla v1 y validación pendiente',/A ·/.test(cf.m)&&/v1/.test(cf.r)&&/Sin validar/.test(cf.v)&&cf.pb===true,cf);
 await p.fill('#fc-regla-pct','60'); await p.evaluate(()=>finCrearRegla()); await p.waitForTimeout(300);
 const rg=s.rpcs.find(r=>r.n==='fin_regla_crear');
 ok('Crear regla envía alcance, % y fecha de vigencia',rg&&rg.body.p_alcance==='negocio'&&rg.body.p_pct===60&&rg.body.p_barbero===null&&/^\d{4}-\d{2}-\d{2}$/.test(rg.body.p_desde),rg);
 await p.fill('#fc-motivo',''); await p.evaluate(()=>finCambiarModelo()); await p.waitForTimeout(300);
 const cm=s.rpcs.find(r=>r.n==='fin_cambiar_modelo');
 ok('Cambiar modelo envía fecha y motivo (la base valida)',cm&&cm.body.p_modelo==='A'&&'p_motivo' in cm.body&&/^\d{4}/.test(cm.body.p_desde),cm);
 await p.evaluate(()=>{ document.getElementById('fc-prod-boleta').checked=false; }); await p.evaluate(()=>finGuardarDatos()); await p.waitForTimeout(300);
 const gd=writesG.find(w=>/barberias/.test(w.u)&&w.b&&'comision_producto_en_boleta' in w.b);
 ok('Interruptor de comisión de productos en boleta se guarda',gd&&gd.b.comision_producto_en_boleta===false&&gd.b.rut==='76.111.111-1',gd);
 ok('sin errores de JavaScript',errs.length===0,errs);
 await p.evaluate(()=>document.querySelectorAll('.overlay.open').forEach(o=>o.classList.remove('open'))); await p.screenshot({path:'/tmp/fin-config.png',fullPage:true});
 await p.evaluate(()=>finTab('caja')); await p.waitForTimeout(400); await p.screenshot({path:'/tmp/fin-caja.png',fullPage:true});
 await s.b.close();
 console.log(res.join('\n')); process.exit(res.some(x=>x.startsWith('FALLO'))?1:0);
})();
