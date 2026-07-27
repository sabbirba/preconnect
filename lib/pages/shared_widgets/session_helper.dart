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
  final parsed = await RepositoryCache.instance.readInt(
    StorageKeys.currentSessionSemesterId,
  );
  if (parsed != null && parsed > 0) {
    _cachedCurrentSessionSemesterId = parsed;
    return parsed;
  }
  final sessions = await ScheduleService().fetchSemesterSessions(
    forceRefresh: forceRefresh,
  );
  if (sessions.isNotEmpty) {
    _cachedCurrentSessionSemesterId = sessions.first.semesterSessionId;
    return _cachedCurrentSessionSemesterId;
  }
  return null;
}

Future<int?> resolveCurrentSessionSemesterIdWithRetry({
  int attempts = 1,
  Duration delay = Duration.zero,
  bool refreshProfileIfMissing = false,
}) async {
  return resolveCurrentSessionSemesterId();
}

Future<String?> resolveSemesterName([int? semesterSessionId]) async {
  final item = await ScheduleService().resolveSemesterSessionItem(
    semesterSessionId,
  );
  return item?.description;
}
