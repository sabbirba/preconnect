import 'dart:async';

class PollingTimer {
  PollingTimer(Duration interval, void Function(Timer timer) onTick)
    : _timer = Timer.periodic(interval, onTick);

  final Timer _timer;

  bool get isActive => _timer.isActive;

  void cancel() => _timer.cancel();
}
