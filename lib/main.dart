import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:preconnect/api/fcm.dart';
import 'package:preconnect/firebase_options.dart';
import 'app.dart';
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
        if (!kReleaseMode) {
          FlutterError.presentError(details);
        }
      };
      PlatformDispatcher.instance.onError = (error, stackTrace) {
        return false;
      };

      Future<FirebaseApp>? firebaseInit;
      if (!isChromeRuntimeAvailable()) {
        firebaseInit = Firebase.initializeApp(
          options: DefaultFirebaseOptions.currentPlatform,
        );
      }

      await AppStorage.initialize();

      PaintingBinding.instance.imageCache.maximumSize = 200;
      PaintingBinding.instance.imageCache.maximumSizeBytes = 100 << 20;
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);

      final initialState = MyApp.bootstrapSync();

      runApp(MyApp(bootstrapState: initialState));

      try {
        if (firebaseInit != null) {
          await firebaseInit;
          FirebaseMessaging.onBackgroundMessage(FCMService.backgroundHandler);
        }
      } catch (_) {}
    },
    (error, stackTrace) {},
    zoneSpecification: ZoneSpecification(
      print: (Zone self, ZoneDelegate parent, Zone zone, String line) {
        if (!kReleaseMode) {
          parent.print(zone, line);
        }
      },
    ),
  );
}
