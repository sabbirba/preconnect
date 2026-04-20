import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:background_fetch/background_fetch.dart';
import 'app.dart';
import 'tools/app_storage.dart';
import 'tools/push_notifications_service.dart';

bool _supportsBackgroundFetchHeadlessRegistration() {
  if (kIsWeb) return false;
  return defaultTargetPlatform == TargetPlatform.android;
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await AppStorage.initialize();

  if (_supportsBackgroundFetchHeadlessRegistration()) {
    try {
      BackgroundFetch.registerHeadlessTask(backgroundFetchHeadlessTask);
    } on MissingPluginException {
      // Desktop/web builds do not implement this channel.
    }
  }
  PaintingBinding.instance.imageCache.maximumSize = 1 << 30;
  PaintingBinding.instance.imageCache.maximumSizeBytes = 1 << 62;
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  final bootstrapState = await MyApp.bootstrap();
  runApp(MyApp(bootstrapState: bootstrapState));
}
