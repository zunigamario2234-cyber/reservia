// Acceso "Ubicación y horario" + su modal, compartido por reservar.html y
// club.html. Antes vivía duplicado dentro de reservar.html; se extrajo cuando
// club.html iba a necesitar lo mismo, porque textoHorarioDia() ya había tenido
// que cambiar una vez (al agregar la colación) y con dos copias ese cambio se
// hace en dos lados.
//
// Es una hoja a propósito: no sabe de Supabase, ni del flujo de reserva, ni de
// slotsParaDia(). Recibe los datos ya cargados y solo los presenta. Por eso se
// pudo extraer sin tocar la duplicación grande entre reservar.html y club.html.
//
// Script CLÁSICO con ruta relativa, no módulo ES: un type="module" lo bloquea
// CORS al abrir la página con file:// (que es como se prueba este proyecto), y
// una ruta absoluta bajo file:// apunta a la raíz del disco. Así funciona igual
// servido por Vercel que abierto como archivo.
//
// USO:
//   <script src="ubicacion-modal.js"></script>
//   montarAccesoUbicacion({
//     negocio:    {nombre, direccion, telefono, whatsapp},
//     horario:    {0:{...}, 1:{...}},   // indexado por dia_semana, 0=domingo
//     contenedor: document.getElementById('header-meta')
//   });
//
// DEPENDENCIA DE CSS: el botón "Cómo llegar" usa las clases .btn y
// .btn-primary de la página que lo hospeda, para que se vea igual que el resto
// de sus botones. Hoy reservar.html y club.html las definen idénticas. Una
// página que no las tenga va a mostrar ese botón sin estilo; el resto del
// modal se pinta con el CSS que inyecta este archivo y no depende de nada.
//
// Llámalo con guarda desde el init() de la página:
//   if(typeof montarAccesoUbicacion==='function') montarAccesoUbicacion({...});
// Si este archivo no cargara (404, caché a medias), sin la guarda el
// ReferenceError cortaría el init() entero y la página se quedaría sin
// renderizar. El modal es accesorio; reservar no lo es.

(function(){
'use strict';

const DIAS = ['Domingo','Lunes','Martes','Miércoles','Jueves','Viernes','Sábado'];
// dia_semana usa 0=domingo, pero la semana se muestra partiendo el lunes.
const ORDEN = [1,2,3,4,5,6,0];

// Espacio duro. Se arma con fromCharCode y no con el carácter literal porque
// un U+00A0 en el fuente es invisible y cualquiera lo "corrige" a un espacio
// normal sin notarlo.
const NBSP = String.fromCharCode(160);

const CSS = `
.ubic-link{background:none;border:none;color:#7c6af7;font-size:11px;font-family:inherit;padding:0;cursor:pointer}
.ubic-link:hover{text-decoration:underline}
.ubic-overlay{display:none;position:fixed;inset:0;background:rgba(0,0,0,0.72);z-index:100;align-items:center;justify-content:center;padding:16px}
.ubic-overlay.open{display:flex}
.ubic-modal{background:#0f1018;border:0.5px solid #222;border-radius:12px;padding:20px;width:100%;max-width:400px;max-height:85vh;overflow-y:auto}
.ubic-hdr{display:flex;align-items:center;justify-content:space-between;margin-bottom:18px}
.ubic-titulo{font-size:13px;font-weight:600;color:#e8e6e0}
.ubic-x{background:none;border:none;color:#555;font-size:20px;line-height:1;padding:0 4px;cursor:pointer}
.ubic-x:hover{color:#e8e6e0}
.ubic-seccion{margin-bottom:18px}
.ubic-seccion:last-child{margin-bottom:0}
.ubic-label{font-size:10px;color:#555;text-transform:uppercase;letter-spacing:0.05em;margin-bottom:6px}
.ubic-dato{font-size:13px;color:#e8e6e0;line-height:1.7}
.ubic-dato a{color:#7c6af7;text-decoration:none}
.ubic-dato a:hover{text-decoration:underline}
.ubic-mapa{display:block;text-decoration:none;text-align:center;margin-top:12px}
.ubic-fila{display:flex;justify-content:space-between;gap:12px;font-size:12px;padding:6px 0;border-bottom:0.5px solid #1a1a1a}
.ubic-fila:last-child{border-bottom:none}
.ubic-dia{color:#888}
.ubic-dia.hoy{color:#e8e6e0;font-weight:600}
.ubic-horas{color:#e8e6e0;text-align:right}
.ubic-horas.apagado{color:#555}
`;

// Qué decir de un día. Se mantiene alineado con lo que slotsParaDia() hace de
// verdad, no con lo que uno supondría:
//   - sin fila para ese día, el calendario cae a HORARIOS_BASE y SÍ ofrece
//     turnos, así que poner "Cerrado" sería mentirle al cliente → "Consultar".
//   - con cerrado=true, o con horas vacías, slotsParaDia devuelve [] → cerrado
//     de verdad, aunque el motivo sea distinto.
//   - con colación se muestran los dos tramos: decir "09:00 a 19:00" a secas
//     mientras el calendario rechaza los turnos del mediodía contradice la
//     grilla que el cliente tiene al lado.
function textoHorarioDia(cfg){
  if(!cfg) return {texto:'Consultar', apagado:true};
  if(cfg.cerrado) return {texto:'Cerrado', apagado:true};
  const abre=(cfg.hora_apertura||'').slice(0,5), cierra=(cfg.hora_cierre||'').slice(0,5);
  if(!abre||!cierra) return {texto:'Cerrado', apagado:true};
  const colIni=(cfg.hora_colacion_inicio||'').slice(0,5), colFin=(cfg.hora_colacion_fin||'').slice(0,5);
  // El espacio duro deja que el renglón se corte entre los dos tramos, pero
  // nunca dentro de uno ("09:00 a" arriba y "13:00" abajo).
  const tramo=(a,b)=>a+NBSP+'a'+NBSP+b;
  if(colIni&&colFin) return {texto:tramo(abre,colIni)+' · '+tramo(colFin,cierra), apagado:false};
  return {texto:tramo(abre,cierra), apagado:false};
}

// Búsqueda por nombre + dirección, no solo dirección: si el negocio está
// registrado en Google Maps, así cae en su ficha real en vez de un punto a
// mitad de cuadra. Esquema universal — en el celular abre la app con
// navegación. Sin dirección devuelve null: con la query vacía Maps muestra
// cualquier cosa o la ubicación del visitante.
//
// app.html arma esta misma URL en verEnMapa(), para que el dueño verifique su
// dirección. Si cambia el formato acá, hay que cambiarlo allá.
function urlComoLlegar(negocio){
  const dir = (negocio.direccion||'').trim();
  if(!dir) return null;
  const query = ((negocio.nombre||'')+' '+dir).trim();
  return 'https://www.google.com/maps/search/?api=1&query='+encodeURIComponent(query);
}

function inyectarEstilos(){
  if(document.getElementById('ubic-estilos')) return;
  const st = document.createElement('style');
  st.id = 'ubic-estilos';
  st.textContent = CSS;
  document.head.appendChild(st);
}

// El markup se construye acá en vez de pedirlo en el HTML de cada página, así
// sumar el modal a una página nueva es cargar el script y llamar una función.
function construirModal(){
  const overlay = document.createElement('div');
  overlay.className = 'ubic-overlay';
  overlay.id = 'ubic-overlay';
  overlay.innerHTML =
    '<div class="ubic-modal">'+
      '<div class="ubic-hdr">'+
        '<span class="ubic-titulo">Ubicación y horario</span>'+
        '<button class="ubic-x" type="button" aria-label="Cerrar">×</button>'+
      '</div>'+
      '<div class="ubic-seccion" id="ubic-sec-dir" style="display:none">'+
        '<div class="ubic-label">Dirección</div>'+
        '<div class="ubic-dato" id="ubic-dir"></div>'+
        '<a class="btn btn-primary ubic-mapa" id="ubic-comollegar" target="_blank" rel="noopener">Cómo llegar</a>'+
      '</div>'+
      '<div class="ubic-seccion" id="ubic-sec-contacto" style="display:none">'+
        '<div class="ubic-label">Contacto</div>'+
        '<div class="ubic-dato" id="ubic-contacto"></div>'+
      '</div>'+
      '<div class="ubic-seccion" id="ubic-sec-horario" style="display:none">'+
        '<div class="ubic-label">Horario</div>'+
        '<div id="ubic-horario"></div>'+
      '</div>'+
    '</div>';
  document.body.appendChild(overlay);

  // Clic afuera cierra, adentro no. Con listeners y no con onclick inline
  // porque estas funciones viven dentro del IIFE y el atributo no las vería.
  overlay.addEventListener('click', cerrar);
  overlay.querySelector('.ubic-modal').addEventListener('click', e=>e.stopPropagation());
  overlay.querySelector('.ubic-x').addEventListener('click', cerrar);
  document.addEventListener('keydown', e=>{ if(e.key==='Escape') cerrar(); });
  return overlay;
}

function abrir(){ const o=document.getElementById('ubic-overlay'); if(o) o.classList.add('open'); }
function cerrar(){ const o=document.getElementById('ubic-overlay'); if(o) o.classList.remove('open'); }

function renderContenido(negocio, horario){
  const dir = (negocio.direccion||'').trim();
  if(dir){
    document.getElementById('ubic-dir').textContent = dir;
    document.getElementById('ubic-sec-dir').style.display = '';
    const url = urlComoLlegar(negocio);
    const btn = document.getElementById('ubic-comollegar');
    if(url) btn.href = url; else btn.style.display = 'none';
  }

  // Se arma por DOM en vez de innerHTML: teléfono y WhatsApp son texto libre
  // cargado por el dueño y acá no hay helper de escape.
  const cont = document.getElementById('ubic-contacto');
  cont.innerHTML = '';
  const agregarContacto = (href, texto, externo) => {
    if(cont.childNodes.length) cont.appendChild(document.createElement('br'));
    const a = document.createElement('a');
    a.href = href; a.textContent = texto;
    if(externo){ a.target = '_blank'; a.rel = 'noopener'; }
    cont.appendChild(a);
  };
  if(negocio.telefono) agregarContacto('tel:'+negocio.telefono.replace(/[^\d+]/g,''), '📞 '+negocio.telefono, false);
  if(negocio.whatsapp) agregarContacto('https://wa.me/'+negocio.whatsapp.replace(/\D/g,''), '📱 '+negocio.whatsapp, true);
  if(cont.childNodes.length) document.getElementById('ubic-sec-contacto').style.display = '';

  // Solo si el dueño configuró al menos un día. Con la tabla vacía se oculta
  // la sección entera en vez de mostrar el horario por defecto: presentar como
  // oficial algo que nunca confirmó es peor que no mostrar nada.
  if(Object.keys(horario).length){
    const hoy = new Date().getDay();
    document.getElementById('ubic-horario').innerHTML = ORDEN.map(d=>{
      const {texto,apagado} = textoHorarioDia(horario[d]);
      return '<div class="ubic-fila">'+
        '<span class="ubic-dia'+(d===hoy?' hoy':'')+'">'+DIAS[d]+(d===hoy?' · hoy':'')+'</span>'+
        '<span class="ubic-horas'+(apagado?' apagado':'')+'">'+texto+'</span>'+
      '</div>';
    }).join('');
    document.getElementById('ubic-sec-horario').style.display = '';
  }
}

// Monta el acceso en el contenedor que le pases. No monta nada si no hay ni
// dirección ni horario: un modal vacío es peor que ningún acceso.
window.montarAccesoUbicacion = function({negocio, horario, contenedor}){
  negocio = negocio || {};
  horario = horario || {};
  if(!contenedor) return;
  const hayDir = !!(negocio.direccion||'').trim();
  if(!hayDir && !Object.keys(horario).length) return;

  inyectarEstilos();
  if(!document.getElementById('ubic-overlay')) construirModal();
  renderContenido(negocio, horario);

  const btn = document.createElement('button');
  btn.type = 'button';
  btn.className = 'ubic-link';
  btn.textContent = '📍 Ubicación y horario';
  btn.addEventListener('click', abrir);
  contenedor.appendChild(btn);
};

})();
