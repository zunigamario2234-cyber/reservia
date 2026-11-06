// Prueba del endpoint api/avisar-modificacion-reserva con fetch simulado.
// Corre con: node test-avisar-modificacion.js
process.env.RESEND_API_KEY='x'; process.env.SUPABASE_SERVICE_ROLE_KEY='y'; process.env.SUPABASE_URL='https://x.supabase.co';
const res=[]; const ok=(n,c,x)=>res.push((c?'OK    ':'FALLO ')+n+(c?'':'  -> '+JSON.stringify(x)));
const RID='11111111-1111-1111-1111-111111111111';
let mails=[], patches=[], claimable=true;
global.fetch=async(url,opts={})=>{
  const j=(o,st=200)=>({ok:st<300,status:st,json:async()=>o,text:async()=>JSON.stringify(o)});
  if(/api\.resend\.com/.test(url)){ mails.push(JSON.parse(opts.body)); return j({id:'m'}); }
  if(opts.method==='PATCH'){ patches.push(url); return j(claimable?[{id:'c1'}]:[]); }
  if(/reserva_cambios/.test(url)) return j(claimable?[{id:'c1',anterior:{fecha:'2030-01-02',hora:'10:00:00',servicio:'Corte',barbero:'FELIPE'},nuevo:{fecha:'2030-01-03',hora:'11:00:00',servicio:'Corte',barbero:'MARIO'}}]:[]);
  if(/\/reservas\?/.test(url)) return j([{id:RID,barberia_id:'b',nombre_cliente:'Ana <b>',whatsapp_cliente:'+56911112222',email_cliente:'ana@x.cl'}]);
  if(/\/barberias\?/.test(url)) return j([{nombre:'Essentials',email:'dueno@x.cl'}]);
  if(/\/barberos\?/.test(url)) return j([{nombre:'MARIO',email:'mario@x.cl',activo:true},{nombre:'FELIPE',email:'felipe@x.cl',activo:true}]);
  return j([]);
};
const h=require('./api/avisar-modificacion-reserva.js');
const call=async(body,method='POST')=>{ let out={}; await h({method,body},{setHeader(){},status(c){out.code=c;return this;},json(o){out.body=o;}}); return out; };
(async()=>{
 let r=await call({reservaId:RID});
 ok('responde 200',r.code===200&&r.body.ok,r);
 const dest=mails.map(m=>m.to[0]).sort().join(',');
 ok('avisa al profesional nuevo, al anterior y al cliente',dest==='ana@x.cl,felipe@x.cl,mario@x.cl',dest);
 ok('no molesta al dueño si el profesional sí se enteró',!mails.some(m=>m.to[0]==='dueno@x.cl'));
 const mMario=mails.find(m=>m.to[0]==='mario@x.cl');
 ok('el correo muestra antes y ahora',/line-through/.test(mMario.html)&&/viernes|jueves|miércoles/.test(mMario.html)&&/11:00/.test(mMario.html));
 ok('escapa el nombre del cliente',!/Ana <b>/.test(mMario.html)&&/Ana &lt;b&gt;/.test(mMario.html));
 ok('el profesional anterior recibe "ya no está en tu agenda"',/ya no est/i.test(mails.find(m=>m.to[0]==='felipe@x.cl').subject));
 ok('reclama el aviso con filtro condicional',patches.length===1&&/avisado_at=is\.null/.test(patches[0]),patches);
 mails=[]; claimable=false; r=await call({reservaId:RID});
 ok('una segunda llamada no reenvía nada',mails.length===0&&r.body.motivo,r);
 r=await call({reservaId:'no-es-uuid'}); ok('rechaza ids inválidos',r.code===400);
 r=await call({},'GET'); ok('solo acepta POST',r.code===405);
 console.log(res.join('\n')); console.log(res.filter(x=>x.startsWith('FALLO')).length+' fallos de '+res.length);
})();
