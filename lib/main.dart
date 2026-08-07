import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:preconnect/api/fcm.dart';
import 'package:preconnect/firebase_options.dart';
import 'app.dart';
import 'tools/app_log.dart';
import 'tools/app_storage.dart';

import 'package:preconnect/tools/runtime_stub.dart'
    if (dart.library.js_interop) 'package:preconnect/tools/runtime_web.dart';

Future<void> main() async {
  final oldDebugPrint = debugPrint;
  debugPrint = (String? message, {int? wrapWidth}) {
    if (!kReleaseMode) {
      oldDebugPrint(message, wrapWidth: wrapWidth);
    }
  };

  runZonedGuarded(
    () async {
      WidgetsFlutterBinding.ensureInitialized();

      FlutterError.onError = (details) {
        unawaited(
          AppLog.write(
            'Flutter error: ${details.exceptionAsString()}\n${details.stack}',
          ),
        );
        if (!kReleaseMode) {
          FlutterError.presentError(details);
        }
      };
      PlatformDispatcher.instance.onError = (error, stackTrace) {
        unawaited(AppLog.write('Platform error: $error\n$stackTrace'));
        return true;
      };

      if (!isChromeRuntimeAvailable()) {
        try {
          await Firebase.initializeApp(
            options: DefaultFirebaseOptions.currentPlatform,
          );
          FirebaseMessaging.onBackgroundMessage(FCMService.backgroundHandler);
        } catch (error, stackTrace) {
          unawaited(
            AppLog.write('Firebase initialization failed: $error\n$stackTrace'),
          );
        }
      }

      await AppStorage.initialize();

      PaintingBinding.instance.imageCache.maximumSize = 200;
      PaintingBinding.instance.imageCache.maximumSizeBytes = 100 << 20;
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);

      final initialState = MyApp.bootstrapSync();

      runApp(MyApp(bootstrapState: initialState));
    },
    (error, stackTrace) {
      unawaited(AppLog.write('Uncaught zone error: $error\n$stackTrace'));
    },
    zoneSpecification: ZoneSpecification(
      print: (Zone self, ZoneDelegate parent, Zone zone, String line) {
        if (!kReleaseMode) {
          parent.print(zone, line);
        }
      },
    ),
  );
}
