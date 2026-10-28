class InFlight<K, V> {
  final Map<K, Future<V>> _running = <K, Future<V>>{};

  int get length => _running.length;

  Future<V> run(K key, Future<V> Function() task) {
    final existing = _running[key];
    if (existing != null) return existing;
    final future = task();
    _running[key] = future;
    void done() {
      _running.remove(key);
    }

    future.then<void>((_) => done(), onError: (Object _) => done());
    return future;
  }
}
