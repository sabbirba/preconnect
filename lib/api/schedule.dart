import 'dart:async';
import 'dart:convert';
import 'package:preconnect/tools/app_storage.dart';
import 'package:preconnect/api/api_config.dart';
import 'package:preconnect/api/api_client.dart';
import 'package:preconnect/api/profile.dart';
import 'package:preconnect/api/repository_cache.dart';
import 'package:preconnect/tools/ramadan.dart';
import 'package:preconnect/tools/snapshot_store.dart';
import 'package:preconnect/model/section_info.dart' as section;
import 'package:preconnect/tools/cache_durations.dart';
import 'package:preconnect/tools/storage_keys.dart';

class SemesterSessionItem {
  final int semesterSessionId;
  final String description;

  const SemesterSessionItem({
    required this.semesterSessionId,
    required this.description,
  });

  factory SemesterSessionItem.fromJson(Map<String, dynamic> json) {
    final rawId = json['semesterSessionId'] ?? json['id'] ?? json['sessionId'];
    final id = rawId is num
        ? rawId.toInt()
        : int.tryParse(rawId?.toString() ?? '') ?? 0;
    final desc =
        (json['description'] ??
                json['name'] ??
                json['semesterSessionName'] ??
                json['title'] ??
                '')
            .toString();
    return SemesterSessionItem(semesterSessionId: id, description: desc);
  }

  Map<String, dynamic> toJson() => {
    'semesterSessionId': semesterSessionId,
    'description': description,
  };
}

class ScheduleService {
  static final ScheduleService _instance = ScheduleService._internal();
  factory ScheduleService() => _instance;
  ScheduleService._internal();

  final Map<String, Future<String?>> _scheduleFetchInFlight =
      <String, Future<String?>>{};

  static const String _scheduleKey = 'student_schedule_v1';
  String _cacheKeyForSemester(int semesterSessionId) =>
      '${_scheduleKey}_$semesterSessionId';

  Future<List<SemesterSessionItem>> fetchSemesterSessions({
    bool forceRefresh = false,
  }) async {
    final repo = RepositoryCache.instance;
    const cacheKey = 'student_semester_sessions_v1';
    if (!forceRefresh) {
      final cachedStr = await repo.readString(cacheKey);
      if (cachedStr != null && cachedStr.isNotEmpty) {
        try {
          final decoded = jsonDecode(cachedStr);
          if (decoded is List) {
            final items = decoded
                .whereType<Map>()
                .map(
                  (e) =>
                      SemesterSessionItem.fromJson(e.cast<String, dynamic>()),
                )
                .where((e) => e.semesterSessionId > 0)
                .toList();
            if (items.isNotEmpty) {
              items.sort(
                (a, b) => b.semesterSessionId.compareTo(a.semesterSessionId),
              );
              return items;
            }
          }
        } catch (_) {}
      }
    }
    final asyncPrefs = AppStorage.instance;
    final id = await resolvePortfolioId(
      prefs: asyncPrefs,
      refreshProfile: () => ProfileService().fetchProfile(fromGet: true),
    );
    if (id == null || id.isEmpty) return const <SemesterSessionItem>[];
    final url = '${ApiConfig.connectApiBase}${ApiConfig.sessionsPath(id)}';
    try {
      final response = await ApiClient().authenticatedGet(
        url,
        cacheDuration: CacheDurations.profileOverview,
      );
      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body);
        if (decoded is List) {
          await repo.writeJson(cacheKey, decoded);
          final items = decoded
              .whereType<Map>()
              .map(
                (e) => SemesterSessionItem.fromJson(e.cast<String, dynamic>()),
              )
              .where((e) => e.semesterSessionId > 0)
              .toList();
          items.sort(
            (a, b) => b.semesterSessionId.compareTo(a.semesterSessionId),
          );
          return items;
        }
      }
    } catch (_) {}
    return const <SemesterSessionItem>[];
  }

  Future<SemesterSessionItem?> resolveSemesterSessionItem(
    int? semesterSessionId, {
    bool forceRefresh = false,
  }) async {
    final sessions = await fetchSemesterSessions(forceRefresh: forceRefresh);
    if (sessions.isEmpty) return null;
    if (semesterSessionId == null || semesterSessionId <= 0) {
      return sessions.first;
    }
    return sessions.firstWhere(
      (s) => s.semesterSessionId == semesterSessionId,
      orElse: () => sessions.first,
    );
  }

  List<section.Section> parseStudentSections(
    String? scheduleJson, {
    int? semesterSessionId,
  }) {
    if (scheduleJson == null || scheduleJson.trim().isEmpty) {
      return const <section.Section>[];
    }
    try {
      final decoded = jsonDecode(scheduleJson);
      if (decoded is! List<dynamic>) return const <section.Section>[];
      final sections = decoded
          .whereType<Map>()
          .map((e) => e.cast<String, dynamic>())
          .map(section.Section.fromJson)
          .toList();
      if (semesterSessionId != null && semesterSessionId > 0) {
        final filtered = sections
            .where(
              (s) =>
                  s.semesterSessionId == semesterSessionId ||
                  s.semesterSessionId == 0,
            )
            .toList();
        if (filtered.isNotEmpty) return filtered;
      }
      return sections;
    } catch (e) {
      return const <section.Section>[];
    }
  }

  Future<String?> fetchStudentScheduleForSemester({
    required int semesterSessionId,
    bool fromGet = false,
  }) async {
    final inFlightKey = '$semesterSessionId|$fromGet';
    final inFlight = _scheduleFetchInFlight[inFlightKey];
    if (inFlight != null) {
      return await inFlight;
    }
    final request = _fetchStudentScheduleForSemesterInternal(
      semesterSessionId: semesterSessionId,
      fromGet: fromGet,
    );
    _scheduleFetchInFlight[inFlightKey] = request;
    try {
      return await request;
    } finally {
      _scheduleFetchInFlight.remove(inFlightKey);
    }
  }

  Future<String?> _fetchStudentScheduleForSemesterInternal({
    required int semesterSessionId,
    required bool fromGet,
  }) async {
    final cacheKey = _cacheKeyForSemester(semesterSessionId);
    final repo = RepositoryCache.instance;
    final asyncPrefs = AppStorage.instance;
    final id = await resolvePortfolioId(
      prefs: asyncPrefs,
      refreshProfile: () => ProfileService().fetchProfile(fromGet: true),
    );
    if (id == null || id.isEmpty) {
      return getStudentScheduleForSemester(
        semesterSessionId: semesterSessionId,
        fromFetch: true,
      );
    }

    final url =
        '${ApiConfig.connectApiBase}'
        '${ApiConfig.schedulePath(id, semesterSessionId: semesterSessionId)}';

    try {
      final response = await ApiClient().authenticatedGet(
        url,
        cacheDuration: CacheDurations.short,
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        await repo.writeJson(cacheKey, data);
        await asyncPrefs.setString(cacheKey, response.body);
        return response.body;
      }
    } catch (_) {}

    return getStudentScheduleForSemester(
      semesterSessionId: semesterSessionId,
      fromFetch: true,
    );
  }

  Future<String?> getStudentScheduleForSemester({
    required int semesterSessionId,
    bool fromFetch = false,
  }) async {
    final cacheKey = _cacheKeyForSemester(semesterSessionId);
    return RepositoryCache.instance.readString(cacheKey);
  }

  Future<String?> getCachedStudentScheduleForSemester({
    required int semesterSessionId,
  }) async {
    return RepositoryCache.instance.readString(
      _cacheKeyForSemester(semesterSessionId),
    );
  }

  Future<void> preloadAllSemesters({bool forceRefresh = false}) async {
    final sessions = await fetchSemesterSessions(forceRefresh: forceRefresh);
    for (final s in sessions) {
      if (s.semesterSessionId <= 0) continue;
      await getUnifiedStudentSchedule(
        semesterSessionId: s.semesterSessionId,
        forceRefresh: forceRefresh,
      );
    }
  }

  List<section.Section>? getCachedSectionsSync(int semesterSessionId) {
    final raw = AppStorage.instance.getStringSync(
      _cacheKeyForSemester(semesterSessionId),
    );
    if (raw == null || raw.trim().isEmpty) return null;
    return parseStudentSections(raw, semesterSessionId: semesterSessionId);
  }

  List<section.Section>? getStudentSectionsSync([int? semesterSessionId]) {
    try {
      final targetSessionId =
          semesterSessionId ??
          AppStorage.instance.getIntSync(StorageKeys.currentSessionSemesterId);
      List<section.Section>? sections;
      if (targetSessionId != null && targetSessionId > 0) {
        sections = getCachedSectionsSync(targetSessionId);
      }
      if (sections == null || sections.isEmpty) {
        final raw = AppStorage.instance.getStringSync(
          StorageKeys.alarmsSnapshot,
        );
        if (raw != null && raw.trim().isNotEmpty) {
          final decoded = jsonDecode(raw);
          if (decoded is Map<String, dynamic> && decoded['sections'] is List) {
            sections = (decoded['sections'] as List)
                .whereType<Map>()
                .map((e) => section.Section.fromJson(e.cast<String, dynamic>()))
                .toList(growable: false);
          }
        }
      }
      return sections;
    } catch (_) {
      return null;
    }
  }

  Future<List<section.Section>> getUnifiedStudentSchedule({
    required int semesterSessionId,
    bool forceRefresh = false,
  }) async {
    final cachedJson = !forceRefresh
        ? await getCachedStudentScheduleForSemester(
            semesterSessionId: semesterSessionId,
          )
        : null;
    final jsonString =
        cachedJson ??
        await fetchStudentScheduleForSemester(
          semesterSessionId: semesterSessionId,
          fromGet: forceRefresh,
        );
    final sections = parseStudentSections(
      jsonString,
      semesterSessionId: semesterSessionId,
    );
    final isRamadan = await RamadanTiming.isRamadan(forceRefresh: forceRefresh);
    final currentSessionId = AppStorage.instance.getIntSync(
      StorageKeys.currentSessionSemesterId,
    );
    if (sections.isNotEmpty &&
        (currentSessionId == null || semesterSessionId == currentSessionId)) {
      unawaited(
        JsonSnapshotStore.updateSections(sections, isRamadan: isRamadan),
      );
    }
    return sections;
  }
}
