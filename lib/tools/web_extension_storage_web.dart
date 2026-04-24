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
  try {
    final local = web.window.localStorage.getItem(key);
    if (local != null && local.isNotEmpty) return local;
  } catch (_) {}
  try {
    final session = web.window.sessionStorage.getItem(key);
    if (session != null && session.isNotEmpty) return session;
  } catch (_) {}
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
  } catch (_) {}
}

Future<void> webExtensionStorageRemoveKeys(Iterable<String> keys) async {
  final keyList = keys.toList();
  if (keyList.isEmpty) return;
  if (_isChromeStorageAvailable()) {
    await chrome.storage.local.remove(keyList);
    return;
  }
  for (final key in keyList) {
    try {
      web.window.localStorage.removeItem(key);
    } catch (_) {}
    try {
      web.window.sessionStorage.removeItem(key);
    } catch (_) {}
  }
}
