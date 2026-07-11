import 'dart:async';
import 'package:chrome_extension/tabs.dart';

Future<String?> openChromeExtensionOAuthFlow(
  String oauthUrl,
  String redirectUri,
) async {
  final tab = await chrome.tabs.create(
    CreateProperties(url: oauthUrl, active: true),
  );
  final tabId = tab.id;
  if (tabId != null) {
    final codeCompleter = Completer<String?>();
    final subscription = chrome.tabs.onUpdated.listen((event) {
      if (event.tabId == tabId && event.changeInfo.url != null) {
        final url = event.changeInfo.url!;
        if (url.startsWith(redirectUri)) {
          final uri = Uri.parse(url);
          final code = uri.queryParameters['code'];
          if (!codeCompleter.isCompleted) {
            codeCompleter.complete(code);
          }
        }
      }
    });
    final removalSubscription = chrome.tabs.onRemoved.listen((event) {
      if (event.tabId == tabId) {
        if (!codeCompleter.isCompleted) {
          codeCompleter.complete(null);
        }
      }
    });
    final authCode = await codeCompleter.future;
    await subscription.cancel();
    await removalSubscription.cancel();
    try {
      await chrome.tabs.remove(tabId);
    } catch (_) {}
    return authCode;
  }
  return null;
}
