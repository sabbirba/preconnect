import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:preconnect/api/api_client.dart';
import 'package:preconnect/api/api_config.dart';
import 'package:preconnect/api/calendar.dart';
import 'package:preconnect/api/custom_schedules.dart';
import 'package:preconnect/api/friend_store.dart';
import 'package:preconnect/api/notification.dart';
import 'package:preconnect/api/profile.dart';
import 'package:preconnect/api/progress.dart';
import 'package:preconnect/api/schedule.dart';
import 'package:preconnect/pages/alarms.dart';
import 'package:preconnect/pages/class_schedule.dart';
import 'package:preconnect/pages/custom_schedules.dart';
import 'package:preconnect/pages/degree_progress.dart';
import 'package:preconnect/pages/devs.dart';
import 'package:preconnect/pages/exam_schedule.dart';
import 'package:preconnect/pages/shared_widgets/session_helper.dart';
import 'package:preconnect/pages/shared_widgets/import_dialog.dart';
import 'package:preconnect/pages/student_profile.dart';
import 'package:preconnect/pages/ui_kit.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:preconnect/tools/http/http_utils.dart';
import 'package:preconnect/tools/bracu_logout.dart';
import 'package:preconnect/tools/pkce.dart';
import 'package:preconnect/tools/preconnect_constants.dart';
import 'package:preconnect/tools/refresh_bus.dart';
import 'package:preconnect/tools/token_storage.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';

bool get _shouldUseMobileUserAgent {
  if (kIsWeb) return false;
  return defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS;
}

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
        ..setJavaScriptMode(JavaScriptMode.unrestricted);
      if (_shouldUseMobileUserAgent) {
        controller.setUserAgent(kPreConnectUserAgent);
      }
      controller.loadRequest(
        Uri.parse(ApiConfig.authUrlWithPkce(codeChallenge)),
      );
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
    _pkceVerifier = null;
    if (kIsWeb) return;
    try {
      final manager = WebViewCookieManager();
      await manager.clearCookies();
    } catch (_) {}
  }

  static Future<void> openLogoutWebView(
    BuildContext context, {
    required String idToken,
  }) async {
    if (kIsWeb || idToken.trim().isEmpty || !context.mounted) return;
    final logoutUrl = BracuLogout.ssoLogoutUri(idToken: idToken);
    await Navigator.of(context, rootNavigator: true).push<void>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => _MobileLogoutWebViewPage(logoutUrl: logoutUrl),
      ),
    );
  }

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _MobileLogoutWebViewPage extends StatefulWidget {
  const _MobileLogoutWebViewPage({required this.logoutUrl});

  final Uri logoutUrl;

  @override
  State<_MobileLogoutWebViewPage> createState() =>
      _MobileLogoutWebViewPageState();
}

class _MobileLogoutWebViewPageState extends State<_MobileLogoutWebViewPage> {
  static const Duration _logoutTimeout = Duration(seconds: 12);

  late final WebViewController _controller;
  Timer? _timeoutTimer;
  bool _didComplete = false;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onNavigationRequest: (request) {
            if (_isLogoutRedirect(request.url)) {
              _complete();
              return NavigationDecision.prevent;
            }
            return NavigationDecision.navigate;
          },
          onPageStarted: (url) {
            if (_isLogoutRedirect(url)) {
              _complete();
            }
          },
        ),
      )
      ..loadRequest(widget.logoutUrl);
    if (_shouldUseMobileUserAgent) {
      _controller.setUserAgent(kPreConnectUserAgent);
    }
    unawaited(LoginPage._configureCookies(_controller));
    _timeoutTimer = Timer(_logoutTimeout, _complete);
  }

  bool _isLogoutRedirect(String url) {
    return BracuLogout.isConnectLogoutRedirect(url);
  }

  void _complete() {
    if (_didComplete) return;
    _didComplete = true;
    _timeoutTimer?.cancel();
    if (mounted) {
      Navigator.of(context).maybePop();
    }
  }

  @override
  void dispose() {
    _timeoutTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(child: WebViewWidget(controller: _controller)),
    );
  }
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
    LoginPage._pkceVerifier ??= generatePkceVerifier();
    final codeChallenge = codeChallengeS256(LoginPage._pkceVerifier!);
    final controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted);
    if (_shouldUseMobileUserAgent) {
      controller.setUserAgent(kPreConnectUserAgent);
    }
    controller.loadRequest(Uri.parse(ApiConfig.authUrlWithPkce(codeChallenge)));
    unawaited(LoginPage._configureCookies(controller));
    return controller;
  }

  void _attachNavigationDelegate(WebViewController controller) {
    controller.setNavigationDelegate(
      NavigationDelegate(
        onNavigationRequest: (request) {
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

      final uri = Uri.parse(ApiConfig.tokenEndpoint);
      final body = HttpUtils.formBody(<String, String>{
        'grant_type': 'authorization_code',
        'client_id': ApiConfig.clientId,
        'code': code,
        'redirect_uri': ApiConfig.redirectUri,
        'code_verifier': verifier,
      });
      final response = await HttpUtils.client
          .post(
            uri,
            headers: <String, String>{
              'Content-Type': 'application/x-www-form-urlencoded',
              ...compressionHeadersForUri(uri),
            },
            body: body,
          )
          .timeout(_loginRequestTimeout);

      if (response.statusCode != 200) return false;

      final data = json.decode(response.body);
      if (data is! Map<String, dynamic>) return false;

      final accessToken = data['access_token'] as String?;
      final refreshToken = data['refresh_token'] as String?;
      final idToken = data['id_token'] as String?;
      if (accessToken == null ||
          accessToken.isEmpty ||
          refreshToken == null ||
          refreshToken.isEmpty) {
        return false;
      }

      try {
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
      } on TokenPersistenceException {
        return false;
      }

      RefreshBus.instance.notify(reason: 'auth');
      if (mounted) {
        Navigator.of(context).pushNamedAndRemoveUntil('/', (route) => false);
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
          final semesterSessionId =
              await resolveCurrentSessionSemesterIdWithRetry();
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
    if (kIsWeb) {
      return _WebLoginPage(
        onOpenLogin: _launchWebLogin,
        onImportPressed: _handleImportSession,
      );
    }

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
    _webViewController = null;
    super.dispose();
  }

  Future<void> _launchWebLogin() async {
    final verifier = generatePkceVerifier();
    final challenge = codeChallengeS256(verifier);
    await TokenStorage.instance.write(
      key: PreConnectStorageKeys.pkceVerifier,
      value: verifier,
    );
    final uri = Uri.parse(ApiConfig.authUrlWithPkce(challenge));
    await launchUrl(
      uri,
      mode: LaunchMode.externalApplication,
      webOnlyWindowName: '_self',
    );
  }

  Future<void> _handleImportSession() async {
    final result = await ImportSessionDialog.show(context);
    if (result == true) {
      RefreshBus.instance.notify(reason: 'auth');
      if (mounted) {
        Navigator.of(context).pushNamedAndRemoveUntil('/', (route) => false);
      }
      unawaited(_warmAuthenticatedData());
    }
  }
}

class _WebLoginPage extends StatelessWidget {
  const _WebLoginPage({
    required this.onOpenLogin,
    required this.onImportPressed,
  });

  final Future<void> Function() onOpenLogin;
  final VoidCallback onImportPressed;

  @override
  Widget build(BuildContext context) {
    final textSecondary = Theme.of(
      context,
    ).colorScheme.onSurface.withAlpha(128);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 40),
                  const Icon(
                    Icons.school_rounded,
                    size: 52,
                    color: Color(0xFF1E6BE3),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'PreConnect',
                    style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Sign in with your BRACU student account',
                    style: TextStyle(fontSize: 13.5, color: textSecondary),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 40),
                  FilledButton.icon(
                    onPressed: () => unawaited(onOpenLogin()),
                    icon: const Icon(Icons.login_rounded),
                    label: const Text('Sign in with BRACU'),
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      textStyle: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      Expanded(
                        child: Divider(color: textSecondary.withAlpha(60)),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 14),
                        child: Text(
                          'or sync from mobile app',
                          style: TextStyle(fontSize: 12, color: textSecondary),
                        ),
                      ),
                      Expanded(
                        child: Divider(color: textSecondary.withAlpha(60)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  OutlinedButton.icon(
                    onPressed: onImportPressed,
                    icon: const Icon(Icons.qr_code_scanner_rounded),
                    label: const Text('Sync Session (QR / Copy Code)'),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      textStyle: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1E6BE3).withAlpha(15),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: const Color(0xFF1E6BE3).withAlpha(38),
                      ),
                    ),
                    child: Text(
                      'To sync: open PreConnect on your phone → Settings → Sync Session → Copy or scan the QR code.',
                      style: TextStyle(
                        fontSize: 12,
                        color: textSecondary,
                        height: 1.5,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                  const SizedBox(height: 40),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
