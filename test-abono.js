// abono.html: pantalla del cliente (transferir, comprobante, cuenta regresiva, estados).
const { chromium } = require('playwright');
const RID='11111111-1111-4111-8111-111111111111', TOK='22222222-2222-4222-8222-222222222222', BID='b0000000-0000-4000-8000-000000000001';
const res=[]; const ok=(n,c,x)=>res.push((c?'OK    ':'FALLO ')+n+(c?'':'  -> '+JSON.stringify(x)));
function estado(o){ const ahora=new Date(); return Object.assign({abono_estado:'Pendiente',estado:'Pendiente de abono',monto:5000,
  vence_at:new Date(ahora.getTime()+25*60000).toISOString(),ahora:ahora.toISOString(),subio_comprobante:false,exige_comprobante:false,
  banco:'Banco Estado',tipo_cuenta:'Cuenta RUT',numero_cuenta:'12345678',titular:'Essentials SpA',rut:'76.123.456-7',instrucciones:'Pon tu nombre en el comentario',
  negocio:'Essentials Studio',barberia_id:BID},o||{}); }
async function abrir(S,url){
  const b=await chromium.launch(); const p=await b.newPage({viewport:{width:390,height:800}});
  const errs=[],rpcs=[],uploads=[]; p.on('pageerror',e=>errs.push(e.message));
  await p.route(/^https:\/\/(cdn\.jsdelivr\.net|cdnjs\.cloudflare\.com|unpkg\.com)\//, r=>{const u=r.request().url();
    r.fulfill({path:/supabase-js/.test(u)?'/tmp/cdn/node_modules/@supabase/supabase-js/dist/umd/supabase.js':'/dev/null',contentType:'application/javascript'});});
  await p.route(/supabase\.co\/(rest|auth|storage)\//, async r=>{
    const req=r.request(),u=req.url(); const json=(o,st=200)=>r.fulfill({status:st,contentType:'application/json',body:JSON.stringify(o)});
    if(/\/storage\//.test(u)){ uploads.push(u); return json({Key:'ok'}); }
    if(/\/rpc\/(\w+)/.test(u)){ const n=u.match(/\/rpc\/(\w+)/)[1]; const body=JSON.parse(req.postData()||'{}'); rpcs.push({n,body});
      if(n==='get_abono_publico') return json(S.cur);
      if(n==='abono_marcar_transferido'){ if(S.falla) return json({message:S.falla},400); S.cur=Object.assign({},S.cur,{abono_estado:'Por confirmar',subio_comprobante:!!body.p_path}); return json({ok:true}); }
      return json(null); }
    if(/barberias/.test(u)) return json({id:BID,nombre:'Essentials Studio',modo_tema:'oscuro'});
    json([]); });
  await p.goto(url); await p.waitForTimeout(600); return {p,b,errs,rpcs,uploads};
}
(async()=>{
 // 1. pendiente con comprobante opcional
 let S={cur:estado()}; let t=await abrir(S,`http://localhost:8765/abono.html?r=${RID}&t=${TOK}`);
 let txt=await t.p.evaluate(()=>document.body.innerText);
 ok('muestra monto',/\$5\.000/.test(txt),txt.slice(0,200));
 ok('muestra datos bancarios',/Banco Estado/.test(txt)&&/12345678/.test(txt)&&/Essentials SpA/.test(txt)&&/76\.123\.456-7/.test(txt));
 ok('muestra instrucciones',/Pon tu nombre/.test(txt));
 const rel=await t.p.textContent('#reloj-t'); ok('cuenta regresiva ~25 min',/^(24|25):\d\d$/.test(rel),rel);
 ok('botón "Ya transferí"',/Ya transferí/.test(await t.p.textContent('#btn-enviar')));
 await t.p.click('#btn-enviar'); await t.p.waitForTimeout(500);
 ok('sin comprobante igual avisa (opcional)',t.rpcs.some(r=>r.n==='abono_marcar_transferido'&&r.body.p_path===null),t.rpcs.map(r=>r.n));
 ok('pasa a "Recibimos tu aviso"',/Recibimos tu aviso/.test(await t.p.evaluate(()=>document.body.innerText)));
 ok('sin errores de página',t.errs.length===0,t.errs); await t.b.close();
 // 2. comprobante obligatorio
 S={cur:estado({exige_comprobante:true})}; t=await abrir(S,`http://localhost:8765/abono.html?r=${RID}&t=${TOK}`);
 ok('botón dice "Enviar comprobante"',/Enviar comprobante/.test(await t.p.textContent('#btn-enviar')));
 await t.p.click('#btn-enviar'); await t.p.waitForTimeout(300);
 ok('sin archivo bloquea y avisa',await t.p.isVisible('#error')&&!t.rpcs.some(r=>r.n==='abono_marcar_transferido'));
 await t.p.setInputFiles('#archivo',{name:'comp.png',mimeType:'image/png',buffer:Buffer.from('89504e470d0a1a0a','hex')});
 await t.p.click('#btn-enviar'); await t.p.waitForTimeout(600);
 const m=t.rpcs.find(r=>r.n==='abono_marcar_transferido');
 ok('sube archivo al bucket',t.uploads.length===1&&/comprobantes-abono/.test(t.uploads[0]),t.uploads);
 ok('ruta con barberia/reserva/token',m&&m.body.p_path&&m.body.p_path.startsWith(`${BID}/${RID}/${TOK}`),m);
 await t.b.close();
 // 3. archivo muy grande y formato inválido
 S={cur:estado()}; t=await abrir(S,`http://localhost:8765/abono.html?r=${RID}&t=${TOK}`);
 await t.p.setInputFiles('#archivo',{name:'gr.png',mimeType:'image/png',buffer:Buffer.alloc(5*1024*1024+10)});
 ok('rechaza >5 MB',await t.p.isVisible('#error')); await t.b.close();
 // 4. error del servidor se muestra
 S={cur:estado(),falla:'Esta reserva fue cancelada. Escríbele al negocio'}; t=await abrir(S,`http://localhost:8765/abono.html?r=${RID}&t=${TOK}`);
 await t.p.click('#btn-enviar'); await t.p.waitForTimeout(400);
 ok('muestra error del servidor y rehabilita botón',/cancelada/.test(await t.p.textContent('#error'))&&!(await t.p.isDisabled('#btn-enviar'))); await t.b.close();
 // 5. estados finales
 for(const [e,re,nm] of [['Confirmado',/Tu hora está confirmada/,'confirmado'],['Por confirmar',/Recibimos tu aviso/,'por confirmar'],['Vencido',/Se acabó el tiempo/,'vencido'],['Rechazado',/no se confirmó/,'rechazado']]){
   S={cur:estado({abono_estado:e})}; t=await abrir(S,`http://localhost:8765/abono.html?r=${RID}&t=${TOK}`);
   ok('estado '+nm,re.test(await t.p.evaluate(()=>document.body.innerText))); 
   if(e==='Vencido') ok('vencido ofrece "Ya transferí, avisar"',/Ya transferí, avisar/.test(await t.p.evaluate(()=>document.body.innerText)));
   await t.b.close(); }
 // 6. enlace inválido / reserva inexistente
 S={cur:null}; t=await abrir(S,`http://localhost:8765/abono.html?r=${RID}&t=${TOK}`);
 ok('reserva inexistente',/No encontramos esta reserva/.test(await t.p.evaluate(()=>document.body.innerText))); await t.b.close();
 t=await abrir(S,`http://localhost:8765/abono.html?r=xx&t=yy`);
 ok('enlace inválido sin llamar al servidor',/No encontramos/.test(await t.p.evaluate(()=>document.body.innerText))&&t.rpcs.length===0); await t.b.close();
 // 7. sin scroll horizontal en móvil
 S={cur:estado()}; t=await abrir(S,`http://localhost:8765/abono.html?r=${RID}&t=${TOK}`);
 ok('sin scroll horizontal',await t.p.evaluate(()=>document.documentElement.scrollWidth<=innerWidth)); 
 await t.p.screenshot({path:'/tmp/abono-movil.png',fullPage:true}); await t.b.close();
 console.log(res.join('\n')); console.log(res.filter(x=>x.startsWith('FALLO')).length?'HAY FALLOS':'TODO OK');
})();
