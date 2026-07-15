(function () {
  function clean() {
    if (window.location.hash) {
      window.history.replaceState(null, null, window.location.pathname + window.location.search);
    }
  }
  clean();
  window.addEventListener('hashchange', clean);
  var push = window.history.pushState;
  var replace = window.history.replaceState;
  window.history.pushState = function (state, title, url) {
    if (url && url.indexOf('#') !== -1) {
      url = url.split('#')[0];
    }
    return push.apply(this, [state, title, url]);
  };
  window.history.replaceState = function (state, title, url) {
    if (url && url.indexOf('#') !== -1) {
      url = url.split('#')[0];
    }
    return replace.apply(this, [state, title, url]);
  };
})();
