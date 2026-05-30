import 'dart:convert';
import 'package:preconnect/tools/app_storage.dart';
import 'package:preconnect/api/api_config.dart';
import 'package:preconnect/api/api_client.dart';
import 'package:preconnect/api/profile_service.dart';
import 'package:preconnect/api/app_preferences_store.dart';
import 'package:preconnect/model/section_info.dart' as section;

class ScheduleService {
  static final ScheduleService _instance = ScheduleService._internal();
  factory ScheduleService() => _instance;
  ScheduleService._internal();

  final ApiClient _client = ApiClient();
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
    final store = AppPreferencesStore();
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

    return _client.fetchWithFallback<String>(
      url: url,
      fromGet: fromGet,
      etag: await store.getString(etagKey),
      cacheEtag: (etag) => store.setString(etagKey, etag),
      cacheResponse: (response) async {
        final data = jsonDecode(response.body);
        await store.setJson(cacheKey, data);
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
    return readStoredStringWithFallback(
      key: cacheKey,
      fromFetch: fromFetch,
      onCacheMiss: () => fetchStudentScheduleForSemester(
        semesterSessionId: semesterSessionId,
        fromGet: true,
      ),
    );
  }

  Future<String?> getCachedStudentScheduleForSemester({
    required int semesterSessionId,
  }) async {
    return AppPreferencesStore().getString(
      _cacheKeyForSemester(semesterSessionId),
    );
  }
}
