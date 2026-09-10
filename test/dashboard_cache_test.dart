import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:preconnect/pages/home.dart';
import 'package:preconnect/pages/ui_kit.dart';
import 'package:preconnect/tools/app_storage.dart';
import 'package:preconnect/tools/refresh_bus.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('auth refresh shows saved profile on the first dashboard frame', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'home_dashboard_snapshot_v1': jsonEncode({
        'profile': {'studentId': 'DEMO123', 'fullName': 'Example Student'},
        'personalSchedules': [],
        'examOverrides': {},
      }),
    });
    await tester.runAsync(AppStorage.initialize);
    RefreshBus.instance.notify(reason: 'auth');
    await tester.pumpWidget(const MaterialApp(home: HomePage()));
    expect(find.textContaining('Example'), findsWidgets);
    expect(find.byType(Shimmer), findsNothing);
    await tester.pump(const Duration(seconds: 1));
    expect(find.textContaining('Example'), findsWidgets);
    expect(find.byType(Shimmer), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 60));
    RefreshBus.instance.notify();
  });
}
