import 'package:preconnect/api/repository_cache.dart';
import 'package:preconnect/api/schedule.dart';
import 'package:preconnect/tools/storage_keys.dart';

int? _cachedCurrentSessionSemesterId;

Future<int?> resolveCurrentSessionSemesterId({
  bool forceRefresh = false,
}) async {
  if (!forceRefresh &&
      _cachedCurrentSessionSemesterId != null &&
      _cachedCurrentSessionSemesterId! > 0) {
    return _cachedCurrentSessionSemesterId;
  }

  final storedSemesterId = await RepositoryCache.instance.readInt(
    StorageKeys.currentSessionSemesterId,
  );
  if (storedSemesterId != null && storedSemesterId > 0) {
    _cachedCurrentSessionSemesterId = storedSemesterId;
    return storedSemesterId;
  }

  final sessions = await ScheduleService().fetchSemesterSessions(
    forceRefresh: forceRefresh,
  );
  if (sessions.isEmpty) return null;

  final semesterId = sessions.first.semesterSessionId;
  _cachedCurrentSessionSemesterId = semesterId;
  return semesterId;
}

Future<int?> resolveCurrentSessionSemesterIdWithRetry({
  int attempts = 1,
  Duration delay = Duration.zero,
  bool refreshProfileIfMissing = false,
}) {
  return resolveCurrentSessionSemesterId();
}
