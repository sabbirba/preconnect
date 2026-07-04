import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'libsync_config.dart';

class GoogleOAuthWebViewPage extends StatefulWidget {
  const GoogleOAuthWebViewPage({super.key});

  @override
  State<GoogleOAuthWebViewPage> createState() => _GoogleOAuthWebViewPageState();
}

class _GoogleOAuthWebViewPageState extends State<GoogleOAuthWebViewPage> {
  late final WebViewController _controller;
  bool _loading = true;

  @override
  void initState() {
    super.initState();

    final oauthUrl = Uri.parse('https://accounts.google.com/o/oauth2/v2/auth').replace(
      queryParameters: {
        'client_id': LibSyncConfig.googleClientId,
        'redirect_uri': LibSyncConfig.googleRedirectUri,
        'response_type': 'code',
        'scope': LibSyncConfig.googleScopes,
        'access_type': 'offline',
        'prompt': 'consent',
      },
    );

    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setUserAgent('Mozilla/5.0 (Linux; Android 10; K) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/114.0.0.0 Mobile Safari/537.36')
      ..setNavigationDelegate(
        NavigationDelegate(
          onNavigationRequest: (request) {
            if (request.url.startsWith(LibSyncConfig.googleRedirectUri)) {
              final uri = Uri.parse(request.url);
              final code = uri.queryParameters['code'];
              if (code != null) {
                Navigator.of(context).pop(code);
              } else {
                Navigator.of(context).pop();
              }
              return NavigationDecision.prevent;
            }
            return NavigationDecision.navigate;
          },
          onPageStarted: (_) {
            if (mounted) setState(() => _loading = true);
          },
          onPageFinished: (_) {
            if (mounted) setState(() => _loading = false);
          },
        ),
      )
      ..loadRequest(oauthUrl);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Google Sign-In'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: Stack(
        children: [
          WebViewWidget(controller: _controller),
          if (_loading)
            const Center(
              child: CircularProgressIndicator(),
            ),
        ],
      ),
    );
  }
}
