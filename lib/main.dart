import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:preconnect/api/fcm.dart';
import 'package:preconnect/firebase_options.dart';
import 'package:preconnect/tools/app_log.dart';
import 'app.dart';
import 'tools/app_storage.dart';

Future<void> main() async {
  final oldDebugPrint = debugPrint;
  debugPrint = (String? message, {int? wrapWidth}) {
    if (message != null) {
      AppLog.write(message);
    }
    if (!kReleaseMode) {
      oldDebugPrint(message, wrapWidth: wrapWidth);
    }
  };

  runZonedGuarded(
    () async {
      WidgetsFlutterBinding.ensureInitialized();
      unawaited(AppLog.logDeviceInfo());

      FlutterError.onError = (details) {
        AppLog.write('FlutterError: $details');
        if (!kReleaseMode) {
          FlutterError.presentError(details);
        }
      };
      PlatformDispatcher.instance.onError = (error, stackTrace) {
        AppLog.write('PlatformError: $error\n$stackTrace');
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

      runApp(MyApp(bootstrapState: initialState));
    },
    (error, stackTrace) {
      AppLog.write('FatalError: $error\n$stackTrace');
    },
    zoneSpecification: ZoneSpecification(
      print: (Zone self, ZoneDelegate parent, Zone zone, String line) {
        AppLog.write(line);
        if (!kReleaseMode) {
          parent.print(zone, line);
        }
      },
    ),
  );
}
