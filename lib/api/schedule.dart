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

class ScheduleService {
  static final ScheduleService _instance = ScheduleService._internal();
  factory ScheduleService() => _instance;
  ScheduleService._internal();

  final Map<String, Future<String?>> _scheduleFetchInFlight =
      <String, Future<String?>>{};

  static const String _scheduleKey = 'student_schedule_v1';
  String _cacheKeyForSemester(int semesterSessionId) =>
      '${_scheduleKey}_$semesterSessionId';

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
          .whereType<Map>()
          .map((e) => e.cast<String, dynamic>())
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
        cacheDuration: const Duration(seconds: 2),
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        await repo.writeJson(cacheKey, data);
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

  Future<List<section.Section>> getUnifiedStudentSchedule({
    required int semesterSessionId,
    bool forceRefresh = false,
  }) async {
    final cachedJson = await getCachedStudentScheduleForSemester(
      semesterSessionId: semesterSessionId,
    );
    final jsonString =
        cachedJson ??
        (forceRefresh
            ? await fetchStudentScheduleForSemester(
                semesterSessionId: semesterSessionId,
                fromGet: true,
              )
            : await getStudentScheduleForSemester(
                semesterSessionId: semesterSessionId,
              ));
    var sections = parseStudentSections(
      jsonString,
      semesterSessionId: semesterSessionId,
    );
    final isRamadan = await RamadanTiming.isRamadan(forceRefresh: forceRefresh);
    if (sections.isEmpty) {
      final cachedSections = await JsonSnapshotStore.readSections();
      if (cachedSections != null && cachedSections.isNotEmpty) {
        sections = cachedSections;
      }
    } else {
      unawaited(
        JsonSnapshotStore.updateSections(sections, isRamadan: isRamadan),
      );
    }
    return sections;
  }
}
