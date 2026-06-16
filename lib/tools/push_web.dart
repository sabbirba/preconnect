import 'package:chrome_extension/chrome.dart';
import 'package:preconnect/tools/preconnect_constants.dart';

Future<void> requestWebExtensionPushTokenSync() async {
  try {
    if (!chrome.runtime.isAvailable || Uri.base.scheme != 'chrome-extension') {
      return;
    }
  } catch (_) {
    return;
  }
  try {
    await chrome.runtime.sendMessage(null, {
      'type': PreConnectPushConfig.syncPushTokenMessageType,
    }, null);
  } catch (_) {}
}
