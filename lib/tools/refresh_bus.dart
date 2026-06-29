import 'package:flutter/material.dart';

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

mixin RefreshBusState<T extends StatefulWidget> on State<T> {
  String? get refreshBusReason => RefreshBus.instance.reason;

  bool isRefreshingFrom(String reason) => RefreshBus.instance.isReason(reason);

  bool isRefreshingFromAny(Iterable<String> reasons) =>
      RefreshBus.instance.isAnyReason(reasons);

  void bindRefreshBus(void Function() handler) {
    RefreshBus.instance.addListener(handler);
  }

  void unbindRefreshBus(void Function() handler) {
    RefreshBus.instance.removeListener(handler);
  }
}

Future<bool> ensureOnline(BuildContext context, {bool notify = true}) async {
  return true;
}
