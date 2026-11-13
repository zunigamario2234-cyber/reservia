// Fotos de cortes (Reservia). Lo usan mi-agenda.html (profesional), app.html (dueño)
// y club.html (cliente). Ver migration_fotos_cortes.sql.
//
// · comprimir(): achica la foto en el navegador (lado mayor 1280 px, JPEG) hasta
//   ~300 KB, para no llenar el almacenamiento. El bucket rechaza más de 1 MB.
// · montar(): panel completo dentro de una cita: fotos de ESTA cita (máx. 2,
//   agregar/borrar) y cortes anteriores del mismo cliente (para saber qué se hizo).
// · abrirVisor(): foto grande con botón Descargar (también lo usa el Club).
(function () {
  const MAX_LADO = 1280, MAX_BYTES = 300 * 1024, MAX_FOTOS = 2;

  function css() {
    if (document.getElementById('fc-css')) return;
    const s = document.createElement('style'); s.id = 'fc-css';
    s.textContent = `
.fc-panel{margin-top:10px;padding:10px;border-radius:10px;background:var(--bg2,rgba(127,127,127,.12));font-size:13px}
.fc-tit{font-weight:600;margin:0 0 8px;font-size:12px;opacity:.85}
.fc-fila{display:flex;flex-wrap:wrap;gap:8px;align-items:flex-start}
.fc-th{position:relative;width:84px}
.fc-th img{width:84px;height:84px;object-fit:cover;border-radius:8px;display:block;cursor:pointer;background:rgba(127,127,127,.25)}
.fc-th small{display:block;font-size:10px;line-height:1.3;margin-top:3px;opacity:.75}
.fc-x{position:absolute;top:3px;right:3px;width:22px;height:22px;border-radius:50%;border:0;background:rgba(0,0,0,.65);color:#fff;font-size:13px;line-height:22px;padding:0;cursor:pointer}
.fc-add{width:84px;height:84px;border-radius:8px;border:1.5px dashed currentColor;opacity:.6;background:none;color:inherit;font-size:12px;cursor:pointer;display:flex;flex-direction:column;align-items:center;justify-content:center;gap:2px}
.fc-msg{font-size:12px;margin-top:6px;opacity:.85}
.fc-sep{height:10px}
.fc-visor{position:fixed;inset:0;z-index:99999;background:rgba(0,0,0,.92);display:flex;flex-direction:column;align-items:center;justify-content:center;gap:12px;padding:16px}
.fc-visor img{max-width:100%;max-height:75vh;border-radius:10px}
.fc-visor .fc-bar{display:flex;gap:10px}
.fc-visor button{padding:10px 16px;border-radius:10px;border:0;font-size:14px;cursor:pointer;background:#fff;color:#111}
.fc-visor .fc-pie{color:#ddd;font-size:13px;text-align:center}
`;
    document.head.appendChild(s);
  }

  async function cargarImagen(file) {
    try { return await createImageBitmap(file, { imageOrientation: 'from-image' }); }
    catch (e) {
      return await new Promise((ok, no) => {
        const i = new Image();
        i.onload = () => ok(i);
        i.onerror = () => no(new Error('No pudimos leer esa imagen. Prueba con otra foto.'));
        i.src = URL.createObjectURL(file);
      });
    }
  }

  async function comprimir(file) {
    const img = await cargarImagen(file);
    const w0 = img.width || img.naturalWidth, h0 = img.height || img.naturalHeight;
    let escala = Math.min(1, MAX_LADO / Math.max(w0, h0));
    let blob = null;
    for (let paso = 0; paso < 4; paso++) {
      const c = document.createElement('canvas');
      c.width = Math.max(1, Math.round(w0 * escala)); c.height = Math.max(1, Math.round(h0 * escala));
      const ctx = c.getContext('2d');
      ctx.fillStyle = '#fff'; ctx.fillRect(0, 0, c.width, c.height);
      ctx.drawImage(img, 0, 0, c.width, c.height);
      for (let q = 0.74; q >= 0.5; q -= 0.08) {
        blob = await new Promise(r => c.toBlob(r, 'image/jpeg', q));
        if (blob && blob.size <= MAX_BYTES) return blob;
      }
      escala *= 0.8;
    }
    if (!blob) throw new Error('No pudimos procesar esa foto.');
    return blob;
  }

  function uuid() {
    return (crypto.randomUUID ? crypto.randomUUID() : String(Date.now()) + Math.random().toString(16).slice(2));
  }

  async function subir(sb, tipo, id, barberiaId, file) {
    const blob = await comprimir(file);
    const path = barberiaId + '/' + uuid() + '.jpg';
    const up = await sb.storage.from('cortes').upload(path, blob, { contentType: 'image/jpeg' });
    if (up.error) throw new Error('No se pudo subir la foto. Revisa tu conexión.');
    const url = sb.storage.from('cortes').getPublicUrl(path).data.publicUrl;
    const { error } = await sb.rpc('agenda_foto_agregar', { p_tipo: tipo, p_id: id, p_path: path, p_url: url });
    if (error) { await sb.storage.from('cortes').remove([path]).catch(() => {}); throw new Error(error.message); }
    return blob.size;
  }

  async function eliminar(sb, fotoId) {
    const { data, error } = await sb.rpc('agenda_foto_eliminar', { p_foto_id: fotoId });
    if (error) throw new Error(error.message);
    if (data) await sb.storage.from('cortes').remove([data]).catch(() => {});
  }

  async function descargar(url, nombre) {
    try {
      const r = await fetch(url); const b = await r.blob();
      const a = document.createElement('a'); a.href = URL.createObjectURL(b); a.download = nombre || 'corte.jpg';
      document.body.appendChild(a); a.click(); a.remove();
      setTimeout(() => URL.revokeObjectURL(a.href), 4000);
    } catch (e) { window.open(url, '_blank'); }
  }

  function abrirVisor(url, pie, nombreArchivo) {
    css();
    const v = document.createElement('div'); v.className = 'fc-visor';
    const img = document.createElement('img'); img.src = url; img.alt = 'Foto del corte';
    const p = document.createElement('div'); p.className = 'fc-pie'; p.textContent = pie || '';
    const bar = document.createElement('div'); bar.className = 'fc-bar';
    const d = document.createElement('button'); d.textContent = '⬇ Descargar'; d.onclick = () => descargar(url, nombreArchivo);
    const c = document.createElement('button'); c.textContent = 'Cerrar'; c.onclick = () => v.remove();
    bar.append(d, c); v.append(img, p, bar);
    v.addEventListener('click', e => { if (e.target === v) v.remove(); });
    document.body.appendChild(v);
  }

  const MESES = ['ene', 'feb', 'mar', 'abr', 'may', 'jun', 'jul', 'ago', 'sep', 'oct', 'nov', 'dic'];
  function fechaCorta(f) {
    const p = String(f || '').split('-'); if (p.length < 3) return String(f || '');
    return Number(p[2]) + ' ' + MESES[Number(p[1]) - 1] + ' ' + p[0];
  }
  function pie(f) {
    return fechaCorta(f.fecha) + (f.servicio ? ' · ' + f.servicio : '') + (f.barbero_nombre ? ' · ' + f.barbero_nombre : '');
  }

  function miniatura(f, onDel) {
    const d = document.createElement('div'); d.className = 'fc-th';
    const i = document.createElement('img'); i.src = f.url; i.loading = 'lazy'; i.alt = 'Corte';
    i.onclick = () => abrirVisor(f.url, pie(f), 'corte-' + f.fecha + '.jpg');
    d.appendChild(i);
    if (onDel) { const x = document.createElement('button'); x.type = 'button'; x.className = 'fc-x'; x.textContent = '×'; x.title = 'Borrar foto'; x.onclick = onDel; d.appendChild(x); }
    const s = document.createElement('small'); s.textContent = onDel ? '' : fechaCorta(f.fecha) + (f.barbero_nombre ? ' · ' + f.barbero_nombre : '');
    if (!onDel) d.appendChild(s);
    return d;
  }

  // opts: { sb, tipo:'reserva'|'visita', id, barberiaId }
  async function montar(el, opts) {
    css();
    el.innerHTML = '';
    el.classList.add('fc-panel');
    const msg = document.createElement('div'); msg.className = 'fc-msg';
    const render = async () => {
      el.innerHTML = '';
      const { data, error } = await opts.sb.rpc('agenda_fotos_cita', { p_tipo: opts.tipo, p_id: opts.id });
      if (error) { el.textContent = 'No se pudieron cargar las fotos: ' + error.message; return; }
      const actuales = (data || []).filter(f => f.es_actual), previas = (data || []).filter(f => !f.es_actual);
      const t1 = document.createElement('div'); t1.className = 'fc-tit'; t1.textContent = '📷 Fotos de este corte (' + actuales.length + '/' + MAX_FOTOS + ')';
      const fila = document.createElement('div'); fila.className = 'fc-fila';
      actuales.forEach(f => fila.appendChild(miniatura(f, async () => {
        msg.textContent = 'Borrando…';
        try { await eliminar(opts.sb, f.id); await render(); } catch (e) { msg.textContent = e.message; }
      })));
      if (actuales.length < MAX_FOTOS) {
        const inp = document.createElement('input'); inp.type = 'file'; inp.accept = 'image/*'; inp.style.display = 'none';
        const add = document.createElement('button'); add.type = 'button'; add.className = 'fc-add';
        add.innerHTML = '<span style="font-size:22px">📷</span><span>Agregar foto</span>';
        add.onclick = () => inp.click();
        inp.onchange = async () => {
          const file = inp.files && inp.files[0]; if (!file) return;
          add.disabled = true; msg.textContent = 'Subiendo foto…';
          try { await subir(opts.sb, opts.tipo, opts.id, opts.barberiaId, file); await render(); }
          catch (e) { add.disabled = false; msg.textContent = e.message; }
        };
        fila.append(add, inp);
      }
      el.append(t1, fila, msg);
      if (previas.length) {
        const sep = document.createElement('div'); sep.className = 'fc-sep';
        const t2 = document.createElement('div'); t2.className = 'fc-tit'; t2.textContent = '✂️ Cortes anteriores de este cliente';
        const f2 = document.createElement('div'); f2.className = 'fc-fila';
        previas.forEach(f => f2.appendChild(miniatura(f, null)));
        el.append(sep, t2, f2);
      }
    };
    await render();
  }

  window.FotosCortes = { comprimir, subir, eliminar, descargar, abrirVisor, montar, fechaCorta };
})();
