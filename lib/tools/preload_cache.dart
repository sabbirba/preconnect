class PreloadCache<T> {
  T? value;
  Future<T>? inFlight;

  Future<T> load({
    required bool forceRefresh,
    required Future<T> Function() fetch,
  }) async {
    if (!forceRefresh && value != null) return value as T;
    if (!forceRefresh && inFlight != null) return inFlight!;

    final future = fetch();
    inFlight = future;
    try {
      final loaded = await future;
      value = loaded;
      return loaded;
    } finally {
      if (identical(inFlight, future)) {
        inFlight = null;
      }
    }
  }

  Future<void> seed(Future<T> Function() fetch) async {
    value = await fetch();
  }
}

class CachedPageController<T> {
  CachedPageController(this._fetch);

  final Future<T> Function({bool forceRefresh}) _fetch;
  final PreloadCache<T> _cache = PreloadCache<T>();

  T? get value => _cache.value;
  set value(T? newVal) => _cache.value = newVal;

  Future<T>? get inFlight => _cache.inFlight;
  set inFlight(Future<T>? newInFlight) => _cache.inFlight = newInFlight;

  Future<T> load({bool forceRefresh = false}) {
    return _cache.load(
      forceRefresh: forceRefresh,
      fetch: () => _fetch(forceRefresh: forceRefresh),
    );
  }

  void clear() {
    _cache.value = null;
    _cache.inFlight = null;
  }
}
