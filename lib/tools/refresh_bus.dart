import 'package:flutter/material.dart';
import 'package:signals_flutter/signals_flutter.dart';
import 'package:preconnect/api/api_client.dart';
import 'package:preconnect/pages/ui_kit.dart';

class RefreshBus {
  RefreshBus._();
  static final RefreshBus instance = RefreshBus._();

  final reason = signal<String?>(null);
  final tick = signal<int>(0);

  bool isReason(String value) => reason.value == value;
  bool isAnyReason(Iterable<String> values) => values.contains(reason.value);

  void notify({String? reason}) {
    this.reason.value = reason;
    tick.value++;
  }
}

mixin RefreshBusState<T extends StatefulWidget> on State<T> {
  final Map<void Function(), VoidCallback> _subscribers = {};

  String? get refreshBusReason => RefreshBus.instance.reason.value;
  bool isRefreshingFrom(String r) => RefreshBus.instance.isReason(r);
  bool isRefreshingFromAny(Iterable<String> r) =>
      RefreshBus.instance.isAnyReason(r);

  void bindRefreshBus(void Function() handler) {
    if (_subscribers.containsKey(handler)) return;
    _subscribers[handler] = RefreshBus.instance.tick.subscribe(
      (_) => handler(),
    );
  }

  void unbindRefreshBus(void Function() handler) {
    final dispose = _subscribers.remove(handler);
    if (dispose != null) dispose();
  }

  @override
  void dispose() {
    for (final dispose in _subscribers.values) {
      dispose();
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
