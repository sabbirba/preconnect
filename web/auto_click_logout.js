(function () {
  function waitFor(predicate, timeoutMs) {
    return new Promise(function (resolve) {
      var startedAt = Date.now();
      var timer = setInterval(function () {
        if (predicate()) {
          clearInterval(timer);
          resolve(true);
          return;
        }
        if (Date.now() - startedAt >= timeoutMs) {
          clearInterval(timer);
          resolve(false);
        }
      }, 100);
    });
  }

  function matchesLogout(element) {
    if (!element) return false;
    var text = ((element.textContent || '') + ' ' +
      (element.getAttribute('aria-label') || '') + ' ' +
      (element.getAttribute('title') || '')).trim().toLowerCase();
    return (
      text === 'logout' ||
      text.indexOf('logout') !== -1 ||
      text.indexOf('log out') !== -1 ||
      text.indexOf('sign out') !== -1
    );
  }

  function clickLogout() {
    var exactSelectors = [
      '#kc-logout',
      'input#kc-logout',
      'input[name="confirmLogout"]',
      'button#kc-logout',
      'button[name="confirmLogout"]',
    ];

    for (var i = 0; i < exactSelectors.length; i++) {
      var exact = document.querySelector(exactSelectors[i]);
      if (!exact) continue;
      exact.click();
      return true;
    }

    var selectors = [
      'button',
      'a',
      '[role="button"]',
      'input[type="submit"]',
    ];

    for (var i = 0; i < selectors.length; i++) {
      var nodes = document.querySelectorAll(selectors[i]);
      for (var j = 0; j < nodes.length; j++) {
        var element = nodes[j];
        if (!matchesLogout(element)) continue;
        element.click();
        return true;
      }
    }

    return false;
  }

  waitFor(clickLogout, 4000);
})();
