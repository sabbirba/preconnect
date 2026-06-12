import 'package:chrome_extension/runtime.dart';

bool isChromeRuntimeAvailable() {
  try {
    return chrome.runtime.isAvailable && Uri.base.scheme == 'chrome-extension';
  } catch (_) {
    return false;
  }
}
