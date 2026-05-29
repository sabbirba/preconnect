import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:preconnect/tools/http/http_service.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';

import 'package:preconnect/api/api_config.dart';
import 'package:preconnect/api/profile_service.dart';
import 'package:preconnect/api/schedule_service.dart';
import 'package:preconnect/api/calendar_service.dart';
import 'package:preconnect/api/custom_schedules_service.dart';
import 'package:preconnect/api/friend_schedule_store.dart';
import 'package:preconnect/api/notification_service.dart';
import 'package:preconnect/api/progress_service.dart';
import 'package:preconnect/pages/alarms.dart';
import 'package:preconnect/pages/class_schedule.dart';
import 'package:preconnect/pages/custom_schedules.dart';
import 'package:preconnect/pages/degree_progress.dart';
import 'package:preconnect/pages/devs.dart';
import 'package:preconnect/pages/exam_schedule.dart';
import 'package:preconnect/pages/student_profile.dart';
import 'package:preconnect/pages/shared_widgets/current_session_helper.dart';
import 'package:preconnect/tools/pkce.dart';
import 'package:preconnect/tools/preconnect_constants.dart';
import 'package:preconnect/tools/refresh_bus.dart';
import 'package:preconnect/tools/token_storage.dart';
import 'package:preconnect/pages/ui_kit.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  static WebViewController? _preloadedWebViewController;
  static bool _isPreloadingWebView = false;
  static String? _pkceVerifier;

  static Future<void> preloadNextPage() async {
    if (kIsWeb) return;
    if (_preloadedWebViewController != null || _isPreloadingWebView) return;
    _isPreloadingWebView = true;
    try {
      _pkceVerifier = generatePkceVerifier();
      final codeChallenge = codeChallengeS256(_pkceVerifier!);
      final controller = WebViewController()
        ..setJavaScriptMode(JavaScriptMode.unrestricted)
        ..setUserAgent(kPreconnectUserAgent)
        ..loadRequest(Uri.parse(ApiConfig.authUrlWithPkce(codeChallenge)));
      await _configureCookies(controller);
      _preloadedWebViewController = controller;
    } catch (_) {
      _preloadedWebViewController = null;
    } finally {
      _isPreloadingWebView = false;
    }
  }

  static WebViewController? takePreloadedWebView() {
    final controller = _preloadedWebViewController;
    _preloadedWebViewController = null;
    return controller;
  }

  static Future<void> _configureCookies(WebViewController controller) async {
    final platform = controller.platform;
    if (platform is AndroidWebViewController) {
      final cookieManager = AndroidWebViewCookieManager(
        PlatformWebViewCookieManagerCreationParams(),
      );
      await cookieManager.setAcceptThirdPartyCookies(platform, true);
    }
  }

  static Future<void> clearSessionArtifacts() async {
    _preloadedWebViewController = null;
    _isPreloadingWebView = false;
    _pkceVerifier = null; // FIX: also clear stale verifier on logout
    if (kIsWeb) return;
    try {
      final manager = WebViewCookieManager();
      await manager.clearCookies();
    } catch (_) {}
  }

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  static const Duration _loginRequestTimeout = Duration(seconds: 12);

  WebViewController? _webViewController;
  bool _handledRedirect = false;
  bool _isLoggingIn = false;

  @override
  void initState() {
    super.initState();
    if (kIsWeb) return;
    final controller =
        LoginPage.takePreloadedWebView() ?? _buildMobileWebView();
    _attachNavigationDelegate(controller);
    _webViewController = controller;
  }

  WebViewController _buildMobileWebView() {
    // Reuse existing verifier if already generated (e.g. partial preload)
    LoginPage._pkceVerifier ??= generatePkceVerifier();
    final codeChallenge = codeChallengeS256(LoginPage._pkceVerifier!);
    final controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setUserAgent(kPreconnectUserAgent)
      ..loadRequest(Uri.parse(ApiConfig.authUrlWithPkce(codeChallenge)));
    // Fire-and-forget; cookie config doesn't affect initial page load
    unawaited(LoginPage._configureCookies(controller));
    return controller;
  }

  void _attachNavigationDelegate(WebViewController controller) {
    controller.setNavigationDelegate(
      NavigationDelegate(
        onNavigationRequest: (request) {
          // PERF: Single intercept point - removed onPageStarted duplicate
          if (_isRedirectUrl(request.url)) {
            _handleRedirect(request.url);
            return NavigationDecision.prevent;
          }
          return NavigationDecision.navigate;
        },
      ),
    );
  }

  bool _isRedirectUrl(String url) {
    final uri = Uri.tryParse(url);
    return uri != null && uri.host == 'connect.bracu.ac.bd';
  }

  void _handleRedirect(String url) {
    // PERF: Idempotency guard — prevents double-fire from simultaneous callbacks
    if (_handledRedirect || _isLoggingIn) return;

    final uri = Uri.parse(url);
    final authCode = uri.queryParameters['code'];
    if (authCode == null || authCode.isEmpty) return;

    _handledRedirect = true;
    if (mounted) setState(() => _isLoggingIn = true);

    _exchangeCodeForToken(authCode)
        .then((didLogin) {
          if (!mounted) return;
          setState(() => _isLoggingIn = false);
          if (!didLogin) {
            showAppSnackBar(context, 'Login failed. Please try again.');
            _handledRedirect = false;
            _webViewController?.loadRequest(Uri.parse(ApiConfig.authUrl));
          }
        })
        .catchError((_) {
          if (!mounted) return;
          setState(() => _isLoggingIn = false);
          _handledRedirect = false;
        });
  }

  Future<bool> _exchangeCodeForToken(String code) async {
    try {
      final verifier = LoginPage._pkceVerifier;
      if (verifier == null || verifier.isEmpty) return false;

      final response = await HttpService.client
          .post(
            Uri.parse(ApiConfig.tokenEndpoint),
            headers: {'Content-Type': 'application/x-www-form-urlencoded'},
            body: {
              'grant_type': 'authorization_code',
              'client_id': ApiConfig.clientId,
              'code': code,
              'redirect_uri': ApiConfig.redirectUri,
              'code_verifier': verifier,
            },
          )
          .timeout(_loginRequestTimeout);

      if (response.statusCode != 200) return false;

      final data = json.decode(response.body);
      if (data is! Map<String, dynamic>) return false;

      final accessToken = data['access_token'] as String?;
      final refreshToken = data['refresh_token'] as String?;
      if (accessToken == null ||
          accessToken.isEmpty ||
          refreshToken == null ||
          refreshToken.isEmpty) {
        return false;
      }

      try {
        await Future.wait([
          TokenStorage.instance.write(
            key: PreconnectStorageKeys.accessToken,
            value: accessToken,
          ),
          TokenStorage.instance.write(
            key: PreconnectStorageKeys.refreshToken,
            value: refreshToken,
          ),
        ]);
      } on TokenPersistenceException {
        return false;
      }

      // PERF: Removed redundant read-back verification — write failure is
      // already surfaced via TokenPersistenceException above.

      RefreshBus.instance.notify(reason: 'auth');
      if (mounted) {
        Navigator.of(
          context,
        ).pushNamedAndRemoveUntil('/home', (route) => false);
      }
      unawaited(_warmAuthenticatedData());
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> _handlePullToRefresh() async {
    if (_isLoggingIn) return;
    _handledRedirect = false;
    await _webViewController?.reload();
  }

  Future<void> _warmAuthenticatedData() async {
    await Future.wait(
      [
        ProfileService().fetchProfile().then((_) {}),
        AttendanceService().getAttendanceInfo().then((_) {}),
        PaymentService().getPaymentInfo().then((_) {}),
        ProgressService().getProgress().then((_) {}),
        () async {
          final semesterSessionId = await resolveCurrentSessionSemesterId();
          if (semesterSessionId == null) return;
          await ScheduleService().fetchStudentScheduleForSemester(
            semesterSessionId: semesterSessionId,
          );
        }(),
        CustomSchedulesService().getItems(forceRefresh: true).then((_) {}),
        FriendScheduleStore().loadSnapshot().then((_) {}),
        CalendarService().getCalendar().then((_) {}),
        NotificationService().getRecentNotifications().then((_) {}),
        DegreeProgressPage.preload(),
        StudentProfile.preload(),
        DevsPage.preload(),
        AlarmPage.preload(),
        ClassSchedule.preload(),
        ExamSchedule.preload(),
        CustomSchedulesPage.preload(),
      ].map((task) => task.catchError((_) {})),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (kIsWeb) return const WebExtensionLoginPage();

    return Scaffold(
      resizeToAvoidBottomInset: false,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) => BracuRefreshList(
            onRefresh: _handlePullToRefresh,
            padding: EdgeInsets.zero,
            children: [
              SizedBox(
                height: constraints.maxHeight,
                child: PopScope(
                  canPop: false,
                  onPopInvokedWithResult: (didPop, result) async {
                    final controller = _webViewController;
                    if (controller == null || !mounted) return;
                    final navigator = Navigator.of(context);
                    if (await controller.canGoBack()) {
                      await controller.goBack();
                    } else {
                      navigator.pushNamedAndRemoveUntil(
                        '/onboarding',
                        (route) => false,
                      );
                    }
                  },
                  child: Stack(
                    children: [
                      if (_webViewController != null)
                        Positioned.fill(
                          child: WebViewWidget(controller: _webViewController!),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _webViewController = null; // Release reference; platform cleans up
    super.dispose();
  }
}
