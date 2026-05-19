import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:in_app_update/in_app_update.dart';
import 'package:preconnect/api/calendar_service.dart';
import 'package:preconnect/tools/app_storage.dart';
import 'package:preconnect/api/app_preferences_store.dart';
import 'package:preconnect/api/auth_service.dart';
import 'package:preconnect/api/api_client.dart';
import 'package:preconnect/api/custom_schedules_service.dart';
import 'package:preconnect/api/friend_schedule_store.dart';
import 'package:preconnect/api/notification_service.dart';
import 'package:preconnect/api/profile_service.dart';
import 'package:preconnect/api/progress_service.dart';
import 'package:preconnect/api/seat_status_service.dart';
import 'package:preconnect/api/schedule_service.dart';
import 'package:preconnect/pages/home.dart';
import 'package:preconnect/pages/home_tab.dart';
import 'package:preconnect/pages/alarms.dart';
import 'package:preconnect/pages/bus.dart';
import 'package:preconnect/pages/class_schedule.dart';
import 'package:preconnect/pages/custom_schedules.dart';
import 'package:preconnect/pages/degree_progress.dart';
import 'package:preconnect/pages/devs.dart';
import 'package:preconnect/pages/exam_schedule.dart';
import 'package:preconnect/pages/login.dart';
import 'package:preconnect/pages/onboarding.dart';
import 'package:preconnect/pages/notifications.dart';
import 'package:preconnect/pages/student_profile.dart';
import 'package:preconnect/pages/ui_kit.dart';
import 'package:preconnect/pages/wifi_printer.dart';
import 'package:preconnect/pages/shared_widgets/current_session_helper.dart';
import 'package:preconnect/tools/ads_bridge.dart';
import 'package:preconnect/tools/preconnect_constants.dart';
import 'package:preconnect/tools/play_install_referrer.dart';
import 'package:preconnect/tools/reward_support_controller.dart';
import 'package:preconnect/tools/quiet_mode_controller.dart';
import 'package:preconnect/tools/token_storage.dart';
import 'package:preconnect/tools/refresh_bus.dart';
import 'package:preconnect/tools/storage_keys.dart';
import 'package:preconnect/tools/web_extension_shortcut_bridge_stub.dart'
    if (dart.library.html) 'package:preconnect/tools/web_extension_shortcut_bridge_web.dart';

class AppBootstrapState {
  const AppBootstrapState({
    required this.themeMode,
    required this.isLoggedIn,
    required this.canOpenOffline,
    required this.initialHomeTab,
  });

  final ThemeMode themeMode;
  final bool isLoggedIn;
  final bool canOpenOffline;
  final HomeTab initialHomeTab;
}

class MyApp extends StatefulWidget {
  const MyApp({super.key, this.bootstrapState});

  final AppBootstrapState? bootstrapState;

  static Future<AppBootstrapState> bootstrap() async {
    final prefs = AppStorage.instance;
    final savedTheme = await prefs.getString(StorageKeys.themeMode) ?? 'system';
    final initialHomeTab = _decodeHomeTab(
      await prefs.getString(StorageKeys.homeTab),
    );

    final token = await TokenStorage.instance.read(
      key: PreconnectStorageKeys.accessToken,
    );
    final refreshToken = await TokenStorage.instance.read(
      key: PreconnectStorageKeys.refreshToken,
    );
    final tokenPresent = token != null && token.isNotEmpty;
    final refreshTokenPresent = refreshToken != null && refreshToken.isNotEmpty;
    final hasToken = tokenPresent && refreshTokenPresent;

    if (!hasToken) {
      await prefs.setBool(PreconnectStorageKeys.cachedHasAuthSession, false);
      final keepKeys = <String>{
        PreconnectStorageKeys.accessToken,
        PreconnectStorageKeys.refreshToken,
        StorageKeys.themeMode,
        CustomSchedulesService.cacheKey,
      };
      await AppPreferencesStore().clearAllExcept(keepKeys);
    }

    final canOpenOffline = hasToken && await _hasOfflineSnapshot();
    if (hasToken) {
      unawaited(_warmStartupCaches());
    }

    return AppBootstrapState(
      themeMode: _decodeTheme(savedTheme),
      isLoggedIn: hasToken,
      canOpenOffline: canOpenOffline,
      initialHomeTab: initialHomeTab,
    );
  }

  static Future<bool> _hasOfflineSnapshot() async {
    final prefs = AppStorage.instance;
    final studentId = (await prefs.getString(StorageKeys.studentId) ?? '')
        .trim();
    final fullName = (await prefs.getString(StorageKeys.fullName) ?? '').trim();
    final schedule = (await prefs.getString(StorageKeys.studentSchedule) ?? '')
        .trim();
    if (schedule.isNotEmpty) return true;
    return studentId.isNotEmpty && fullName.isNotEmpty;
  }

  static Future<void> _warmStartupCaches() async {
    final tasks = <Future<void>>[
      preloadHomeDashboardData().then((_) {}),
      ProfileService().getProfile().then((_) {}),
      AttendanceService().getAttendanceInfo().then((_) {}),
      PaymentService().getPaymentInfo().then((_) {}),
      ProgressService().getProgress().then((_) {}),
      () async {
        final semesterSessionId = await resolveCurrentSessionSemesterId();
        if (semesterSessionId == null) return;
        await ScheduleService().getStudentScheduleForSemester(
          semesterSessionId: semesterSessionId,
        );
      }(),
      CustomSchedulesService().getItems().then((_) {}),
      FriendScheduleStore().loadSnapshot().then((_) {}),
      CalendarService().getCalendar().then((_) {}),
      NotificationService().getRecentNotifications().then((_) {}),
      SeatStatusService.preload(),
      BusPage.preload(),
      NotificationsPage.preload(),
      DegreeProgressPage.preload(),
      StudentProfile.preload(),
      DevsPage.preload(),
      AlarmPage.preload(),
      ClassSchedule.preload(),
      ExamSchedule.preload(),
      CustomSchedulesPage.preload(),
      CampusPrinterPage.preload(),
    ];
    await Future.wait(tasks.map((task) => task.catchError((_) {})));
  }

  static void warmStartupCaches() {
    unawaited(_warmStartupCaches());
  }

  static Future<void> warmStartupCachesAsync() {
    return _warmStartupCaches();
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

  static HomeTab _decodeHomeTab(String? raw) {
    final value = (raw ?? '').trim();
    if (value.isEmpty) return HomeTab.dashboard;
    try {
      return HomeTab.values.byName(value);
    } catch (_) {
      return HomeTab.dashboard;
    }
  }

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp>
    with WidgetsBindingObserver, RefreshBusState {
  late final ValueNotifier<ThemeMode> _themeMode;
  final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();
  late bool _initialLoggedIn;
  late bool _canOpenOffline;
  AppBootstrapState? _resolvedBootstrapState;
  bool _appLockEnabled = false;
  bool _isUnlocked = true;
  bool _isUnlocking = false;
  bool _backgroundWarmupInFlight = false;
  DateTime? _lastBackgroundWarmupAt;
  WebExtensionSessionFlow? _webExtensionSessionFlow;
  StreamSubscription<WebExtensionSessionEvent>? _webSessionSub;
  WebExtensionShortcutBridge? _webShortcutBridge;

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
    if (kIsWeb) {
      _webExtensionSessionFlow = WebExtensionSessionFlow();
      _webSessionSub = _webExtensionSessionFlow!.events.listen(
        _handleWebExtensionSessionEvent,
      );
      _webShortcutBridge = WebExtensionShortcutBridge(
        onShortcut: _handleShortcutAction,
      );
    }
    if (!kIsWeb) {
      unawaited(_initializeAppLock());
    }
    if (!kIsWeb) {
      bindRefreshBus(_onRefreshSignal);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!kIsWeb) {
        unawaited(AdsPreferences.instance.load());
        unawaited(AdsBridge.initialize());
        unawaited(RewardSupportController.instance.load());
        PlayIntegrity.prepare().catchError((_) {});
        PlayInstallReferrer.prefetch().catchError((_) {});
      }
      unawaited(_setupQuickAccessShortcuts());
      if (!kIsWeb) {
        unawaited(_runStartupChecks());
      }
      if (_initialLoggedIn) {
        _validateSessionInBackground();
      }
    });
  }

  Future<void> _bootstrapInBackground() async {
    try {
      final next = await MyApp.bootstrap();
      if (!mounted) return;
      _resolvedBootstrapState = next;
      _initialLoggedIn = next.isLoggedIn;
      _canOpenOffline = next.canOpenOffline;
      _themeMode.value = next.themeMode;
      setState(() {});
    } catch (_) {}
  }

  Future<void> _setupQuickAccessShortcuts() async {
    try {
      await _consumePendingShortcutAction();
    } catch (_) {}
  }

  Future<void> _consumePendingShortcutAction() async {
    final pendingAction = kIsWeb
        ? await TokenStorage.instance.read(
            key: PreconnectStorageKeys.pendingShortcutAction,
          )
        : await AppStorage.instance.getString(
            PreconnectStorageKeys.pendingShortcutAction,
          );
    if (pendingAction == null || pendingAction.isEmpty) return;
    await _clearPendingShortcutAction();
    _handleShortcutAction(pendingAction);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_consumePendingShortcutAction());
      unawaited(_refreshAndUnlockIfNeeded());
      unawaited(QuietModeController.instance.refresh());
      return;
    }
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused) {
      if (_initialLoggedIn) {
        unawaited(_warmBackgroundCaches());
      }
      if (_appLockEnabled && _isUnlocked) {
        setState(() {
          _isUnlocked = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _webSessionSub?.cancel();
    _webExtensionSessionFlow?.dispose();
    unawaited(_webShortcutBridge?.dispose());
    if (!kIsWeb) {
      unbindRefreshBus(_onRefreshSignal);
    }
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  void _handleWebExtensionSessionEvent(WebExtensionSessionEvent event) {
    if (!mounted) return;
    if (event.type != WebExtensionSessionEventKind.logoutComplete) return;
    setState(() {
      _initialLoggedIn = false;
      _canOpenOffline = false;
    });
    _navigatorKey.currentState?.pushNamedAndRemoveUntil(
      '/onboarding',
      (route) => false,
    );
  }

  void _onRefreshSignal() {
    if (!mounted) return;
    if (isRefreshingFrom('app_lock_settings_changed')) {
      unawaited(_refreshAndUnlockIfNeeded());
    }
    if (isRefreshingFromAny(<String>{
      'auth',
      'cache_cleared',
      'schedule',
      'class_schedule',
      'exam_schedule',
      'custom_schedules',
      'quiet_mode_settings_changed',
    })) {
      unawaited(QuietModeController.instance.refresh());
    }
  }

  void _handleShortcutAction(String action) {
    final tab = _tabFromShortcutAction(action);
    if (tab == null) return;
    _openHomeTab(tab);
    unawaited(_clearPendingShortcutAction());
  }

  Future<void> _clearPendingShortcutAction() async {
    if (kIsWeb) {
      await TokenStorage.instance.write(
        key: PreconnectStorageKeys.pendingShortcutAction,
        value: null,
      );
      return;
    }
    await AppStorage.instance.remove(
      PreconnectStorageKeys.pendingShortcutAction,
    );
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
      case PreconnectBrowserActionIds.shortcutCustomSchedule:
      case 'customSchedule':
      case 'custom_schedule':
        return HomeTab.personalSchedules;
      case PreconnectBrowserActionIds.shortcutProfile:
      case 'profile':
        return HomeTab.profile;
      case PreconnectBrowserActionIds.shortcutClasses:
      case 'classes':
        return HomeTab.studentSchedule;
      case PreconnectBrowserActionIds.shortcutExams:
      case 'exams':
        return HomeTab.examSchedule;
      case PreconnectBrowserActionIds.shortcutFriends:
      case 'friends':
        return HomeTab.friendSchedule;
      case PreconnectBrowserActionIds.shortcutShare:
      case 'share':
        return HomeTab.shareSchedule;
      case PreconnectBrowserActionIds.shortcutScan:
      case 'scan':
        return HomeTab.scanSchedule;
      case PreconnectBrowserActionIds.shortcutSeatStatus:
      case 'seatStatus':
      case 'seat_status':
        return HomeTab.seatStatus;
      default:
        return null;
    }
  }

  Future<void> _runStartupChecks() async {
    await _maybeCheckForUpdates();
  }

  Future<void> _warmBackgroundCaches() async {
    if (_backgroundWarmupInFlight) return;
    final now = DateTime.now();
    if (_lastBackgroundWarmupAt != null &&
        now.difference(_lastBackgroundWarmupAt!) < const Duration(minutes: 1)) {
      return;
    }
    _backgroundWarmupInFlight = true;
    _lastBackgroundWarmupAt = now;
    try {
      await Future.wait<void>(
        <Future<void>>[
          preloadHomeDashboardData().then((_) {}),
          ProfileService().getProfile().then((_) {}),
          AttendanceService().getAttendanceInfo().then((_) {}),
          PaymentService().getPaymentInfo().then((_) {}),
          ProgressService().getProgress().then((_) {}),
          () async {
            final semesterSessionId = await resolveCurrentSessionSemesterId();
            if (semesterSessionId == null) return;
            await ScheduleService().getStudentScheduleForSemester(
              semesterSessionId: semesterSessionId,
            );
          }(),
          CustomSchedulesService().getItems().then((_) {}),
          FriendScheduleStore().loadSnapshot().then((_) {}),
          CalendarService().getCalendar().then((_) {}),
          NotificationService().getRecentNotifications().then((_) {}),
          SeatStatusService.preload(),
          BusPage.preload(),
          NotificationsPage.preload(),
          DegreeProgressPage.preload(),
          StudentProfile.preload(),
          DevsPage.preload(),
          AlarmPage.preload(),
          ClassSchedule.preload(),
          ExamSchedule.preload(),
          CustomSchedulesPage.preload(),
        ].map((task) => task.catchError((_) {})),
      );
    } finally {
      _backgroundWarmupInFlight = false;
    }
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
                  OutlinedButton.icon(
                    onPressed: _isUnlocking
                        ? null
                        : () {
                            unawaited(_unlockApp());
                          },
                    icon: const Icon(Icons.fingerprint),
                    label: const Text('Unlock'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: BracuPalette.textPrimary(context),
                      backgroundColor: Colors.transparent,
                      splashFactory: NoSplash.splashFactory,
                      overlayColor: Colors.transparent,
                      enableFeedback: false,
                      side: BorderSide(
                        color: BracuPalette.textSecondary(
                          context,
                        ).withValues(alpha: 0.18),
                      ),
                      minimumSize: const Size(0, 44),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      textStyle: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
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
    await prefs.setString(StorageKeys.themeMode, value);
  }

  Future<void> _validateSessionInBackground() async {
    try {
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
    } catch (_) {}
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
      fontFamily: 'Roboto',
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
            borderRadius: BorderRadius.circular(12),
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
            borderRadius: BorderRadius.circular(12),
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
                    const mobileShellWidth = 390.0;
                    if (!kIsWeb && constraints.maxWidth >= 700) {
                      const shellWidth = 700.0;
                      final shellSize = Size(
                        shellWidth,
                        mediaQuery.size.height,
                      );
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
                    }

                    final shellWidth = constraints.maxWidth < mobileShellWidth
                        ? constraints.maxWidth
                        : mobileShellWidth;
                    final shellHeight = mediaQuery.size.height;
                    final shellSize = Size(shellWidth, shellHeight);
                    final shellMediaQuery = mediaQuery.copyWith(
                      size: shellSize,
                    );
                    return ValueListenableBuilder(
                      valueListenable: HomeCardPreferences.decorationNotifier,
                      builder: (context, decorationsEnabled, child) {
                        return Container(
                          decoration: decorationsEnabled
                              ? BoxDecoration(
                                  gradient: LinearGradient(
                                    begin: Alignment.topCenter,
                                    end: Alignment.bottomCenter,
                                    colors: [
                                      BracuPalette.bgTop(context),
                                      BracuPalette.bgBottom(context),
                                    ],
                                  ),
                                )
                              : null,
                          child: Center(
                            child: Container(
                              width: shellWidth,
                              height: shellHeight,
                              margin: const EdgeInsets.symmetric(vertical: 0),
                              decoration: BoxDecoration(
                                color: Theme.of(
                                  context,
                                ).scaffoldBackgroundColor,
                                borderRadius: BorderRadius.circular(
                                  kIsWeb ? 32 : 0,
                                ),
                                boxShadow: kIsWeb
                                    ? [
                                        BoxShadow(
                                          color: Colors.black.withValues(
                                            alpha: 0.16,
                                          ),
                                          blurRadius: 30,
                                          offset: const Offset(0, 16),
                                        ),
                                      ]
                                    : null,
                              ),
                              clipBehavior: Clip.antiAlias,
                              child: MediaQuery(
                                data: shellMediaQuery,
                                child: content,
                              ),
                            ),
                          ),
                        );
                      },
                    );
                  },
                ),
              );
            },
            navigatorKey: _navigatorKey,
            routes: {
              '/login': (context) => const LoginPage(),
              '/home': (context) => HomePage(
                initialTab:
                    _resolvedBootstrapState?.initialHomeTab ??
                    HomeTab.dashboard,
              ),
              '/onboarding': (context) => const OnboardingPage(),
            },
            home: _resolvedBootstrapState == null
                ? const _StartupFrame()
                : (_initialLoggedIn || _canOpenOffline)
                ? HomePage(
                    initialTab:
                        _resolvedBootstrapState?.initialHomeTab ??
                        HomeTab.dashboard,
                  )
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
      backgroundColor: Colors.transparent,
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              BracuPalette.bgTop(context),
              BracuPalette.bgBottom(context),
            ],
          ),
        ),
        child: Center(
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 20),
            padding: const EdgeInsets.all(24),
            constraints: const BoxConstraints(maxWidth: 320),
            decoration: BoxDecoration(
              color: Theme.of(context).scaffoldBackgroundColor,
              borderRadius: BorderRadius.circular(28),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.12),
                  blurRadius: 28,
                  offset: const Offset(0, 16),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.school_outlined,
                  size: 30,
                  color: BracuPalette.primary,
                ),
                const SizedBox(height: 14),
                Text(
                  'PreConnect',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: BracuPalette.textSecondary(context),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
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
