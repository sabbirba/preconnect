import 'dart:async';
import 'package:flutter/material.dart';
import 'package:preconnect/api/api_client.dart';
import 'package:preconnect/pages/ui_kit.dart';

class RefreshBus {
  RefreshBus._();
  static final RefreshBus instance = RefreshBus._();

  String? _reason;
  String? get reason => _reason;

  final _controller = StreamController<String?>.broadcast();
  Stream<String?> get stream => _controller.stream;

  bool isReason(String value) => _reason == value;
  bool isAnyReason(Iterable<String> values) => values.contains(_reason);

  void notify({String? reason}) {
    _reason = reason;
    _controller.add(reason);
  }
}

mixin RefreshBusState<T extends StatefulWidget> on State<T> {
  final Map<void Function(), StreamSubscription<String?>> _subscribers = {};

  String? get refreshBusReason => RefreshBus.instance.reason;
  bool isRefreshingFrom(String r) => RefreshBus.instance.isReason(r);
  bool isRefreshingFromAny(Iterable<String> r) =>
      RefreshBus.instance.isAnyReason(r);

  void bindRefreshBus(void Function() handler) {
    if (_subscribers.containsKey(handler)) return;
    _subscribers[handler] = RefreshBus.instance.stream.listen((_) => handler());
  }

  void unbindRefreshBus(void Function() handler) {
    final sub = _subscribers.remove(handler);
    sub?.cancel();
  }

  @override
  void dispose() {
    for (final sub in _subscribers.values) {
      sub.cancel();
    }
    _subscribers.clear();
    super.dispose();
  }
}

Future<bool> ensureOnline(BuildContext context, {bool notify = true}) async {
  final online = await ApiClient().hasConnection();
  if (!online && notify && context.mounted) {
    showAppSnackBar(context, 'Offline. Showing stored data.');
  }
  return online;
}
