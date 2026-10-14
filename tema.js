// ═══════════════════════════════════════════════════════════════════════
// TEMA POR LOGO — funciones puras.
//
// Vive en la raíz y no depende del DOM salvo en extraerPaleta(), que
// necesita canvas. El resto es aritmética de color, así que la Entrega 3
// (los correos, que corren en Node) usa ESTE archivo y no una copia: la
// cuarta copia de una fórmula es cómo se desincronizan los números.
//
// Dos espacios de color, a propósito:
//   · HSV para CLASIFICAR saturación. HSL se vuelve inútil cerca del
//     blanco — #FEFFFF tiene saturación HSL 0,98 porque el denominador
//     (2-max-min) se va a cero. Medido en Tico: HSL daba mediana 0,333
//     (ruido numérico) y HSV da 0,012, que es la verdad: logo blanco.
//   · HSL para MANIPULAR luminosidad, que es lo que HSL hace bien.
// ═══════════════════════════════════════════════════════════════════════

// ── constantes del mockup aprobado ────────────────────────────────────
var AZUL_RESERVIA = '#2957D6';
var TXT_OSCURO    = '#15181D';   // texto oscuro y superficie del modo oscuro
var MONO_CLARO    = '#1B2130';   // acento monocromático en modo claro
var MONO_OSCURO   = '#FFFFFF';   // acento monocromático en modo oscuro

// ── umbrales, calibrados contra los logos reales ──────────────────────
// dist>70: en Tico, >40 daba sMed 0,089 y >70 da 0,333 — los píxeles de
//   antialias arrastran la mediana. A partir de 70 se estabiliza.
// masa>=0,5%: el primer plano de Sintonía es 2,18% del archivo. Un umbral
//   de 5% la clasificaba como monocromática, que fue el error original.
// sHSV<0,06 mono: Essentials 0,000 y Tico 0,012 caen holgados.
// sHSV>=0,25 color: #2957D6 tiene sHSV 0,81. Sintonía queda en 0,121, al
//   medio de "sutil", que es donde debe estar.
var U_DIST = 70, U_MASA = 0.005, S_MONO = 0.06, S_COLOR = 0.25;
var U_FONDO_UNIFORME = 0.02;   // desv. est. de L en el anillo del borde
var U_MODO_OSCURO    = 0.18;   // L=0,184 es el punto medio perceptual (L*=50)
// El fondo transparente se decide por las CUATRO ESQUINAS, no por el
// anillo del borde. Medido: el PNG de Essentials es un círculo que toca los
// bordes y deja 20,4% del anillo opaco, justo en el filo de un umbral del
// 20%. Y un wordmark recortado ajustado tiene el anillo lleno de LETRA, no
// de fondo, así que por anillo saldría "con fondo" y el filtro de distancia
// descartaría el logo entero. Las esquinas son el único lugar donde un logo
// centrado no dibuja.
var U_ESQUINA        = 0.08;   // lado del parche, como fracción del lienzo
var U_ESQUINA_OPACO  = 0.20;   // menos de esto en las esquinas = transparente
var SUP_CLARA = '#F5F6FA';     // la superficie del modo claro, para comparar

// satHSV es inestable cerca del negro: (1,5,17) da 0,94 y (4,4,6) da 0,33
// sin tener color real, porque el denominador es el canal máximo. Un píxel
// solo cuenta para la saturación y para los grupos de color si tiene brillo
// y separación de canales de verdad. Sintonía pasa: #8D877D tiene máximo
// 141 y diferencia 16.
var U_BRILLO_MIN = 50;         // canal máximo mínimo
var U_DIF_MIN    = 10;         // max - min mínimo
var U_FRAC_COLOR = 0.10;       // fracción del primer plano con color medible
function tieneColorMedible(r, g, b) {
  var mx = Math.max(r, g, b), mn = Math.min(r, g, b);
  return mx >= U_BRILLO_MIN && (mx - mn) >= U_DIF_MIN;
}
var OBJ_TEXTO = 4.5;           // WCAG AA, texto normal
var OBJ_UI    = 3.0;           // WCAG AA, elemento de interfaz

// ── hex ───────────────────────────────────────────────────────────────
// La MISMA expresión que el check de la base. Los anclajes ^ y $ son la
// defensa contra inyección de CSS: sin ellos, "#2957D6;}body{display:none"
// pasaría la validación.
function hexValido(s) {
  return typeof s === 'string' && /^#[0-9A-Fa-f]{6}$/.test(s);
}
function rgbDe(hex) {
  return [parseInt(hex.slice(1, 3), 16), parseInt(hex.slice(3, 5), 16), parseInt(hex.slice(5, 7), 16)];
}
function hexDe(r, g, b) {
  var v = [r, g, b].map(function (x) {
    return Math.max(0, Math.min(255, Math.round(x))).toString(16).padStart(2, '0');
  });
  return ('#' + v.join('')).toUpperCase();
}

// ── luminancia y contraste (WCAG 2.x) ─────────────────────────────────
function canalLineal(c) {
  c = c / 255;
  return c <= 0.03928 ? c / 12.92 : Math.pow((c + 0.055) / 1.055, 2.4);
}
function luminancia(hex) {
  var p = rgbDe(hex);
  return 0.2126 * canalLineal(p[0]) + 0.7152 * canalLineal(p[1]) + 0.0722 * canalLineal(p[2]);
}
function contraste(l1, l2) {
  var a = Math.max(l1, l2), b = Math.min(l1, l2);
  return (a + 0.05) / (b + 0.05);
}
function contrasteHex(h1, h2) { return contraste(luminancia(h1), luminancia(h2)); }

// ── espacios de color ─────────────────────────────────────────────────
function satHSV(r, g, b) {
  var mx = Math.max(r, g, b), mn = Math.min(r, g, b);
  return mx ? (mx - mn) / mx : 0;
}
function aHsl(hex) {
  var p = rgbDe(hex), r = p[0] / 255, g = p[1] / 255, b = p[2] / 255;
  var mx = Math.max(r, g, b), mn = Math.min(r, g, b), d = mx - mn;
  var l = (mx + mn) / 2, h = 0, s = 0;
  if (d) {
    s = l > 0.5 ? d / (2 - mx - mn) : d / (mx + mn);
    h = mx === r ? ((g - b) / d + (g < b ? 6 : 0)) : mx === g ? ((b - r) / d + 2) : ((r - g) / d + 4);
    h = h / 6;
  }
  return [h, s, l];
}
function deHsl(h, s, l) {
  if (!s) return hexDe(l * 255, l * 255, l * 255);
  var q = l < 0.5 ? l * (1 + s) : l + s - l * s, p = 2 * l - q;
  var f = function (t) {
    if (t < 0) t += 1; if (t > 1) t -= 1;
    if (t < 1 / 6) return p + (q - p) * 6 * t;
    if (t < 1 / 2) return q;
    if (t < 2 / 3) return p + (q - p) * (2 / 3 - t) * 6;
    return p;
  };
  return hexDe(f(h + 1 / 3) * 255, f(h) * 255, f(h - 1 / 3) * 255);
}
// Mezcla lineal en sRGB. `t` es el peso de `b`: mezclar(x,'#FFFFFF',0.9)
// es 90% blanco. El redondeo queda fijado acá y en ningún otro lugar.
function mezclar(a, b, t) {
  var p = rgbDe(a), q = rgbDe(b);
  return hexDe(p[0] + (q[0] - p[0]) * t, p[1] + (q[1] - p[1]) * t, p[2] + (q[2] - p[2]) * t);
}

// ── ajuste del acento ─────────────────────────────────────────────────
// Dos direcciones, porque el acento convive con texto distinto en cada
// modo. En claro lleva texto BLANCO encima, así que tiene que ser oscuro.
// En oscuro lleva texto OSCURO encima, así que tiene que ser claro.
// Las dos conservan tono y saturación: solo se mueve la luminosidad.
function oscurecerHasta(hex, obj) {
  obj = obj || OBJ_TEXTO;
  if (contraste(1, luminancia(hex)) >= obj) return hex;
  var p = aHsl(hex), h = p[0], s = p[1], l = p[2];
  for (var i = 0; i < 260 && l > 0; i++) {
    l -= 0.004;
    var c = deHsl(h, s, Math.max(l, 0));
    if (contraste(1, luminancia(c)) >= obj) return c;
  }
  return '#000000';
}
function aclararHasta(hex, obj, textoOscuro) {
  obj = obj || OBJ_TEXTO;
  var lo = luminancia(textoOscuro || TXT_OSCURO);
  if (contraste(lo, luminancia(hex)) >= obj) return hex;
  var p = aHsl(hex), h = p[0], s = p[1], l = p[2];
  for (var i = 0; i < 260 && l < 1; i++) {
    l += 0.004;
    var c = deHsl(h, s, Math.min(l, 1));
    if (contraste(lo, luminancia(c)) >= obj) return c;
  }
  return '#FFFFFF';
}
function ajustarAcento(hex, modo, obj) {
  return modo === 'oscuro' ? aclararHasta(hex, obj) : oscurecerHasta(hex, obj);
}
// Se prefiere blanco; si no llega al objetivo se usa el oscuro; si ninguno
// llega se devuelve el mejor y se marca, para que el panel lo pueda decir.
function textoSobre(acento, obj) {
  obj = obj || OBJ_TEXTO;
  var la = luminancia(acento);
  var cB = contraste(1, la), cO = contraste(luminancia(TXT_OSCURO), la);
  if (cB >= obj) return { color: '#FFFFFF', contraste: cB, cumple: true };
  if (cO >= obj) return { color: TXT_OSCURO, contraste: cO, cumple: true };
  return cB >= cO
    ? { color: '#FFFFFF', contraste: cB, cumple: false }
    : { color: TXT_OSCURO, contraste: cO, cumple: false };
}

// ── clasificación ─────────────────────────────────────────────────────
// Dos preguntas separadas, porque una sola mediana no las responde:
//   1. ¿hay SUFICIENTE material con color? -> fraccionConColor
//   2. ¿qué saturación tiene ESE material? -> satMediana (solo de esos px)
//
// Medir la mediana sobre todo el primer plano falla en los dos sentidos.
// Si los píxeles sin color se descartan, Tico (logo blanco) sube a "sutil"
// porque solo queda su borde de antialias con un tinte leve. Si se cuentan
// como cero, un logo con 30% de letras de color baja a "monocromático"
// porque la mayoría no tiene color. La fracción resuelve las dos.
//
// Umbral 10%, con los datos: Essentials 0,0% y Tico 4,6% son
// monocromáticos; Sintonía 91,6%, ZZ prueba 58,7% y un logo con 13,5% de
// letras tienen color. El hueco entre 4,6% y 13,5% es de 3x.
function clasificar(masa, fraccionConColor, satMediana) {
  if (masa < U_MASA) return 'monocromatico';
  if (fraccionConColor < U_FRAC_COLOR) return 'monocromatico';
  if (satMediana < S_MONO) return 'monocromatico';
  if (satMediana < S_COLOR) return 'sutil';
  return 'color';
}
function modoPorFondo(fondoHex, uniforme) {
  return (uniforme && luminancia(fondoHex) < U_MODO_OSCURO) ? 'oscuro' : 'claro';
}
// Sin fondo propio no hay luminancia de fondo que mirar, así que se decide
// por dónde el logo se LEE mejor: gana la superficie contra la que el color
// medio del logo da más contraste. Un logo blanco pide fondo oscuro, uno
// negro pide claro, y un azul medio se lee mejor sobre claro.
function modoPorContraste(colorLogo) {
  return contrasteHex(colorLogo, SUP_CLARA) > contrasteHex(colorLogo, TXT_OSCURO)
    ? 'claro' : 'oscuro';
}
// El acento sale del GRUPO de color más frecuente entre los píxeles que
// tienen saturación de verdad, con la mediana RGB de ese grupo. El promedio
// de todo el primer plano mezclaría dos marcas distintas en un color que no
// es ninguna de las dos: 60% rojo y 40% azul promediados dan violeta.
function colorRepresentativo(grupos) {
  var mejor = null, n = 0;
  Object.keys(grupos).forEach(function (k) {
    if (grupos[k].r.length > n) { n = grupos[k].r.length; mejor = k; }
  });
  if (!mejor) return null;
  var G = grupos[mejor];
  return hexDe(mediana(G.r), mediana(G.g), mediana(G.b));
}
// La paleta que ve el dueño sale de la MEDIANA RGB de cada grupo, no de la
// cubeta cuantizada. La cubeta es el color redondeado a múltiplos de 24,
// que no existe en el logo: en Sintonía aparecían dos rosados apagados que
// la marca no tiene, porque el redondeo los había corrido de lugar.
//
// Y se deduplica por distancia: dos cubetas vecinas dan medianas casi
// iguales, y ofrecer seis variantes del mismo beige no es una paleta.
function paletaDeGrupos(grupos, n, minDist) {
  n = n || 6; minDist = minDist || 40;
  var claves = Object.keys(grupos).sort(function (a, b) {
    return grupos[b].r.length - grupos[a].r.length;
  });
  var out = [];
  for (var i = 0; i < claves.length && out.length < n; i++) {
    var G = grupos[claves[i]];
    var hex = hexDe(mediana(G.r), mediana(G.g), mediana(G.b));
    var cerca = false;
    for (var j = 0; j < out.length; j++) {
      var p = rgbDe(out[j]), q = rgbDe(hex);
      var dr = p[0] - q[0], dg = p[1] - q[1], db = p[2] - q[2];
      if (Math.sqrt(dr * dr + dg * dg + db * db) < minDist) { cerca = true; break; }
    }
    if (!cerca) out.push(hex);
  }
  return out;
}
// Las muestras que ve el dueño. Función pura para que la suite la cubra:
// vivía en app.html y ahí no se podía probar.
//
// Cuando el logo es MONOCROMÁTICO no se ofrece "Del logo".
// colorRepresentativo cae al promedio del primer plano cuando no hay
// grupos de color, y ese promedio no es un color de la marca: es un número
// sacado de miles de píxeles. Peor aún, el WebP con pérdida le mete croma a
// píxeles neutros — medido: el mismo píxel que en el JPEG es #060606 sale
// #070504 en el WebP, y #070707 sale #050807. Sobre miles de píxeles los
// sesgos no se cancelan y el promedio aterriza con un tinte que el logo no
// tiene. Ofrecer eso como "color de tu logo" justo después de decirle al
// dueño que su logo no tiene color sería contradecirse.
function muestrasPara(an, limite) {
  limite = limite || 8;
  var vistos = {}, out = [];
  var sumar = function (hex, etq) {
    if (!hexValido(hex) || vistos[hex]) return;
    vistos[hex] = 1; out.push({ hex: hex, etq: etq });
  };
  if (an) {
    sumar(an.acentoSugerido, 'Sugerido');
    if (an.clase !== 'monocromatico') sumar(an.colorRepresentativo, 'Del logo');
    (an.paleta || []).forEach(function (h) { sumar(h, ''); });
  }
  sumar(AZUL_RESERVIA, 'Reservia');
  return out.slice(0, limite);
}
function acentoPara(clase, modo, colorBase) {
  if (clase === 'monocromatico') return modo === 'oscuro' ? MONO_OSCURO : MONO_CLARO;
  return ajustarAcento(colorBase, modo);
}

// ── el tema: los 11 tokens del mockup ─────────────────────────────────
// El ajuste de contraste va ADENTRO: ninguna pantalla puede pintar un
// acento que no sostenga su texto, ni por olvido ni por pasarle un color
// crudo. Si ya cumple, ajustarAcento lo devuelve sin tocar.
function generarTema(op) {
  var modo = op.modo === 'oscuro' ? 'oscuro' : 'claro';
  var acento = ajustarAcento(hexValido(op.color) ? op.color : AZUL_RESERVIA, modo);
  var t = modo === 'oscuro'
    ? { '--fondo': '#15181D', '--tarjeta': '#1F242B', '--fondo-suave': '#262B33',
        '--borde-suave': '#333944', '--borde': '#2B313A',
        '--texto': '#F4F5F7', '--texto-atenuado': '#9AA3AF',
        '--acento': acento,
        '--acento-tinte': 'rgba(255,255,255,0.10)',
        '--acento-borde': 'rgba(255,255,255,0.20)',
        '--texto-sobre-acento': TXT_OSCURO }
    : { '--fondo': '#F5F6FA', '--tarjeta': '#FFFFFF', '--fondo-suave': '#F7F8FB',
        '--borde-suave': '#EEF0F5', '--borde': '#D8DEE8',
        '--texto': '#1B2130', '--texto-atenuado': '#6B7280',
        '--acento': acento,
        '--acento-tinte': mezclar(acento, '#FFFFFF', 0.90),
        '--acento-borde': mezclar(acento, '#FFFFFF', 0.72),
        '--texto-sobre-acento': '#FFFFFF' };
  return t;
}
// El acento es un elemento de interfaz, no texto: contra la superficie que
// lo rodea necesita 3:1, no 4,5:1. Si no llega, el panel lo DICE en vez de
// esconderlo — un botón que no se distingue del fondo es un botón perdido.
function acentoContraSuperficie(acento, superficie) {
  var k = contrasteHex(acento, superficie);
  return { contraste: k, cumple: k >= OBJ_UI };
}

// ── escritura: setProperty y nada más ─────────────────────────────────
// Nunca se arma texto CSS ni se inyecta <style>: un valor que no pase
// hexValido no debe poder convertirse en una regla. setProperty no
// interpreta reglas, así que el peor caso es una variable ignorada.
function aplicarTema(tokens, raiz) {
  var el = raiz || (typeof document !== 'undefined' ? document.documentElement : null);
  if (!el || !el.style) return false;
  Object.keys(tokens).forEach(function (k) { el.style.setProperty(k, tokens[k]); });
  return true;
}

// ── extracción (necesita canvas) ──────────────────────────────────────
function mediana(a) {
  if (!a.length) return 0;
  var s = a.slice().sort(function (x, y) { return x - y; });
  var m = s.length >> 1;
  return s.length % 2 ? s[m] : (s[m - 1] + s[m]) / 2;
}
// 150x150 SIN suavizar. Medido: a 50x50 con suavizado el logo blanco de
// Essentials desaparecía entero (0% de píxeles claros contra 1,9% real) y
// Tico perdía ocho de cada diez. A 150 sin suavizar queda a 0,2 puntos de
// la resolución completa usando 1/12 de los píxeles.
function extraerPaleta(src, N) {
  N = N || 150;
  return new Promise(function (res) {
    var img = new Image();
    img.crossOrigin = 'anonymous';   // permite re-extraer del logo ya guardado
    img.onerror = function () { res(null); };
    img.onload = function () {
      var c = document.createElement('canvas');
      c.width = N; c.height = N;
      var x = c.getContext('2d');
      x.imageSmoothingEnabled = false;
      x.drawImage(img, 0, 0, N, N);
      var d;
      try { d = x.getImageData(0, 0, N, N).data; }
      catch (e) { res(null); return; }          // canvas contaminado
      // Las cuatro esquinas deciden si hay fondo. La mediana de una lista
      // vacía da 0, que hexDe convierte en #000000: ese negro inventado
      // arrastraba a modo oscuro a cualquier logo con alfa, que va a ser el
      // caso normal al exportar en PNG/WebP.
      var pe = Math.max(4, Math.round(N * U_ESQUINA));
      var nEsq = 0, opEsq = 0;
      [[0, 0], [N - pe, 0], [0, N - pe], [N - pe, N - pe]].forEach(function (e) {
        for (var y = e[1]; y < e[1] + pe; y++) for (var z = e[0]; z < e[0] + pe; z++) {
          nEsq++;
          if (d[(y * N + z) * 4 + 3] >= 100) opEsq++;
        }
      });
      var transparente = nEsq ? (opEsq / nEsq) < U_ESQUINA_OPACO : true;
      var gr = Math.max(2, Math.round(N * 0.02));
      var rr = [], gg = [], bb = [], ll = [];
      for (var j = 0; j < N; j++) for (var i = 0; i < N; i++) {
        if (i >= gr && i < N - gr && j >= gr && j < N - gr) continue;
        var k = (j * N + i) * 4;
        if (d[k + 3] < 100) continue;
        rr.push(d[k]); gg.push(d[k + 1]); bb.push(d[k + 2]);
        ll.push(luminancia(hexDe(d[k], d[k + 1], d[k + 2])));
      }
      var fr = mediana(rr), fg = mediana(gg), fb = mediana(bb);
      var fondo = transparente ? null : hexDe(fr, fg, fb);
      var mu = ll.reduce(function (a, b) { return a + b; }, 0) / (ll.length || 1);
      var sd = Math.sqrt(ll.reduce(function (a, b) { return a + (b - mu) * (b - mu); }, 0) / (ll.length || 1));
      var uniforme = transparente ? false : (sd < U_FONDO_UNIFORME);
      var op = 0, sats = [], sr = 0, sg = 0, sb = 0, nfg = 0, nmed = 0;
      var cuenta = {}, grupos = {};
      for (var j2 = 0; j2 < N; j2++) for (var i2 = 0; i2 < N; i2++) {
        var k2 = (j2 * N + i2) * 4;
        if (d[k2 + 3] < 100) continue;
        op++;
        // Sin fondo propio no hay de qué separarse: el primer plano son
        // todos los píxeles opacos. Con el filtro puesto, un logo negro
        // sobre transparente se descartaría entero contra ese #000000
        // inventado.
        if (!transparente) {
          var dr = d[k2] - fr, dg = d[k2 + 1] - fg, db = d[k2 + 2] - fb;
          if (Math.sqrt(dr * dr + dg * dg + db * db) <= U_DIST) continue;
        }
        nfg++;
        sr += d[k2]; sg += d[k2 + 1]; sb += d[k2 + 2];
        var q = function (v) { return Math.round(v / 24) * 24; };
        var key = hexDe(q(d[k2]), q(d[k2 + 1]), q(d[k2 + 2]));
        cuenta[key] = (cuenta[key] || 0) + 1;
        // Un píxel sin color medible cuenta como saturación CERO, no se
        // descarta. Es la diferencia que importa: un píxel casi blanco o
        // casi negro es EVIDENCIA de que el logo no tiene color, así que
        // sacarlo de la muestra sube la mediana artificialmente. Medido:
        // descartándolos, Tico (logo blanco, #EBEDEE con diferencia 3)
        // pasaba a "sutil" con un acento gris azulado, porque solo quedaba
        // el borde de antialias con un tinte leve. Contándolos como 0,
        // vuelve a ser monocromático, que es lo que es.
        // Los píxeles sin color medible NO entran a la muestra de
        // saturación: se cuentan aparte, con la fracción. Así la mediana
        // describe el material que SÍ tiene color, y la fracción dice si
        // ese material alcanza para hablar de un color de marca.
        if (!tieneColorMedible(d[k2], d[k2 + 1], d[k2 + 2])) continue;
        nmed++;
        var st = satHSV(d[k2], d[k2 + 1], d[k2 + 2]);
        sats.push(st);
        if (st >= S_MONO) {
          if (!grupos[key]) grupos[key] = { r: [], g: [], b: [] };
          grupos[key].r.push(d[k2]); grupos[key].g.push(d[k2 + 1]); grupos[key].b.push(d[k2 + 2]);
        }
      }
      var masa = op ? nfg / op : 0;
      var satMed = mediana(sats);
      var medio = nfg ? hexDe(sr / nfg, sg / nfg, sb / nfg) : (fondo || SUP_CLARA);
      var repr = colorRepresentativo(grupos) || medio;
      var fracColor = nfg ? nmed / nfg : 0;
      var clase = clasificar(masa, fracColor, satMed);
      var modo = transparente ? modoPorContraste(medio) : modoPorFondo(fondo, uniforme);
      var paleta = paletaDeGrupos(grupos, 6, 40);
      res({ fondo: fondo, lumFondo: fondo === null ? null : luminancia(fondo),
            sdFondo: sd, fondoUniforme: uniforme, fondoTransparente: transparente,
            masa: masa, satMediana: satMed, fraccionConColor: fracColor, colorMedio: medio, colorRepresentativo: repr,
            clase: clase, modoSugerido: modo,
            acentoSugerido: acentoPara(clase, modo, repr), paleta: paleta });
    };
    img.src = src;
  });
}

if (typeof module !== 'undefined' && module.exports) {
  module.exports = {
    AZUL_RESERVIA: AZUL_RESERVIA, TXT_OSCURO: TXT_OSCURO,
    MONO_CLARO: MONO_CLARO, MONO_OSCURO: MONO_OSCURO,
    U_DIST: U_DIST, U_MASA: U_MASA, S_MONO: S_MONO, S_COLOR: S_COLOR,
    OBJ_TEXTO: OBJ_TEXTO, OBJ_UI: OBJ_UI,
    U_ESQUINA: U_ESQUINA, U_ESQUINA_OPACO: U_ESQUINA_OPACO, SUP_CLARA: SUP_CLARA,
    U_BRILLO_MIN: U_BRILLO_MIN, U_DIF_MIN: U_DIF_MIN, U_FRAC_COLOR: U_FRAC_COLOR, tieneColorMedible: tieneColorMedible,
    hexValido: hexValido, rgbDe: rgbDe, hexDe: hexDe,
    luminancia: luminancia, contraste: contraste, contrasteHex: contrasteHex,
    satHSV: satHSV, aHsl: aHsl, deHsl: deHsl, mezclar: mezclar,
    oscurecerHasta: oscurecerHasta, aclararHasta: aclararHasta,
    ajustarAcento: ajustarAcento, textoSobre: textoSobre,
    clasificar: clasificar, modoPorFondo: modoPorFondo, modoPorContraste: modoPorContraste,
    colorRepresentativo: colorRepresentativo, paletaDeGrupos: paletaDeGrupos,
    muestrasPara: muestrasPara,
    acentoPara: acentoPara,
    generarTema: generarTema, acentoContraSuperficie: acentoContraSuperficie,
    aplicarTema: aplicarTema, mediana: mediana
  };
}
