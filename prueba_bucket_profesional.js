// ═══════════════════════════════════════════════════════════════════════
// PRUEBA DEL BUCKET — sesión de PROFESIONAL.
//
// Cubre el único hueco que quedaba: que la política rechace de verdad a un
// rol que no es dueño. Simular S.perfil.rol en la consola NO prueba esto,
// porque el JWT sigue siendo el del dueño y auth_rol() en la base sigue
// devolviendo 'dueno'. Esto necesita una sesión real.
//
// CÓMO SE CORRE
// Con la sesión de la cuenta de profesional de "ZZ prueba bucket" abierta,
// en app.html o en mi-agenda.html (las dos definen `sb`). Pegar y Enter.
//
// El rol y el negocio se leen de la BASE, no de una variable del navegador:
// así la prueba no se puede engañar desde la consola.
//
// ABORTA si el negocio no es ZZ prueba bucket, o si el rol ES 'dueno'.
//
// QUÉ TOCA: nada, si la política está bien. Intenta escribir
// `canario-profesional.png` en las cinco carpetas del negocio de prueba y
// después verifica por URL pública que no quedó ninguno.
// ═══════════════════════════════════════════════════════════════════════
(async () => {
  const ESPERADO = 'd75633ff-4f6a-4f32-b5b4-83b62ee80f24';
  const ARCHIVO = 'canario-profesional.png';
  const CARPETAS = ['logos', 'portadas', 'profesionales', 'servicios', 'alianzas'];

  if (typeof sb === 'undefined') {
    console.error('✗ No encuentro el cliente `sb`. Abre app.html o mi-agenda.html con la sesión iniciada.');
    return;
  }

  const { data: sesion } = await sb.auth.getUser();
  const uid = sesion?.user?.id;
  if (!uid) { console.error('✗ No hay sesión iniciada.'); return; }

  // El rol y el negocio salen de perfiles, que es lo que lee auth_rol() y
  // auth_barberia_id() del lado del servidor.
  const { data: perfil, error: ePerfil } = await sb.from('perfiles')
    .select('barberia_id,rol,nombre').eq('id', uid).single();
  if (ePerfil || !perfil) {
    console.error('✗ No pude leer tu perfil:', ePerfil?.message || 'sin datos');
    return;
  }

  console.log('sesión de:', perfil.nombre, '· rol:', perfil.rol, '· negocio:', perfil.barberia_id);

  if (perfil.barberia_id !== ESPERADO) {
    console.error('✗ ABORTADO: no se escribió nada.');
    console.error('  Esta cuenta pertenece al negocio ' + perfil.barberia_id);
    console.error('  Esperaba ZZ prueba bucket (' + ESPERADO + ').');
    return;
  }
  if (perfil.rol === 'dueno') {
    console.error('✗ ABORTADO: no se escribió nada.');
    console.error('  Esta cuenta tiene rol "dueno". Esta prueba necesita la cuenta de PROFESIONAL.');
    console.error('  Con el dueño se corre prueba_bucket_dueno.js, que es la otra mitad.');
    return;
  }

  const c = document.createElement('canvas');
  c.width = 1; c.height = 1;
  const blob = await new Promise(r => c.toBlob(r, 'image/png'));

  const existe = async (ruta) => {
    const { data } = sb.storage.from('fotos').getPublicUrl(ruta);
    try {
      const r = await fetch(data.publicUrl + '?t=' + Date.now(), { cache: 'no-store' });
      return r.ok;
    } catch (e) { return false; }
  };

  const filas = [];

  // ─── las cinco carpetas propias: todas deben rechazar ────────────────
  // Son carpetas de SU PROPIO negocio: la única condición que falla es
  // auth_rol() = 'dueno'. Eso es exactamente lo que queremos aislar.
  for (const carpeta of CARPETAS) {
    const ruta = `${carpeta}/${perfil.barberia_id}/${ARCHIVO}`;
    const { error } = await sb.storage.from('fotos')
      .upload(ruta, blob, { upsert: true, contentType: 'image/png' });
    const quedo = await existe(ruta);
    filas.push({
      prueba: `subir a ${carpeta}/ de su propio negocio`,
      esperado: 'rechazado',
      obtenido: error ? 'rechazado: ' + error.message.slice(0, 40) : 'ACEPTADO',
      archivo: quedo ? '⚠ QUEDÓ ' + ruta : 'no quedó nada',
      resultado: (!!error && !quedo) ? 'PASA' : 'FALLA'
    });
  }

  // ─── borrar algo del negocio: también debe rechazar ──────────────────
  // Apunta al canario del dueño, que SÍ existe: así distingue de verdad
  // "denegado" de "no había nada". Si la política fallara, se vería porque
  // el canario desaparece.
  {
    const ruta = `logos/${perfil.barberia_id}/canario-prueba.png`;
    const habia = await existe(ruta);
    await sb.storage.from('fotos').remove([ruta]);
    const sigue = await existe(ruta);
    filas.push({
      prueba: 'borrar el canario del dueño',
      esperado: 'no lo borra',
      obtenido: !habia ? 'el canario no existía (prueba inválida)' : (sigue ? 'no lo borró' : 'LO BORRÓ'),
      archivo: habia && sigue ? 'canario intacto' : (habia ? '⚠ CANARIO PERDIDO' : 'crear el canario primero'),
      resultado: (habia && sigue) ? 'PASA' : 'FALLA'
    });
  }

  // ─── listar el negocio: no debería ver nada ──────────────────────────
  // fotos_select_propia compara [2] con auth_barberia_id(), que para este
  // profesional ES su negocio — así que acá listar SÍ puede funcionar. No es
  // un fallo de seguridad: la lectura de imágenes es pública de todos modos.
  // Se anota como informativo, no como PASA/FALLA.
  {
    const { data, error } = await sb.storage.from('fotos').list(`logos/${perfil.barberia_id}`);
    console.log('informativo · listar logos/ de su negocio:',
      error ? 'rechazado: ' + error.message : `${(data || []).length} archivo(s) visibles`);
    console.log('  (no es un fallo: las imágenes del bucket son de lectura pública por diseño)');
  }

  // ─── el pre-chequeo de la UI, si estamos en app.html ─────────────────
  if (typeof puedeSubirFotos === 'function') {
    const dejo = puedeSubirFotos();
    filas.push({
      prueba: 'pre-chequeo de la UI (puedeSubirFotos)',
      esperado: 'false + aviso naranja',
      obtenido: String(dejo),
      archivo: 'debería haber salido el aviso abajo a la derecha',
      resultado: dejo === false ? 'PASA' : 'FALLA'
    });
  } else {
    console.log('informativo · puedeSubirFotos no existe acá: estás en mi-agenda.html.');
    console.log('  Para probar el aviso de la UI hay que correr esto en app.html.');
  }

  console.table(filas);
  const fallan = filas.filter(f => f.resultado === 'FALLA');
  console.log(
    '%c' + (fallan.length === 0
      ? '✓ Las ' + filas.length + ' pruebas del profesional pasan: no puede escribir ni borrar.'
      : '✗ ' + fallan.length + ' de ' + filas.length + ' FALLAN.'),
    'color:' + (fallan.length === 0 ? '#0a0' : '#c00') + ';font-weight:bold;font-size:14px'
  );
  if (fallan.length) {
    console.table(fallan);
    console.warn('Si alguna dice QUEDÓ o LO BORRÓ, la política no exige auth_rol() = dueno. Avisar antes de seguir.');
  }
})();
