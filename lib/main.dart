import 'dart:async';
import 'dart:ui';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:preconnect/firebase_options.dart';
import 'app.dart';
import 'tools/app_storage.dart';

Future<void> main() async {
  runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();

    FlutterError.onError = (details) {
      FlutterError.presentError(details);
    };
    PlatformDispatcher.instance.onError = (error, stackTrace) {
      return true;
    };
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );

    await AppStorage.initialize();
    PaintingBinding.instance.imageCache.maximumSize = 200;
    PaintingBinding.instance.imageCache.maximumSizeBytes = 100 << 20;
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
