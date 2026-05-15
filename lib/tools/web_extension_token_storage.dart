import 'package:chrome_extension/storage.dart';
import 'package:preconnect/tools/preconnect_constants.dart';

class WebExtensionTokenStorage {
  WebExtensionTokenStorage._();

  static final WebExtensionTokenStorage instance = WebExtensionTokenStorage._();

  Future<String?> read({required String key}) async {
    if (!chrome.storage.isAvailable) return null;
    final values = await chrome.storage.local.get(key);
    final value = values[key];
    if (value == null) return null;
    final text = '$value'.trim();
    return text.isEmpty ? null : text;
  }

  Future<void> write({required String key, String? value}) async {
    if (!chrome.storage.isAvailable) return;
    if (value == null || value.trim().isEmpty) {
      await chrome.storage.local.remove(key);
      return;
    }
    await chrome.storage.local.set({key: value});
  }

  Future<void> deleteAll() async {
    if (!chrome.storage.isAvailable) return;
    await chrome.storage.local.remove(const [
      PreconnectStorageKeys.accessToken,
      PreconnectStorageKeys.refreshToken,
      PreconnectStorageKeys.cachedHasAuthSession,
    ]);
  }
}
