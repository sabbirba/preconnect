import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:preconnect/tools/refresh_bus.dart';

class _Probe extends StatefulWidget {
  const _Probe({required this.onSignal});

  final void Function(String? reason) onSignal;

  @override
  State<_Probe> createState() => _ProbeState();
}

class _ProbeState extends State<_Probe> with RefreshBusState {
  @override
  void initState() {
    super.initState();
    bindRefreshBus(_onRefreshSignal);
  }

  void _onRefreshSignal() {
    widget.onSignal(refreshBusReason);
  }

  @override
  void dispose() {
    unbindRefreshBus(_onRefreshSignal);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

void main() {
  testWidgets(
    'each notify is observed with its own reason even when several fire '
    'synchronously in a row',
    (tester) async {
      final observed = <String?>[];
      await tester.pumpWidget(_Probe(onSignal: observed.add));

      RefreshBus.instance.notify(reason: 'mercure_foo');
      RefreshBus.instance.notify(reason: 'cache_cleared');
      RefreshBus.instance.notify(reason: 'foo');

      await tester.pump();

      expect(observed, <String?>['mercure_foo', 'cache_cleared', 'foo']);
    },
  );
}
