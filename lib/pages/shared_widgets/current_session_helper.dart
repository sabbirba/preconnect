import 'package:preconnect/api/profile_service.dart';
import 'package:preconnect/api/app_preferences_store.dart';
import 'package:preconnect/tools/app_storage.dart';
import 'package:preconnect/tools/storage_keys.dart';

Future<int?> resolveCurrentSessionSemesterId() async {
  final cachedFromAppStorage = int.tryParse(
    (await AppStorage.instance.getString(
              StorageKeys.currentSessionSemesterId,
            ) ??
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

Future<int?> resolveCurrentSessionSemesterIdWithRetry({
  int attempts = 10,
  Duration delay = const Duration(milliseconds: 300),
  bool refreshProfileIfMissing = true,
}) async {
  final totalAttempts = attempts < 1 ? 1 : attempts;
  for (var i = 0; i < totalAttempts; i++) {
    final resolved = await resolveCurrentSessionSemesterId();
    if (resolved != null) return resolved;
    if (i == totalAttempts - 1) break;
    await Future<void>.delayed(delay);
  }
  if (refreshProfileIfMissing) {
    try {
      await ProfileService().fetchProfile(fromGet: true);
    } catch (_) {}
    final resolved = await resolveCurrentSessionSemesterId();
    if (resolved != null) return resolved;
  }
  return null;
}
