// Pruebas de agendaBandas (franjas bloqueadas de la agenda). Función pura:
// se extrae de app.html y se ejecuta en node. Uso: node test-agenda-bandas.js
const fs=require('fs'); const src=fs.readFileSync(__dirname+'/app.html','utf8');
const i=src.indexOf('function hmAMin'), j=src.indexOf('function agendaBandasHtml');
const {hmAMin,agendaBandas}=new Function(src.slice(i,j)+';return {hmAMin,agendaBandas};')();
let ok=0,mal=0; const t=(n,c,x)=>{ if(c)ok++; else{mal++;console.log('FALLA',n,x===undefined?'':JSON.stringify(x));} };
const H=(o={})=>Array.from({length:7},(_,d)=>Object.assign({dia_semana:d,hora_apertura:'11:00',hora_cierre:'19:00',cerrado:false,hora_colacion_inicio:'14:00',hora_colacion_fin:'15:00'},o));
const F='2026-11-06'; // viernes (5)
const A=480,Z=1200; // 08:00–20:00
let r=agendaBandas(F,H(),[],'p1',A,Z);
t('abre 11 y cierra 19, colación 14-15 → 3 franjas',r.length===3,r);
t('antes de abrir 08:00–11:00',r[0].ini===480&&r[0].fin===660&&r[0].tipo==='cerrado');
t('después de cerrar 19:00–20:00',r[1].ini===1140&&r[1].fin===1200&&r[1].texto==='Fuera de horario');
t('colación nombrada',r[2].tipo==='colacion'&&r[2].texto==='Colación'&&r[2].ini===840&&r[2].fin===900);
r=agendaBandas(F,H({hora_colacion_inicio:null,hora_colacion_fin:null}),[],'p1',A,Z);
t('sin colación: solo los dos extremos',r.length===2,r);
r=agendaBandas(F,H({cerrado:true}),[],'p1',A,Z);
t('día cerrado: toda la jornada',r.length===1&&r[0].ini===A&&r[0].fin===Z&&r[0].texto==='Cerrado',r);
r=agendaBandas(F,H({hora_apertura:'07:00',hora_cierre:'22:00'}),[],'p1',A,Z);
t('horario más amplio que la grilla: sin franjas de borde',!r.some(x=>x.tipo==='cerrado'),r);
r=agendaBandas(F,H({hora_apertura:'06:00',hora_cierre:'12:00'}),[],'p1',A,Z);
t('recorta a la grilla (cierra 12:00 → 12:00–20:00)',r.some(x=>x.ini===720&&x.fin===1200),r);
// bloqueos
const B=(o)=>Object.assign({activo:true,profesional_id:'p1',tipo:'puntual',fecha:F,hora_inicio:'16:00',hora_fin:'17:00',motivo:'Dentista'},o);
const sinH=[]; // sin horario cargado: solo bloqueos
r=agendaBandas(F,sinH,[B()],'p1',A,Z);
t('bloqueo puntual con motivo',r.length===1&&r[0].tipo==='bloqueo'&&r[0].texto==='Dentista'&&r[0].ini===960&&r[0].fin===1020,r);
r=agendaBandas(F,sinH,[B({motivo:null})],'p1',A,Z); t('sin motivo se llama Bloqueo',r[0].texto==='Bloqueo');
r=agendaBandas(F,sinH,[B()],'p2',A,Z); t('bloqueo de otro profesional no aparece',r.length===0);
r=agendaBandas(F,sinH,[B({activo:false})],'p1',A,Z); t('bloqueo desactivado no aparece',r.length===0);
r=agendaBandas(F,sinH,[B({fecha:'2026-11-07'})],'p1',A,Z); t('bloqueo de otra fecha no aparece',r.length===0);
r=agendaBandas(F,sinH,[B({tipo:'dia_completo',hora_inicio:null,hora_fin:null,motivo:'Vacaciones'})],'p1',A,Z);
t('día completo cubre toda la grilla',r.length===1&&r[0].ini===A&&r[0].fin===Z&&r[0].texto==='Vacaciones',r);
r=agendaBandas(F,sinH,[B({tipo:'dia_completo',fecha:'2026-11-07'})],'p1',A,Z); t('día completo de otra fecha no aparece',r.length===0);
r=agendaBandas(F,sinH,[B({tipo:'recurrente',fecha:null,dia_semana:5,motivo:'Clase'})],'p1',A,Z); t('recurrente en su día de semana (viernes)',r.length===1&&r[0].texto==='Clase',r);
r=agendaBandas(F,sinH,[B({tipo:'recurrente',fecha:null,dia_semana:4})],'p1',A,Z); t('recurrente de otro día no aparece',r.length===0);
r=agendaBandas(F,sinH,[B({hora_inicio:'06:00',hora_fin:'09:00'})],'p1',A,Z); t('bloqueo recortado a la grilla (08:00–09:00)',r.length===1&&r[0].ini===480&&r[0].fin===540,r);
r=agendaBandas(F,sinH,[B({hora_inicio:'05:00',hora_fin:'07:00'})],'p1',A,Z); t('bloqueo totalmente fuera de la grilla no aparece',r.length===0);
r=agendaBandas(F,H(),[B(),B({motivo:'Clase',hora_inicio:'09:00',hora_fin:'10:00'})],'p1',A,Z); t('horario + colación + 2 bloqueos',r.length===5,r.length);
// domingo/sábado: el índice sigue getDay (0=domingo)
r=agendaBandas('2026-11-08',H().map(h=>h.dia_semana===0?Object.assign(h,{cerrado:true}):h),[],'p1',A,Z); t('domingo cerrado usa dia_semana 0',r.length===1&&r[0].texto==='Cerrado',r);
t('hmAMin acepta HH:MM:SS',hmAMin('14:30:00')===870&&hmAMin(null)===null);
console.log(ok+'/'+(ok+mal)); process.exit(mal?1:0);
