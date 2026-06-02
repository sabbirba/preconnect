(function () {
  if (
    window.chrome &&
    chrome.runtime &&
    chrome.runtime.id &&
    'serviceWorker' in navigator
  ) {
    try {
      const sw = navigator.serviceWorker;
      sw.register = async () => null;
      sw.getRegistration = async () => null;
      sw.getRegistrations = async () => [];
    } catch (_) {}
  }

  window.flutterConfiguration = Object.assign(
    window.flutterConfiguration || {},
    {
      renderer: 'html',
      canvasKitBaseUrl: '',
      canvasKitForceCpuOnly: true,
      fontFallbackBaseUrl: '',
    }
  );

  const _origFetch = window.fetch;
  window.fetch = function (input) {
    const url = typeof input === 'string' ? input : (input && input.url) || '';
    if (url.includes('canvaskit')) {
      return Promise.reject(new TypeError('canvaskit blocked'));
    }
    return _origFetch.apply(this, arguments);
  };
})();
