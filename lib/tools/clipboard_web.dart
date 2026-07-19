import 'dart:js_interop';
import 'package:web/web.dart' as web;

Future<String?> readClipboardText() async {
  try {
    final clipboard = web.window.navigator.clipboard;
    final jsString = await clipboard.readText().toDart;
    return jsString.toDart;
  } catch (_) {}
  return null;
}
