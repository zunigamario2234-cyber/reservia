// Las fotos de los profesionales se ven en la lista de reservar.html (y club.html las usa igual).
const { chromium } = require('playwright'); const fs=require('fs');
const BID='b0000000-0000-4000-8000-000000000001';
const PNG='data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==';
const res=[]; const ok=(n,c,x)=>res.push((c?'OK    ':'FALLO ')+n+(c?'':'  -> '+JSON.stringify(x)));
(async()=>{
 const b=await chromium.launch(); const p=await b.newPage({viewport:{width:390,height:800}}); const errs=[]; p.on('pageerror',e=>errs.push(e.message));
 await p.route(/^https:\/\/(cdn\.jsdelivr\.net|cdnjs\.cloudflare\.com|unpkg\.com)\//, r=>{const u=r.request().url();r.fulfill({path:/supabase-js/.test(u)?'/tmp/cdn/node_modules/@supabase/supabase-js/dist/umd/supabase.js':'/dev/null',contentType:'application/javascript'});});
 await p.route(/supabase\.co\/(rest|auth)\//, r=>{const u=r.request().url();const t=(u.match(/\/rest\/v1\/([a-z_]+)/)||[])[1];
  const T={barberias:{id:BID,nombre:'Essentials',modo_tema:'oscuro',intervalo_min:30},servicios:[{id:'s1',barberia_id:BID,nombre:'Corte',precio:12000,duracion_min:30,activo:true}],
   barberos:[{id:'p1',barberia_id:BID,nombre:'Felipe',activo:true,foto_url:PNG},{id:'p2',barberia_id:BID,nombre:'Vicente',activo:true,foto_url:null}],barbero_servicios:[]};
  const acc=r.request().headers()['accept']||''; const v=T[t]===undefined?[]:T[t];
  if(/pgrst\.object/.test(acc)) return r.fulfill({status:200,contentType:'application/json',body:JSON.stringify(Array.isArray(v)?v[0]:v)});
  r.fulfill({status:200,contentType:'application/json',body:JSON.stringify(Array.isArray(v)?v:[v])});});
 await p.goto('http://localhost:8765/reservar.html?barberia='+BID); await p.waitForTimeout(800);
 await p.evaluate(()=>{ SEL.servicio=null; renderProfesionals(); document.querySelectorAll('.step-content').forEach(s=>s.classList.remove('active')); document.getElementById('lista-profesionals').closest('.step-content').classList.add('active'); }); await p.waitForTimeout(400);
 const r=await p.evaluate(()=>({imgs:[...document.querySelectorAll('#lista-profesionals .profesional-avatar img')].map(i=>({ok:i.complete&&i.naturalWidth>0,w:i.getBoundingClientRect().width})),tijeras:[...document.querySelectorAll('#lista-profesionals .profesional-avatar')].map(a=>a.textContent.trim()).filter(Boolean)}));
 ok('Felipe muestra su foto',r.imgs.length===1&&r.imgs[0].ok&&r.imgs[0].w>=60,r);
 ok('Vicente (sin foto) muestra tijera',r.tijeras.length===1&&r.tijeras[0]==='✂',r);
 ok('sin errores de página',errs.length===0,errs);
 await p.screenshot({path:'/tmp/fotos-prof.png'}); await b.close();
 const club=fs.readFileSync('club.html','utf8'); ok('club.html usa foto_url en la lista',/profesional-avatar">\$\{b\.foto_url/.test(club));
 console.log(res.join('\n'));
})();
