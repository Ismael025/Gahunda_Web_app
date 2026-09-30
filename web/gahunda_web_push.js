(function () {
  'use strict';

  const deviceKey = 'gahunda_web_push_device_id';

  function base64UrlToBytes(value) {
    const padding = '='.repeat((4 - (value.length % 4)) % 4);
    const normalized = (value + padding).replace(/-/g, '+').replace(/_/g, '/');
    const binary = atob(normalized);
    return Uint8Array.from(binary, (character) => character.charCodeAt(0));
  }

  function deviceId() {
    let value = localStorage.getItem(deviceKey);
    if (!value) {
      value = self.crypto && self.crypto.randomUUID
        ? self.crypto.randomUUID()
        : `web-${Date.now()}-${Math.random().toString(16).slice(2)}`;
      localStorage.setItem(deviceKey, value);
    }
    return value;
  }

  window.gahundaSubscribeForPush = async function (vapidPublicKey) {
    if (!('serviceWorker' in navigator) || !('PushManager' in window)) {
      throw new Error('This browser does not support background Web Push.');
    }
    if (Notification.permission !== 'granted') {
      throw new Error('Notification permission must be granted first.');
    }

    const registration = await navigator.serviceWorker.ready;
    let subscription = await registration.pushManager.getSubscription();
    if (!subscription) {
      subscription = await registration.pushManager.subscribe({
        userVisibleOnly: true,
        applicationServerKey: base64UrlToBytes(vapidPublicKey),
      });
    }

    const json = subscription.toJSON();
    if (!json.endpoint || !json.keys || !json.keys.p256dh || !json.keys.auth) {
      throw new Error('The browser returned an incomplete push subscription.');
    }
    return JSON.stringify({
      device_id: deviceId(),
      endpoint: json.endpoint,
      p256dh: json.keys.p256dh,
      auth: json.keys.auth,
    });
  };

  window.gahundaUnsubscribeFromPush = async function () {
    if (!('serviceWorker' in navigator)) return false;
    const registration = await navigator.serviceWorker.ready;
    const subscription = await registration.pushManager.getSubscription();
    return subscription ? subscription.unsubscribe() : false;
  };
})();
