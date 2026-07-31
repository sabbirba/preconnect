import 'dart:convert';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:chrome_extension/runtime.dart';

Map<String, dynamic>? decodeExtensionMessage(Object? message) {
  final dartified = (message as JSAny?)?.dartify();
  if (dartified is Map) {
    return Map<String, dynamic>.from(dartified);
  }
  if (dartified is! String) return null;

  try {
    final decoded = jsonDecode(dartified);
    return decoded is Map ? Map<String, dynamic>.from(decoded) : null;
  } on FormatException {
    return null;
  }
}

void acknowledgeExtensionMessage(OnMessageEvent event) {
  try {
    event.sendResponse.callAsFunction(null, {'ok': true}.jsify());
  } catch (_) {}
}

bool sendExtensionRuntimeMessage(Map<String, dynamic> message) {
  try {
    var extensionObject = globalContext.getProperty('chrome'.toJS);
    if (extensionObject.isUndefinedOrNull) {
      extensionObject = globalContext.getProperty('browser'.toJS);
    }
    if (extensionObject.isUndefinedOrNull) return false;

    final runtime = (extensionObject as JSObject).getProperty('runtime'.toJS);
    if (runtime.isUndefinedOrNull) return false;

    final runtimeObject = runtime as JSObject;
    final sendMessage = runtimeObject.getProperty('sendMessage'.toJS);
    if (sendMessage.isUndefinedOrNull) return false;

    (sendMessage as JSFunction).callAsFunction(
      runtimeObject,
      jsonEncode(message).toJS,
    );
    return true;
  } catch (_) {
    return false;
  }
}
