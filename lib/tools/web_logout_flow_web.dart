import 'package:chrome_extension/runtime.dart';

class WebLogoutFlow {
  static Future<void> openConnectLogoutPage() async {
    try {
      if (!chrome.runtime.isAvailable) return;
    } catch (_) {
      return;
    }
    await chrome.runtime.sendMessage(null, {
      'type': 'preconnect.startLogout',
    }, null);
  }
}
