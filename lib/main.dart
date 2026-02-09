import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'app.dart';
import 'package:preconnect/tools/local_notifications.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  runApp(const MyApp());
  unawaited(_initNotificationsSafe());
}

Future<void> _initNotificationsSafe() async {
  try {
    await LocalNotificationsService.instance.initialize();
  } catch (_) {
    // Ignore notifications init errors on unsupported platforms.
  }
}
