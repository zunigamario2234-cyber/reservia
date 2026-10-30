// ═══════════════════════════════════════════════════════════════════════
// TELÉFONOS CHILENOS: UNA SOLA NORMALIZACIÓN.
//
// Vive en la raíz y no depende del DOM salvo en abrirWA(), que abre una
// ventana. El resto es texto puro, así que los api/*.js lo pueden usar en
// Node con el mismo doble export que tema.js.
//
// POR QUÉ EXISTE ESTE ARCHIVO. Había dos criterios de "mismo teléfono"
// conviviendo y eso costó 18 fichas duplicadas en producción, en Essentials
// studio y Tico Barber:
//
//   · la base usa whatsapp_norm, columna GENERADA en clientes y en reservas:
//       right(regexp_replace(coalesce(whatsapp,''),'\D','','g'), 9)
//     o sea los ÚLTIMOS 9 DÍGITOS.
//   · impNormWsp() del importador usaba replace(/\D/g,''), TODOS los
//     dígitos. Así "+56987542136" (11) y "987542136" (9) no se reconocían
//     como la misma persona, mientras la base sí los considera iguales.
//
// Y además había OCHO caminos distintos armando enlaces de wa.me: cuatro
// copias de abrirWA() en app.html, club.html, mi-agenda.html, reservar.html
// y unirse.html, más tres enlaces escritos a mano. Siete de los ocho usaban
// la lógica vieja. Este archivo es el único lugar donde se decide.
// ═══════════════════════════════════════════════════════════════════════

// wspClave() es la clave de DEDUPLICADO, y es la expresión de la columna
// generada escrita en JavaScript. Si se cambia una, hay que cambiar la
// otra: el arnés compara las dos contra las trece formas de teléfono que
// hay hoy en la base.
function wspClave(valor){
  return String(valor==null?'':valor).replace(/\D/g,'').slice(-9);
}

// wspChile() responde otra pregunta: no "¿son la misma persona?" sino "¿a
// qué número escribo?". Devuelve '' cuando no se puede normalizar, y quien
// llama decide qué hacer con eso.
//
// ⚠ El prefijo es '56', NO '569'. El 9 del móvil ya viene dentro de los
// nueve dígitos, así que '569'+últimos9 lo DUPLICA y produce doce dígitos.
// La forma correcta es la que tienen 202 de las 242 fichas: +56987542136,
// once dígitos.
//
// ⚠ ES ESTRICTA A PROPÓSITO. Una versión anterior tomaba los últimos 9
// dígitos de cualquier número largo y les pegaba el país, así que convertía
// CELULARES EXTRANJEROS en números chilenos falsos: un móvil de Brasil,
// +55 11 9XXXX-XXXX, termina en nueve dígitos que empiezan con 9, así que
// salía como un +569 que le pertenece a otra persona en Chile. El dueño
// habría escrito a un desconocido creyendo que era su cliente.
//
// Ahora solo se limpia lo que es inequívocamente ruido de marcado —ceros de
// salida por delante y un 56 repetido— y después se EXIGE la forma.
//
// Límite conocido y aceptado: un número pelado de nueve dígitos que empieza
// con 9 también es un móvil válido en Perú, y no hay forma de distinguirlo
// sin más contexto. Se asume Chile porque la aplicación es chilena y 26
// fichas están guardadas así.
function wspChile(valor){
  var d = String(valor==null?'':valor).replace(/\D/g,'');
  d = d.replace(/^0+/,'');              // 00 o 0 de salida
  if(/^5656/.test(d)) d = d.slice(2);   // 56 repetido por pegar dos veces el país
  if(/^569\d{8}$/.test(d)) return d;    // ya viene completo
  if(/^9\d{8}$/.test(d))   return '56'+d;
  return '';
}

// wspLink() arma la URL de wa.me, o '' si el número no sirve. Separado de
// abrirWA() para que los enlaces <a href> escritos en HTML —que son tres en
// la aplicación— puedan usar la misma lógica sin abrir nada.
function wspLink(valor, mensaje){
  var n = wspChile(valor);
  if(!n) return '';
  return 'https://wa.me/' + n + (mensaje ? ('?text=' + encodeURIComponent(mensaje)) : '');
}

// wspAbrir() es el único punto que abre WhatsApp. Devuelve true si abrió.
// Se llama wspAbrir y no abrirWA a propósito: app.html define su propio
// abrirWA(wsp,msg) como envoltorio, y dos declaraciones `function` con el
// mismo nombre se pisan sin avisar — la del script que corre después gana.
// Con nombres distintos el envoltorio puede llamar a esta sin recursión.
//
// Cuando el número no se puede normalizar NO abre nada: una URL de wa.me
// con un número inválido lleva a una pantalla de error de WhatsApp, y quien
// aprieta el botón no tiene forma de saber que el problema es el teléfono
// guardado. El aviso se delega a `avisar`, que cada página pasa: en el
// panel es notify(), y una página que no tenga toast puede pasar un alert o
// nada.
function wspAbrir(valor, mensaje, avisar){
  var url = wspLink(valor, mensaje);
  if(!url){
    if(typeof avisar === 'function'){
      avisar('Ese teléfono no parece un móvil chileno. Revísalo en la ficha del cliente.','warn');
    }
    return false;
  }
  if(typeof window !== 'undefined' && window.open) window.open(url,'_blank');
  return true;
}

if (typeof module !== 'undefined' && module.exports) {
  module.exports = {
    wspClave: wspClave,
    wspChile: wspChile,
    wspLink: wspLink,
    wspAbrir: wspAbrir
  };
}
