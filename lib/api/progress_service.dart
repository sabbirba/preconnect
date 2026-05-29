import 'dart:convert';

import 'package:preconnect/tools/app_storage.dart';
import 'package:preconnect/api/api_client.dart';
import 'package:preconnect/api/api_config.dart';
import 'package:preconnect/api/profile_service.dart';
import 'package:preconnect/api/app_preferences_store.dart';
import 'package:preconnect/model/progress_info.dart';

class ProgressService {
  ProgressService._internal();
  static final ProgressService _instance = ProgressService._internal();
  factory ProgressService() => _instance;

  static const String _cacheKey = 'student_progress_v1';
  static const String _summaryCacheKey = 'student_progress_summary_v1';
  static const String _majorMinorsCacheKey = 'student_progress_major_minors_v1';
  static const String _completedCoursesCacheKey =
      'student_progress_completed_courses_v1';
  static const String _curriculumCacheKey = 'student_progress_curriculum_v1';
  static const String _coursePrerequisitesCacheKey =
      'student_progress_course_prerequisites_v1';
  static const List<String> _coursePrerequisitesUrls = <String>[
    '${ApiConfig.publicJsonBase}/data/course-prerequisites.json',
  ];
  static const String _majorMinorsEtagKey = 'student_progress_major_etag_v1';
  static const String _completedCoursesEtagKey =
      'student_progress_completed_etag_v1';
  static const String _curriculumEtagKey = 'student_progress_curr_etag_v1';
  final ApiClient _client = ApiClient();
  final Map<String, Future<ProgressInfo?>> _fetchInFlight =
      <String, Future<ProgressInfo?>>{};

  Future<ProgressInfo?> fetchProgress({bool fromGet = false}) async {
    final inFlightKey = 'progress|$fromGet';
    final inFlight = _fetchInFlight[inFlightKey];
    if (inFlight != null) {
      return await inFlight;
    }
    final request = _fetchProgressInternal(fromGet: fromGet);
    _fetchInFlight[inFlightKey] = request;
    try {
      return await request;
    } finally {
      _fetchInFlight.remove(inFlightKey);
    }
  }

  Future<ProgressInfo?> _fetchProgressInternal({required bool fromGet}) async {
    final asyncPrefs = AppStorage.instance;
    final portfolioId = await resolvePortfolioId(
      prefs: asyncPrefs,
      refreshProfile: () => ProfileService().fetchProfile(fromGet: true),
    );

    if (portfolioId == null || portfolioId.isEmpty) {
      if (fromGet) return null;
      return getProgress(fromFetch: true);
    }

    if (!await _client.hasConnection()) {
      return fromGet ? null : getProgress(fromFetch: true);
    }

    try {
      final majorMinorsUrl =
          '${ApiConfig.connectApiBase}${ApiConfig.majorMinorsPath(portfolioId)}';
      final completedCoursesUrl =
          '${ApiConfig.connectApiBase}${ApiConfig.completedCoursesPath(portfolioId)}';
      final curriculumUrl =
          '${ApiConfig.connectApiBase}${ApiConfig.programCurriculumsPath(portfolioId)}';
      final cache = AppPreferencesStore();

      final etags = await Future.wait<String?>([
        cache.getString(_majorMinorsEtagKey),
        cache.getString(_completedCoursesEtagKey),
        cache.getString(_curriculumEtagKey),
      ]);
      final majorEtag = etags[0];
      final completedEtag = etags[1];
      final curriculumEtag = etags[2];

      final responses = await Future.wait([
        _client.authenticatedGet(
          majorMinorsUrl,
          additionalHeaders: ifNoneMatchHeader(majorEtag),
          acceptedStatusCodes: const <int>{200, 304},
        ),
        _client.authenticatedGet(
          completedCoursesUrl,
          additionalHeaders: ifNoneMatchHeader(completedEtag),
          acceptedStatusCodes: const <int>{200, 304},
        ),
        _client.authenticatedGet(
          curriculumUrl,
          additionalHeaders: ifNoneMatchHeader(curriculumEtag),
          acceptedStatusCodes: const <int>{200, 304},
        ),
      ]);

      final resolved = await Future.wait<dynamic>([
        _resolveComponent(
          cache: cache,
          response: responses[0],
          dataKey: _majorMinorsCacheKey,
          etagKey: _majorMinorsEtagKey,
        ),
        _resolveComponent(
          cache: cache,
          response: responses[1],
          dataKey: _completedCoursesCacheKey,
          etagKey: _completedCoursesEtagKey,
        ),
        _resolveComponent(
          cache: cache,
          response: responses[2],
          dataKey: _curriculumCacheKey,
          etagKey: _curriculumEtagKey,
        ),
        _resolvePublicComponent(
          cache: cache,
          urls: _coursePrerequisitesUrls,
          dataKey: _coursePrerequisitesCacheKey,
        ),
      ]);
      final majorMinors = resolved[0];
      final completedCourses = resolved[1];
      final curriculum = resolved[2];
      final coursePrerequisites = resolved[3];

      if (majorMinors == null ||
          completedCourses == null ||
          curriculum == null) {
        if (fromGet) return null;
        return getProgress(fromFetch: true);
      }

      final payload = <String, dynamic>{
        'majorMinors': majorMinors,
        'completedCourses': completedCourses,
        'curriculum': curriculum,
        'coursePrerequisites': coursePrerequisites,
      };
      final info = ProgressInfo.fromPayload(payload);
      final summary = ProgressSummary.fromProgressInfo(info);
      await cache.setJson(_cacheKey, payload);
      await cache.setJson(_summaryCacheKey, summary.toJson());
      return info;
    } catch (_) {
      if (fromGet) return null;
      return getProgress(fromFetch: true);
    }
  }

  Future<dynamic> _resolveComponent({
    required AppPreferencesStore cache,
    required dynamic response,
    required String dataKey,
    required String etagKey,
  }) async {
    if (response.statusCode == 304) {
      final cached = await cache.getString(dataKey);
      if (cached == null || cached.trim().isEmpty) return null;
      try {
        return jsonDecode(cached);
      } catch (e) {
        return await _readCachedComponent(cache, dataKey);
      }
    }
    if (response.statusCode != 200) return null;
    try {
      final decoded = jsonDecode(response.body);
      await cache.setJson(dataKey, decoded);
      final etag = extractEtagFromHeaders(response.headers);
      if (etag != null && etag.isNotEmpty) {
        await cache.setString(etagKey, etag);
      }
      return decoded;
    } catch (e) {
      return await _readCachedComponent(cache, dataKey);
    }
  }

  Future<dynamic> _resolvePublicComponent({
    required AppPreferencesStore cache,
    required List<String> urls,
    required String dataKey,
  }) async {
    for (final url in urls) {
      try {
        final response = await _client.publicGet(url);
        final decoded = jsonDecode(response.body);
        await cache.setJson(dataKey, decoded);
        return decoded;
      } catch (_) {
        continue;
      }
    }
    final cached = await cache.getString(dataKey);
    if (cached == null || cached.trim().isEmpty) return null;
    return jsonDecode(cached);
  }

  Future<void> preloadCoursePrerequisites() async {
    final cache = AppPreferencesStore();
    await _resolvePublicComponent(
      cache: cache,
      urls: _coursePrerequisitesUrls,
      dataKey: _coursePrerequisitesCacheKey,
    );
  }

  Future<dynamic> _readCachedComponent(
    AppPreferencesStore cache,
    String dataKey,
  ) async {
    final cached = await cache.getString(dataKey);
    if (cached == null || cached.trim().isEmpty) return null;
    try {
      return jsonDecode(cached);
    } catch (_) {
      return null;
    }
  }

  Future<ProgressInfo?> getProgress({bool fromFetch = false}) async {
    return readStoredJsonMapWithFallback<ProgressInfo>(
      key: _cacheKey,
      fromFetch: fromFetch,
      decoder: ProgressInfo.fromPayload,
      onCacheMiss: () async {
        final fetched = await fetchProgress(fromGet: true);
        return fetched;
      },
    );
  }

  Future<ProgressSummary?> getProgressSummary({bool fromFetch = false}) async {
    return readStoredJsonMapWithFallback<ProgressSummary>(
      key: _summaryCacheKey,
      fromFetch: fromFetch,
      decoder: ProgressSummary.fromJson,
      onCacheMiss: () async {
        await fetchProgress(fromGet: true);
        return AppPreferencesStore()
            .getJsonMap(_summaryCacheKey)
            .then(
              (value) => value == null ? null : ProgressSummary.fromJson(value),
            );
      },
    );
  }
}
