import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:rhttp/rhttp.dart';
import 'app.dart';
import 'tools/app_storage.dart';

Future<void> main() async {
  runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();
    await Rhttp.init();

    FlutterError.onError = (details) {
      FlutterError.presentError(details);
    };
    PlatformDispatcher.instance.onError = (error, stackTrace) {
      return true;
    };

    await AppStorage.initialize();
    PaintingBinding.instance.imageCache.maximumSize = 1 << 30;
    PaintingBinding.instance.imageCache.maximumSizeBytes = 1 << 62;
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);

    runApp(
      AppRestart(
        key: AppRestart.restartKey,
        bootstrap: MyApp.bootstrap,
        builder: (bootstrapState) => MyApp(bootstrapState: bootstrapState),
        child: const MyApp(),
      ),
    );
  }, (error, stackTrace) {});
}
