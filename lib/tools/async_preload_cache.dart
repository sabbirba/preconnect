class AsyncPreloadCache<T> {
  T? value;
  Future<T>? _inFlight;

  Future<T> get({
    required Future<T> Function() loader,
    bool forceRefresh = false,
  }) async {
    if (!forceRefresh) {
      final cached = value;
      if (cached != null) return cached;
      final active = _inFlight;
      if (active != null) return active;
    }

    final future = loader();
    _inFlight = future;
    try {
      final loaded = await future;
      value = loaded;
      return loaded;
    } finally {
      if (identical(_inFlight, future)) {
        _inFlight = null;
      }
    }
  }

  void clear() {
    value = null;
    _inFlight = null;
  }
}
