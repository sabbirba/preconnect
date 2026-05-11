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
