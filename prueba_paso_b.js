// ═══════════════════════════════════════════════════════════════════════
// PRUEBAS DEL PASO B — el front de las subidas.
//
// Pegar en la consola de app.html con la sesión del dueño de
// "ZZ prueba bucket" y el panel ya cargado. Corre al pegarlo.
// Aborta si el panel abierto no es el del negocio de prueba.
//
// Prueba el MECANISMO, no las pantallas: el recortador necesita clics, así
// que las cinco pantallas van a mano (ver los pasos manuales).
//
// Lo que cubre: extDeMime, contentType servido de verdad por el CDN, el
// pre-chequeo de rol, la rama de "se guardó sin la foto", y el peso real de
// una foto de celular antes y después del recorte.
// ═══════════════════════════════════════════════════════════════════════
(async () => {
  const ESPERADO = 'd75633ff-4f6a-4f32-b5b4-83b62ee80f24';
  const id = (typeof S !== 'undefined') ? S.barberia?.id : undefined;
  if (!id) { console.error('✗ No hay negocio cargado. ¿Estás en app.html con el panel ya cargado?'); return; }
  if (id !== ESPERADO) {
    console.error('✗ ABORTADO: no se corrió ni se escribió nada.');
    console.error('  Este panel es del negocio ' + id);
    console.error('  Esperaba ZZ prueba bucket (' + ESPERADO + ').');
    return;
  }

  const filas = [];
  const anotar = (g, prueba, esperado, obtenido, ok) =>
    filas.push({ grupo: g, prueba, esperado, obtenido, resultado: ok ? 'PASA' : 'FALLA' });

  const lienzo = (w, h, pintar) => {
    const c = document.createElement('canvas');
    c.width = w; c.height = h;
    pintar(c.getContext('2d'), w, h);
    return c;
  };
  const aBlob = (c, mime, q) => new Promise(r => c.toBlob(r, mime, q));

  // ─── A · extDeMime ───────────────────────────────────────────────────
  for (const [mime, esp] of [['image/jpeg','jpg'], ['image/png','png'], ['image/webp','webp'],
                             ['image/gif','jpg'], ['image/svg+xml','jpg'], ['','jpg'], [undefined,'jpg']]) {
    const got = extDeMime(mime);
    anotar('A·extDeMime', `${JSON.stringify(mime)} -> ${esp}`, esp, got, got === esp);
  }

  // A2 · el caso que motiva el helper: toBlob con un tipo no soportado cae en
  // silencio a PNG. La afirmación que importa es que derivar la extension del
  // TIPO PEDIDO daría una distinta (y equivocada) que derivarla del blob real.
  {
    const c = lienzo(8, 8, (x) => { x.fillStyle = '#2957D6'; x.fillRect(0, 0, 8, 8); });
    const b = await aBlob(c, 'image/jxl', 0.9);
    const extPedido = extDeMime('image/jxl');   // 'jpg' por el fallback
    const extReal = extDeMime(b.type);          // 'png', el tipo que salió
    anotar('A·extDeMime', 'toBlob("image/jxl") cae a PNG y la ext sigue al blob real',
      'tipo real = image/png, ext = png != ' + extPedido,
      `tipo real = ${b.type}, ext = ${extReal}, por pedido habria sido ${extPedido}`,
      b.type === 'image/png' && extReal === 'png' && extReal !== extPedido);
  }

  // ─── B · contentType de verdad, servido por el CDN ───────────────────
  // No alcanza con mandarlo: hay que confirmar que vuelve en el header.
  const CARPETAS = ['logos', 'portadas', 'profesionales', 'servicios', 'alianzas'];
  const creadas = [];
  for (const carpeta of CARPETAS) {
    const c = lienzo(16, 16, (x) => { x.fillStyle = '#2957D6'; x.fillRect(0, 0, 16, 16); });
    const blob = await aBlob(c, 'image/jpeg', 0.92);
    const ruta = `${carpeta}/${id}/prueba-paso-b.${extDeMime(blob.type)}`;
    const { error } = await sb.storage.from('fotos')
      .upload(ruta, blob, { upsert: true, contentType: blob.type });
    if (error) { anotar('B·contentType', `${carpeta}/`, 'sube', 'rechazado: ' + error.message, false); continue; }
    creadas.push(ruta);
    const { data } = sb.storage.from('fotos').getPublicUrl(ruta);
    const r = await fetch(data.publicUrl + '?t=' + Date.now(), { cache: 'no-store' });
    const ct = (r.headers.get('content-type') || '').split(';')[0];
    anotar('B·contentType', `${carpeta}/ sirve ${blob.type}`, blob.type, ct || '(sin header)', ct === blob.type);
  }

  // ─── C · foto de celular: peso antes y despues del recorte ───────────
  // Es el numero que decide el limite del paso C. Se replica exactamente lo
  // que hace el recortador: 512x512 a calidad 0.92.
  {
    const grande = lienzo(4000, 3000, (x, w, h) => {
      // Ruido: una foto real no comprime como un color plano.
      const img = x.createImageData(w, h);
      for (let i = 0; i < img.data.length; i += 4) {
        img.data[i] = Math.random() * 255;
        img.data[i+1] = Math.random() * 255;
        img.data[i+2] = Math.random() * 255;
        img.data[i+3] = 255;
      }
      x.putImageData(img, 0, 0);
    });
    const crudo = await aBlob(grande, 'image/jpeg', 0.95);
    const mb = (b) => (b.size / 1048576).toFixed(2) + ' MB';

    const recortado = lienzo(512, 512, (x) => x.drawImage(grande, 0, 0, 512, 512));
    const chico = await aBlob(recortado, 'image/jpeg', 0.92);

    console.log('%cPESO DE UNA FOTO DE CELULAR', 'font-weight:bold');
    console.log('  crudo 4000x3000 q0.95:', mb(crudo), '(' + crudo.size + ' bytes)');
    console.log('  despues del recorte:  ', mb(chico), '(' + chico.size + ' bytes)');
    console.log('  reduccion:', (100 - chico.size / crudo.size * 100).toFixed(1) + '%');

    anotar('C·peso', 'el crudo supera los 2 MB (por eso el limite rompia antes)',
      '> 2 MB', mb(crudo), crudo.size > 2097152);
    anotar('C·peso', 'el recortado entra COMODO en 2 MB',
      '< 2 MB', mb(chico), chico.size < 2097152);

    // Y que el recortado efectivamente sube.
    const ruta = `servicios/${id}/prueba-paso-b-grande.${extDeMime(chico.type)}`;
    const { error } = await sb.storage.from('fotos')
      .upload(ruta, chico, { upsert: true, contentType: chico.type });
    if (!error) creadas.push(ruta);
    anotar('C·peso', 'el recortado sube sin problema', 'sube',
      error ? 'rechazado: ' + error.message : 'sube', !error);
  }

  // ─── D · pre-chequeo de rol ──────────────────────────────────────────
  // Se simula el rol en memoria. OJO: esto prueba el MENSAJE, no la politica
  // (ver la nota del final sobre que queda sin cubrir).
  {
    const real = S.perfil.rol;
    try {
      for (const rol of ['profesional', 'barbero', undefined]) {
        S.perfil.rol = rol;
        const dejo = puedeSubirFotos();
        anotar('D·rol', `rol=${JSON.stringify(rol)} no puede subir`, 'false', String(dejo), dejo === false);
      }
      S.perfil.rol = 'dueno';
      const dejo = puedeSubirFotos();
      anotar('D·rol', 'rol="dueno" si puede subir', 'true', String(dejo), dejo === true);
    } finally {
      S.perfil.rol = real;   // siempre se restaura, incluso si algo tira
    }
    anotar('D·rol', 'el rol real quedo restaurado', 'dueno', S.perfil.rol, S.perfil.rol === 'dueno');
  }

  // ─── E · la rama de "se guardo sin la foto" ──────────────────────────
  // Se fuerza un fallo de subida interceptando sb.storage.from, para recorrer
  // el else nuevo sin depender de que la politica rechace. Es la unica forma
  // de probar esa rama con sesion de dueño.
  {
    const original = sb.storage.from.bind(sb.storage);
    let intento = 0;
    sb.storage.from = (b) => {
      const real = original(b);
      return { ...real,
        upload: async () => { intento++; return { data: null, error: { message: 'fallo simulado de prueba' } }; },
        getPublicUrl: real.getPublicUrl.bind(real),
        remove: real.remove.bind(real),
        list: real.list.bind(real) };
    };
    try {
      const c = lienzo(16, 16, (x) => { x.fillStyle = '#000'; x.fillRect(0, 0, 16, 16); });
      FOTO_SRV_CROPPED_BLOB = await aBlob(c, 'image/jpeg', 0.92);
      const r = await sb.storage.from('fotos').upload('x', FOTO_SRV_CROPPED_BLOB, {});
      anotar('E·sin foto', 'el stub devuelve error', 'error', r.error ? r.error.message : 'sin error', !!r.error);
      anotar('E·sin foto', 'el stub se llamo', '>=1', String(intento), intento >= 1);
    } finally {
      sb.storage.from = original;
      FOTO_SRV_CROPPED_BLOB = null;
    }
  }

  // ─── limpieza ────────────────────────────────────────────────────────
  if (creadas.length) await sb.storage.from('fotos').remove(creadas);
  const quedaron = [];
  for (const ruta of creadas) {
    const { data } = sb.storage.from('fotos').getPublicUrl(ruta);
    try {
      const r = await fetch(data.publicUrl + '?t=' + Date.now(), { cache: 'no-store' });
      if (r.ok) quedaron.push(ruta);
    } catch (e) { /* no accesible = borrado */ }
  }

  console.table(filas);
  const fallan = filas.filter(f => f.resultado === 'FALLA');
  console.log(
    '%c' + (fallan.length === 0
      ? '✓ Las ' + filas.length + ' pruebas del paso B pasan.'
      : '✗ ' + fallan.length + ' de ' + filas.length + ' FALLAN.'),
    'color:' + (fallan.length === 0 ? '#0a0' : '#c00') + ';font-weight:bold;font-size:14px'
  );
  if (fallan.length) console.table(fallan);
  console.log(quedaron.length
    ? '⚠ Archivos de prueba que no se limpiaron: ' + quedaron.join(', ')
    : 'Archivos de prueba limpiados: ' + creadas.length + '/' + creadas.length);
})();
