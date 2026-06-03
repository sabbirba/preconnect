import 'package:chrome_extension/runtime.dart';

class WebLogoutFlow {
  static Future<bool> openConnectLogoutPage() async {
    try {
      if (!chrome.runtime.isAvailable) return false;
    } catch (_) {
      return false;
    }
    try {
      await chrome.runtime.sendMessage(null, {
        'type': 'preconnect.startLogout',
      }, null);
      return true;
    } catch (_) {
      return false;
    }
  }
}
