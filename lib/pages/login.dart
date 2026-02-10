import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart'
    show kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';
import 'package:http/http.dart' as http;
import 'package:preconnect/api/bracu_auth_manager.dart';
import 'package:webview_windows/webview_windows.dart' as win;
import 'home.dart';
import 'package:preconnect/tools/token_storage.dart';
import 'package:preconnect/tools/user_agent.dart';
import 'package:preconnect/pages/ui_kit.dart';
import 'package:preconnect/tools/refresh_bus.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final TokenStorage _secureStorage = TokenStorage.instance;
  WebViewController? _webViewController;
  win.WebviewController? _winController;
  StreamSubscription<String>? _winUrlSub;
  StreamSubscription<win.HistoryChanged>? _winHistorySub;
  bool _winCanGoBack = false;
  bool _handledRedirect = false;

  final String _clientId = "slm";
  final String _redirectUri = "https://connect.bracu.ac.bd/";
  final String _authUrl =
      "https://sso.bracu.ac.bd/realms/bracu/protocol/openid-connect/auth"
      "?client_id=slm"
      "&redirect_uri=https%3A%2F%2Fconnect.bracu.ac.bd%2F"
      "&response_type=code"
      "&response_mode=query"
      "&scope=openid offline_access";
  bool _isLoggingIn = false;

  @override
  void initState() {
    super.initState();
    if (kIsWeb) return;
    if (defaultTargetPlatform == TargetPlatform.windows) {
      _initWindowsWebview();
      return;
    }
    _webViewController = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setUserAgent(kPreconnectUserAgent)
      ..setNavigationDelegate(
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
      )
      ..loadRequest(Uri.parse(_authUrl));
    _configureCookies(_webViewController!);
  }

  Future<void> _initWindowsWebview() async {
    _winController = win.WebviewController();
    try {
      await _winController!.initialize();
      await _winController!.setUserAgent(kPreconnectUserAgent);
      await _winController!
          .setPopupWindowPolicy(win.WebviewPopupWindowPolicy.deny);
      _winUrlSub = _winController!.url.listen((url) {
        if (_isRedirectUrl(url)) {
          _handleRedirect(url);
        }
      });
      _winHistorySub = _winController!.historyChanged.listen((history) {
        _winCanGoBack = history.canGoBack;
      });
      await _winController!.loadUrl(_authUrl);
      if (mounted) setState(() {});
    } catch (_) {
      if (!mounted) return;
      showAppSnackBar(context, 'WebView failed to initialize.');
    }
  }

  Future<void> _configureCookies(WebViewController controller) async {
    final platform = controller.platform;
    if (platform is AndroidWebViewController) {
      final cookieManager = AndroidWebViewCookieManager(
        PlatformWebViewCookieManagerCreationParams(),
      );
      await cookieManager.setAcceptThirdPartyCookies(platform, true);
    }
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
        "client_id": _clientId,
        "code": code,
        "redirect_uri": _redirectUri,
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

  @override
  Widget build(BuildContext context) {
    if (kIsWeb) {
      return Scaffold(
        body: const Center(
          child: Padding(
            padding: EdgeInsets.all(16),
            child: Text(
              "Login is not supported on the web build.\n\n"
              "Run this app on Android/iOS (or a desktop build with WebView support) to sign in via BRACU SSO.",
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }

    return Scaffold(
      resizeToAvoidBottomInset: false,
      body: SafeArea(
        child: PopScope(
          canPop: false,
          onPopInvokedWithResult: (didPop, result) async {
            if (defaultTargetPlatform == TargetPlatform.windows) {
              final controller = _winController;
              if (controller == null) return;
              if (!mounted) return;
              final navigator = Navigator.of(context);
              if (_winCanGoBack) {
                await controller.goBack();
              } else {
                navigator.maybePop();
              }
              return;
            }
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
              if (defaultTargetPlatform == TargetPlatform.windows &&
                  _winController != null)
                Positioned.fill(child: win.Webview(_winController!))
              else if (_webViewController != null)
                Positioned.fill(
                  child: WebViewWidget(controller: _webViewController!),
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
    );
  }

  @override
  void dispose() {
    _winUrlSub?.cancel();
    _winHistorySub?.cancel();
    _winController?.dispose();
    super.dispose();
  }
}
