import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:preconnect/app.dart';
import 'package:preconnect/tools/app_storage.dart';
import 'package:preconnect/pages/home_tab.dart';

Future<void> main() async {
  runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();

    FlutterError.onError = (details) {
      FlutterError.presentError(details);
    };
    WidgetsBinding.instance.platformDispatcher.onError = (error, stackTrace) {
      return true;
    };

    await AppStorage.initialize();
    PaintingBinding.instance.imageCache.maximumSize = 1 << 30;
    PaintingBinding.instance.imageCache.maximumSizeBytes = 1 << 62;
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);

    AppBootstrapState bootstrapState;
    try {
      bootstrapState = await MyApp.bootstrap();
    } catch (_) {
      bootstrapState = const AppBootstrapState(
        themeMode: ThemeMode.system,
        isLoggedIn: false,
        canOpenOffline: false,
        initialHomeTab: HomeTab.dashboard,
      );
    }

    runApp(MyApp(bootstrapState: bootstrapState));
  }, (error, stackTrace) {});
}
