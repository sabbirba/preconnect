import 'dart:async';
import 'dart:convert';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:clock/clock.dart';
import 'package:preconnect/tools/http/http_utils.dart';
import 'package:preconnect/tools/runtime_stub.dart'
    if (dart.library.html) 'package:preconnect/tools/runtime_web.dart';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:in_app_update/in_app_update.dart';
import 'package:preconnect/api/analytics.dart';
import 'package:preconnect/api/api_config.dart';
import 'package:preconnect/api/fcm.dart';
import 'package:preconnect/tools/app_storage.dart';
import 'package:preconnect/tools/app_log_observer.dart';
import 'package:preconnect/api/preferences_store.dart';
import 'package:preconnect/api/auth.dart';
import 'package:preconnect/api/custom_schedules.dart';
import 'package:preconnect/api/profile.dart';
import 'package:preconnect/api/schedule.dart';
import 'package:preconnect/api/api_client.dart';
import 'package:preconnect/api/cdn_warmup.dart';
import 'package:preconnect/pages/home.dart';
import 'package:preconnect/pages/home_tab.dart';
import 'package:preconnect/pages/class_schedule.dart';
import 'package:preconnect/pages/exam_schedule.dart';
import 'package:preconnect/pages/onboarding.dart';
import 'package:preconnect/pages/captive_wifi.dart';
import 'package:preconnect/pages/student_profile.dart';
import 'package:preconnect/pages/ui_kit.dart';
import 'package:preconnect/pages/wifi_printer.dart';
import 'package:preconnect/pages/shared_widgets/session_helper.dart';
import 'package:preconnect/tools/preconnect_constants.dart';
import 'package:preconnect/tools/quiet_controller.dart';
import 'package:preconnect/tools/token_storage.dart';
import 'package:preconnect/tools/refresh_bus.dart';
import 'package:preconnect/tools/storage_keys.dart';
import 'package:preconnect/tools/shortcut_stub.dart'
    if (dart.library.html) 'package:preconnect/tools/shortcut_web.dart';

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
  const MyApp({super.key, this.bootstrapState, this.isPreBoot = false});

  final AppBootstrapState? bootstrapState;
  final bool isPreBoot;

  static Future<AppBootstrapState> bootstrap() async {
    if (kIsWeb && !isChromeRuntimeAvailable()) {
      final code = Uri.base.queryParameters['code'];
      if (code != null && code.trim().isNotEmpty) {
        try {
          final storedVerifier = await TokenStorage.instance.read(
            key: PreConnectStorageKeys.pkceVerifier,
          );
          await TokenStorage.instance.write(
            key: PreConnectStorageKeys.pkceVerifier,
            value: null,
          );
          final uri = Uri.parse(ApiConfig.tokenEndpoint);
          final body = HttpUtils.formBody(<String, String>{
            'grant_type': 'authorization_code',
            'client_id': ApiConfig.clientId,
            'code': code.trim(),
            'redirect_uri': ApiConfig.redirectUri,
            if (storedVerifier != null && storedVerifier.isNotEmpty)
              'code_verifier': storedVerifier,
          });
          final response = await HttpUtils.client
              .post(
                uri,
                headers: <String, String>{
                  'Content-Type': 'application/x-www-form-urlencoded',
                },
                body: body,
              )
              .timeout(const Duration(seconds: 10));

          if (response.statusCode == 200) {
            final data = json.decode(response.body);
            if (data is Map<String, dynamic>) {
              final accessToken = data['access_token'] as String?;
              final refreshToken = data['refresh_token'] as String?;
              final idToken = data['id_token'] as String?;
              if (accessToken != null &&
                  accessToken.isNotEmpty &&
                  refreshToken != null &&
                  refreshToken.isNotEmpty) {
                await Future.wait([
                  TokenStorage.instance.write(
                    key: PreConnectStorageKeys.accessToken,
                    value: accessToken,
                  ),
                  TokenStorage.instance.write(
                    key: PreConnectStorageKeys.refreshToken,
                    value: refreshToken,
                  ),
                  if (idToken != null && idToken.isNotEmpty)
                    TokenStorage.instance.write(
                      key: PreConnectStorageKeys.idToken,
                      value: idToken,
                    ),
                ]);
              }
            }
          }
        } catch (_) {
        } finally {
          cleanUrlCodeParameter();
        }
      }
      final shortcut = Uri.base.queryParameters['shortcut'];
      if (shortcut != null && shortcut.trim().isNotEmpty) {
        await TokenStorage.instance.write(
          key: PreConnectStorageKeys.pendingShortcutAction,
          value: shortcut.trim(),
        );
      }
    }

    final prefs = AppStorage.instance;
    final savedTheme = await prefs.getString(StorageKeys.themeMode) ?? 'system';
    final initialHomeTab = _decodeHomeTab(
      await prefs.getString(StorageKeys.homeTab),
    );

    final token = await TokenStorage.instance.read(
      key: PreConnectStorageKeys.accessToken,
    );
    final refreshToken = await TokenStorage.instance.read(
      key: PreConnectStorageKeys.refreshToken,
    );
    final tokenPresent = token != null && token.isNotEmpty;
    final refreshTokenPresent = refreshToken != null && refreshToken.isNotEmpty;
    final hasToken = tokenPresent && refreshTokenPresent;

    if (!hasToken) {
      await prefs.setBool(PreConnectStorageKeys.cachedHasAuthSession, false);
      final keepKeys = <String>{
        PreConnectStorageKeys.accessToken,
        PreConnectStorageKeys.refreshToken,
        StorageKeys.themeMode,
        CustomSchedulesService.cacheKey,
        HomeCardPreferences.showQuickAccessSectionKey,
        HomeCardPreferences.showRamadanCardKey,
        HomeCardPreferences.showExamCountdownCardKey,
        HomeCardPreferences.showTodayScheduleKey,
        HomeCardPreferences.showDecorationsKey,
        HomeCardPreferences.showCampusMapContactsKey,
        HomeCardPreferences.showFundingSectionKey,
      };
      await AppPreferencesStore().clearAllExcept(keepKeys);
    } else {
      await prefs.setBool(PreConnectStorageKeys.cachedHasAuthSession, true);
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

  static AppBootstrapState bootstrapSync() {
    final prefs = AppStorage.instance;
    final savedTheme = prefs.getStringSync(StorageKeys.themeMode) ?? 'system';
    final initialHomeTab = _decodeHomeTab(
      prefs.getStringSync(StorageKeys.homeTab),
    );

    final hasToken =
        prefs.getBoolSync(PreConnectStorageKeys.cachedHasAuthSession) ?? false;
    final canOpenOffline = hasToken && _hasOfflineSnapshotSync();

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

  static bool _hasOfflineSnapshotSync() {
    final prefs = AppStorage.instance;
    final studentId = (prefs.getStringSync(StorageKeys.studentId) ?? '').trim();
    final fullName = (prefs.getStringSync(StorageKeys.fullName) ?? '').trim();
    final schedule = (prefs.getStringSync(StorageKeys.studentSchedule) ?? '')
        .trim();
    if (schedule.isNotEmpty) return true;
    return studentId.isNotEmpty && fullName.isNotEmpty;
  }

  static Future<void> _warmStartupCaches({bool forceRefresh = false}) async {
    final tasks = _buildWarmupTasks(
      includeCampusPrinter: false,
      forceRefresh: forceRefresh,
    );
    await Future.wait(tasks.map((task) => task.catchError((_) {})));
  }

  static List<Future<void>> _buildWarmupTasks({
    required bool includeCampusPrinter,
    bool forceRefresh = false,
  }) {
    final tasks = <Future<void>>[
      preloadHomeDashboardData(forceRefresh: forceRefresh).then((_) {}),
      ProfileService().getProfile(fromFetch: forceRefresh).then((_) {}),
      () async {
        final semesterSessionId =
            await resolveCurrentSessionSemesterIdWithRetry();
        if (semesterSessionId == null) return;
        await ScheduleService().getStudentScheduleForSemester(
          semesterSessionId: semesterSessionId,
          fromFetch: forceRefresh,
        );
      }(),
      StudentProfile.preload(forceRefresh: forceRefresh),
      ClassSchedule.preload(forceRefresh: forceRefresh),
      ExamSchedule.preload(forceRefresh: forceRefresh),
    ];
    if (includeCampusPrinter) {
      tasks.add(CampusPrinterPage.preload());
    }
    return tasks;
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
    if (value.isEmpty || value == 'moreQuickAccess') return HomeTab.dashboard;
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
  final _RouteTrackingObserver _routeObserver = _RouteTrackingObserver();
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
  StreamSubscription<List<ConnectivityResult>>? _connectivitySub;
  bool _lastWasOffline = false;
  DateTime? _lastAppRefreshAt;
  bool _appRefreshInFlight = false;

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
    if (!widget.isPreBoot) {
      unawaited(_bootstrapInBackground());
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
        unawaited(_warmPublicCdnCaches());
        if (_supportsInAppUpdates) {
          unawaited(_maybeCheckForUpdates());
        }
        unawaited(_runDeferredStartupWork());
      });
      unawaited(FCMService.instance.init());
      _connectivitySub = Connectivity().onConnectivityChanged.listen(
        _onConnectivityChanged,
      );
    }
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
      if (_initialLoggedIn) {
        unawaited(triggerAppRefresh());
      }
    } catch (_) {
      if (!mounted) return;
      _resolvedBootstrapState = const AppBootstrapState(
        themeMode: ThemeMode.system,
        isLoggedIn: false,
        canOpenOffline: false,
        initialHomeTab: HomeTab.dashboard,
      );
      _initialLoggedIn = false;
      _canOpenOffline = false;
      _themeMode.value = ThemeMode.system;
      setState(() {});
    }
  }

  Future<void> _setupQuickAccessShortcuts() async {
    try {
      await _consumePendingShortcutAction();
    } catch (_) {}
  }

  bool get _supportsInAppUpdates =>
      kReleaseMode &&
      !kIsWeb &&
      defaultTargetPlatform == TargetPlatform.android;

  Future<void> _runDeferredStartupWork() async {
    await Future<void>.delayed(const Duration(milliseconds: 1800));
    if (!mounted) return;
    await _loadDeferredServices();
    unawaited(_setupQuickAccessShortcuts());
    if (_initialLoggedIn) {
      _validateSessionInBackground();
    }
  }

  Future<void> _loadDeferredServices() async {
    if (kIsWeb) return;
  }

  Future<void> _warmPublicCdnCaches() async {
    await CdnWarmupService.instance.warmPublicCdnData();
  }

  Future<void> _consumePendingShortcutAction() async {
    final pendingAction = kIsWeb
        ? await TokenStorage.instance.read(
            key: PreConnectStorageKeys.pendingShortcutAction,
          )
        : await AppStorage.instance.getString(
            PreConnectStorageKeys.pendingShortcutAction,
          );
    if (pendingAction == null || pendingAction.isEmpty) return;
    await _clearPendingShortcutAction();
    _handleShortcutAction(pendingAction);
  }

  Future<bool> _maybeCheckForUpdates() async {
    if (!_supportsInAppUpdates) return false;
    try {
      final info = await InAppUpdate.checkForUpdate();
      final availability = info.updateAvailability;
      final installStatus = info.installStatus;

      if (installStatus == InstallStatus.downloaded ||
          availability ==
              UpdateAvailability.developerTriggeredUpdateInProgress) {
        await InAppUpdate.completeFlexibleUpdate();
        return true;
      }

      if (availability == UpdateAvailability.updateAvailable) {
        if (info.flexibleUpdateAllowed) {
          final result = await InAppUpdate.startFlexibleUpdate();
          if (result == AppUpdateResult.success) {
            return true;
          }
        }

        if (info.immediateUpdateAllowed) {
          final result = await InAppUpdate.performImmediateUpdate();
          return result == AppUpdateResult.success;
        }
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_consumePendingShortcutAction());
      unawaited(_refreshAndUnlockIfNeeded());
      unawaited(QuietModeController.instance.refresh());
      if (_initialLoggedIn) {
        unawaited(triggerAppRefresh());
      }
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

  void _onConnectivityChanged(List<ConnectivityResult> results) {
    final isOffline =
        results.isEmpty || results.every((r) => r == ConnectivityResult.none);
    if (isOffline) {
      _lastWasOffline = true;
      return;
    }
    if (!_lastWasOffline) return;
    _lastWasOffline = false;
    unawaited(triggerAppRefresh(forceRefresh: true));
  }

  Future<void> triggerAppRefresh({bool forceRefresh = false}) async {
    if (_appRefreshInFlight) return;
    final now = clock.now();
    if (!forceRefresh &&
        _lastAppRefreshAt != null &&
        now.difference(_lastAppRefreshAt!) < const Duration(seconds: 30)) {
      return;
    }
    _appRefreshInFlight = true;
    _lastAppRefreshAt = now;
    try {
      if (await ApiClient().hasConnection()) {
        ApiClient().clearTransientCaches();
        await Future.wait<void>([
          CdnWarmupService.instance.warmPublicCdnData(forceRefresh: true),
          if (_initialLoggedIn) _warmBackgroundCaches(forceRefresh: true),
        ]);
        RefreshBus.instance.notify(reason: 'class_schedule');
        RefreshBus.instance.notify(reason: 'exam_schedule');
        RefreshBus.instance.notify(reason: 'student_profile');
        RefreshBus.instance.notify(reason: 'home_dashboard');
        RefreshBus.instance.notify(reason: 'degree_progress');
        RefreshBus.instance.notify(reason: 'calendar');
        RefreshBus.instance.notify(reason: 'notifications');
      }
    } catch (_) {
    } finally {
      _appRefreshInFlight = false;
    }
  }

  @override
  void dispose() {
    _connectivitySub?.cancel();
    if (!widget.isPreBoot) {
      _webSessionSub?.cancel();
      _webExtensionSessionFlow?.dispose();
      unawaited(_webShortcutBridge?.dispose());
      if (!kIsWeb) {
        unbindRefreshBus(_onRefreshSignal);
      }
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
    AuthService.navigatorKey.currentState?.pushAndRemoveUntil(
      MaterialPageRoute(builder: (context) => const OnboardingPage()),
      (route) => false,
    );
  }

  void _onRefreshSignal() {
    if (!mounted) return;
    if (isRefreshingFrom('app_lock_settings_changed')) {
      unawaited(_refreshAndUnlockIfNeeded());
    }
    if (isRefreshingFrom('auth')) {
      unawaited(() async {
        final loggedIn = await AuthService().isLoggedIn();
        if (mounted) {
          setState(() {
            _initialLoggedIn = loggedIn;
            _canOpenOffline = loggedIn;
          });
          if (!loggedIn) {
            _themeMode.value = ThemeMode.system;
            AuthService.navigatorKey.currentState?.pushAndRemoveUntil(
              MaterialPageRoute(builder: (context) => const OnboardingPage()),
              (route) => false,
            );
          }
        }
      }());
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
    if (action == 'captive_wifi') {
      _openCaptiveWifi();
      return;
    }
    final tab = _tabFromShortcutAction(action);
    if (tab == null) return;
    _openHomeTab(tab);
    unawaited(_clearPendingShortcutAction());
  }

  void _openCaptiveWifi() {
    final navigator = AuthService.navigatorKey.currentState;
    if (navigator != null) {
      navigator.push(
        MaterialPageRoute(builder: (context) => const CaptiveWifiPage()),
      );
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        AuthService.navigatorKey.currentState?.push(
          MaterialPageRoute(builder: (context) => const CaptiveWifiPage()),
        );
      });
    }
    unawaited(_clearPendingShortcutAction());
  }

  Future<void> _clearPendingShortcutAction() async {
    if (kIsWeb) {
      await TokenStorage.instance.write(
        key: PreConnectStorageKeys.pendingShortcutAction,
        value: null,
      );
      return;
    }
    await AppStorage.instance.remove(
      PreConnectStorageKeys.pendingShortcutAction,
    );
  }

  void _openHomeTab(HomeTab tab) {
    if (!_initialLoggedIn && !_canOpenOffline) return;
    HomePage.requestShortcutTab(tab);
    final navigator = AuthService.navigatorKey.currentState;
    if (navigator != null) {
      navigator.pushAndRemoveUntil(
        MaterialPageRoute(builder: (context) => HomePage(initialTab: tab)),
        (route) => false,
      );
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      AuthService.navigatorKey.currentState?.pushAndRemoveUntil(
        MaterialPageRoute(builder: (context) => HomePage(initialTab: tab)),
        (route) => false,
      );
    });
  }

  HomeTab? _tabFromShortcutAction(String action) {
    switch (action) {
      case PreConnectBrowserActionIds.shortcutCustomSchedule:
      case 'customSchedule':
      case 'custom_schedule':
        return HomeTab.personalSchedules;
      case PreConnectBrowserActionIds.shortcutProfile:
      case 'profile':
        return HomeTab.profile;
      case PreConnectBrowserActionIds.shortcutClasses:
      case 'classes':
        return HomeTab.studentSchedule;
      case PreConnectBrowserActionIds.shortcutExams:
      case 'exams':
        return HomeTab.examSchedule;
      case PreConnectBrowserActionIds.shortcutFriends:
      case 'friends':
        return HomeTab.friendSchedule;
      case PreConnectBrowserActionIds.shortcutShare:
      case 'share':
        return HomeTab.shareSchedule;
      case PreConnectBrowserActionIds.shortcutScan:
      case 'scan':
        return HomeTab.scanSchedule;
      case PreConnectBrowserActionIds.shortcutSeatStatus:
      case 'seatStatus':
      case 'seat_status':
        return HomeTab.seatStatus;
      case PreConnectBrowserActionIds.shortcutNotifications:
      case 'notifications':
        return HomeTab.notifications;
      default:
        return null;
    }
  }

  Future<void> _warmBackgroundCaches({bool forceRefresh = false}) async {
    if (_backgroundWarmupInFlight) return;
    final now = clock.now();
    if (!forceRefresh &&
        _lastBackgroundWarmupAt != null &&
        now.difference(_lastBackgroundWarmupAt!) < const Duration(minutes: 1)) {
      return;
    }
    _backgroundWarmupInFlight = true;
    _lastBackgroundWarmupAt = now;
    try {
      final tasks = MyApp._buildWarmupTasks(
        includeCampusPrinter: false,
        forceRefresh: forceRefresh,
      );
      await Future.wait(tasks.map((task) => task.catchError((_) {})));
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
    final unlocked = await AppLockService().authenticate();
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
        AuthService.navigatorKey.currentState?.pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const OnboardingPage()),
          (route) => false,
        );
      }
    } catch (_) {}
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
            title: 'PreConnect',
            debugShowCheckedModeBanner: false,
            theme: lightTheme,
            darkTheme: darkTheme,
            themeMode: mode,
            navigatorKey: widget.isPreBoot ? null : AuthService.navigatorKey,
            navigatorObservers: [
              _routeObserver,
              AnalyticsService.observer,
              AppLogNavigatorObserver(),
            ],
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
                  if (_appLockEnabled &&
                      !_isUnlocked &&
                      !_routeObserver.isBypassedRoute)
                    Positioned.fill(child: _buildLockLayer(context)),
                ],
              );
              return AnnotatedRegion<SystemUiOverlayStyle>(
                value: overlayStyle,
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final isWide = constraints.maxWidth >= 480.0;
                    final shellWidth = isWide ? 480.0 : constraints.maxWidth;
                    final shellHeight = mediaQuery.size.height;
                    final shellSize = Size(shellWidth, shellHeight);
                    final shellMediaQuery = mediaQuery.copyWith(
                      size: shellSize,
                    );
                    return ValueListenableBuilder(
                      valueListenable: HomeCardPreferences.decorationNotifier,
                      builder: (context, decorationsEnabled, child) {
                        final baseColor = Theme.of(
                          context,
                        ).scaffoldBackgroundColor;
                        return Stack(
                          children: [
                            Positioned.fill(
                              child: Container(
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
                                    : BoxDecoration(color: baseColor),
                              ),
                            ),
                            Center(
                              child: Container(
                                width: shellWidth,
                                height: shellHeight,
                                margin: const EdgeInsets.symmetric(vertical: 0),
                                decoration: BoxDecoration(
                                  color: Theme.of(
                                    context,
                                  ).scaffoldBackgroundColor,
                                  borderRadius: BorderRadius.circular(
                                    isWide ? 32 : 0,
                                  ),
                                  boxShadow: isWide
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
                          ],
                        );
                      },
                    );
                  },
                ),
              );
            },

            home: _resolvedBootstrapState == null
                ? const StartupFrame()
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

class _RouteTrackingObserver extends NavigatorObserver {
  Route<dynamic>? _currentRoute;

  bool get isBypassedRoute {
    return _currentRoute?.settings.name == '/secure_access' &&
        _currentRoute?.settings.arguments ==
            PreConnectRouteTokens.privateAccess;
  }

  void _update(Route<dynamic>? route) {
    _currentRoute = route;
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _update(route);
    super.didPush(route, previousRoute);
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _update(previousRoute);
    super.didPop(route, previousRoute);
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    _update(newRoute);
    super.didReplace(newRoute: newRoute, oldRoute: oldRoute);
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _update(previousRoute);
    super.didRemove(route, previousRoute);
  }
}

class StartupFrame extends StatelessWidget {
  const StartupFrame({super.key});

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
