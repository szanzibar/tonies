const CACHE_NAME = 'tonie-v1';

self.addEventListener('install', () => self.skipWaiting());

self.addEventListener('activate', event => {
  event.waitUntil(
    caches.keys().then(keys => Promise.all(keys.filter(k => k !== CACHE_NAME).map(k => caches.delete(k)))),
  );
  self.clients.claim();
});

self.addEventListener('fetch', event => {
  const { request } = event;
  const url = new URL(request.url);

  // Only handle GET requests on the same origin
  if (request.method !== 'GET' || url.origin !== self.location.origin) return;

  // Skip LiveView WebSocket and reload socket paths
  if (url.pathname.startsWith('/live') || url.pathname.startsWith('/phoenix')) return;

  // Cache-first for versioned static assets and images
  if (url.pathname.startsWith('/assets/') || url.pathname.startsWith('/images/') || url.pathname === '/favicon.ico') {
    event.respondWith(
      caches.match(request).then(
        cached =>
          cached ||
          fetch(request).then(response => {
            if (response.ok) {
              caches.open(CACHE_NAME).then(cache => cache.put(request, response.clone()));
            }
            return response;
          }),
      ),
    );
    return;
  }

  // Network-first for HTML navigation — fall back to cached version offline
  if (request.mode === 'navigate') {
    event.respondWith(
      fetch(request)
        .then(response => {
          if (response.ok) {
            caches.open(CACHE_NAME).then(cache => cache.put(request, response.clone()));
          }
          return response;
        })
        .catch(() => caches.match(request).then(cached => cached || caches.match('/'))),
    );
  }
});
