{{flutter_js}}
{{flutter_build_config}}

const gahundaServiceWorkerVersion = '{{flutter_service_worker_version}}';

if (
  'serviceWorker' in navigator &&
  gahundaServiceWorkerVersion !== 'null' &&
  !gahundaServiceWorkerVersion.startsWith('{{')
) {
  navigator.serviceWorker.register(
    `gahunda_service_worker.js?v=${gahundaServiceWorkerVersion}`,
  );
}

_flutter.loader.load();
