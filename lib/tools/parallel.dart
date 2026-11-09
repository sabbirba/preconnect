import 'dart:math' as math;

Future<void> runInParallel<T>(
  List<T> items,
  int limit,
  Future<void> Function(T item) task,
) async {
  var next = 0;
  Future<void> worker() async {
    while (next < items.length) {
      await task(items[next++]);
    }
  }

  await Future.wait(<Future<void>>[
    for (var i = 0; i < math.min(limit, items.length); i++) worker(),
  ]);
}
