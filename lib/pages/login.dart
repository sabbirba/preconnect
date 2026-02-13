import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart'
    show kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';
import 'package:http/http.dart' as http;
import 'package:preconnect/api/bracu_auth_manager.dart';
import 'home.dart';
import 'package:preconnect/tools/token_storage.dart';
import 'package:preconnect/tools/user_agent.dart';
import 'package:preconnect/pages/ui_kit.dart';
import 'package:preconnect/tools/refresh_bus.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  static const String clientId = "slm";
  static const String redirectUri = "https://connect.bracu.ac.bd/";
  static const String authUrl =
      "https://sso.bracu.ac.bd/realms/bracu/protocol/openid-connect/auth"
      "?client_id=slm"
      "&redirect_uri=https%3A%2F%2Fconnect.bracu.ac.bd%2F"
      "&response_type=code"
      "&response_mode=query"
      "&scope=openid offline_access";
  static WebViewController? _preloadedWebViewController;
  static bool _isPreloadingWebView = false;

  static Future<void> preloadNextPage() async {
    if (kIsWeb || defaultTargetPlatform == TargetPlatform.windows) return;
    if (_preloadedWebViewController != null || _isPreloadingWebView) return;
    _isPreloadingWebView = true;
    try {
      final controller = WebViewController()
        ..setJavaScriptMode(JavaScriptMode.unrestricted)
        ..setUserAgent(kPreconnectUserAgent)
        ..loadRequest(Uri.parse(authUrl));
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

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final TokenStorage _secureStorage = TokenStorage.instance;
  WebViewController? _webViewController;
  bool _handledRedirect = false;

  bool _isLoggingIn = false;

  @override
  void initState() {
    super.initState();
    if (kIsWeb || defaultTargetPlatform == TargetPlatform.windows) return;
    _webViewController =
        LoginPage.takePreloadedWebView() ?? _buildMobileWebView();
    _attachNavigationDelegate(_webViewController!);
  }

  WebViewController _buildMobileWebView() {
    final controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setUserAgent(kPreconnectUserAgent)
      ..loadRequest(Uri.parse(LoginPage.authUrl));
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
    if (_handledRedirect) return;
    final Uri uri = Uri.parse(url);
    final String? authCode = uri.queryParameters["code"];

    if (authCode != null) {
      _handledRedirect = true;
      setState(() => _isLoggingIn = true);
      await _exchangeCodeForToken(authCode);
      setState(() => _isLoggingIn = false);
    }
  }

  Future<void> _exchangeCodeForToken(String code) async {
    const String tokenUrl =
        "https://sso.bracu.ac.bd/realms/bracu/protocol/openid-connect/token";

    final response = await http.post(
      Uri.parse(tokenUrl),
      headers: {"Content-Type": "application/x-www-form-urlencoded"},
      body: {
        "grant_type": "authorization_code",
        "client_id": LoginPage.clientId,
        "code": code,
        "redirect_uri": LoginPage.redirectUri,
      },
    );

    if (response.statusCode == 200) {
      final Map<String, dynamic> data = json.decode(response.body);
      final String accessToken = data["access_token"];
      final String refreshToken = data["refresh_token"];

      await _secureStorage.write(key: 'access_token', value: accessToken);
      await _secureStorage.write(key: 'refresh_token', value: refreshToken);

      unawaited(BracuAuthManager().getProfile());
      unawaited(BracuAuthManager().getStudentSchedule());
      unawaited(BracuAuthManager().fetchProfile());
      unawaited(BracuAuthManager().fetchStudentSchedule());

      RefreshBus.instance.notify(reason: 'auth');
      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const HomePage()),
        );
      }
    } else {
      if (!mounted) return;
      showAppSnackBar(context, 'Login failed. Please try again.');
    }
  }

  Future<void> _handlePullToRefresh() async {
    if (_isLoggingIn) return;
    _handledRedirect = false;
    await _webViewController?.reload();
  }

  @override
  Widget build(BuildContext context) {
    if (kIsWeb || defaultTargetPlatform == TargetPlatform.windows) {
      return Scaffold(
        body: const Center(
          child: Padding(
            padding: EdgeInsets.all(16),
            child: Text(
              "Login is not supported on this platform.\n\n"
              "Run this app on Android/iOS (or macOS) to sign in via BRACU SSO.",
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }

    return Scaffold(
      resizeToAvoidBottomInset: false,
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _handlePullToRefresh,
          child: LayoutBuilder(
            builder: (context, constraints) => ListView(
              physics: const AlwaysScrollableScrollPhysics(),
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
                        navigator.maybePop();
                      }
                    },
                    child: Stack(
                      children: [
                        if (_webViewController != null)
                          Positioned.fill(
                            child: WebViewWidget(
                              controller: _webViewController!,
                            ),
                          ),
                        if (_isLoggingIn)
                          Positioned.fill(
                            child: Container(
                              color: Colors.black.withValues(alpha: 0.08),
                              alignment: Alignment.center,
                              child: const SizedBox.shrink(),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
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
