// Bloqueo de varios días: la página de reservas, el Club y Mi Agenda lo respetan en todo el rango.
const fs=require('fs');
let ok=0,mal=0; const t=(n,c,x)=>{ if(c)ok++; else{mal++;console.log('FALLA',n,x===undefined?'':JSON.stringify(x));} };
function sacar(archivo,nombre){ const s=fs.readFileSync(archivo,'utf8'); const i=s.indexOf('function '+nombre+'('); let d=0,j=s.indexOf('{',i);
  for(let k=j;k<s.length;k++){ if(s[k]==='{')d++; else if(s[k]==='}'){d--; if(!d) return s.slice(i,k+1);} } }
const hm=h=>{const [a,b]=String(h).split(':').map(Number);return a*60+(b||0);};
const ctx={timeToMin:hm,rTimeToMin:hm,seSolapan:(a,b,c,d)=>a<d&&c<b,rSeSolapan:(a,b,c,d)=>a<d&&c<b};
const res=new Function(...Object.keys(ctx), sacar('reservar.html','bloqueoChocaCon')+';return bloqueoChocaCon;')(...Object.values(ctx));
const club=new Function(...Object.keys(ctx), sacar('club.html','rBloqueoChocaCon')+';return rBloqueoChocaCon;')(...Object.values(ctx));
const vac={tipo:'dia_completo',fecha:'2026-12-10',fecha_hasta:'2026-12-20'};
const uno={tipo:'dia_completo',fecha:'2026-12-10'};
const casos=[['2026-12-09',false],['2026-12-10',true],['2026-12-15',true],['2026-12-20',true],['2026-12-21',false]];
for(const [f,esp] of casos){ t('reservar '+f,res(vac,600,30,f,2)===esp); t('club '+f,club(vac,600,30,f,2)===esp); }
t('un solo día sigue igual (reservar)',res(uno,600,30,'2026-12-10',2)&&!res(uno,600,30,'2026-12-11',2));
t('un solo día sigue igual (club)',club(uno,600,30,'2026-12-10',2)&&!club(uno,600,30,'2026-12-11',2));
const ma=fs.readFileSync('mi-agenda.html','utf8');
t('mi agenda: bandas usan fecha_hasta',/b\.tipo==='dia_completo'&&b\.fecha&&b\.fecha<=fecha&&fecha<=\(b\.fecha_hasta\|\|b\.fecha\)/.test(ma));
t('mi agenda: horas libres usan fecha_hasta',/if\(b\.tipo==='dia_completo'\) return !!b\.fecha && b\.fecha<=fecha && fecha<=\(b\.fecha_hasta\|\|b\.fecha\)/.test(ma));
const ag=new Function('hmAMin',sacar('mi-agenda.html','agendaBandas')+';return agendaBandas;')(h=>h?hm(h):null);
t('mi agenda: banda dentro del rango',ag('2026-12-15',[],[{...vac,activo:true,profesional_id:'p'}],'p',540,1200).length===1);
t('mi agenda: sin banda fuera del rango',ag('2026-12-21',[],[{...vac,activo:true,profesional_id:'p'}],'p',540,1200).length===0);
console.log(ok+'/'+(ok+mal));
