// Crea el canario para las pruebas del bucket. Pegar en la consola de
// app.html con la sesión del dueño de "ZZ prueba bucket" abierta.
//
// Va envuelto en una función anónima a propósito: no declara nada global,
// así que se puede pegar más de una vez sin el error "Identifier has
// already been declared".
//
// Aborta si el panel abierto no es el del negocio de prueba.
(async () => {
  const ESPERADO = 'd75633ff-4f6a-4f32-b5b4-83b62ee80f24';

  const id = window.S?.barberia?.id;
  if (!id) {
    console.error('✗ No hay negocio cargado. ¿Estás en app.html con la sesión abierta y el panel ya cargado?');
    return;
  }
  if (id !== ESPERADO) {
    console.error('✗ ABORTADO: no se creó nada.');
    console.error('  Este panel es del negocio ' + id);
    console.error('  Esperaba ZZ prueba bucket (' + ESPERADO + ').');
    console.error('  Entra con la cuenta del negocio de prueba y vuelve a pegarlo.');
    return;
  }

  const ruta = `logos/${id}/canario-prueba.png`;

  const c = document.createElement('canvas');
  c.width = 1;
  c.height = 1;
  const blob = await new Promise(r => c.toBlob(r, 'image/png'));

  const { error } = await sb.storage.from('fotos')
    .upload(ruta, blob, { upsert: true, contentType: 'image/png' });
  if (error) {
    console.error('✗ No se pudo crear el canario:', error.message);
    return;
  }

  // Se verifica por la URL pública, que no pasa por RLS: así la
  // comprobación no depende de las políticas que vamos a probar.
  const { data } = sb.storage.from('fotos').getPublicUrl(ruta);
  const r = await fetch(data.publicUrl + '?t=' + Date.now(), { cache: 'no-store' });

  console.log(
    '%c' + (r.ok ? '✓ CANARIO CREADO Y VERIFICADO' : '⚠ Se subió pero no se pudo leer de vuelta'),
    'color:' + (r.ok ? '#0a0' : '#c80') + ';font-weight:bold;font-size:14px'
  );
  console.log('ruta:', ruta);
  console.log('bytes:', blob.size, '· lectura pública: HTTP', r.status);
  if (r.ok) console.log('Listo. Ahora sí se puede aplicar la migración.');
})();
