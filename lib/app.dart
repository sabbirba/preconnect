import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:in_app_update/in_app_update.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:preconnect/api/bracu_auth_manager.dart';
import 'package:preconnect/pages/home.dart';
import 'package:preconnect/pages/login.dart';
import 'package:preconnect/pages/onboarding.dart';

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  late final ValueNotifier<ThemeMode> _themeMode = ValueNotifier<ThemeMode>(
    ThemeMode.system,
  );
  late final Future<_StartupState> _startupFuture = _bootstrap();
  StreamSubscription<InstallStatus>? _updateSubscription;
  Future<void>? _updateCheckInFlight;
  _UpdatePolicy _updatePolicy = _UpdatePolicy.normal;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(_lifecycleObserver);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _maybeCheckForUpdates();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(_lifecycleObserver);
    _updateSubscription?.cancel();
    super.dispose();
  }

  late final WidgetsBindingObserver _lifecycleObserver = _LifecycleObserver(
    onResumed: _maybeCheckForUpdates,
  );

  ThemeMode _decodeTheme(String raw) {
    switch (raw) {
      case 'light':
        return ThemeMode.light;
      case 'dark':
        return ThemeMode.dark;
      default:
        return ThemeMode.system;
    }
  }

  Future<void> _persistTheme(ThemeMode mode) async {
    final prefs = await SharedPreferences.getInstance();
    final value = switch (mode) {
      ThemeMode.light => 'light',
      ThemeMode.dark => 'dark',
      ThemeMode.system => 'system',
    };
    await prefs.setString('themeMode', value);
  }

  Future<_StartupState> _bootstrap() async {
    final prefs = await SharedPreferences.getInstance();
    final savedTheme = prefs.getString('themeMode') ?? 'system';
    _themeMode.value = _decodeTheme(savedTheme);

    final loggedIn = await BracuAuthManager().ensureSignedIn().timeout(
      const Duration(seconds: 10),
      onTimeout: () => false,
    );

    return _StartupState(isLoggedIn: loggedIn);
  }

  Future<void> _maybeCheckForUpdates() async {
    if (!Platform.isAndroid || _updateCheckInFlight != null) return;
    _updateCheckInFlight = () async {
      final info = await InAppUpdate.checkForUpdate();
      final availability = info.updateAvailability;

      if (info.installStatus == InstallStatus.downloaded) {
        await InAppUpdate.completeFlexibleUpdate();
        return;
      }

      final shouldRunImmediate =
          info.immediateUpdateAllowed &&
          (availability ==
                  UpdateAvailability.developerTriggeredUpdateInProgress ||
              (availability == UpdateAvailability.updateAvailable &&
                  _updatePolicy != _UpdatePolicy.skipImmediateForSession));

      if (shouldRunImmediate) {
        await _runImmediateUpdate();
        return;
      }
      if (availability == UpdateAvailability.updateAvailable &&
          info.flexibleUpdateAllowed &&
          _updateSubscription == null) {
        await _startFlexibleUpdate();
      }
    }();

    try {
      await _updateCheckInFlight;
    } catch (_) {
    } finally {
      _updateCheckInFlight = null;
    }
  }

  Future<void> _runImmediateUpdate() async {
    try {
      if (await InAppUpdate.performImmediateUpdate() !=
          AppUpdateResult.success) {
        _updatePolicy = _UpdatePolicy.skipImmediateForSession;
      }
    } catch (_) {
      _updatePolicy = _UpdatePolicy.skipImmediateForSession;
    }
  }

  Future<void> _startFlexibleUpdate() async {
    _updateSubscription = InAppUpdate.installUpdateListener.listen((status) {
      if (status == InstallStatus.downloaded) {
        InAppUpdate.completeFlexibleUpdate();
      } else if ({
        InstallStatus.installed,
        InstallStatus.failed,
        InstallStatus.canceled,
      }.contains(status)) {
        _clearUpdateSubscription();
      }
    });
    if (await InAppUpdate.startFlexibleUpdate() != AppUpdateResult.success) {
      _clearUpdateSubscription();
    }
  }

  void _clearUpdateSubscription() {
    _updateSubscription?.cancel();
    _updateSubscription = null;
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData lightTheme = ThemeData(
      brightness: Brightness.light,
      colorScheme: const ColorScheme.light(
        primary: Color(0xFF1E6BE3),
        secondary: Color(0xFF22B573),
      ),
      scaffoldBackgroundColor: Colors.white,
      useMaterial3: true,
    );

    final ThemeData darkTheme = ThemeData(
      brightness: Brightness.dark,
      colorScheme: const ColorScheme.dark(
        primary: Color(0xFF1E6BE3),
        secondary: Color(0xFF22B573),
        surface: Colors.black,
        onSurface: Colors.white,
      ),
      scaffoldBackgroundColor: Colors.black,
      dialogTheme: const DialogThemeData(backgroundColor: Colors.black),
      useMaterial3: true,
    );

    return ValueListenableBuilder<ThemeMode>(
      valueListenable: _themeMode,
      builder: (context, mode, _) {
        return ThemeController(
          notifier: _themeMode,
          onChanged: _persistTheme,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: lightTheme,
            darkTheme: darkTheme,
            themeMode: mode,
            builder: (context, child) {
              return child ?? const SizedBox.shrink();
            },
            routes: {
              '/login': (context) => const LoginPage(),
              '/home': (context) => const HomePage(),
            },
            home: _AppGate(startupFuture: _startupFuture),
          ),
        );
      },
    );
  }
}

class _StartupState {
  const _StartupState({required this.isLoggedIn});

  final bool isLoggedIn;
}

enum _UpdatePolicy { normal, skipImmediateForSession }

class _AppGate extends StatelessWidget {
  const _AppGate({required this.startupFuture});

  final Future<_StartupState> startupFuture;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_StartupState>(
      future: startupFuture,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return const Scaffold(
            body: Center(
              child: Text('Startup failed. Please restart the app.'),
            ),
          );
        }
        if (snapshot.connectionState != ConnectionState.done) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        final isLoggedIn = snapshot.data?.isLoggedIn;
        if (isLoggedIn == true) {
          return const HomePage();
        }
        return const OnboardingPage();
      },
    );
  }
}

class ThemeController extends InheritedWidget {
  const ThemeController({
    super.key,
    required this.notifier,
    required this.onChanged,
    required super.child,
  });

  final ValueNotifier<ThemeMode> notifier;
  final Future<void> Function(ThemeMode mode) onChanged;

  static ValueNotifier<ThemeMode> of(BuildContext context) {
    final ThemeController? controller = context
        .dependOnInheritedWidgetOfExactType<ThemeController>();
    return controller!.notifier;
  }

  static Future<void> setTheme(BuildContext context, ThemeMode mode) async {
    final ThemeController? controller = context
        .dependOnInheritedWidgetOfExactType<ThemeController>();
    controller!.notifier.value = mode;
    await controller.onChanged(mode);
  }

  @override
  bool updateShouldNotify(ThemeController oldWidget) {
    return notifier != oldWidget.notifier;
  }
}

class _LifecycleObserver extends WidgetsBindingObserver {
  _LifecycleObserver({required this.onResumed});

  final VoidCallback onResumed;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      onResumed();
    }
  }
}
