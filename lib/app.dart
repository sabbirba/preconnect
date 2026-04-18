import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:in_app_update/in_app_update.dart';
import 'package:preconnect/tools/app_storage.dart';
import 'package:preconnect/api/auth_service.dart';
import 'package:preconnect/api/api_client.dart';
import 'package:preconnect/pages/home.dart';
import 'package:preconnect/pages/home_tab.dart';
import 'package:preconnect/pages/login.dart';
import 'package:preconnect/pages/onboarding.dart';
import 'package:preconnect/pages/ui_kit.dart';
import 'package:preconnect/tools/ads_bridge.dart';
import 'package:preconnect/tools/play_install_referrer.dart';
import 'package:preconnect/tools/reward_support_controller.dart';
import 'package:preconnect/tools/token_storage.dart';
import 'package:preconnect/tools/push_notifications_service.dart';
import 'package:preconnect/tools/refresh_bus.dart';

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
  const MyApp({super.key, this.bootstrapState});

  final AppBootstrapState? bootstrapState;

  static Future<AppBootstrapState> bootstrap() async {
    final prefs = AppStorage.instance;
    final savedTheme = await prefs.getString('themeMode') ?? 'system';

    // CRITICAL: ONLY check actual tokens from storage, NEVER trust cached data
    final token = await TokenStorage.instance.read(key: 'access_token');
    final refreshToken = await TokenStorage.instance.read(key: 'refresh_token');
    final tokenPresent = token != null && token.isNotEmpty;
    final refreshTokenPresent = refreshToken != null && refreshToken.isNotEmpty;
    final hasToken = tokenPresent && refreshTokenPresent;

    // If tokens are missing, DO NOT ALLOW OFFLINE ACCESS
    // Tokens = source of truth for login state
    if (!hasToken) {
      // Clear everything that depends on valid tokens
      await prefs.setBool('cached_has_auth_session', false);
      await prefs.remove('StudentSchedule');
      await prefs.remove('StudentProgramProgress');
      await prefs.remove('StudentProgramProgressSummary');
      await prefs.remove('SemesterPaymentInfo');
    } else {}

    // offline access ONLY if tokens exist AND offline snapshot available
    final canOpenOffline = hasToken && await _hasOfflineSnapshot();

    return AppBootstrapState(
      themeMode: _decodeTheme(savedTheme),
      isLoggedIn: hasToken,
      canOpenOffline: canOpenOffline,
    );
  }

  static Future<bool> _hasOfflineSnapshot() async {
    final prefs = AppStorage.instance;
    final studentId = (await prefs.getString('studentId') ?? '').trim();
    final fullName = (await prefs.getString('fullName') ?? '').trim();
    final schedule = (await prefs.getString('StudentSchedule') ?? '').trim();
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

class _MyAppState extends State<MyApp>
    with WidgetsBindingObserver, RefreshBusState {
  static const String _pendingShortcutPrefsKey = 'pending_shortcut_action';
  static const String _shortcutProfile = 'quick.profile';
  static const String _shortcutClasses = 'quick.classes';
  static const String _shortcutExams = 'quick.exams';
  static const String _shortcutFriends = 'quick.friends';

  late final ValueNotifier<ThemeMode> _themeMode;
  final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();
  late bool _initialLoggedIn;
  late bool _canOpenOffline;
  AppBootstrapState? _resolvedBootstrapState;
  bool _appLockEnabled = false;
  bool _isUnlocked = true;
  bool _isUnlocking = false;

  @override
  void initState() {
    super.initState();
    _resolvedBootstrapState = widget.bootstrapState;
    _initialLoggedIn = widget.bootstrapState?.isLoggedIn ?? false;
    _canOpenOffline = widget.bootstrapState?.canOpenOffline ?? false;
    _themeMode = ValueNotifier<ThemeMode>(
      widget.bootstrapState?.themeMode ?? ThemeMode.system,
    );
    WidgetsBinding.instance.addObserver(this);
    if (_resolvedBootstrapState == null) {
      unawaited(_bootstrapInBackground());
    }
    unawaited(_initializeAppLock());
    bindRefreshBus(_onRefreshSignal);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(AdsPreferences.instance.load());
      unawaited(AdsBridge.initialize());
      unawaited(RewardSupportController.instance.load());
      PushNotificationsService().initialize().catchError((_) {});
      SeatAlertSyncService().initialize().catchError((_) {});
      PlayIntegrity.prepare().catchError((_) {});
      PlayInstallReferrer.prefetch().catchError((_) {});
      unawaited(_setupQuickAccessShortcuts());
      unawaited(_runStartupChecks());
      unawaited(_consumePendingSeatAlertLaunch());
      if (_initialLoggedIn) {
        _validateSessionInBackground();
      }
    });
  }

  Future<void> _bootstrapInBackground() async {
    final next = await MyApp.bootstrap();
    if (!mounted) return;
    _resolvedBootstrapState = next;
    _initialLoggedIn = next.isLoggedIn;
    _canOpenOffline = next.canOpenOffline;
    _themeMode.value = next.themeMode;
    setState(() {});
  }

  Future<void> _setupQuickAccessShortcuts() async {
    if (kIsWeb) return;
    try {
      await _consumePendingShortcutAction();
    } catch (_) {}
  }

  Future<void> _consumePendingShortcutAction() async {
    final prefs = AppStorage.instance;
    final pendingAction = await prefs.getString(_pendingShortcutPrefsKey);
    if (pendingAction == null || pendingAction.isEmpty) return;
    await prefs.remove(_pendingShortcutPrefsKey);
    _handleShortcutAction(pendingAction);
  }

  Future<void> _consumePendingSeatAlertLaunch() async {
    final pendingSectionId = await SeatAlertSyncService()
        .consumePendingSectionId();
    if (pendingSectionId == null) return;
    if (!_initialLoggedIn && !_canOpenOffline) return;
    HomePage.requestShortcutTab(HomeTab.seatStatus);
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

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_consumePendingShortcutAction());
      unawaited(_consumePendingSeatAlertLaunch());
      unawaited(_refreshAndUnlockIfNeeded());
    }
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused) {
      if (_appLockEnabled && _isUnlocked) {
        setState(() {
          _isUnlocked = false;
        });
      }
    }
  }

  @override
  void dispose() {
    unbindRefreshBus(_onRefreshSignal);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  void _onRefreshSignal() {
    if (!mounted) return;
    if (isRefreshingFrom('app_lock_settings_changed')) {
      unawaited(_refreshAndUnlockIfNeeded());
    }
  }

  void _handleShortcutAction(String action) {
    final tab = _tabFromShortcutAction(action);
    if (tab == null) return;
    _openHomeTab(tab);
  }

  void _openHomeTab(HomeTab tab) {
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
      case _shortcutExams:
      case 'exams':
        return HomeTab.examSchedule;
      case _shortcutFriends:
      case 'friends':
        return HomeTab.friendSchedule;
      default:
        return null;
    }
  }

  Future<void> _runStartupChecks() async {
    await _maybeCheckForUpdates();
  }

  Future<void> _initializeAppLock() async {
    final enabled = await AppLockService().isEnabled();
    if (!mounted) return;
    setState(() {
      _appLockEnabled = enabled;
      _isUnlocked = !enabled;
    });
    if (enabled) {
      await _unlockApp();
    }
  }

  Future<void> _refreshAndUnlockIfNeeded() async {
    final enabled = await AppLockService().isEnabled();
    if (!mounted) return;
    if (!enabled) {
      if (_appLockEnabled || !_isUnlocked) {
        setState(() {
          _appLockEnabled = false;
          _isUnlocked = true;
        });
      }
      return;
    }
    if (!_appLockEnabled) {
      setState(() {
        _appLockEnabled = true;
      });
    }
    if (!_isUnlocked) {
      await _unlockApp();
    }
  }

  Future<void> _unlockApp() async {
    if (_isUnlocking) return;
    _isUnlocking = true;
    final unlocked = await AppLockService().authenticate(
      reason: 'Unlock PreConnect',
    );
    _isUnlocking = false;
    if (!mounted) return;
    setState(() {
      _isUnlocked = unlocked;
    });
  }

  Widget _buildLockLayer(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: BracuPageScaffold(
        title: 'App Locked',
        subtitle: 'Security',
        icon: Icons.lock_outline_rounded,
        showBack: false,
        body: ListView(
          physics: const NeverScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
          children: [
            const SizedBox(height: 120),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: BracuPalette.card(context),
                borderRadius: BorderRadius.circular(18),
              ),
              child: Column(
                children: [
                  Icon(
                    Icons.lock_outline_rounded,
                    size: 42,
                    color: BracuPalette.textPrimary(context),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'App Locked',
                    style: TextStyle(
                      color: BracuPalette.textPrimary(context),
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      decoration: TextDecoration.none,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Use your system lock to continue',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: BracuPalette.textSecondary(context),
                      fontSize: 12,
                      decoration: TextDecoration.none,
                    ),
                  ),
                  const SizedBox(height: 14),
                  ElevatedButton.icon(
                    onPressed: _isUnlocking
                        ? null
                        : () {
                            unawaited(_unlockApp());
                          },
                    icon: const Icon(Icons.fingerprint),
                    label: const Text('Unlock'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _persistTheme(ThemeMode mode) async {
    final prefs = AppStorage.instance;
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
      _themeMode.value = ThemeMode.system;
      _navigatorKey.currentState?.pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const OnboardingPage()),
        (route) => false,
      );
    }
  }

  Future<bool> _maybeCheckForUpdates() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      return false;
    }
    try {
      final info = await InAppUpdate.checkForUpdate();
      final availability = info.updateAvailability;
      final installStatus = info.installStatus;

      if (installStatus == InstallStatus.downloaded) {
        return await _completeFlexibleUpdate();
      }
      if (availability ==
          UpdateAvailability.developerTriggeredUpdateInProgress) {
        return await _completeFlexibleUpdate();
      }
      if (availability == UpdateAvailability.updateAvailable) {
        final result = await InAppUpdate.startFlexibleUpdate();
        return result == AppUpdateResult.success;
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  Future<bool> _completeFlexibleUpdate() async {
    try {
      await InAppUpdate.completeFlexibleUpdate();
      return true;
    } catch (_) {
      return false;
    }
  }

  ThemeData _buildTheme({
    required Brightness brightness,
    required Color scaffoldBackgroundColor,
    required Color primary,
    required Color secondary,
    required Color foreground,
    Color? surface,
    Color? onSurface,
    DialogThemeData? dialogTheme,
  }) {
    final colorScheme = brightness == Brightness.dark
        ? ColorScheme.dark(
            primary: primary,
            secondary: secondary,
            surface: surface ?? Colors.black,
            onSurface: onSurface ?? Colors.white,
          )
        : ColorScheme.light(primary: primary, secondary: secondary);
    return ThemeData(
      brightness: brightness,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: scaffoldBackgroundColor,
      dialogTheme: dialogTheme,
      useMaterial3: true,
      splashFactory: NoSplash.splashFactory,
      splashColor: Colors.transparent,
      highlightColor: Colors.transparent,
      hoverColor: Colors.transparent,
      focusColor: Colors.transparent,
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: brightness == Brightness.dark
              ? Colors.white
              : primary,
          disabledForegroundColor:
              (brightness == Brightness.dark ? Colors.white : primary)
                  .withValues(alpha: 0.45),
          splashFactory: NoSplash.splashFactory,
          overlayColor: Colors.transparent,
          enableFeedback: false,
          side: BorderSide(
            color: (brightness == Brightness.dark ? Colors.white : primary)
                .withValues(alpha: 0.30),
          ),
          minimumSize: const Size(0, 44),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: primary,
          foregroundColor: Colors.white,
          splashFactory: NoSplash.splashFactory,
          overlayColor: Colors.transparent,
          enableFeedback: false,
          minimumSize: const Size(0, 44),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: brightness == Brightness.dark
              ? Colors.white
              : primary,
          splashFactory: NoSplash.splashFactory,
          overlayColor: Colors.transparent,
          enableFeedback: false,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primary,
          foregroundColor: Colors.white,
          elevation: 0,
          splashFactory: NoSplash.splashFactory,
          overlayColor: Colors.transparent,
          enableFeedback: false,
          minimumSize: const Size(0, 44),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final lightTheme = _buildTheme(
      brightness: Brightness.light,
      scaffoldBackgroundColor: Colors.white,
      primary: const Color(0xFF1E6BE3),
      secondary: const Color(0xFF22B573),
      foreground: Colors.black87,
    );

    final darkTheme = _buildTheme(
      brightness: Brightness.dark,
      scaffoldBackgroundColor: Colors.black,
      primary: const Color(0xFF1E6BE3),
      secondary: const Color(0xFF22B573),
      foreground: Colors.white,
      surface: Colors.black,
      onSurface: Colors.white,
      dialogTheme: const DialogThemeData(backgroundColor: Colors.black),
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
              final mediaQuery = MediaQuery.of(context);
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
              final content = Stack(
                children: [
                  child ?? const SizedBox.shrink(),
                  if (_appLockEnabled && !_isUnlocked)
                    Positioned.fill(child: _buildLockLayer(context)),
                ],
              );
              return AnnotatedRegion<SystemUiOverlayStyle>(
                value: overlayStyle,
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    if (kIsWeb || constraints.maxWidth < 900) {
                      return content;
                    }
                    const shellWidth = 420.0;
                    final shellSize = Size(shellWidth, mediaQuery.size.height);
                    final shellMediaQuery = mediaQuery.copyWith(
                      size: shellSize,
                    );
                    return Container(
                      color: Theme.of(context).scaffoldBackgroundColor,
                      alignment: Alignment.center,
                      child: SizedBox(
                        width: shellWidth,
                        height: mediaQuery.size.height,
                        child: MediaQuery(
                          data: shellMediaQuery,
                          child: content,
                        ),
                      ),
                    );
                  },
                ),
              );
            },
            navigatorKey: _navigatorKey,
            routes: {
              '/login': (context) => const LoginPage(),
              '/home': (context) => const HomePage(),
              '/onboarding': (context) => const OnboardingPage(),
            },
            home: _resolvedBootstrapState == null
                ? const _StartupFrame()
                : (_initialLoggedIn || _canOpenOffline)
                ? const HomePage()
                : const OnboardingPage(),
          ),
        );
      },
    );
  }
}

class _StartupFrame extends StatelessWidget {
  const _StartupFrame();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: const SizedBox.expand(),
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
