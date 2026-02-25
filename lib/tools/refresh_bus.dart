import 'package:flutter/foundation.dart';

class RefreshBus extends ChangeNotifier {
  RefreshBus._();

  static final RefreshBus instance = RefreshBus._();

  String? _reason;
  int _tick = 0;

  String? get reason => _reason;
  int get tick => _tick;

  bool isReason(String value) => _reason == value;

  bool isAnyReason(Iterable<String> values) => values.contains(_reason);

  void notify({String? reason}) {
    _reason = reason;
    _tick++;
    notifyListeners();
  }
}
