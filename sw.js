/* Service Worker — offline cache for the portfolio (PWA) */
const CACHE = 'mm-portfolio-v2';
const ASSETS = [
  './',
  'index.html',
  'manifest.json',
  'icon-192.png',
  'icon-512.png',
  'favicon.ico',
  'og-image.jpg',
  'profile.jpg',
  'Mena-Medhat-CV.pdf'
];

self.addEventListener('install', function(e){
  e.waitUntil(
    Promise.all(ASSETS.map(function(u){
      return caches.open(CACHE).then(function(c){ return c.add(u).catch(function(){}); });
    })).then(function(){ return self.skipWaiting(); })
  );
});

self.addEventListener('activate', function(e){
  e.waitUntil(
    caches.keys().then(function(keys){
      return Promise.all(keys.filter(function(k){ return k !== CACHE; }).map(function(k){ return caches.delete(k); }));
    }).then(function(){ return self.clients.claim(); })
  );
});

self.addEventListener('fetch', function(e){
  if(e.request.method !== 'GET') return;
  e.respondWith(
    caches.match(e.request).then(function(cached){
      var fetched = fetch(e.request).then(function(res){
        if(res && res.status === 200 && res.type === 'basic'){
          var clone = res.clone();
          caches.open(CACHE).then(function(c){ c.put(e.request, clone); });
        }
        return res;
      }).catch(function(){ return cached; });
      return cached || fetched;
    })
  );
});
