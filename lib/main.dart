import 'dart:async';
import 'dart:ui';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:preconnect/api/fcm.dart';
import 'package:preconnect/firebase_options.dart';
import 'app.dart';
import 'tools/app_storage.dart';

Future<void> main() async {
  runZonedGuarded(
    () async {
      WidgetsFlutterBinding.ensureInitialized();

      FlutterError.onError = (details) {
        FlutterError.presentError(details);
        debugPrint('[FlutterError] ${details.exception}\n${details.stack}');
      };
      PlatformDispatcher.instance.onError = (error, stackTrace) {
        debugPrint('[PlatformDispatcherError] $error\n$stackTrace');
        return false;
      };
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
      FirebaseMessaging.onBackgroundMessage(FCMService.backgroundHandler);

      await AppStorage.initialize();
      PaintingBinding.instance.imageCache.maximumSize = 200;
      PaintingBinding.instance.imageCache.maximumSizeBytes = 100 << 20;
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);

      final initialState = MyApp.bootstrapSync();

      runApp(
        AppRestart(
          key: AppRestart.restartKey,
          bootstrap: MyApp.bootstrap,
          initialData: initialState,
          builder: (bootstrapState) => MyApp(bootstrapState: bootstrapState),
          child: const MyApp(isPreBoot: true),
        ),
      );
    },
    (error, stackTrace) {
      debugPrint('[ZoneError] $error\n$stackTrace');
    },
  );
}
