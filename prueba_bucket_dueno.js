// ═══════════════════════════════════════════════════════════════════════
// PRUEBAS DEL BUCKET `fotos` — lado del DUEÑO.
//
// Pegar en la consola de app.html con la sesión del dueño de
// "ZZ prueba bucket" y el panel ya cargado. Corre al pegarlo.
//
// Va envuelto en una función anónima: no declara nada global, así que se
// puede pegar más de una vez sin el error "Identifier has already been
// declared".
//
// ABORTA si el panel abierto no es el del negocio de prueba.
//
// Usa el cliente `sb` que ya creó la página, con la sesión que ya está en
// el navegador: ninguna credencial sale de ahí y este archivo no contiene
// ninguna.
//
// QUÉ TOCA: solo archivos `canario-prueba.png` dentro de la carpeta del
// negocio de prueba. Las pruebas contra "otra carpeta" usan un uuid
// inexistente y fijo, y se verifica después que no quedó nada.
// ═══════════════════════════════════════════════════════════════════════
(async () => {
  const ESPERADO = 'd75633ff-4f6a-4f32-b5b4-83b62ee80f24';
  const CANARIO = 'canario-prueba.png';

  // uuid válido pero inexistente. Prueba lo mismo que el de un negocio
  // real, porque la política compara contra auth_barberia_id() y cualquier
  // id distinto del propio toma el mismo camino — y así no hay forma de
  // ensuciar la carpeta de nadie.
  const AJENO = '00000000-0000-0000-0000-000000000bad';
  const OTRAS = ['portadas', 'profesionales', 'servicios', 'alianzas'];

  const id = window.S?.barberia?.id;
  if (!id) {
    console.error('✗ No hay negocio cargado. ¿Estás en app.html con el panel ya cargado?');
    return;
  }
  if (id !== ESPERADO) {
    console.error('✗ ABORTADO: no se corrió ni se escribió nada.');
    console.error('  Este panel es del negocio ' + id);
    console.error('  Esperaba ZZ prueba bucket (' + ESPERADO + ').');
    return;
  }

  const c = document.createElement('canvas');
  c.width = 1;
  c.height = 1;
  const blob = await new Promise(r => c.toBlob(r, 'image/png'));

  const subir = (ruta) => sb.storage.from('fotos')
    .upload(ruta, blob, { upsert: true, contentType: 'image/png' });

  // ¿El archivo existe de verdad? Por la URL pública, que no pasa por RLS:
  // así la comprobación no depende de las políticas que estamos probando.
  const existe = async (ruta) => {
    const { data } = sb.storage.from('fotos').getPublicUrl(ruta);
    try {
      const r = await fetch(data.publicUrl + '?t=' + Date.now(), { cache: 'no-store' });
      return r.ok;
    } catch (e) {
      return false;
    }
  };

  const filas = [];
  const anotar = (n, prueba, esperado, obtenido, ok, nota) =>
    filas.push({ '#': n, prueba, esperado, obtenido, resultado: ok ? 'PASA' : 'FALLA', nota: nota || '' });

  // ─── 6 · subir a su propia carpeta ───────────────────────────────────
  {
    const { error } = await subir(`logos/${id}/${CANARIO}`);
    anotar(6, 'subir a su propia carpeta (logos/)', 'funciona',
      error ? 'rechazado: ' + error.message : 'funciona', !error);
  }

  // ─── 7 · upsert sobre la misma ruta ──────────────────────────────────
  // Es la prueba de que la política UPDATE quedó bien: sin ella, el
  // segundo upsert sobre la misma ruta falla.
  {
    const { error } = await subir(`logos/${id}/${CANARIO}`);
    anotar(7, 'upsert sobre la misma ruta (INSERT + UPDATE)', 'funciona',
      error ? 'rechazado: ' + error.message : 'funciona', !error);
  }

  // ─── 6b · las otras cuatro carpetas propias ──────────────────────────
  // Verifica que el whitelist de la política cubre las cinco rutas reales.
  // Un typo ahí rompería una pantalla entera sin que se note hasta que un
  // dueño la use.
  for (const carpeta of OTRAS) {
    const { error } = await subir(`${carpeta}/${id}/${CANARIO}`);
    anotar('6·' + carpeta, `subir a ${carpeta}/ (carpeta propia)`, 'funciona',
      error ? 'rechazado: ' + error.message : 'funciona', !error);
  }

  // ─── 8 · carpeta de otro negocio ─────────────────────────────────────
  // La prueba fuerte de aislamiento: si la política está mal, esto CREA un
  // archivo, así que después se verifica que no quedó nada.
  {
    const ruta = `logos/${AJENO}/${CANARIO}`;
    const { error } = await subir(ruta);
    const quedo = await existe(ruta);
    anotar(8, 'subir a la carpeta de OTRO negocio', 'rechazado',
      error ? 'rechazado' : 'ACEPTADO', !!error && !quedo,
      quedo ? '⚠ QUEDÓ UN ARCHIVO EN ' + ruta : 'no quedó nada');
  }

  // ─── 9 · un nivel extra ──────────────────────────────────────────────
  // Prueba el array_length(storage.foldername(name),1) = 2.
  {
    const ruta = `logos/${id}/sub/${CANARIO}`;
    const { error } = await subir(ruta);
    const quedo = await existe(ruta);
    anotar(9, 'subir con un nivel extra (logos/{id}/sub/)', 'rechazado',
      error ? 'rechazado' : 'ACEPTADO', !!error && !quedo,
      quedo ? '⚠ QUEDÓ ' + ruta : 'no quedó nada');
  }

  // ─── 10 · path traversal ─────────────────────────────────────────────
  // Corresponde al `ext` sin sanitizar de guardarServicio/guardarAlianza:
  // un nombre con ../ agrega segmentos y la política lo rechaza aunque el
  // front todavía no esté arreglado.
  {
    const destino = `logos/${AJENO}/${CANARIO}`;
    const { error } = await subir(`logos/${id}/x.png/../../${destino}`);
    const quedo = await existe(destino);
    anotar(10, 'path traversal con ../ hacia otra carpeta', 'rechazado',
      error ? 'rechazado' : 'ACEPTADO', !!error && !quedo,
      quedo ? '⚠ ESCRIBIÓ EN LA CARPETA AJENA' : 'no quedó nada');
  }

  // ─── 11 · borrar lo propio ───────────────────────────────────────────
  // ⚠ remove() puede devolver {data:[], error:null} cuando RLS filtra la
  // fila: éxito aparente sin haber borrado nada. Por eso no se mira el
  // error, se verifica el archivo.
  {
    const ruta = `portadas/${id}/${CANARIO}`;
    const antes = await existe(ruta);
    const { error } = await sb.storage.from('fotos').remove([ruta]);
    const despues = await existe(ruta);
    anotar(11, 'borrar un archivo propio', 'desaparece',
      !antes ? 'no existía (prueba inválida)' : (despues ? 'sigue ahí' : 'desaparece'),
      antes && !despues, error ? 'error: ' + error.message : '');
  }

  // ─── 11b · borrar en la carpeta de otro ──────────────────────────────
  // PRUEBA DÉBIL, y queda dicho: esa carpeta está vacía, así que no
  // distingue "denegado" de "no había nada". El borrado ajeno de verdad lo
  // probó la #3 del script anónimo, que apunta al canario. El aislamiento
  // lo prueban la #8 y la #10, con la misma condición que usa DELETE.
  {
    const { error, data } = await sb.storage.from('fotos').remove([`logos/${AJENO}/logo.jpg`]);
    const borro = Array.isArray(data) && data.length > 0;
    anotar('11b', 'borrar en la carpeta de otro (prueba débil)', 'no borra nada',
      borro ? 'BORRÓ ALGO' : 'no borró nada', !borro,
      'débil: la carpeta está vacía por diseño' + (error ? ' · ' + error.message : ''));
  }

  // ─── 12 · listar lo propio ───────────────────────────────────────────
  {
    const { data, error } = await sb.storage.from('fotos').list(`logos/${id}`);
    anotar(12, 'listar su propia carpeta', 'funciona',
      error ? 'rechazado: ' + error.message : `${(data || []).length} archivo(s)`, !error);
  }

  // ─── limpieza ────────────────────────────────────────────────────────
  // Se borran las sondas de las otras cuatro carpetas. El canario de
  // logos/ SE DEJA: lo necesitan las pruebas anónimas, y es inerte
  // (ninguna fila lo referencia, así que no se muestra en ninguna
  // pantalla).
  const sondas = OTRAS.map(x => `${x}/${id}/${CANARIO}`);
  await sb.storage.from('fotos').remove(sondas);
  const quedaron = [];
  for (const r of sondas) if (await existe(r)) quedaron.push(r);

  console.table(filas);
  const fallan = filas.filter(f => f.resultado === 'FALLA');
  console.log(
    '%c' + (fallan.length === 0
      ? '✓ Las ' + filas.length + ' pruebas del dueño pasan.'
      : '✗ ' + fallan.length + ' de ' + filas.length + ' FALLAN.'),
    'color:' + (fallan.length === 0 ? '#0a0' : '#c00') + ';font-weight:bold;font-size:14px'
  );
  if (fallan.length) console.table(fallan);

  const vive = await existe(`logos/${id}/${CANARIO}`);
  console.log('Canario para las pruebas anónimas: ' + (vive ? 'intacto ✓' : '⚠ NO ESTÁ — vuelve a crearlo'));
  console.log(quedaron.length
    ? '⚠ Sondas que no se pudieron limpiar: ' + quedaron.join(', ')
    : 'Sondas limpiadas: ' + sondas.length + '/' + sondas.length);
})();
