import 'dart:js_interop';

import 'package:chrome_extension/permissions.dart';
import 'package:preconnect/tools/runtime_web.dart';
import 'package:web/web.dart' as web;

Future<String?> readClipboardText() async {
  if (isChromeRuntimeAvailable() && !await _allowClipboardRead()) return null;
  final text = await web.window.navigator.clipboard.readText().toDart;
  return text.toDart;
}

Future<bool> _allowClipboardRead() {
  return chrome.permissions.request(
    Permissions(permissions: const <String>['clipboardRead']),
  );
}
