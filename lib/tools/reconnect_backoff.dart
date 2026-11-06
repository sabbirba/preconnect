import 'dart:math' as math;

class ReconnectBackoff {
  ReconnectBackoff({required this.min, required this.max}) : _next = min;

  final Duration min;
  final Duration max;
  Duration _next;

  Duration next() {
    final current = _next;
    _next = Duration(
      milliseconds: math.min(current.inMilliseconds * 2, max.inMilliseconds),
    );
    return current;
  }

  void reset() {
    _next = min;
  }
}
