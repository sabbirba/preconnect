import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:preconnect/api/bracu_auth_manager.dart';
import 'home.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();
  WebViewController? _webViewController;
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
    _webViewController = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setUserAgent("Mozilla/5.0 (Windows NT 10.0; Win64; x64)")
      ..setNavigationDelegate(
        NavigationDelegate(
          onNavigationRequest: (request) {
            if (_isRedirectUrl(request.url)) {
              _handleRedirect(request.url);
              return NavigationDecision.prevent;
            }
            return NavigationDecision.navigate;
          },
          onUrlChange: (change) {
            final url = change.url;
            if (url != null && _isRedirectUrl(url)) {
              _handleRedirect(url);
            }
          },
        ),
      )
      ..loadRequest(Uri.parse(_authUrl));
    _configureCookies();
  }

  Future<void> _configureCookies() async {
    final controller = _webViewController;
    if (controller == null) return;
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

      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const HomePage()),
        );
      }
    } else {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Login failed. Please try again.')),
      );
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
      body: Stack(
        children: [
          if (_webViewController != null)
            WebViewWidget(controller: _webViewController!),
          if (_isLoggingIn)
            Positioned.fill(
              child: Container(
                color: Colors.black.withValues(alpha: 0.08),
                alignment: Alignment.center,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: const [
                    CircularProgressIndicator(),
                    SizedBox(height: 12),
                    Text("Loading...", style: TextStyle(fontSize: 14)),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
