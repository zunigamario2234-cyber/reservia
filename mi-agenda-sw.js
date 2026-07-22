// Service worker mínimo — existe solo para que mi-agenda.html cumpla el
// criterio de instalabilidad de PWA (service worker registrado, con un
// listener de "fetch"). A propósito NO cachea absolutamente nada: ni la
// página, ni las llamadas a Supabase (login, mi_agenda_citas, comisiones,
// etc.). Cachear cualquiera de esas respuestas mostraría datos viejos de
// la agenda en vez de los reales — el listener de "fetch" de abajo deja
// pasar todo directo a la red, sin cache.match() ni cache.put() en ningún
// lado. No hay soporte offline: sin red, la página simplemente no carga,
// igual que antes de agregar el service worker.

self.addEventListener('install', () => {
  self.skipWaiting();
});

self.addEventListener('activate', (event) => {
  event.waitUntil(self.clients.claim());
});

self.addEventListener('fetch', () => {
  // No-op intencional: no se llama a event.respondWith(), así que el
  // navegador maneja cada request exactamente como si no hubiera service
  // worker (siempre red, nunca caché).
});
