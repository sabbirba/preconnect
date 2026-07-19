import 'package:chrome_extension/runtime.dart';
import 'package:web/web.dart' as web;

bool isExtensionPage() {
  try {
    final scheme = Uri.base.scheme;
    return scheme == 'chrome-extension' || scheme == 'moz-extension';
  } catch (_) {
    return false;
  }
}

bool isChromeRuntimeAvailable() {
  try {
    return chrome.runtime.isAvailable && isExtensionPage();
  } catch (_) {
    return false;
  }
}

void cleanUrlCodeParameter() {
  try {
    final current = Uri.parse(web.window.location.href);
    final params = Map<String, String>.from(current.queryParameters)
      ..remove('code')
      ..remove('session_state');
    final cleaned = current.replace(
      queryParameters: params.isEmpty ? null : params,
    );
    web.window.history.replaceState(null, '', cleaned.toString());
  } catch (_) {}
}
