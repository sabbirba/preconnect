import 'dart:convert';
import 'package:preconnect/tools/app_storage.dart';
import 'package:preconnect/api/api_config.dart';
import 'package:preconnect/api/api_client.dart';
import 'package:preconnect/api/profile.dart';
import 'package:preconnect/api/repository_cache.dart';
import 'package:preconnect/model/section_info.dart' as section;

class ScheduleService {
  static final ScheduleService _instance = ScheduleService._internal();
  factory ScheduleService() => _instance;
  ScheduleService._internal();

  final Map<String, Future<String?>> _scheduleFetchInFlight =
      <String, Future<String?>>{};

  static const String _scheduleKey = 'student_schedule_v1';
  static const String _scheduleEtagKey = 'student_schedule_etag_v1';
  String _cacheKeyForSemester(int semesterSessionId) =>
      '${_scheduleKey}_$semesterSessionId';
  String _etagKeyForSemester(int semesterSessionId) =>
      '${_scheduleEtagKey}_$semesterSessionId';

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
      var sections = decoded
          .whereType<Map<String, dynamic>>()
          .map(section.Section.fromJson)
          .toList();
      if (semesterSessionId != null && semesterSessionId > 0) {
        sections = sections
            .where((s) => s.semesterSessionId == semesterSessionId)
            .toList();
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
    final etagKey = _etagKeyForSemester(semesterSessionId);
    final repo = RepositoryCache.instance;
    final asyncPrefs = AppStorage.instance;
    final id = await resolvePortfolioId(
      prefs: asyncPrefs,
      refreshProfile: () => ProfileService().fetchProfile(fromGet: true),
    );
    if (id == null || id.isEmpty) {
      if (fromGet) return null;
      return getStudentScheduleForSemester(
        semesterSessionId: semesterSessionId,
        fromFetch: true,
      );
    }

    final url =
        '${ApiConfig.connectApiBase}'
        '${ApiConfig.schedulePath(id, semesterSessionId: semesterSessionId)}';

    return repo.fetchWithStoredEtag<String>(
      url: url,
      fromGet: fromGet,
      etagKey: etagKey,
      cacheResponse: (response) async {
        final data = jsonDecode(response.body);
        await repo.writeJson(cacheKey, data);
      },
      readCache: ({required bool fromFetch}) => getStudentScheduleForSemester(
        semesterSessionId: semesterSessionId,
        fromFetch: fromFetch,
      ),
    );
  }

  Future<String?> getStudentScheduleForSemester({
    required int semesterSessionId,
    bool fromFetch = false,
  }) async {
    final cacheKey = _cacheKeyForSemester(semesterSessionId);
    return RepositoryCache.instance.readStringWithFallback<String>(
      key: cacheKey,
      fromFetch: fromFetch,
      decoder: (value) => value,
      onCacheMiss: () => fetchStudentScheduleForSemester(
        semesterSessionId: semesterSessionId,
        fromGet: true,
      ),
    );
  }

  Future<String?> getCachedStudentScheduleForSemester({
    required int semesterSessionId,
  }) async {
    return RepositoryCache.instance.readString(
      _cacheKeyForSemester(semesterSessionId),
    );
  }
}
