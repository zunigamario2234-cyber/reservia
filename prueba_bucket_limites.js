// ═══════════════════════════════════════════════════════════════════════
// PRUEBAS DEL PASO C — límite de tamaño y tipos permitidos del bucket.
//
// Correr DESPUÉS de aplicar la migración del paso C, en la consola de
// app.html con la sesión del dueño de "ZZ prueba bucket" y el panel
// cargado. Corre al pegarlo. Aborta si el negocio no coincide.
//
// Las cuatro pruebas verifican, además del código de respuesta, que no
// quedó ningún archivo: un rechazo que igual escribe no es un rechazo.
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

  const LIMITE = 2097152;
  const filas = [];
  const creadas = [];

  const existe = async (ruta) => {
    const { data } = sb.storage.from('fotos').getPublicUrl(ruta);
    try {
      const r = await fetch(data.publicUrl + '?t=' + Date.now(), { cache: 'no-store' });
      return r.ok;
    } catch (e) { return false; }
  };

  // PNG real de 512x512, chico: el caso que DEBE pasar.
  const pngChico = await (async () => {
    const c = document.createElement('canvas');
    c.width = 512; c.height = 512;
    const x = c.getContext('2d');
    x.fillStyle = '#2957D6'; x.beginPath(); x.arc(256, 256, 200, 0, 7); x.fill();
    return new Promise(r => c.toBlob(r, 'image/png'));
  })();

  const probar = async (n, desde, ruta, blob, tipo, debePasar) => {
    const { error } = await sb.storage.from('fotos')
      .upload(ruta, blob, { upsert: true, contentType: tipo });
    const quedo = await existe(ruta);
    // Se agenda para limpiar si la subida salió bien O si el archivo existe
    // igual. Lo segundo no debería pasar nunca, pero si una política o un
    // límite fallan de forma rara, lo que importa es no dejar basura: mirar
    // solo el error dejaría el archivo ahí justo en el caso que falla.
    if (!error || quedo) creadas.push(ruta);
    const ok = debePasar ? (!error && quedo) : (!!error && !quedo);
    filas.push({
      '#': n,
      prueba: desde,
      bytes: blob.size,
      contentType: tipo,
      esperado: debePasar ? 'sube' : 'rechazado',
      obtenido: error ? 'rechazado: ' + error.message.slice(0, 48) : 'ACEPTADO',
      archivo: quedo ? (debePasar ? 'quedó ✓' : '⚠ QUEDÓ ' + ruta) : (debePasar ? '⚠ NO QUEDÓ' : 'no quedó nada'),
      resultado: ok ? 'PASA' : 'FALLA'
    });
  };

  // (a) PNG chico y válido → DEBE PASAR.
  // Es la prueba que importa en el otro sentido: si el límite o el whitelist
  // están mal puestos, esto falla y el dueño no puede subir nada.
  await probar('a', 'PNG de 512x512, tipo correcto', `logos/${id}/limite-a.png`,
    pngChico, 'image/png', true);

  // (b) Más de 2 MB con tipo correcto → rechazado POR TAMAÑO.
  // El tipo va bien a propósito, para que el único motivo sea el peso.
  await probar('b', 'archivo de 3 MB, tipo correcto', `logos/${id}/limite-b.png`,
    new Blob([new Uint8Array(3 * 1024 * 1024)], { type: 'image/png' }), 'image/png', false);

  // (c) SVG → rechazado POR TIPO. Chico a propósito, para que el peso no
  // sea el motivo. Es el caso que motivó todo: un SVG servido desde un
  // bucket público puede llevar scripts.
  await probar('c', 'SVG chico', `logos/${id}/limite-c.svg`,
    new Blob(['<svg xmlns="http://www.w3.org/2000/svg"/>'], { type: 'image/svg+xml' }),
    'image/svg+xml', false);

  // (d) Contenido VÁLIDO pero declarado como binario genérico → rechazado
  // por tipo. Prueba que el whitelist mira el encabezado declarado y no
  // adivina por el contenido.
  //
  // Los bytes del PNG se re-envuelven en un Blob cuyo PROPIO type también es
  // application/octet-stream, en vez de pasar pngChico (que es image/png) y
  // confiar en que la opción contentType gane. Así el tipo declarado es el
  // mismo por las dos vías y la prueba no depende de cuál de las dos usa
  // supabase-js por dentro.
  await probar('d', 'PNG válido declarado octet-stream', `logos/${id}/limite-d.png`,
    new Blob([pngChico], { type: 'application/octet-stream' }), 'application/octet-stream', false);

  // ─── limpieza ────────────────────────────────────────────────────────
  if (creadas.length) await sb.storage.from('fotos').remove(creadas);
  const quedaron = [];
  for (const r of creadas) if (await existe(r)) quedaron.push(r);

  console.table(filas);
  const fallan = filas.filter(f => f.resultado === 'FALLA');
  console.log(
    '%c' + (fallan.length === 0
      ? '✓ Las ' + filas.length + ' pruebas del límite pasan.'
      : '✗ ' + fallan.length + ' de ' + filas.length + ' FALLAN.'),
    'color:' + (fallan.length === 0 ? '#0a0' : '#c00') + ';font-weight:bold;font-size:14px'
  );
  if (fallan.length) console.table(fallan);
  console.log('límite configurado: ' + LIMITE + ' bytes (' + (LIMITE / 1048576) + ' MB)');
  console.log(quedaron.length
    ? '⚠ Archivos de prueba que no se limpiaron: ' + quedaron.join(', ')
    : 'Archivos de prueba limpiados: ' + creadas.length + '/' + creadas.length);

  // Y el canario sigue donde estaba.
  const vive = await existe(`logos/${id}/canario-prueba.png`);
  console.log('Canario: ' + (vive ? 'intacto ✓' : '⚠ NO ESTÁ'));
})();
