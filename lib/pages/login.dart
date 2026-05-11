import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';
import 'package:http/http.dart' as http;
import 'package:preconnect/api/api_config.dart';
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
    _webViewController =
        LoginPage.takePreloadedWebView() ?? _buildMobileWebView();
    _attachNavigationDelegate(_webViewController!);
  }

  WebViewController _buildMobileWebView() {
    LoginPage._pkceVerifier ??= generatePkceVerifier();
    final codeChallenge = codeChallengeS256(LoginPage._pkceVerifier!);
    final controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setUserAgent(kPreconnectUserAgent)
      ..loadRequest(Uri.parse(ApiConfig.authUrlWithPkce(codeChallenge)));
    LoginPage._configureCookies(controller);
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
        onPageStarted: (url) {
          if (_isRedirectUrl(url)) {
            _handleRedirect(url);
          }
        },
      ),
    );
  }

  bool _isRedirectUrl(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null) return false;
    return uri.host == 'connect.bracu.ac.bd';
  }

  void _handleRedirect(String url) async {
    if (_handledRedirect || _isLoggingIn) {
      return;
    }
    final Uri uri = Uri.parse(url);
    final String? authCode = uri.queryParameters["code"];

    if (authCode == null || authCode.isEmpty) {
      return;
    }
    _handledRedirect = true;
    if (mounted) {
      setState(() => _isLoggingIn = true);
    }

    var needsRetry = false;
    try {
      final didLogin = await _exchangeCodeForToken(authCode);
      if (!didLogin) {
        needsRetry = true;
        if (mounted) {
          showAppSnackBar(context, 'Login failed. Please try again.');
        }
      }
    } finally {
      if (mounted) {
        setState(() => _isLoggingIn = false);
      }
    }

    if (needsRetry && mounted) {
      _handledRedirect = false;
      try {
        await _webViewController?.loadRequest(Uri.parse(ApiConfig.authUrl));
      } catch (_) {}
    }
  }

  Future<bool> _exchangeCodeForToken(String code) async {
    try {
      final verifier = LoginPage._pkceVerifier;
      if (verifier == null || verifier.isEmpty) {
        return false;
      }
      final response = await http
          .post(
            Uri.parse(ApiConfig.tokenEndpoint),
            headers: {"Content-Type": "application/x-www-form-urlencoded"},
            body: {
              "grant_type": "authorization_code",
              "client_id": ApiConfig.clientId,
              "code": code,
              "redirect_uri": ApiConfig.redirectUri,
              "code_verifier": verifier,
            },
          )
          .timeout(_loginRequestTimeout);
      if (response.statusCode != 200) {
        return false;
      }
      final data = json.decode(response.body);
      if (data is! Map<String, dynamic>) {
        return false;
      }

      final accessToken = data["access_token"] as String?;
      final refreshToken = data["refresh_token"] as String?;
      if (accessToken == null ||
          accessToken.isEmpty ||
          refreshToken == null ||
          refreshToken.isEmpty) {
        return false;
      }

      try {
        await TokenStorage.instance.write(
          key: PreconnectStorageKeys.accessToken,
          value: accessToken,
        );
        await TokenStorage.instance.write(
          key: PreconnectStorageKeys.refreshToken,
          value: refreshToken,
        );
      } on TokenPersistenceException {
        return false;
      }

      final persistedAccessToken = await TokenStorage.instance.read(
        key: PreconnectStorageKeys.accessToken,
      );
      final persistedRefreshToken = await TokenStorage.instance.read(
        key: PreconnectStorageKeys.refreshToken,
      );
      if (persistedAccessToken == null ||
          persistedAccessToken.isEmpty ||
          persistedRefreshToken == null ||
          persistedRefreshToken.isEmpty) {
        return false;
      }
      RefreshBus.instance.notify(reason: 'auth');
      if (mounted) {
        Navigator.of(
          context,
        ).pushNamedAndRemoveUntil('/home', (route) => false);
      }
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

  @override
  Widget build(BuildContext context) {
    if (kIsWeb) {
      return const WebExtensionLoginPage();
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
                    if (controller == null) return;
                    if (!mounted) return;
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
    super.dispose();
  }
}
