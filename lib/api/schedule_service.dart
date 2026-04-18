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

  static const String _scheduleKey = 'StudentSchedule';
  static const String _validSemestersKey = 'StudentScheduleValidSemesters';
  static const String _archiveSourceFingerprintKey =
      'StudentScheduleArchiveSourceFingerprint';
  String _cacheKeyForSemester(int? semesterSessionId) =>
      semesterSessionId == null
      ? _scheduleKey
      : '${_scheduleKey}_$semesterSessionId';

  int _guessCurrentSessionId() {
    final now = DateTime.now();
    final code = switch (now.month) {
      >= 1 && <= 4 => 1,
      >= 5 && <= 8 => 2,
      _ => 3,
    };
    return now.year * 10 + code;
  }

  List<int> _buildSessionOptions(int baseSessionId, {int count = 12}) {
    final values = <int>[];
    var cursor = baseSessionId;
    for (var i = 0; i < count; i++) {
      values.add(cursor);
      cursor = _previousSessionId(cursor);
    }
    return values;
  }

  int _previousSessionId(int sessionId) {
    final year = sessionId ~/ 10;
    final code = sessionId % 10;
    return switch (code) {
      3 => (year * 10) + 2,
      2 => (year * 10) + 1,
      1 => ((year - 1) * 10) + 3,
      _ => ((year - 1) * 10) + 3,
    };
  }

  bool _hasAnyScheduleData(String? scheduleJson) {
    if (scheduleJson == null || scheduleJson.trim().isEmpty) return false;
    try {
      final decoded = jsonDecode(scheduleJson);
      return decoded is List && decoded.isNotEmpty;
    } catch (e) {
      return false;
    }
  }

  List<section.Section> parseStudentSections(String? scheduleJson) {
    if (scheduleJson == null || scheduleJson.trim().isEmpty) {
      return const <section.Section>[];
    }
    try {
      final decoded = jsonDecode(scheduleJson);
      if (decoded is! List<dynamic>) return const <section.Section>[];
      return decoded
          .whereType<Map<String, dynamic>>()
          .map(section.Section.fromJson)
          .toList();
    } catch (e) {
      return const <section.Section>[];
    }
  }

  String _scheduleFingerprint(String? scheduleJson) {
    final value = (scheduleJson ?? '').trim();
    if (value.isEmpty) return '';
    var hash = 2166136261;
    for (final codeUnit in value.codeUnits) {
      hash ^= codeUnit;
      hash = (hash * 16777619) & 0xFFFFFFFF;
    }
    return hash.toUnsigned(32).toRadixString(16);
  }

  Future<List<section.Section>> getStudentSections({
    int? semesterSessionId,
    bool forceRefresh = false,
  }) async {
    if (forceRefresh) {
      await fetchStudentScheduleForSemester(
        semesterSessionId: semesterSessionId,
      );
    }
    final jsonString = await getStudentScheduleForSemester(
      semesterSessionId: semesterSessionId,
    );
    return parseStudentSections(jsonString);
  }

  List<int> _decodeSemesterIds(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const <int>[];
      final ids =
          decoded
              .map((e) => e is int ? e : int.tryParse('$e'))
              .whereType<int>()
              .where((id) => id > 0)
              .toSet()
              .toList()
            ..sort((a, b) => b.compareTo(a));
      return ids;
    } catch (e) {
      return const <int>[];
    }
  }

  Future<List<int>> getCachedValidSemesterSessionIds() async {
    final raw = await AppPreferencesStore().getString(_validSemestersKey) ?? '';
    if (raw.trim().isEmpty) return const <int>[];
    return _decodeSemesterIds(raw);
  }

  Future<List<int>> preloadValidSemesterSessionIds({
    int? baseSessionId,
    int count = 12,
    bool forceRefresh = false,
  }) async {
    final store = AppPreferencesStore();
    final cachedRaw = await store.getString(_validSemestersKey);
    final cached = (cachedRaw == null || cachedRaw.trim().isEmpty)
        ? const <int>[]
        : _decodeSemesterIds(cachedRaw);
    if (!forceRefresh && cached.isNotEmpty) {
      return cached;
    }

    final candidates = _buildSessionOptions(
      baseSessionId ?? _guessCurrentSessionId(),
      count: count,
    );
    final available = <int>[];
    const batchSize = 4;
    for (var i = 0; i < candidates.length; i += batchSize) {
      final end = (i + batchSize > candidates.length)
          ? candidates.length
          : i + batchSize;
      final batch = candidates.sublist(i, end);
      final checks = await Future.wait(
        batch.map(
          (sessionId) =>
              _ensureSemesterHasData(sessionId, forceRefresh: forceRefresh),
        ),
      );
      for (var j = 0; j < batch.length; j++) {
        if (checks[j]) available.add(batch[j]);
      }
    }
    available.sort((a, b) => b.compareTo(a));
    await store.setJson(_validSemestersKey, available);
    return available;
  }

  Future<List<int>> refreshArchiveSemesterCacheIfNeeded({
    required String? currentScheduleJson,
    int? baseSessionId,
    int count = 12,
  }) async {
    final store = AppPreferencesStore();
    final currentFingerprint = _scheduleFingerprint(currentScheduleJson);
    final cachedFingerprint =
        await store.getString(_archiveSourceFingerprintKey) ?? '';
    final cached = await getCachedValidSemesterSessionIds();

    if (cached.isNotEmpty && currentFingerprint == cachedFingerprint) {
      return cached;
    }

    final refreshed = await preloadValidSemesterSessionIds(
      baseSessionId: baseSessionId,
      count: count,
      forceRefresh: true,
    );
    await store.setString(_archiveSourceFingerprintKey, currentFingerprint);
    await preloadSemesterScheduleCache(
      semesterSessionIds: refreshed,
      forceRefresh: true,
    );
    return refreshed;
  }

  Future<void> preloadSemesterScheduleCache({
    List<int>? semesterSessionIds,
    bool forceRefresh = false,
  }) async {
    final ids = semesterSessionIds ?? await getCachedValidSemesterSessionIds();
    if (ids.isEmpty) return;

    const batchSize = 4;
    for (var i = 0; i < ids.length; i += batchSize) {
      final end = (i + batchSize > ids.length) ? ids.length : i + batchSize;
      final batch = ids.sublist(i, end);
      await Future.wait(
        batch.map(
          (sessionId) =>
              _ensureSemesterHasData(sessionId, forceRefresh: forceRefresh),
        ),
      );
    }
  }

  Future<bool> _ensureSemesterHasData(
    int sessionId, {
    bool forceRefresh = false,
  }) async {
    String? jsonString;
    if (!forceRefresh) {
      jsonString = await getStudentScheduleForSemester(
        semesterSessionId: sessionId,
        fromFetch: true,
      );
      if (_hasAnyScheduleData(jsonString)) return true;
    }
    jsonString = await fetchStudentScheduleForSemester(
      semesterSessionId: sessionId,
      fromGet: true,
    );
    return _hasAnyScheduleData(jsonString);
  }

  Future<String?> fetchStudentSchedule({bool fromGet = false}) async {
    return fetchStudentScheduleForSemester(
      fromGet: fromGet,
      semesterSessionId: null,
    );
  }

  Future<String?> fetchStudentScheduleForSemester({
    required int? semesterSessionId,
    bool fromGet = false,
  }) async {
    final inFlightKey = '${semesterSessionId ?? -1}|$fromGet';
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
    required int? semesterSessionId,
    required bool fromGet,
  }) async {
    final cacheKey = _cacheKeyForSemester(semesterSessionId);
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

  Future<String?> getStudentSchedule({bool fromFetch = false}) async {
    return getStudentScheduleForSemester(
      semesterSessionId: null,
      fromFetch: fromFetch,
    );
  }

  Future<String?> getStudentScheduleForSemester({
    required int? semesterSessionId,
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
}
