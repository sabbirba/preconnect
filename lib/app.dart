import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_shortcut_plus/flutter_shortcut.dart';
import 'package:in_app_update/in_app_update.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:preconnect/api/auth_service.dart';
import 'package:preconnect/pages/home.dart';
import 'package:preconnect/pages/home_tab.dart';
import 'package:preconnect/pages/login.dart';
import 'package:preconnect/pages/onboarding.dart';
import 'package:preconnect/tools/play_install_referrer.dart';
import 'package:preconnect/tools/play_integrity.dart';
import 'package:preconnect/tools/token_storage.dart';

class AppBootstrapState {
  const AppBootstrapState({
    required this.themeMode,
    required this.isLoggedIn,
    required this.canOpenOffline,
  });

  final ThemeMode themeMode;
  final bool isLoggedIn;
  final bool canOpenOffline;
}

class MyApp extends StatefulWidget {
  const MyApp({super.key, required this.bootstrapState});

  final AppBootstrapState bootstrapState;

  static Future<AppBootstrapState> bootstrap() async {
    final prefs = await SharedPreferences.getInstance();
    final savedTheme = prefs.getString('themeMode') ?? 'system';
    final token = await TokenStorage.instance.read(key: 'access_token');
    final hasToken = token != null && token.isNotEmpty;
    final canOpenOffline = !hasToken && _hasOfflineSnapshot(prefs);
    return AppBootstrapState(
      themeMode: _decodeTheme(savedTheme),
      isLoggedIn: hasToken,
      canOpenOffline: canOpenOffline,
    );
  }

  static bool _hasOfflineSnapshot(SharedPreferences prefs) {
    final studentId = (prefs.getString('studentId') ?? '').trim();
    final fullName = (prefs.getString('fullName') ?? '').trim();
    final schedule = (prefs.getString('StudentSchedule') ?? '').trim();
    if (schedule.isNotEmpty) return true;
    return studentId.isNotEmpty && fullName.isNotEmpty;
  }

  static ThemeMode _decodeTheme(String raw) {
    switch (raw) {
      case 'light':
        return ThemeMode.light;
      case 'dark':
        return ThemeMode.dark;
      default:
        return ThemeMode.system;
    }
  }

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  static const String _pendingShortcutPrefsKey = 'pending_shortcut_action';
  static const String _shortcutProfile = 'quick.profile';
  static const String _shortcutClasses = 'quick.classes';
  static const String _shortcutAlarms = 'quick.alarms';
  static const String _shortcutExams = 'quick.exams';
  static const String _shortcutFriends = 'quick.friends';
  static const String _shortcutDevs = 'quick.devs';

  late final ValueNotifier<ThemeMode> _themeMode = ValueNotifier<ThemeMode>(
    widget.bootstrapState.themeMode,
  );
  final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();
  late final bool _initialLoggedIn = widget.bootstrapState.isLoggedIn;
  late final bool _canOpenOffline = widget.bootstrapState.canOpenOffline;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      PlayIntegrity.prepare().catchError((_) {});
      PlayInstallReferrer.prefetch().catchError((_) {});
      unawaited(_setupQuickAccessShortcuts());
      unawaited(_runStartupChecks());
      if (_initialLoggedIn) {
        _validateSessionInBackground();
      }
    });
  }

  Future<void> _setupQuickAccessShortcuts() async {
    if (kIsWeb) return;
    try {
      await FlutterShortcut.initialize(debug: false);
      await FlutterShortcut.clearShortcutItems();
      await FlutterShortcut.setShortcutItems(
        shortcutItems: const <ShortcutItem>[
          ShortcutItem(
            id: 'profile',
            action: _shortcutProfile,
            shortLabel: 'Profile',
            longLabel: 'Open Profile',
            icon: 'assets/shortcuts/profile.png',
          ),
          ShortcutItem(
            id: 'classes',
            action: _shortcutClasses,
            shortLabel: 'Classes',
            longLabel: 'Open Classes',
            icon: 'assets/shortcuts/classes.png',
          ),
          ShortcutItem(
            id: 'alarms',
            action: _shortcutAlarms,
            shortLabel: 'Alarms',
            longLabel: 'Open Alarms',
            icon: 'assets/shortcuts/alarms.png',
          ),
          ShortcutItem(
            id: 'exams',
            action: _shortcutExams,
            shortLabel: 'Exams',
            longLabel: 'Open Exams',
            icon: 'assets/shortcuts/exams.png',
          ),
          ShortcutItem(
            id: 'friends',
            action: _shortcutFriends,
            shortLabel: 'Friends',
            longLabel: 'Open Friends',
            icon: 'assets/shortcuts/friends.png',
          ),
          ShortcutItem(
            id: 'devs',
            action: _shortcutDevs,
            shortLabel: 'Devs',
            longLabel: 'Open Devs',
            icon: 'assets/shortcuts/devs.png',
          ),
        ],
      );
      await FlutterShortcut.listenAction((action) {
        _handleShortcutAction(action);
      });
      if (Platform.isIOS) {
        final prefs = await SharedPreferences.getInstance();
        final pendingAction = prefs.getString(_pendingShortcutPrefsKey);
        if (pendingAction != null && pendingAction.isNotEmpty) {
          await prefs.remove(_pendingShortcutPrefsKey);
          _handleShortcutAction(pendingAction);
        }
      }
    } catch (_) {}
  }

  void _handleShortcutAction(String action) {
    final tab = _tabFromShortcutAction(action);
    if (tab == null) return;
    if (!_initialLoggedIn && !_canOpenOffline) return;
    HomePage.requestShortcutTab(tab);
    final navigator = _navigatorKey.currentState;
    if (navigator != null) {
      navigator.pushNamedAndRemoveUntil('/home', (route) => false);
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _navigatorKey.currentState?.pushNamedAndRemoveUntil(
        '/home',
        (route) => false,
      );
    });
  }

  HomeTab? _tabFromShortcutAction(String action) {
    switch (action) {
      case _shortcutProfile:
      case 'profile':
        return HomeTab.profile;
      case _shortcutClasses:
      case 'classes':
        return HomeTab.studentSchedule;
      case _shortcutAlarms:
      case 'alarms':
        return HomeTab.alarms;
      case _shortcutExams:
      case 'exams':
        return HomeTab.examSchedule;
      case _shortcutFriends:
      case 'friends':
        return HomeTab.friendSchedule;
      case _shortcutDevs:
      case 'devs':
        return HomeTab.devs;
      default:
        return null;
    }
  }

  Future<void> _runStartupChecks() async {
    await _maybeCheckForUpdates();
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

  Future<void> _validateSessionInBackground() async {
    final signedIn = await AuthService().ensureSignedIn().timeout(
      const Duration(seconds: 10),
      onTimeout: () => true,
    );
    if (!signedIn && mounted) {
      _navigatorKey.currentState?.pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const OnboardingPage()),
        (route) => false,
      );
    }
  }

  Future<bool> _maybeCheckForUpdates() async {
    if (!Platform.isAndroid) return false;
    try {
      final info = await InAppUpdate.checkForUpdate();
      final availability = info.updateAvailability;
      final installStatus = info.installStatus;

      if (installStatus == InstallStatus.downloaded ||
          availability == UpdateAvailability.developerTriggeredUpdateInProgress) {
        return await _runImmediateUpdate();
      }
      if (availability == UpdateAvailability.updateAvailable) {
        return await _runImmediateUpdate();
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  Future<bool> _runImmediateUpdate() async {
    try {
      final result = await InAppUpdate.performImmediateUpdate();
      return result == AppUpdateResult.success;
    } catch (_) {
      return false;
    }
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
              final isDark = Theme.of(context).brightness == Brightness.dark;
              final overlayStyle = SystemUiOverlayStyle(
                statusBarColor: Colors.transparent,
                systemStatusBarContrastEnforced: false,
                statusBarIconBrightness: isDark
                    ? Brightness.light
                    : Brightness.dark,
                statusBarBrightness: isDark
                    ? Brightness.dark
                    : Brightness.light,
                systemNavigationBarColor: Colors.transparent,
                systemNavigationBarContrastEnforced: false,
                systemNavigationBarIconBrightness: isDark
                    ? Brightness.light
                    : Brightness.dark,
              );
              return AnnotatedRegion<SystemUiOverlayStyle>(
                value: overlayStyle,
                child: child ?? const SizedBox.shrink(),
              );
            },
            navigatorKey: _navigatorKey,
            routes: {
              '/login': (context) => const LoginPage(),
              '/home': (context) => const HomePage(),
              '/onboarding': (context) => const OnboardingPage(),
            },
            home: (_initialLoggedIn || _canOpenOffline)
                ? const HomePage()
                : const OnboardingPage(),
          ),
        );
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
