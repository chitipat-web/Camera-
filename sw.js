// Service worker แบบเรียบง่าย: cache ไฟล์หลักเพื่อให้เปิดแอพแบบออฟไลน์ได้
const CACHE_NAME = 'motioncam-v3';
const ASSETS = ['.', 'index.html', 'style.css', 'app.js', 'manifest.json', 'icon.svg'];

self.addEventListener('install', (e) => {
  e.waitUntil(caches.open(CACHE_NAME).then((c) => c.addAll(ASSETS)));
  self.skipWaiting();
});

self.addEventListener('activate', (e) => {
  e.waitUntil(
    caches.keys().then((keys) =>
      Promise.all(keys.filter((k) => k !== CACHE_NAME).map((k) => caches.delete(k)))
    )
  );
  self.clients.claim();
});

self.addEventListener('fetch', (e) => {
  e.respondWith(
    caches.match(e.request).then((cached) => cached || fetch(e.request))
  );
});
