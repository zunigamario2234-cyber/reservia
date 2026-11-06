const {chromium}=require('playwright');const fs=require('fs');
const src=fs.readFileSync(__dirname+'/app.html','utf8');
function grab(startMarker,endMarker){const i=src.indexOf(startMarker);const j=src.indexOf(endMarker,i);if(i<0||j<0)throw new Error('no '+startMarker);return src.slice(i,j);}
const code=[
 "const MESES_CORTO=['ene','feb','mar','abr','may','jun','jul','ago','sep','oct','nov','dic'];",
 grab('function fmtDateLocal','function setDashPeriodo'),
 grab('// ─── PERIODOS DE VENTAS','function setDashPeriodo'),
 grab('function deltaHtml','// Los charts de ingresos'),
 grab('function getRepVentasRango','// Comisiones por profesional'),
 grab('function getRepCitasRango','function repProfRango'),
 grab("let REP_PRESET='mes';","function renderReporteResumen(){"),
 grab('function renderReporteResumen(){','  // Por servicio')+'}',
 'function renderVentasPeriodos(){'+grab('function renderVentasPeriodos(){','function renderDashboard(){').slice('function renderVentasPeriodos(){'.length),
].join('\n');
// Sintaxis de TODOS los <script> inline de app.html: una declaración repetida
// (pasó el 2026-11-06) deja el panel entero muerto y las funciones sueltas no lo notan.
{ const cp=require('child_process'); let malos=0; let i=0;
  for(const m of src.matchAll(/<script(?![^>]*src)[^>]*>([\s\S]*?)<\/script>/g)){ const f='/tmp/_chk_'+(i++)+'.js'; fs.writeFileSync(f,m[1]); const r=cp.spawnSync('node',['--check',f],{encoding:'utf8'}); if(r.status){malos++;console.log('FALLA sintaxis script',i,r.stderr.slice(0,200));} }
  if(malos){process.exit(1);} console.log('sintaxis de '+i+' scripts: ok'); }
(async()=>{
 const b=await chromium.launch();const pg=await b.newPage();
 const errs=[];pg.on('pageerror',e=>errs.push(e.message));
 await pg.setContent(`<div id="rep-presets"><div class="tab" data-r="mes"></div><div class="tab" data-r="custom"></div></div>
 <span id="rep-custom"></span><input id="rep-desde"><input id="rep-hasta"><select id="rep-agrupar"><option value="auto">a</option><option value="dia">d</option><option value="mes">m</option></select>
 <div id="rep-rango-txt"></div><div id="rep-metrics"></div><span id="rep-evol-titulo"></span><div id="rep-evolucion"></div>
 <b id="vp-hoy"></b><i id="vp-hoy-sub"></i><b id="vp-semana"></b><i id="vp-semana-sub"></i><b id="vp-mes"></b><i id="vp-mes-sub"></i><b id="vp-anio"></b><i id="vp-anio-sub"></i>`);
 await pg.evaluate(c=>{
  window.S={visitas:[],ventas:[]};
  window.fmt=n=>'$'+(Math.round(n)||0).toLocaleString('es-CL');
  window.ivaDe=b=>Math.round((b||0)*19/119);
  window.HOY='2026-11-06';
  window.ahoraEnChile=()=>({fecha:window.HOY});
  (0,eval)(c);
  // exponer las lets/consts al global
  window.__set=(p)=>{REP_PRESET=p;};
 },code);
 const res=await pg.evaluate(()=>{
  const out=[];const ok=(n,c,x)=>out.push([n,!!c,x]);
  // calendario real
  const r=(t,h,d,hh)=>rangoVentas(t,h,d,hh);
  let x=r('hoy','2026-11-06');ok('hoy',x.desde==='2026-11-06'&&x.prevDesde==='2026-11-05',JSON.stringify(x));
  x=r('semana','2026-11-06'); // viernes
  ok('semana viernes: lunes 2 nov',x.desde==='2026-11-02'&&x.hasta==='2026-11-06'&&x.prevDesde==='2026-10-26'&&x.prevHasta==='2026-10-30',JSON.stringify(x));
  x=r('semana','2026-11-02');ok('semana lunes: solo hoy',x.desde==='2026-11-02'&&x.prevHasta==='2026-10-26',JSON.stringify(x));
  x=r('semana','2026-11-08');ok('semana domingo: lunes 2',x.desde==='2026-11-02',JSON.stringify(x));
  x=r('mes','2026-11-06');ok('mes',x.desde==='2026-11-01'&&x.prevDesde==='2026-10-01'&&x.prevHasta==='2026-10-06',JSON.stringify(x));
  x=r('mes','2026-03-31');ok('mes: 31 mar vs feb clamp',x.prevDesde==='2026-02-01'&&x.prevHasta==='2026-02-28',JSON.stringify(x));
  x=r('mes','2026-01-15');ok('mes enero vs dic',x.prevDesde==='2025-12-01'&&x.prevHasta==='2025-12-15',JSON.stringify(x));
  x=r('anio','2026-11-06');ok('anio',x.desde==='2026-01-01'&&x.prevDesde==='2025-01-01'&&x.prevHasta==='2025-11-06',JSON.stringify(x));
  x=r('anio','2028-02-29');ok('anio bisiesto',x.prevHasta==='2027-02-28',JSON.stringify(x));
  x=r('custom','2026-11-06','2026-11-04','2026-11-06');ok('3 dias + prev 3 dias',x.desde==='2026-11-04'&&x.prevDesde==='2026-11-01'&&x.prevHasta==='2026-11-03',JSON.stringify(x));
  x=r('custom','2026-11-06','2026-11-06','2026-11-01');ok('invertido se ordena',x.desde==='2026-11-01'&&x.hasta==='2026-11-06',JSON.stringify(x));
  x=r('custom','2026-11-06','2026-11-03','');ok('solo desde',x.desde==='2026-11-03'&&x.hasta==='2026-11-03',JSON.stringify(x));
  // datos
  const V=[['2026-11-06',10000],['2026-11-06',5000],['2026-11-04',20000],['2026-11-02',7000],['2026-11-01',1000],['2026-10-31',3000],['2026-10-05',4000],['2026-10-07',9000],['2026-01-01',100],['2025-11-06',50],['2025-12-31',70]];
  S.ventas=V.map(([f,v])=>({fecha:f,valor:v,tipo:'servicio'}));
  S.visitas=S.ventas.filter((_,i)=>i<5);
  const T=(t)=>{const q=rangoVentas(t,'2026-11-06');return totalVentas(S.ventas,q.desde,q.hasta).total;};
  ok('total hoy 15000',T('hoy')===15000,T('hoy'));
  ok('total semana 42000',T('semana')===42000,T('semana'));
  ok('total mes 43000',T('mes')===43000,T('mes'));
  ok('total anio 59100',T('anio')===59100,T('anio'));
  ok('mes prev (1-6 oct) 4000',totalVentas(S.ventas,'2026-10-01','2026-10-06').total===4000,'');
  // dashboard
  renderVentasPeriodos();
  ok('dash hoy',document.getElementById('vp-hoy').textContent==='$15.000',document.getElementById('vp-hoy').textContent);
  ok('dash semana',document.getElementById('vp-semana').textContent==='$42.000',document.getElementById('vp-semana').textContent);
  ok('dash mes',document.getElementById('vp-mes').textContent==='$43.000','');
  ok('dash anio 59100',document.getElementById('vp-anio').textContent==='$59.100',document.getElementById('vp-anio').textContent);
  ok('dash sub cobros',/2 cobros/.test(document.getElementById('vp-hoy-sub').textContent),document.getElementById('vp-hoy-sub').textContent);
  // reportes
  setRepPreset('custom'); // por defecto 3 dias hasta hoy
  ok('custom default 3 dias',document.getElementById('rep-desde').value==='2026-11-04'&&document.getElementById('rep-hasta').value==='2026-11-06','');
  const m=document.getElementById('rep-metrics').textContent;
  ok('custom ventas 35000',/\$35\.000/.test(m),m);
  ok('custom agrupa por dia con 3 filas',document.getElementById('rep-evol-titulo').textContent==='Ventas por día'&&document.getElementById('rep-evolucion').children.length===3,document.getElementById('rep-evolucion').children.length);
  ok('dia sin ventas aparece $0',/\$0/.test(document.getElementById('rep-evolucion').textContent),'');
  setRepPreset('anio');
  ok('anio agrupa por mes, 11 filas',document.getElementById('rep-evol-titulo').textContent==='Ventas por mes'&&document.getElementById('rep-evolucion').children.length===11,document.getElementById('rep-evolucion').children.length);
  ok('anio delta presente',/vs el año pasado/.test(document.getElementById('rep-metrics').innerHTML),'');
  setRepPreset('todo');
  ok('todo sin delta',!/vs /.test(document.getElementById('rep-metrics').innerHTML),'');
  ok('todo texto',document.getElementById('rep-rango-txt').textContent==='Todo el historial','');
  setRepPreset('mes');document.getElementById('rep-agrupar').value='mes';renderReporteResumen();
  ok('forzar mes: 1 fila',document.getElementById('rep-evolucion').children.length===1,'');
  // citas cuentan solo visitas
  ok('total citas mes = visitas del mes',/Total citas<\/div><div class="mc-val">5</.test(document.getElementById('rep-metrics').innerHTML),'');
  return out;
 });
 let bad=0;res.forEach(([n,c,x])=>{if(!c){bad++;console.log('FALLA',n,x);}});
 console.log(res.length-bad+'/'+res.length,errs.join('|'));await b.close();
})();
