import 'package:chrome_extension/storage.dart';
import 'package:web/web.dart' as web;

bool _isChromeStorageAvailable() => chrome.storage.isAvailable;

Future<String?> webExtensionStorageGet(String key) async {
  if (_isChromeStorageAvailable()) {
    final values = await chrome.storage.local.get(key);
    final value = values[key];
    if (value == null) return null;
    return '$value';
  }
  Object? localError;
  try {
    final local = web.window.localStorage.getItem(key);
    if (local != null && local.isNotEmpty) return local;
  } catch (error) {
    localError = error;
  }
  try {
    final session = web.window.sessionStorage.getItem(key);
    if (session != null && session.isNotEmpty) return session;
  } catch (error) {
    if (localError != null) {
      throw StateError(
        'Browser storage read failed for "$key" '
        '(${localError.runtimeType}, ${error.runtimeType}).',
      );
    }
  }
  return null;
}

Future<void> webExtensionStorageSet(String key, String? value) async {
  if (_isChromeStorageAvailable()) {
    if (value == null) {
      await chrome.storage.local.remove(key);
    } else {
      await chrome.storage.local.set({key: value});
    }
    return;
  }
  try {
    if (value == null) {
      web.window.localStorage.removeItem(key);
    } else {
      web.window.localStorage.setItem(key, value);
    }
    return;
  } catch (_) {}
  try {
    if (value == null) {
      web.window.sessionStorage.removeItem(key);
    } else {
      web.window.sessionStorage.setItem(key, value);
    }
  } catch (error) {
    throw StateError(
      'Browser storage write failed for "$key" (${error.runtimeType}).',
    );
  }
}

Future<void> webExtensionStorageRemoveKeys(Iterable<String> keys) async {
  final keyList = keys.toList();
  if (keyList.isEmpty) return;
  if (_isChromeStorageAvailable()) {
    await chrome.storage.local.remove(keyList);
    return;
  }
  for (final key in keyList) {
    Object? removalError;
    try {
      web.window.localStorage.removeItem(key);
    } catch (error) {
      removalError = error;
    }
    try {
      web.window.sessionStorage.removeItem(key);
    } catch (error) {
      removalError ??= error;
    }
    if (removalError != null) {
      throw StateError(
        'Browser storage deletion failed for "$key" '
        '(${removalError.runtimeType}).',
      );
    }
  }
}

Future<Map<String, String>> webExtensionStorageGetAll() async {
  final map = <String, String>{};
  if (_isChromeStorageAvailable()) {
    final Map<dynamic, dynamic> valuesObj = await chrome.storage.local.get(
      null,
    );
    valuesObj.forEach((k, v) {
      if (v != null) {
        map[k.toString()] = v.toString();
      }
    });
    return map;
  }
  try {
    for (int i = 0; i < web.window.localStorage.length; i++) {
      final key = web.window.localStorage.key(i);
      if (key != null) {
        final val = web.window.localStorage.getItem(key);
        if (val != null) map[key] = val;
      }
    }
  } catch (error) {
    throw StateError(
      'Browser storage enumeration failed (${error.runtimeType}).',
    );
  }
  return map;
}
