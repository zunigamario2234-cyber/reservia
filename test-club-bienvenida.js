// Prueba del endpoint api/enviar-club-bienvenida con fetch simulado. node test-club-bienvenida.js
process.env.RESEND_API_KEY='x'; process.env.SUPABASE_SERVICE_ROLE_KEY='y'; process.env.SUPABASE_URL='https://x.supabase.co';
const res=[]; const ok=(n,c,x)=>res.push((c?'OK    ':'FALLO ')+n+(c?'':'  -> '+JSON.stringify(x)));
const CO='11111111-1111-1111-1111-111111111111', B='22222222-2222-2222-2222-222222222222', C='33333333-3333-3333-3333-333333333333';
let mails=[], patches=[], st;
const reset=()=>{ mails=[]; patches=[]; st={rubro:'Barbería / Peluquería / Centro de estética',club:true,email:'ana@x.cl',invitado:null,previas:[],claim:true,resendFalla:false}; };
global.fetch=async(url,opts={})=>{
  const j=(o,s=200)=>({ok:s<300,status:s,json:async()=>o,text:async()=>JSON.stringify(o)});
  if(/api\.resend\.com/.test(url)){ if(st.resendFalla) return j({error:'x'},500); mails.push(JSON.parse(opts.body)); return j({id:'m'}); }
  if(opts.method==='PATCH'){ patches.push({url,body:JSON.parse(opts.body)}); return j(/club_invitado_at=is\.null/.test(url)&&!st.claim?[]:[{id:C}]); }
  if(/\/visitas\?/.test(url)&&/cobro_id=eq/.test(url)) return j([{id:'v1',barberia_id:B,cliente_id:C,cobro_id:CO},{id:'v2',barberia_id:B,cliente_id:C,cobro_id:CO}]);
  if(/\/visitas\?/.test(url)&&/neq/.test(url)) return j(st.previas);
  if(/\/barberias\?/.test(url)) return j([{nombre:'Essentials',logo_url:null,rubro:st.rubro,club_vip_activo:st.club}]);
  if(/\/clientes\?/.test(url)) return j([{nombre:'Ana Pérez',email:st.email,club_invitado_at:st.invitado}]);
  return j([]);
};
const h=require('./api/enviar-club-bienvenida.js');
const call=async(body,method='POST')=>{ let out={}; await h({method,body,headers:{host:'mireservia.cl','x-forwarded-proto':'https'}},{setHeader(){},status(c){out.code=c;return this;},json(o){out.body=o;}}); return out; };
(async()=>{
 reset(); let r=await call({cobroId:CO});
 ok('primera visita: manda 1 correo (aunque el cobro tenga 2 visitas del mismo cliente)',mails.length===1&&r.body.enviados===1,r);
 ok('va al cliente con el link a su Club',mails[0]&&mails[0].to[0]==='ana@x.cl'&&mails[0].html.includes(`https://mireservia.cl/club.html?id=${B}&cliente=${C}`));
 ok('explica cómo instalarla (iPhone y Android)',/iPhone/.test(mails[0].html)&&/Android/.test(mails[0].html)&&/Hola Ana /.test(mails[0].html));
 ok('marca club_invitado_at',patches.some(p=>p.body.club_invitado_at));
 reset(); st.previas=[{id:'old'}]; r=await call({cobroId:CO}); ok('si ya tenía visitas antes: no manda',mails.length===0,r);
 reset(); st.club=false; r=await call({cobroId:CO}); ok('Club apagado: no manda',mails.length===0,r);
 reset(); st.rubro='Otro rubro'; r=await call({cobroId:CO}); ok('rubro sin Club: no manda',mails.length===0,r);
 reset(); st.email=''; r=await call({cobroId:CO}); ok('sin correo: no manda ni marca',mails.length===0&&!patches.length&&r.body.omitidos[0].motivo==='sin_correo',r);
 reset(); st.invitado='2026-11-01'; r=await call({cobroId:CO}); ok('ya invitado: no repite',mails.length===0,r);
 reset(); st.claim=false; r=await call({visitaId:CO}); ok('si otra llamada ganó el reclamo: no duplica',mails.length===0,r);
 reset(); st.resendFalla=true; r=await call({cobroId:CO}); ok('si falla el envío libera la marca para reintentar',patches.some(p=>p.body.club_invitado_at===null),patches);
 r=await call({cobroId:'x'}); ok('rechaza ids inválidos',r.code===400);
 r=await call({},'GET'); ok('solo acepta POST',r.code===405);
 console.log(res.join('\n')); console.log(res.filter(x=>x.startsWith('FALLO')).length+' fallos de '+res.length);
})();
