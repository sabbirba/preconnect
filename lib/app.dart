import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:preconnect/api/bracu_auth_manager.dart';
import 'package:preconnect/pages/home.dart';
import 'package:preconnect/pages/login.dart';

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

    final loggedIn = await BracuAuthManager().ensureSignedIn();

    if (loggedIn) {
      unawaited(BracuAuthManager().getProfile());
      unawaited(BracuAuthManager().getStudentSchedule());
      unawaited(BracuAuthManager().fetchProfile());
      unawaited(BracuAuthManager().fetchStudentSchedule());
    }

    return _StartupState(isLoggedIn: loggedIn);
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
        surface: Color(0xFF0B0B0B),
        onSurface: Colors.white,
      ),
      scaffoldBackgroundColor: Colors.black,
      dialogTheme: const DialogThemeData(backgroundColor: Color(0xFF0B0B0B)),
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

class _AppGate extends StatelessWidget {
  const _AppGate({required this.startupFuture});

  final Future<_StartupState> startupFuture;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_StartupState>(
      future: startupFuture,
      builder: (context, snapshot) {
        final isLoggedIn = snapshot.data?.isLoggedIn;
        if (isLoggedIn == true) {
          return const HomePage();
        }
        return const LoginPage();
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
