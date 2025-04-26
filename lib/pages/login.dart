import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'home.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();
  late final WebViewController _webViewController;

  final String _clientId = "slm";
  final String _redirectUri = "https://connect.bracu.ac.bd/";
  final String _authUrl =
      "https://sso.bracu.ac.bd/realms/bracu/protocol/openid-connect/auth"
      "?client_id=slm"
      "&redirect_uri=https%3A%2F%2Fconnect.bracu.ac.bd%2F"
      "&response_type=code"
      "&scope=openid offline_access";

  bool _isLoggingIn = false;

  @override
  void initState() {
    super.initState();
    _webViewController =
        WebViewController()
          ..setJavaScriptMode(JavaScriptMode.unrestricted)
          ..setUserAgent("Mozilla/5.0 (Windows NT 10.0; Win64; x64)")
          ..setNavigationDelegate(
            NavigationDelegate(
              onNavigationRequest: (request) {
                if (request.url.startsWith(_redirectUri)) {
                  _handleRedirect(request.url);
                  return NavigationDecision.prevent;
                }
                return NavigationDecision.navigate;
              },
            ),
          )
          ..loadRequest(Uri.parse(_authUrl));
  }

  void _handleRedirect(String url) async {
    final Uri uri = Uri.parse(url);
    final String? authCode = uri.queryParameters["code"];

    if (authCode != null) {
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

      // Navigate to HomeScreen
      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const HomeScreen()),
        );
      }
    } else {
      print("Token exchange failed: ${response.body}");
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Login failed. Please try again.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Login"),
        actions: [
          IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () async {
              if (await _webViewController.canGoBack()) {
                _webViewController.goBack();
              }
            },
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              _webViewController.reload();
            },
          ),
          IconButton(
            icon: const Icon(Icons.arrow_forward),
            onPressed: () async {
              if (await _webViewController.canGoForward()) {
                _webViewController.goForward();
              }
            },
          ),
        ],
      ),
      body: Stack(
        children: [
          WebViewWidget(controller: _webViewController),
          if (_isLoggingIn) const LinearProgressIndicator(minHeight: 3),
        ],
      ),
    );
  }
}
