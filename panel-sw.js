// Service worker del panel (app.html). Solo sirve para los avisos push de
// reservas nuevas. A propósito NO cachea nada: el panel siempre muestra datos
// frescos de la red, igual que antes.
self.addEventListener('install', () => self.skipWaiting());
self.addEventListener('activate', (e) => e.waitUntil(self.clients.claim()));
self.addEventListener('fetch', () => {});

self.addEventListener('push', (event) => {
  let d = {};
  try { d = event.data ? event.data.json() : {}; } catch (e) {}
  // Si el panel está abierto y a la vista, ya suena y muestra su propio aviso:
  // no se duplica con una notificación del sistema.
  event.waitUntil(
    self.clients.matchAll({ type: 'window', includeUncontrolled: true }).then((list) => {
      if (list.some((c) => c.visibilityState === 'visible')) return;
      return self.registration.showNotification(d.title || 'Nueva reserva', {
      body: d.body || '',
      icon: '/panel-icon-192.png',
      badge: '/panel-icon-192.png',
      tag: d.tag || 'reserva',
      renotify: true,
      requireInteraction: true,
      data: { url: d.url || '/app.html' },
      });
    })
  );
});

self.addEventListener('notificationclick', (event) => {
  event.notification.close();
  const url = (event.notification.data && event.notification.data.url) || '/app.html';
  event.waitUntil(
    self.clients.matchAll({ type: 'window', includeUncontrolled: true }).then((list) => {
      for (const c of list) { if (c.url.indexOf('/app.html') !== -1 && 'focus' in c) return c.focus(); }
      return self.clients.openWindow(url);
    })
  );
});
