import 'dart:convert';
import 'dart:js_interop';

import 'package:chrome_extension/runtime.dart';
import 'package:preconnect/tools/runtime_web.dart';

class WebLogoutFlow {
  static Future<bool> openConnectLogoutPage() async {
    try {
      if (!chrome.runtime.isAvailable || !isExtensionPage()) {
        return false;
      }
    } catch (_) {
      return false;
    }
    try {
      await chrome.runtime.sendMessage(
        null,
        jsonEncode({'type': 'preconnect.startLogout'}).toJS,
        null,
      );
      return true;
    } catch (_) {
      return false;
    }
  }
}
