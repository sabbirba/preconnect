(function () {
  function removeLoader() {
    var loader = document.getElementById("loading-container");
    if (loader && !loader.classList.contains("fade-out")) {
      loader.classList.add("fade-out");
      setTimeout(function () {
        if (loader.parentNode) {
          loader.parentNode.removeChild(loader);
        }
      }, 400);
    }
  }
  window.addEventListener("flutter-first-frame", function () {
    removeLoader();
  });
  setTimeout(function () {
    removeLoader();
  }, 15000);
})();
