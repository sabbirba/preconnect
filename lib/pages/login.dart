import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:preconnect/api/api_config.dart';
import 'package:preconnect/api/profile.dart';
import 'package:preconnect/api/progress.dart';
import 'package:preconnect/api/schedule.dart';
import 'package:preconnect/features/auth/data/oauth_exchange.dart';
import 'package:preconnect/features/schedule/application/session_resolver.dart';
import 'package:preconnect/pages/ui_kit.dart';
import 'package:preconnect/pages/home.dart';
import 'package:preconnect/tools/bracu_logout.dart';
import 'package:preconnect/tools/pkce.dart';
import 'package:preconnect/tools/refresh_bus.dart';
import 'package:preconnect/tools/token_storage.dart';
import 'package:preconnect/pages/onboarding.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:preconnect/pages/shared_widgets/preconnect_webview.dart';

bool get _shouldUseMobileUserAgent {
  if (kIsWeb) return false;
  return defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS;
}

class LoginPage extends StatefulWidget {
  const LoginPage({super.key, this.customAuthUrl});

  final String? customAuthUrl;

  static String? pkceVerifier;

  static Future<void> clearSessionArtifacts() async {
    pkceVerifier = null;
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

  Timer? _timeoutTimer;
  bool _didComplete = false;

  @override
  void initState() {
    super.initState();
    _timeoutTimer = Timer(_logoutTimeout, _complete);
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
    return PreConnectWebViewPage(
      initialUrl: widget.logoutUrl.toString(),
      userAgent: _shouldUseMobileUserAgent ? kPreConnectUserAgent : null,
      enablePullToRefresh: false,
      onNavigationRequest: (request) {
        if (BracuLogout.isConnectLogoutRedirect(request.url)) {
          _complete();
          return NavigationDecision.prevent;
        }
        return NavigationDecision.navigate;
      },
      onPageStarted: (url) {
        if (BracuLogout.isConnectLogoutRedirect(url)) {
          _complete();
        }
      },
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
    final controller = _buildMobileWebView();
    _attachNavigationDelegate(controller);
    _webViewController = controller;
  }

  WebViewController _buildMobileWebView() {
    LoginPage.pkceVerifier ??= generatePkceVerifier();
    final codeChallenge = codeChallengeS256(LoginPage.pkceVerifier!);
    final controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted);
    try {
      controller.setBackgroundColor(Colors.transparent);
    } catch (_) {}
    if (_shouldUseMobileUserAgent) {
      controller.setUserAgent(kPreConnectUserAgent);
    }
    final url =
        widget.customAuthUrl ?? ApiConfig.authUrlWithPkce(codeChallenge);
    controller.loadRequest(Uri.parse(url));
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
      final verifier = LoginPage.pkceVerifier;
      if (verifier == null || verifier.isEmpty) {
        return false;
      }

      try {
        await OAuthCodeExchange().exchangeAndPersist(
          code: code,
          verifier: verifier,
          timeout: _loginRequestTimeout,
        );
      } on OAuthCodeExchangeException {
        return false;
      } on TokenPersistenceException {
        return false;
      }

      RefreshBus.instance.notify(reason: 'auth');
      if (mounted) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(
            builder: (context) => const HomePage(isLoggedIn: true),
          ),
          (route) => false,
        );
      }
      unawaited(_warmAuthenticatedData());
      return true;
    } catch (_) {
      return false;
    }
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
      ].map((task) => task.catchError((_) {})),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (kIsWeb) {
      throw UnsupportedError(
        'LoginPage is available only on native platforms.',
      );
    }

    return PreConnectWebViewPage(
      initialUrl: widget.customAuthUrl ?? '',
      preloadedController: _webViewController,
      onBackPress: (context, ctrl) async {
        final navigator = Navigator.of(context);
        if (await ctrl.canGoBack()) {
          await ctrl.goBack();
        } else {
          navigator.pushAndRemoveUntil(
            MaterialPageRoute(builder: (context) => const OnboardingPage()),
            (route) => false,
          );
        }
      },
    );
  }

  @override
  void dispose() {
    _webViewController = null;
    super.dispose();
  }
}
