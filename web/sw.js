// Cache only a public offline notice. Auth, API responses, workouts, and provider
// credentials are never written to a service worker cache.
const NOTICE_CACHE = 'runtrack-offline-v1';
self.addEventListener('install', event => {
  event.waitUntil(caches.open(NOTICE_CACHE).then(cache => cache.add('offline.html')));
  self.skipWaiting();
});
self.addEventListener('activate', event => {
  event.waitUntil(Promise.all([
    caches.keys().then(keys => Promise.all(keys.filter(key => key !== NOTICE_CACHE)
      .map(key => caches.delete(key)))),
    self.clients.claim(),
  ]));
});
self.addEventListener('fetch', event => {
  if (event.request.mode === 'navigate' && new URL(event.request.url).origin === self.location.origin) {
    event.respondWith(fetch(event.request).catch(() => caches.match('offline.html')));
  }
});
