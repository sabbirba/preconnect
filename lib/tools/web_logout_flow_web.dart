import 'package:chrome_extension/runtime.dart';

class WebLogoutFlow {
  static Future<void> openConnectLogoutPage() async {
    await chrome.runtime.sendMessage(
      null,
      {'type': 'preconnect.startLogout'},
      null,
    );
  }
}
