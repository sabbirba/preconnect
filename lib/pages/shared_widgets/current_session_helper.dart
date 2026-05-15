import 'package:preconnect/api/app_preferences_store.dart';
import 'package:preconnect/tools/app_storage.dart';
import 'package:preconnect/tools/storage_keys.dart';

Future<int?> resolveCurrentSessionSemesterId() async {
  final cachedFromAppStorage = int.tryParse(
    (await AppStorage.instance.getString(StorageKeys.currentSessionSemesterId) ??
            '')
        .trim(),
  );
  if (cachedFromAppStorage != null && cachedFromAppStorage > 0) {
    return cachedFromAppStorage;
  }

  final parsed = int.tryParse(
    (await AppPreferencesStore().getString(
              StorageKeys.currentSessionSemesterId,
            ) ??
            '')
        .trim(),
  );
  if (parsed != null && parsed > 0) return parsed;
  return null;
}
