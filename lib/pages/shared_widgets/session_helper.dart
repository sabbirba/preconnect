import 'package:preconnect/api/repository_cache.dart';
import 'package:preconnect/api/schedule.dart';
import 'package:preconnect/tools/storage_keys.dart';

Future<int?> resolveCurrentSessionSemesterId() async {
  final parsed = await RepositoryCache.instance.readInt(
    StorageKeys.currentSessionSemesterId,
  );
  if (parsed != null && parsed > 0) return parsed;
  final sessions = await ScheduleService().fetchSemesterSessions();
  if (sessions.isNotEmpty) {
    return sessions.first.semesterSessionId;
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
