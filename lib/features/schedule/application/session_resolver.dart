import 'package:preconnect/api/profile.dart';
import 'package:preconnect/api/repository_cache.dart';
import 'package:preconnect/api/schedule.dart';
import 'package:preconnect/tools/storage_keys.dart';

int? _cachedCurrentSessionSemesterId;

void resetCachedCurrentSessionSemesterId() {
  _cachedCurrentSessionSemesterId = null;
}

Future<int?> resolveCurrentSessionSemesterId({
  bool forceRefresh = false,
}) async {
  if (!forceRefresh &&
      _cachedCurrentSessionSemesterId != null &&
      _cachedCurrentSessionSemesterId! > 0) {
    return _cachedCurrentSessionSemesterId;
  }

  if (!forceRefresh) {
    final storedSemesterId = await RepositoryCache.instance.readInt(
      StorageKeys.currentSessionSemesterId,
    );
    if (storedSemesterId != null && storedSemesterId > 0) {
      _cachedCurrentSessionSemesterId = storedSemesterId;
      return storedSemesterId;
    }
  }

  final sessions = await ScheduleService().fetchSemesterSessions(
    forceRefresh: forceRefresh,
  );
  if (sessions.isEmpty) {
    if (forceRefresh) {
      final storedSemesterId = await RepositoryCache.instance.readInt(
        StorageKeys.currentSessionSemesterId,
      );
      if (storedSemesterId != null && storedSemesterId > 0) {
        _cachedCurrentSessionSemesterId = storedSemesterId;
        return storedSemesterId;
      }
    }
    return null;
  }

  final semesterId = sessions.first.semesterSessionId;
  _cachedCurrentSessionSemesterId = semesterId;
  await RepositoryCache.instance.writeInt(
    StorageKeys.currentSessionSemesterId,
    semesterId,
  );
  return semesterId;
}

Future<int?> resolveCurrentSessionSemesterIdWithRetry({
  int attempts = 1,
  Duration delay = Duration.zero,
  bool refreshProfileIfMissing = false,
}) async {
  final safeAttempts = attempts < 1 ? 1 : attempts;
  for (var attempt = 0; attempt < safeAttempts; attempt++) {
    if (attempt > 0 && delay > Duration.zero) {
      await Future<void>.delayed(delay);
    }
    final resolved = await resolveCurrentSessionSemesterId(
      forceRefresh: attempt > 0,
    );
    if (resolved != null && resolved > 0) return resolved;
  }
  if (refreshProfileIfMissing) {
    try {
      await ProfileService().fetchProfile(fromGet: true);
    } catch (_) {}
    return resolveCurrentSessionSemesterId(forceRefresh: true);
  }
  return null;
}
