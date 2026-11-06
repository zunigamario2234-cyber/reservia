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
 await p.route(/^https:\/\/(cdn\.jsdelivr\.net|cdnjs\.cloudflare\.com|unpkg\.com)\//, r=>{const u=r.request().url(); const m=/supabase-js/.test(u)?'/tmp/cdn/node_modules/@supabase/supabase-js/dist/umd/supabase.js':/xlsx/i.test(u)?'/tmp/cdn/node_modules/xlsx/dist/xlsx.full.min.js':/chart/i.test(u)?'/tmp/cdn/node_modules/chart.js/dist/chart.umd.js':null; return m&&fs.existsSync(m)?r.fulfill({status:200,contentType:'application/javascript',body:fs.readFileSync(m)}):r.fulfill({status:200,contentType:'application/javascript',body:''});});
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
 const writes=[]; p.on('request',r=>{ if(/iva_historico/.test(r.url())&&r.method()!=='GET') writes.push({m:r.method(),u:r.url(),b:JSON.parse(r.postData()||'null')}); });
 p.on('dialog',d=>d.accept());
 const u=await p.evaluate(()=>({
  m:[ivaParseMes('2025-03'),ivaParseMes('03/2025'),ivaParseMes('3-2025'),ivaParseMes('Marzo 2025'),ivaParseMes('mar-25'),ivaParseMes('Septiembre 2024'),ivaParseMes('set 2024'),ivaParseMes(new Date(Date.UTC(2025,10,1))),ivaParseMes('2025-03-31'),ivaParseMes('marzo','2025'),ivaParseMes('13/2025'),ivaParseMes('hola')],
  n:[ivaParseNum('$1.234.567'),ivaParseNum('1234567'),ivaParseNum(1234567.6),ivaParseNum('1.234'),ivaParseNum(''),ivaParseNum('(5.000)'),ivaParseNum('12,5'),ivaParseNum('abc')]}));
 ok('meses en todos los formatos',JSON.stringify(u.m)===JSON.stringify(['2025-03','2025-03','2025-03','2025-03','2025-03','2024-09','2024-09','2025-11','2025-03','2025-03',null,null]),u.m);
 ok('números en formato chileno',JSON.stringify(u.n)===JSON.stringify([1234567,1234567,1234568,1234,null,-5000,13,null]),u.n);
 const mp=await p.evaluate(()=>ivaMapearFilas([
  {'Mes':'2025-01','IVA Débito':'$420.000','IVA Crédito':'180.000','Remanente':'','Nota':'ok'},
  {'Mes':'Febrero 2025','IVA Débito':385000,'IVA Crédito':210000,'Remanente':50000},
  {'Mes':'Febrero 2025','IVA Débito':1,'IVA Crédito':1},
  {'Mes':'xx','IVA Débito':1,'IVA Crédito':1},
  {'Mes':'2025-03','IVA Débito':-5,'IVA Crédito':1}]));
 ok('mapea filas válidas',mp.ok.length===2&&mp.ok[0].iva_debito===420000&&mp.ok[0].iva_credito===180000&&mp.ok[1].remanente===50000&&mp.ok[0].nota==='ok',mp);
 ok('avisa duplicado, mes ilegible y negativo',mp.errores.length===3&&/repetido/.test(mp.errores.join())&&/no entiendo/.test(mp.errores.join())&&/negativo/.test(mp.errores.join()),mp.errores);
 const sinCol=await p.evaluate(()=>ivaMapearFilas([{A:1,B:2}]).errores);
 ok('avisa si faltan columnas',/columna del mes/.test(sinCol[0]),sinCol);
 // flujo completo con CSV
 await p.evaluate(()=>{ nav('costos'); }); await p.waitForTimeout(300);
 await p.evaluate(()=>{ const t=[...document.querySelectorAll('.tab')].find(x=>/Resumen IVA/.test(x.textContent)); t.click(); }); await p.waitForTimeout(200);
 const csv='Mes,IVA débito,IVA crédito,Remanente\n2025-01,"420.000","180.000",\n2025-02,"385.000","210.000","5.000"\n';
 p.on('console',m=>console.log('C',m.text().slice(0,200)));  await p.setInputFiles('#iva-file',{name:'iva.csv',mimeType:'text/csv',buffer:Buffer.from(csv,'utf8')}); await p.waitForTimeout(600);
  const vista=await p.evaluate(()=>({open:document.getElementById('m-iva-import').classList.contains('open'),txt:document.getElementById('iva-imp-resumen').innerText,filas:document.querySelectorAll('#iva-imp-tabla tr').length}));
 ok('vista previa con 2 meses',vista.open&&vista.filas===2&&/2 meses/.test(vista.txt),vista);
 await p.evaluate(()=>ivaConfirmarImport()); await p.waitForTimeout(400);
 const w=writes[0]; ok('sube con upsert por negocio y mes',w&&w.m==='POST'&&/on_conflict=barberia_id%2Cmes/.test(w.u)&&w.b.length===2&&w.b[0].barberia_id===BID&&w.b[0].iva_debito===420000,writes);
 // historial: simulo lo guardado
 await p.evaluate(()=>{ S.ivaHist=[{mes:'2025-01',iva_debito:420000,iva_credito:180000,remanente:null},{mes:'2025-02',iva_debito:385000,iva_credito:210000,remanente:5000}]; renderIvaHistorial(); });
 const hist=await p.evaluate(()=>document.getElementById('iva-historial').innerText);
 ok('historial lista meses importados',/enero 2025|Enero 2025/i.test(hist)&&/Importado/.test(hist)&&/a pagar/i.test(hist),hist);
 ok('mes con datos de la plataforma muestra "Plataforma"',/Plataforma/.test(hist),hist);
 await p.evaluate(()=>ivaBorrarMes('2025-01')); await p.waitForTimeout(300);
 ok('quitar un mes importado',writes.some(x=>x.m==='DELETE'&&/mes=eq\.2025-01/.test(x.u)),writes);
 ok('sin errores de página',errs.length===0,errs); await b.close();
 const r2=await sesion('recepcion'); ok('recepción no carga el historial de IVA',!r2.reqs.includes('get:iva_historico'),r2.reqs.filter(x=>/iva/.test(x))); await r2.b.close();
 console.log(res.join('\n')); console.log(res.filter(x=>x.startsWith('FALLO')).length+' fallos de '+res.length);
})();
