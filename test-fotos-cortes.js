// Prueba: fotos de cortes (compresión, panel del profesional, Club). node test-fotos-cortes.js
const { chromium } = require('playwright'); const fs=require('fs');
const BID='b0000000-0000-0000-0000-000000000001', CID='c0000000-0000-0000-0000-000000000001';
const res=[]; const ok=(n,c,x)=>res.push((c?'OK    ':'FALLO ')+n+(c?'':'  -> '+JSON.stringify(x)));
(async()=>{
 const b=await chromium.launch(); const p=await b.newPage({viewport:{width:420,height:900}});
 const errs=[]; p.on('pageerror',e=>errs.push(e.message));
 // ── 1) compresión
 await p.goto('http://localhost:8765/test-fecha-chile.html'); await p.addScriptTag({path:'fotos-cortes.js'});
 const c=await p.evaluate(async()=>{
   const cv=document.createElement('canvas'); cv.width=4000; cv.height=3000; const x=cv.getContext('2d');
   for(let i=0;i<3000;i++){x.fillStyle='hsl('+(i*7%360)+',70%,50%)'; x.fillRect(Math.random()*4000,Math.random()*3000,200,200);}
   const big=await new Promise(r=>cv.toBlob(r,'image/png'));
   const out=await FotosCortes.comprimir(new File([big],'foto.png',{type:'image/png'}));
   const im=await createImageBitmap(out); return {orig:big.size,out:out.size,w:im.width,h:im.height,type:out.type};});
 ok('la foto grande baja a ≤300 KB',c.out<=300*1024,c); ok('lado mayor ≤1280 px',Math.max(c.w,c.h)<=1280,c); ok('sale como JPEG',c.type==='image/jpeg',c);
 // ── 2) panel del profesional
 const calls=[]; let fotos=[{id:'f1',es_actual:true,url:'data:image/gif;base64,R0lGODlhAQABAAAAACw=',fecha:'2026-11-13',hora:'11:00:00',servicio:'Corte',barbero_nombre:'MARIO'},
   {id:'f9',es_actual:false,url:'data:image/gif;base64,R0lGODlhAQABAAAAACw=',fecha:'2026-10-13',hora:'16:00:00',servicio:'Corte',barbero_nombre:'FELIPE'}];
 await p.evaluate(()=>{document.body.innerHTML='<div id="pn"></div>';});
 await p.exposeFunction('rpcMock',async(n,a)=>{calls.push({n,a}); if(n==='agenda_fotos_cita') return {data:fotos}; if(n==='agenda_foto_eliminar'){fotos=fotos.filter(f=>f.id!==a.p_foto_id||!f.es_actual); return {data:BID+'/x.jpg'};} if(n==='agenda_foto_agregar'){fotos.push({id:'f2',es_actual:true,url:'data:image/gif;base64,R0lGODlhAQABAAAAACw=',fecha:'2026-11-13',hora:'11:00:00',servicio:'Corte',barbero_nombre:'MARIO'}); return {data:'f2'};} return {data:null};});
 await p.exposeFunction('stMock',async(n,path)=>{calls.push({n,path}); return {error:null};});
 await p.evaluate(({BID})=>{
   window.sbm={rpc:(n,a)=>rpcMock(n,a),storage:{from:()=>({upload:(path)=>stMock('upload',path),remove:(arr)=>stMock('remove',arr[0]),getPublicUrl:(path)=>({data:{publicUrl:'https://x/'+path}})})}};
   return FotosCortes.montar(document.getElementById('pn'),{sb:window.sbm,tipo:'reserva',id:'r1',barberiaId:BID});},{BID});
 await p.waitForTimeout(300);
 ok('muestra contador 1/2',/1\/2/.test(await p.textContent('#pn')));
 ok('hay botón Agregar foto con 1 foto',await p.isVisible('#pn .fc-add'));
 ok('muestra cortes anteriores del cliente',/anteriores/.test(await p.textContent('#pn'))&&/FELIPE/.test(await p.textContent('#pn')));
 const img=await p.$('#pn input[type=file]');
 await img.setInputFiles({name:'a.png',mimeType:'image/png',buffer:Buffer.from('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==','base64')});
 await p.waitForTimeout(700);
 const up=calls.find(x=>x.n==='upload'), ag=calls.find(x=>x.n==='agenda_foto_agregar');
 ok('sube al bucket cortes bajo la carpeta del negocio',up&&up.path.startsWith(BID+'/')&&/\.jpg$/.test(up.path),up);
 ok('registra la foto con la RPC',ag&&ag.a.p_tipo==='reserva'&&ag.a.p_id==='r1'&&ag.a.p_path===up.path&&ag.a.p_url==='https://x/'+up.path,ag);
 ok('con 2 fotos ya no deja agregar',!(await p.$('#pn .fc-add')));
 await p.click('#pn .fc-x'); await p.waitForTimeout(400);
 ok('borrar llama a la RPC y borra el archivo',calls.some(x=>x.n==='agenda_foto_eliminar')&&calls.some(x=>x.n==='remove'&&x.path===BID+'/x.jpg'),calls.map(x=>x.n));
 // ── 3) Club
 const club=await b.newPage({viewport:{width:420,height:900}}); const cerr=[]; club.on('pageerror',e=>cerr.push(e.message));
 await club.route(/^https:\/\/(cdn\.jsdelivr\.net|cdnjs\.cloudflare\.com|unpkg\.com)\//, r=>{const m='/tmp/cdn/node_modules/@supabase/supabase-js/dist/umd/supabase.js';return /supabase-js/.test(r.request().url())&&fs.existsSync(m)?r.fulfill({status:200,contentType:'application/javascript',body:fs.readFileSync(m)}):r.fulfill({status:200,contentType:'application/javascript',body:''});});
 await club.route(/supabase\.co\/rest\//, async r=>{const u=r.request().url();const json=o=>r.fulfill({status:200,contentType:'application/json',headers:{'content-range':'0-0/1'},body:JSON.stringify(o)});
  const t=(u.match(/\/rest\/v1\/(?:rpc\/)?([a-z_]+)/)||[])[1];
  if(t==='get_club_vip_publico')return json([{ok:true,cliente_id:CID,nombre:'M',visitas:1,nivel:null,barberia:{id:BID,nombre:'E',whatsapp:'+56912345678'}}]);
  if(t==='get_club_fotos_cortes')return json([{id:'a',url:'data:image/gif;base64,R0lGODlhAQABAAAAACw=',fecha:'2026-11-13',hora:'11:00:00',servicio:'Corte',profesional:'MARIO'}]);
  json([]);});
 await club.goto('http://localhost:8765/club.html?id='+BID+'&cliente='+CID); await club.waitForTimeout(1200);
 await club.evaluate(()=>cambiarTabTop('mis')); await club.waitForTimeout(600);
 ok('el Club muestra "Mis cortes" con la foto',/Mis cortes/.test(await club.textContent('#mis-cortes'))&&(await club.$$('#mis-cortes-grid img')).length===1);
 await club.click('#mis-cortes-grid img'); await club.waitForTimeout(200);
 ok('al tocar se abre el visor con Descargar',await club.isVisible('.fc-visor')&&/Descargar/.test(await club.textContent('.fc-visor')));
 ok('sin errores de página',errs.length===0&&cerr.length===0,[errs,cerr]);
 console.log(res.join('\n')); console.log(res.filter(x=>x.startsWith('FALLO')).length+' fallos de '+res.length); await b.close();
})();
