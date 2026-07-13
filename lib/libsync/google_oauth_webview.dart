import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:preconnect/pages/shared_widgets/preconnect_webview.dart';
import 'libsync_config.dart';

class GoogleOAuthWebViewPage extends StatelessWidget {
  const GoogleOAuthWebViewPage({super.key});

  @override
  Widget build(BuildContext context) {
    final oauthUrl = Uri.parse('https://accounts.google.com/o/oauth2/v2/auth')
        .replace(
          queryParameters: {
            'client_id': LibSyncConfig.googleClientId,
            'redirect_uri': LibSyncConfig.googleRedirectUri,
            'response_type': 'code',
            'scope': LibSyncConfig.googleScopes,
            'access_type': 'offline',
            'prompt': 'consent',
          },
        );

    return PreConnectWebViewPage(
      initialUrl: oauthUrl.toString(),
      userAgent:
          'Mozilla/5.0 (Linux; Android 10; K) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/114.0.0.0 Mobile Safari/537.36',
      delayLoadUntilTransition: true,
      onNavigationRequest: (request) {
        if (request.url.startsWith(LibSyncConfig.googleRedirectUri)) {
          final uri = Uri.parse(request.url);
          final code = uri.queryParameters['code'];
          Future.delayed(Duration.zero, () {
            if (context.mounted) {
              Navigator.of(context).pop(code);
            }
          });
          return NavigationDecision.prevent;
        }
        return NavigationDecision.navigate;
      },
    );
  }
}
