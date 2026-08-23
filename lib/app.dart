import 'dart:async';
import 'dart:convert';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:preconnect/tools/runtime_stub.dart'
    if (dart.library.js_interop) 'package:preconnect/tools/runtime_web.dart';

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:gap/gap.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:http/http.dart' as http;
import 'package:preconnect/api/fcm.dart';
import 'package:preconnect/features/auth/data/oauth_exchange.dart';
import 'package:preconnect/features/auth/application/auth_bridge.dart';
import 'package:preconnect/tools/app_storage.dart';
import 'package:preconnect/api/auth.dart';
import 'package:preconnect/libsync/auth_service.dart';
import 'package:preconnect/api/api_client.dart';
import 'package:preconnect/api/mercure_service.dart';
import 'package:preconnect/pages/home.dart';
import 'package:preconnect/pages/login.dart';
import 'package:preconnect/pages/wifi_printer.dart';
import 'package:preconnect/pages/home_tab.dart';
import 'package:preconnect/pages/onboarding.dart';
import 'package:preconnect/pages/advising_helper.dart';
import 'package:preconnect/pages/captive_wifi.dart';
import 'package:preconnect/pages/ui_kit.dart';
import 'package:preconnect/pages/shared_widgets/map_shared.dart';
import 'package:preconnect/pages/devs.dart';
import 'package:preconnect/api/funding.dart';
import 'package:preconnect/tools/app_navigator.dart';
import 'package:preconnect/tools/preconnect_constants.dart';
import 'package:preconnect/tools/quiet_controller.dart';
import 'package:app_links/app_links.dart';
import 'package:preconnect/tools/token_storage.dart';
import 'package:preconnect/tools/refresh_bus.dart';
import 'package:preconnect/tools/storage_keys.dart';
import 'package:preconnect/tools/store_actions.dart';
import 'package:preconnect/tools/shortcut_stub.dart'
    if (dart.library.js_interop) 'package:preconnect/tools/shortcut_web.dart';
import 'package:url_launcher/url_launcher.dart';

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
  const MyApp({super.key, required this.bootstrapState});

  final AppBootstrapState bootstrapState;

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
          await OAuthCodeExchange().exchangeAndPersist(
            code: code,
            verifier: storedVerifier,
          );
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

    final hasToken =
        prefs.getBoolSync(PreConnectStorageKeys.cachedHasAuthSession) ?? false;

    final canOpenOffline = hasToken && await _hasOfflineSnapshot();

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
      unawaited(MercureService().connect());
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
    try {
      unawaited(MercureService().connect());
      unawaited(fetchCampusMapData(forceRefresh: forceRefresh));
      unawaited(fetchTransportScheduleUrl(forceRefresh: forceRefresh));
      unawaited(FundingService.fetchStatus(forceRefresh: forceRefresh));
      unawaited(DevsPage.preload(forceRefresh: forceRefresh));
    } catch (_) {}
  }

  static void warmStartupCaches() {
    unawaited(_warmStartupCaches());
  }

  static Future<void> warmStartupCachesAsync({bool forceRefresh = false}) {
    return _warmStartupCaches(forceRefresh: forceRefresh);
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
  late final ThemeData _cachedLightTheme = _buildTheme(
    brightness: Brightness.light,
    scaffoldBackgroundColor: Colors.white,
    primary: const Color(0xFF1E6BE3),
    secondary: const Color(0xFF22B573),
    foreground: Colors.black87,
  );
  late final ThemeData _cachedDarkTheme = _buildTheme(
    brightness: Brightness.dark,
    scaffoldBackgroundColor: Colors.black,
    primary: const Color(0xFF1E6BE3),
    secondary: const Color(0xFF22B573),
    foreground: Colors.white,
    surface: Colors.black,
    onSurface: Colors.white,
    dialogTheme: const DialogThemeData(backgroundColor: Colors.black),
  );
  final _RouteTrackingObserver _routeObserver = _RouteTrackingObserver();
  late bool _initialLoggedIn;
  late bool _canOpenOffline;
  late AppBootstrapState _resolvedBootstrapState;
  bool _appLockEnabled = false;
  bool _isUnlocked = true;
  bool _isUnlocking = false;
  WebExtensionSessionFlow? _webExtensionSessionFlow;
  StreamSubscription<WebExtensionSessionEvent>? _webSessionSub;
  WebExtensionShortcutBridge? _webShortcutBridge;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySub;
  StreamSubscription<Uri?>? _deepLinkSub;
  DateTime? _lastAppRefreshAt;
  bool _appRefreshInFlight = false;
  bool _logoutNavigationInFlight = false;

  @override
  void initState() {
    super.initState();
    _configurePresentationBridges();
    _resolvedBootstrapState = widget.bootstrapState;
    _initialLoggedIn = widget.bootstrapState.isLoggedIn;
    _canOpenOffline = widget.bootstrapState.canOpenOffline;
    _themeMode = ValueNotifier<ThemeMode>(widget.bootstrapState.themeMode);
    WidgetsBinding.instance.addObserver(this);
    if (!_initialLoggedIn) {
      unawaited(_bootstrapInBackground());
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        unawaited(triggerAppRefresh());
      });
    }
    if (kIsWeb) {
      _webExtensionSessionFlow = WebExtensionSessionFlow();
      _webSessionSub = _webExtensionSessionFlow!.events.listen(
        _handleWebExtensionSessionEvent,
      );
      _webShortcutBridge = WebExtensionShortcutBridge(
        onShortcut: _handleShortcutAction,
      );
    } else {
      unawaited(_initializeAppLock());
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
    if (!kIsWeb) {
      _initDeepLinkListener();
    }
  }

  void _configurePresentationBridges() {
    AuthUiBridge.configure(
      openLogoutView: (idToken) async {
        final context = AppNavigator.key.currentContext;
        if (context == null || !context.mounted) return false;
        await LoginPage.openLogoutWebView(context, idToken: idToken);
        return true;
      },
      clearLoginArtifacts: LoginPage.clearSessionArtifacts,
      clearPrinterArtifacts: CampusPrinterPage.clearStoredState,
      completeLogout: _completeLogoutNavigation,
    );
    FCMService.instance.configureNavigation(
      openCaptiveWifi: () {
        AppNavigator.key.currentState?.push(
          MaterialPageRoute(builder: (_) => const CaptiveWifiPage()),
        );
      },
      openUrl: (url) async {
        final context = AppNavigator.key.currentContext;
        if (context != null && context.mounted) {
          await openExternalUrl(context, url);
          return;
        }
        await launchUrl(Uri.parse(url), mode: LaunchMode.inAppBrowserView);
      },
    );
  }

  @override
  void didHaveMemoryPressure() {
    super.didHaveMemoryPressure();
    PaintingBinding.instance.imageCache.clear();
    PaintingBinding.instance.imageCache.clearLiveImages();
  }

  void _initDeepLinkListener() {
    final appLinks = AppLinks();
    _deepLinkSub = appLinks.uriLinkStream.listen((uri) {
      _handleIncomingDeepLink(uri);
    }, onError: (err) {});

    appLinks
        .getInitialLink()
        .then((uri) {
          if (uri != null) {
            _handleIncomingDeepLink(uri);
          }
        })
        .catchError((_) {});
  }

  void _handleIncomingDeepLink(Uri uri) {
    if (uri.host == 'preconnect.app' &&
        uri.path.startsWith('/api/auth/callback')) {
      final accessToken = uri.queryParameters['google_access_token'];
      final refreshToken = uri.queryParameters['google_refresh_token'];
      if (accessToken != null && accessToken.isNotEmpty) {
        unawaited(
          LibSyncAuthService.instance
              .authenticateWithTokens(
                googleAccessToken: accessToken,
                googleRefreshToken: refreshToken,
              )
              .then((_) {
                if (mounted) {
                  unawaited(triggerAppRefresh(forceRefresh: true));
                }
              }),
        );
        return;
      }
      final code = uri.queryParameters['code'];
      if (code != null && code.isNotEmpty) {
        unawaited(
          LibSyncAuthService.instance.authenticateWithCode(code).then((_) {
            if (mounted) {
              unawaited(triggerAppRefresh(forceRefresh: true));
            }
          }),
        );
      }
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
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  Future<void> _runDeferredStartupWork() async {
    await Future<void>.delayed(Duration.zero);
    if (!mounted) return;
    await _loadDeferredServices();
    unawaited(_setupQuickAccessShortcuts());
    if (_initialLoggedIn) {
      _validateSessionInBackground();
    }
  }

  Future<void> _loadDeferredServices() async {
    if (kIsWeb) {
      unawaited(
        Future<void>.value().then((_) {
          LibSyncAuthService.instance.initialize();
        }),
      );
      return;
    }
  }

  Future<void> _warmPublicCdnCaches() async {}

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
      if (defaultTargetPlatform == TargetPlatform.iOS) {
        final packageInfo = await PackageInfo.fromPlatform();
        final localVersion = packageInfo.version;
        final bundleId = packageInfo.packageName;

        final response = await http.get(
          Uri.parse('https://itunes.apple.com/lookup?bundleId=$bundleId'),
        );
        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);
          if (data != null &&
              data['resultCount'] != null &&
              data['resultCount'] > 0) {
            final results = data['results'] as List<dynamic>;
            if (results.isNotEmpty) {
              final storeVersion = results[0]['version'] as String;
              final appStoreId = results[0]['trackId']?.toString() ?? '';
              if (storeVersion.compareTo(localVersion) > 0) {
                final targetId = appStoreId.isEmpty ? '6791423431' : appStoreId;
                await launchUrl(
                  Uri.parse(
                    'https://apps.apple.com/us/app/preconnect-bracu-student-app/id$targetId',
                  ),
                  mode: LaunchMode.externalApplication,
                );
                return true;
              }
            }
          }
        }
        return false;
      }

      final info = await StoreActions.checkForUpdate();
      final availability = info['updateAvailability'] as int?;
      final installStatus = info['installStatus'] as int?;

      if (installStatus == StoreUpdateStatus.downloaded ||
          availability == StoreUpdateStatus.inProgress) {
        await StoreActions.completeUpdate();
        return true;
      }

      if (availability == StoreUpdateStatus.available) {
        if (info['isFlexibleUpdateAllowed'] == true) {
          await StoreActions.startUpdate(immediate: false);
          StoreActions.updateEvents.listen((state) {
            if (state['status'] == StoreUpdateStatus.downloaded) {
              unawaited(StoreActions.completeUpdate());
            }
          });
          return true;
        }

        if (info['isImmediateUpdateAllowed'] == true) {
          final result = await StoreActions.startUpdate(immediate: true);
          return result == StoreUpdateStatus.success;
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
      return;
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

  void _onConnectivityChanged(List<ConnectivityResult> results) {
    final isOnline =
        results.isNotEmpty && results.any((r) => r != ConnectivityResult.none);
    if (isOnline) {
      unawaited(triggerAppRefresh(forceRefresh: true));
    }
  }

  Future<void> triggerAppRefresh({bool forceRefresh = false}) async {
    if (_appRefreshInFlight) return;
    final now = DateTime.now();
    if (!forceRefresh &&
        _lastAppRefreshAt != null &&
        now.difference(_lastAppRefreshAt!) < const Duration(seconds: 30)) {
      return;
    }
    _appRefreshInFlight = true;
    _lastAppRefreshAt = now;
    try {
      final connectivity = await Connectivity().checkConnectivity();
      final isOffline =
          connectivity.isEmpty ||
          connectivity.every((r) => r == ConnectivityResult.none);
      if (!isOffline) {
        ApiClient().clearTransientCaches();
        final activeTab = _resolvedBootstrapState.initialHomeTab;
        final activeReason = switch (activeTab) {
          HomeTab.studentSchedule => 'class_schedule',
          HomeTab.examSchedule => 'exam_schedule',
          HomeTab.profile => 'student_profile',
          HomeTab.dashboard => 'home_dashboard',
          HomeTab.degreeProgress => 'degree_progress',
          HomeTab.notifications => 'notifications',
          _ => 'home_dashboard',
        };
        RefreshBus.instance.notify(reason: activeReason);
      }
    } catch (_) {
    } finally {
      _appRefreshInFlight = false;
    }
  }

  @override
  void dispose() {
    _connectivitySub?.cancel();
    _deepLinkSub?.cancel();
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
    unawaited(_completeLogoutNavigation());
  }

  Future<void> _completeLogoutNavigation() async {
    if (!mounted || _logoutNavigationInFlight) return;
    _logoutNavigationInFlight = true;
    _initialLoggedIn = false;
    _canOpenOffline = false;
    _resolvedBootstrapState = const AppBootstrapState(
      themeMode: ThemeMode.system,
      isLoggedIn: false,
      canOpenOffline: false,
      initialHomeTab: HomeTab.dashboard,
    );

    final navigator = AppNavigator.key.currentState;
    if (navigator != null) {
      navigator.pushAndRemoveUntil(
        PageRouteBuilder<void>(
          pageBuilder: (context, animation, secondaryAnimation) =>
              const OnboardingPage(),
          transitionDuration: const Duration(milliseconds: 220),
          reverseTransitionDuration: const Duration(milliseconds: 160),
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            return FadeTransition(
              opacity: CurvedAnimation(
                parent: animation,
                curve: Curves.easeOutCubic,
              ),
              child: child,
            );
          },
        ),
        (route) => false,
      );
    }

    await Future<void>.delayed(const Duration(milliseconds: 240));
    if (mounted) {
      _themeMode.value = ThemeMode.system;
      setState(() {});
    }
    _logoutNavigationInFlight = false;
  }

  void _onRefreshSignal() {
    if (!mounted) return;
    if (isRefreshingFrom('app_lock_settings_changed')) {
      unawaited(_refreshAndUnlockIfNeeded());
    }
    if (isRefreshingFrom('auth')) {
      unawaited(() async {
        final loggedIn = await AuthService().isLoggedIn();
        if (!mounted) return;
        if (!loggedIn) {
          await _completeLogoutNavigation();
        } else {
          setState(() {
            _initialLoggedIn = true;
            _canOpenOffline = true;
          });
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
    if (action == PreConnectBrowserActionIds.shortcutAdvisingHelper ||
        action == 'advising_helper' ||
        action == 'advisingHelper') {
      _openAdvisingHelper();
      return;
    }
    final tab = _tabFromShortcutAction(action);
    if (tab == null) return;
    _openHomeTab(tab);
    unawaited(_clearPendingShortcutAction());
  }

  void _openAdvisingHelper() {
    final navigator = AppNavigator.key.currentState;
    if (navigator != null) {
      navigator.push(
        MaterialPageRoute(builder: (context) => const AdvisingHelperPage()),
      );
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        AppNavigator.key.currentState?.push(
          MaterialPageRoute(builder: (context) => const AdvisingHelperPage()),
        );
      });
    }
    unawaited(_clearPendingShortcutAction());
  }

  void _openCaptiveWifi() {
    final navigator = AppNavigator.key.currentState;
    if (navigator != null) {
      navigator.push(
        MaterialPageRoute(builder: (context) => const CaptiveWifiPage()),
      );
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        AppNavigator.key.currentState?.push(
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
    final navigator = AppNavigator.key.currentState;
    if (navigator != null) {
      navigator.pushAndRemoveUntil(
        MaterialPageRoute(builder: (context) => HomePage(initialTab: tab)),
        (route) => false,
      );
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      AppNavigator.key.currentState?.pushAndRemoveUntil(
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
      case PreConnectBrowserActionIds.shortcutScan:
      case 'scan':
        return HomeTab.friendSchedule;
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
            const Gap(120),
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
                  const Gap(12),
                  Text(
                    'App Locked',
                    style: TextStyle(
                      color: BracuPalette.textPrimary(context),
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      decoration: TextDecoration.none,
                    ),
                  ),
                  const Gap(12),
                  Text(
                    'Use your system lock to continue',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: BracuPalette.textSecondary(context),
                      fontSize: 12,
                      decoration: TextDecoration.none,
                    ),
                  ),
                  const Gap(12),
                  BracuActionButton(
                    onPressed: _isUnlocking
                        ? null
                        : () {
                            unawaited(_unlockApp());
                          },
                    icon: Icons.fingerprint,
                    label: 'Unlock',
                    outlined: true,
                    borderRadius: 12,
                    fontSize: 14,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
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
        AppNavigator.key.currentState?.pushAndRemoveUntil(
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
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: ZoomPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
        },
      ),
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
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: _themeMode,
      builder: (context, mode, _) {
        return ThemeController(
          notifier: _themeMode,
          onChanged: _persistTheme,
          child: MaterialApp(
            title: 'PreConnect',
            debugShowCheckedModeBanner: false,
            theme: _cachedLightTheme,
            darkTheme: _cachedDarkTheme,
            themeMode: mode,
            themeAnimationDuration: const Duration(milliseconds: 140),
            themeAnimationCurve: Curves.easeOutCubic,
            scrollBehavior: const _SmoothScrollBehavior(),
            navigatorKey: AppNavigator.key,
            navigatorObservers: [_routeObserver],
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
                    final shellWidth = constraints.maxWidth;
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
                                  borderRadius: BorderRadius.zero,
                                ),
                                clipBehavior: Clip.antiAlias,
                                child: MediaQuery(
                                  data: shellMediaQuery,
                                  child: Padding(
                                    padding: const EdgeInsets.only(top: 6),
                                    child: content,
                                  ),
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

            home: (_initialLoggedIn || _canOpenOffline)
                ? HomePage(initialTab: _resolvedBootstrapState.initialHomeTab)
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
    if (controller == null) return;
    controller.notifier.value = mode;
    unawaited(controller.onChanged(mode));
  }

  @override
  bool updateShouldNotify(ThemeController oldWidget) {
    return notifier != oldWidget.notifier;
  }
}

class _SmoothScrollBehavior extends ScrollBehavior {
  const _SmoothScrollBehavior();
}
