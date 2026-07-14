import 'dart:async';
import 'package:flutter/foundation.dart';

class PreloadCache<T> {
  T? value;
  Future<T>? inFlight;

  Future<T> load({
    required bool forceRefresh,
    required Future<T> Function() fetch,
    void Function()? onUpdate,
  }) async {
    if (!forceRefresh && value != null) {
      if (inFlight == null) {
        final future = fetch();
        inFlight = future;
        unawaited(
          future
              .then((loaded) {
                final changed = value != loaded;
                value = loaded;
                if (changed && onUpdate != null) {
                  onUpdate();
                }
              })
              .catchError((_) {})
              .whenComplete(() {
                inFlight = null;
              }),
        );
      }
      return value as T;
    }
    if (!forceRefresh && inFlight != null) return inFlight!;

    final future = fetch();
    inFlight = future;
    try {
      final loaded = await future;
      final changed = value != loaded;
      value = loaded;
      if (changed && onUpdate != null) {
        onUpdate();
      }
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

class CachedPageController<T> extends ChangeNotifier {
  CachedPageController(this._fetch);

  final Future<T> Function({bool forceRefresh}) _fetch;
  final PreloadCache<T> _cache = PreloadCache<T>();

  T? get value => _cache.value;
  set value(T? newVal) {
    if (_cache.value != newVal) {
      _cache.value = newVal;
      notifyListeners();
    }
  }

  Future<T>? get inFlight => _cache.inFlight;
  set inFlight(Future<T>? newInFlight) => _cache.inFlight = newInFlight;

  Future<T> load({bool forceRefresh = false}) {
    return _cache.load(
      forceRefresh: forceRefresh,
      fetch: () => _fetch(forceRefresh: forceRefresh),
      onUpdate: () => notifyListeners(),
    );
  }

  void clear() {
    _cache.value = null;
    _cache.inFlight = null;
    notifyListeners();
  }
}
