import 'dart:async';

class PushRegistration {
  PushRegistration({
    required this.events,
    required this.register,
    this.timeout = const Duration(seconds: 15),
  });

  final Stream<String> events;
  final Future<void> Function() register;
  final Duration timeout;
  Future<String>? _pending;

  Future<String> get() {
    final pending = _pending;
    if (pending != null) return pending;
    final result = _request();
    _pending = result;
    result.then<void>(
      (_) => _pending = null,
      onError: (Object error) {
        _pending = null;
      },
    );
    return result;
  }

  Future<String> _request() async {
    final registered = Completer<String>();
    final subscription = events.listen(
      (id) {
        if (!registered.isCompleted && id.isNotEmpty) registered.complete(id);
      },
      onError: (Object error, StackTrace stack) {
        if (!registered.isCompleted) registered.completeError(error, stack);
      },
    );
    try {
      final results = await Future.wait<Object?>([
        registered.future,
        Future<void>.sync(register),
      ], eagerError: true).timeout(timeout);
      return results.first as String;
    } finally {
      await subscription.cancel();
    }
  }
}
