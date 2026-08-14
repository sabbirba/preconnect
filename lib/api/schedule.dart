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
import 'package:preconnect/model/advising_phase.dart';
import 'package:preconnect/tools/app_log.dart';
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

  Future<String?> _resolvePortfolioId({bool forceRefresh = false}) {
    return resolvePortfolioId(
      prefs: AppStorage.instance,
      refreshProfile: () => ProfileService().fetchProfile(fromGet: true),
      forceRefresh: forceRefresh,
    );
  }

  static const String _scheduleKey = 'student_schedule_v1';
  String _cacheKeyForSemester(int semesterSessionId) =>
      '${_scheduleKey}_$semesterSessionId';

  static const String _semesterSessionsCacheKey =
      'student_semester_sessions_v1';
  static const String _semesterSessionsFetchedAtKey =
      'student_semester_sessions_v1_fetched_at';

  Future<List<SemesterSessionItem>> fetchSemesterSessions({
    bool forceRefresh = false,
  }) async {
    final repo = RepositoryCache.instance;
    if (!forceRefresh) {
      final fetchedAtMs = await repo.readInt(_semesterSessionsFetchedAtKey);
      final isFresh =
          fetchedAtMs != null &&
          DateTime.now().millisecondsSinceEpoch - fetchedAtMs <
              CacheDurations.semesterSessions.inMilliseconds;
      if (isFresh) {
        final cachedStr = await repo.readString(_semesterSessionsCacheKey);
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
    }
    final id = await _resolvePortfolioId(forceRefresh: forceRefresh);
    if (id == null || id.isEmpty) return const <SemesterSessionItem>[];
    final url = '${ApiConfig.connectApiBase}${ApiConfig.sessionsPath(id)}';
    try {
      final response = await ApiClient().authenticatedGet(
        url,
        cacheDuration: CacheDurations.profileOverview,
        bypassCache: forceRefresh,
      );
      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body);
        if (decoded is List) {
          await repo.writeJson(_semesterSessionsCacheKey, decoded);
          await repo.writeInt(
            _semesterSessionsFetchedAtKey,
            DateTime.now().millisecondsSinceEpoch,
          );
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
          unawaited(
            AppLog.write('Schedule: Fetched ${items.length} semester sessions'),
          );
          return items;
        }
      }
    } catch (error) {
      unawaited(
        AppLog.write(
          'Schedule Error: Failed to fetch semester sessions ($error)',
        ),
      );
    }
    return const <SemesterSessionItem>[];
  }

  Future<List<section.Section>> fetchRelatedLabSections(
    String phaseQueryValue,
  ) async {
    final id = await _resolvePortfolioId();
    if (id == null || id.isEmpty) return const <section.Section>[];
    final url =
        '${ApiConfig.connectApiBase}'
        '${ApiConfig.relatedLabSectionsPath(id, phase: phaseQueryValue)}';
    final response = await ApiClient().authenticatedGet(url);
    return parseStudentSections(response.body);
  }

  Future<List<section.Section>> fetchStudentCoursesForPhase(
    AdvisingPhase phase,
  ) async {
    final id = await _resolvePortfolioId();
    if (id == null || id.isEmpty) return const <section.Section>[];
    final url =
        '${ApiConfig.connectApiBase}'
        '${ApiConfig.studentCoursesForPhasePath(id, phase)}';
    final response = await ApiClient().authenticatedGet(url);
    return parseStudentSections(response.body);
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
      if (decoded case final List<dynamic> list) {
        final sections = list
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
      }
      return const <section.Section>[];
    } catch (_) {
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
    final id = await _resolvePortfolioId(forceRefresh: fromGet);
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
        bypassCache: fromGet,
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        await repo.writeJson(cacheKey, data);
        await asyncPrefs.setString(cacheKey, response.body);
        unawaited(
          AppLog.write(
            'Schedule: Fetched student schedule for semester $semesterSessionId (${response.body.length} bytes)',
          ),
        );
        return response.body;
      }
    } catch (error) {
      unawaited(
        AppLog.write(
          'Schedule Error: Failed to fetch schedule for semester $semesterSessionId ($error)',
        ),
      );
    }

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

  List<section.Section>? getCachedSectionsSync(int semesterSessionId) {
    final raw = AppStorage.instance.getStringSync(
      _cacheKeyForSemester(semesterSessionId),
    );
    if (raw == null || raw.trim().isEmpty) return null;
    return parseStudentSections(raw, semesterSessionId: semesterSessionId);
  }

  List<section.Section>? getStudentSectionsSync([int? semesterSessionId]) {
    try {
      final currentSessionId = AppStorage.instance.getIntSync(
        StorageKeys.currentSessionSemesterId,
      );
      final targetSessionId = semesterSessionId ?? currentSessionId;
      List<section.Section>? sections;
      if (targetSessionId != null && targetSessionId > 0) {
        sections = getCachedSectionsSync(targetSessionId);
      }
      final isCurrentOrUnspecified =
          semesterSessionId == null ||
          currentSessionId == null ||
          semesterSessionId == currentSessionId;
      if ((sections == null || sections.isEmpty) && isCurrentOrUnspecified) {
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
