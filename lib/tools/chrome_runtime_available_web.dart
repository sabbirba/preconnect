import 'package:chrome_extension/runtime.dart';

bool isChromeRuntimeAvailable() {
  try {
    return chrome.runtime.isAvailable;
  } catch (_) {
    return false;
  }
}
