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

function datosHon(){ const D=datos('dueno');
 D.barberias[0].usa_honorarios=true; D.barberias[0].modo_comision='neto_iva'; D.barberias[0].honorarios_retencion_paga='dividido'; D.barberias[0].honorarios_pct_profesional=50;
 D.retencion_honorarios_tasas=[{desde_anio:2025,pct:14.5},{desde_anio:2026,pct:15.25},{desde_anio:2027,pct:16},{desde_anio:2028,pct:17}];
 const mk=(id,fecha,valor,com,ret,rp)=>({id,barberia_id:BID,fecha,hora:'10:00',cliente_id:'c1',barbero_nombre:'Mario',servicio:'Corte clásico',valor,propina:0,metodo_pago:'Efectivo',estado:'Atendida',comision_monto:com,iva_monto:Math.round(valor*19/119),retencion_pct:15.25,retencion_total:ret,retencion_profesional:rp,retencion_negocio:ret-rp,liquido_profesional:com-rp});
 D.visitas=[mk('h1',hoy,20000,8403,1281,641),mk('h2',hoy,20000,8403,1281,641),
   {id:'h3',barberia_id:BID,fecha:hoy,hora:'12:00',cliente_id:'c1',barbero_nombre:'Mario',servicio:'Corte clásico',valor:15000,propina:0,metodo_pago:'Efectivo',estado:'Atendida',comision_monto:7500}];
 D.cobro_productos=[]; return D; }
(async()=>{
 const T=datosHon();
 const b=await chromium.launch(); const p=await b.newPage({viewport:{width:1360,height:900}});
 const errs=[]; p.on('pageerror',e=>errs.push(e.message)); const patches=[];
 await p.addInitScript(([ref,uid])=>{ try{ localStorage.setItem('sb-'+ref+'-auth-token',JSON.stringify({access_token:'x.y.z',refresh_token:'r',expires_at:Math.floor(Date.now()/1000)+36000,expires_in:36000,token_type:'bearer',user:{id:uid,email:'m@x.cl',aud:'authenticated',role:'authenticated',app_metadata:{},user_metadata:{}}})); }catch(e){} },[REF,UID]);
 await p.route(/^https:\/\/(cdn\.jsdelivr\.net|cdnjs\.cloudflare\.com|unpkg\.com)\//, r=>{const u=r.request().url(); const m=/supabase-js/.test(u)?'/tmp/cdn/node_modules/@supabase/supabase-js/dist/umd/supabase.js':/chart/i.test(u)?'/tmp/cdn/node_modules/chart.js/dist/chart.umd.js':null; return m&&fs.existsSync(m)?r.fulfill({status:200,contentType:'application/javascript',body:fs.readFileSync(m)}):r.fulfill({status:200,contentType:'application/javascript',body:''});});
 await p.route(/supabase\.co\/(rest|auth|storage)\//, async r=>{
   const req=r.request(), u=req.url(); const json=(o,st=200,h={})=>r.fulfill({status:st,contentType:'application/json',headers:h,body:JSON.stringify(o)});
   if(/\/auth\/v1\/user/.test(u)) return json({id:UID,email:'m@x.cl'});
   const t=(u.match(/\/rest\/v1\/(?:rpc\/)?([a-z_]+)/)||[])[1];
   if(/\/rest\/v1\/rpc\//.test(u)) return json([]);
   if(req.method()==='PATCH'&&t==='barberias'){ patches.push(JSON.parse(req.postData())); return json([],204); }
   if(req.method()!=='GET') return json([],204);
   const rows=(T[t]||[]).slice(); const acc=req.headers()['accept']||'';
   if(/pgrst\.object/.test(acc)) return rows[0]?json(rows[0]):json({code:'PGRST116'},406);
   json(rows,200,{'content-range':'0-'+Math.max(rows.length-1,0)+'/'+rows.length}); });
 await p.goto('http://localhost:8765/app.html');
 await p.waitForFunction(()=>document.getElementById('loading-screen')&&document.getElementById('loading-screen').style.display==='none',null,{timeout:15000}).catch(()=>res.push('FALLO no cargó'));
 await p.waitForTimeout(500);
 // Config
 await p.evaluate(()=>nav('config')); await p.waitForTimeout(300);
 ok('el selector muestra "Boleta de honorarios" para este negocio',(await p.inputValue('#cfg-modo-comision'))==='honorarios');
 ok('aparece el panel de honorarios',await p.isVisible('#cfg-honorarios-box'));
 ok('el reparto dividido muestra el % del profesional',await p.isVisible('#cfg-hon-div')&&(await p.inputValue('#cfg-hon-pct'))==='50');
 const ej=await p.textContent('#cfg-comision-ejemplo');
 ok('el ejemplo usa 15,25% y da $1.192 de retención',/15,25%/.test(ej)&&/1\.192/.test(ej),ej);
 ok('al dividir 50/50 el ejemplo da líquido $7.219 y la barbería también queda con $7.219',(ej.match(/7\.219/g)||[]).length===2,ej);
 ok('explica que la tasa sube sola (2027 16%, 2028 17%)',/16%/.test(await p.textContent('#cfg-hon-tasa'))&&/17%/.test(await p.textContent('#cfg-hon-tasa')));
 await p.selectOption('#cfg-hon-paga','profesional');
 ok('si la paga el profesional el ejemplo da líquido $6.623',/6\.623/.test(await p.textContent('#cfg-comision-ejemplo')));
 await p.click('#p-config button:has-text("Guardar cambios")'); await p.waitForTimeout(500);
 const pa=patches.find(x=>'usa_honorarios' in x);
 ok('guarda: modo neto_iva + usa_honorarios + quién paga',pa&&pa.modo_comision==='neto_iva'&&pa.usa_honorarios===true&&pa.honorarios_retencion_paga==='profesional',pa);
 await p.selectOption('#cfg-modo-comision','neto_iva'); await p.click('#p-config button:has-text("Guardar cambios")'); await p.waitForTimeout(400);
 const pb=patches.filter(x=>'usa_honorarios' in x).pop();
 ok('volver a "neto" apaga honorarios',pb.usa_honorarios===false&&pb.modo_comision==='neto_iva',pb);
 // Reporte
 await p.evaluate(()=>{ S.barberia.usa_honorarios=true; nav('reportes'); });
 await p.waitForTimeout(300);
 await p.evaluate(()=>{ const t=document.getElementById('rep-tab-profesional'); switchTab(t,'rep-profesional'); renderReporteProfesional(); });
 await p.waitForTimeout(300);
 const txt=(await p.textContent('#rep-honorarios')).replace(/\s+/g,' ');
 ok('el reporte de honorarios aparece',/Honorarios del período/.test(txt),txt.slice(0,200));
 ok('IVA a pagar = 6.386 (2 × 3.193)',/IVA a pagar al SII\s*\$6\.386/.test(txt),txt.slice(0,300));
 ok('líquido a pagar = 15.524 (2 × 7.762)',/Líquido a pagar a profesionales\s*\$15\.524/.test(txt),txt.slice(0,300));
 ok('retención a declarar = 2.562',/Retención a declarar al SII\s*\$2\.562/.test(txt),txt.slice(0,300));
 ok('avisa del servicio anterior al modo (sin desglose)',/1 servicio del rango son anteriores/.test(txt),txt.slice(-200));
 const fila=await p.$$eval('#rep-honorarios tbody tr',a=>a.map(x=>x.innerText.replace(/\s+/g,' ')));
 ok('la fila de Mario: boleta 16.806, paga profesional 1.282, paga barbería 1.280',/16\.806/.test(fila[0])&&/1\.282/.test(fila[0])&&/1\.280/.test(fila[0]),fila);
 await p.screenshot({path:'/tmp/honorarios.png',fullPage:false});
 ok('sin errores de página',errs.length===0,errs);
 console.log(res.join('\n')); console.log(res.filter(x=>x.startsWith('FALLO')).length+' fallos de '+res.length);
 await b.close();
})();
