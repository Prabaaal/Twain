self.addEventListener('push', (event) => {
  const payload = event.data ? event.data.json() : {};
  const title = payload.title || 'HillsMeetSea';
  const options = {
    body: payload.body || 'New message',
    icon: payload.icon || '/icons/Icon-192.png',
    badge: payload.badge || '/icons/Icon-192.png',
    data: {
      url: payload.url || '/',
    },
  };

  event.waitUntil(self.registration.showNotification(title, options));
});

self.addEventListener('notificationclick', (event) => {
  event.notification.close();

  event.waitUntil((async () => {
    const rawUrl = (event.notification.data && event.notification.data.url) || '/';
    const targetUrl = typeof rawUrl === 'string' && rawUrl.startsWith('/') ? rawUrl : '/';
    const windows = await clients.matchAll({ type: 'window', includeUncontrolled: true });

    for (const client of windows) {
      if ('focus' in client) {
        client.navigate(targetUrl);
        return client.focus();
      }
    }

    if (clients.openWindow) {
      return clients.openWindow(targetUrl);
    }

    return undefined;
  })());
});
