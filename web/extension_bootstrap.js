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
})();
