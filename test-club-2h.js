// Prueba: el Club no deja modificar una reserva a menos de 2 horas. node test-club-2h.js
const { chromium } = require('playwright'); const fs=require('fs');
const BID='b0000000-0000-0000-0000-000000000001', CID='c0000000-0000-0000-0000-000000000001';
(async()=>{
 const b=await chromium.launch(); const p=await b.newPage({viewport:{width:420,height:900}});
 const nowSt=new Date(new Date().toLocaleString('en-US',{timeZone:'America/Santiago'}));
 const f=(d)=>{const x=new Date(nowSt.getTime()+d*60000);const pad=n=>String(n).padStart(2,'0');return {fecha:x.getFullYear()+'-'+pad(x.getMonth()+1)+'-'+pad(x.getDate()),hora:pad(x.getHours())+':'+pad(x.getMinutes())+':00'};};
 const cerca=f(90), lejos=f(180);
 await p.route(/^https:\/\/(cdn\.jsdelivr\.net|cdnjs\.cloudflare\.com|unpkg\.com)\//, r=>{const m='/tmp/cdn/node_modules/@supabase/supabase-js/dist/umd/supabase.js';return /supabase-js/.test(r.request().url())&&fs.existsSync(m)?r.fulfill({status:200,contentType:'application/javascript',body:fs.readFileSync(m)}):r.fulfill({status:200,contentType:'application/javascript',body:''});});
 await p.route(/supabase\.co\/rest\//, async r=>{const u=r.request().url();const json=o=>r.fulfill({status:200,contentType:'application/json',headers:{'content-range':'0-0/1'},body:JSON.stringify(o)});
  const t=(u.match(/\/rest\/v1\/(?:rpc\/)?([a-z_]+)/)||[])[1];
  if(t==='get_club_vip_publico')return json([{ok:true,cliente_id:CID,nombre:'M',visitas:1,nivel:null,barberia:{id:BID,nombre:'E',whatsapp:'+56912345678'}}]);
  if(t==='get_proximas_reservas_club')return json([{id:'r1',...cerca,servicio:'Corte',profesional:'MARIO'},{id:'r2',...lejos,servicio:'Barba',profesional:'MARIO'}]);
  json([]);});
 await p.goto('http://localhost:8765/club.html?id='+BID+'&cliente='+CID); await p.waitForTimeout(1200);
 await p.evaluate(()=>cambiarTabTop('mis')); await p.waitForTimeout(500);
 const n=await p.$$eval('#mis-reservas button',a=>a.filter(x=>/Modificar/.test(x.textContent)).length);
 const txt=await p.textContent('#mis-reservas');
 const r=[['solo 1 botón Modificar (la de 3 h, no la de 1h30)',n===1],['aviso de 2 horas visible',/2 horas antes/.test(txt)]];
 r.forEach(x=>console.log((x[1]?'OK    ':'FALLO ')+x[0])); await b.close();
})();
