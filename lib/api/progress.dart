import 'dart:convert';

import 'package:preconnect/tools/app_storage.dart';
import 'package:preconnect/api/api_client.dart';
import 'package:preconnect/api/api_config.dart';
import 'package:preconnect/api/profile.dart';
import 'package:preconnect/api/repository_cache.dart';
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
  final ApiClient _client = ApiClient();
  final Map<String, Future<ProgressInfo?>> _fetchInFlight =
      <String, Future<ProgressInfo?>>{};

  Future<ProgressInfo?> fetchProgress({
    bool fromGet = false,
    Duration cacheDuration = const Duration(seconds: 30),
  }) async {
    final inFlightKey = 'progress|$fromGet';
    final inFlight = _fetchInFlight[inFlightKey];
    if (inFlight != null) {
      return await inFlight;
    }
    final request = _fetchProgressInternal(
      fromGet: fromGet,
      cacheDuration: cacheDuration,
    );
    _fetchInFlight[inFlightKey] = request;
    try {
      return await request;
    } finally {
      _fetchInFlight.remove(inFlightKey);
    }
  }

  Future<ProgressInfo?> _fetchProgressInternal({
    required bool fromGet,
    required Duration cacheDuration,
  }) async {
    final asyncPrefs = AppStorage.instance;
    final portfolioId = await resolvePortfolioId(
      prefs: asyncPrefs,
      refreshProfile: () => ProfileService().fetchProfile(fromGet: true),
    );

    if (portfolioId == null || portfolioId.isEmpty) {
      return getProgress(fromFetch: true);
    }

    if (!await _client.hasConnection()) {
      return getProgress(fromFetch: true);
    }

    try {
      final majorMinorsUrl =
          '${ApiConfig.connectApiBase}${ApiConfig.majorMinorsPath(portfolioId)}';
      final completedCoursesUrl =
          '${ApiConfig.connectApiBase}${ApiConfig.completedCoursesPath(portfolioId)}';
      final curriculumUrl =
          '${ApiConfig.connectApiBase}${ApiConfig.programCurriculumsPath(portfolioId)}';
      final repo = RepositoryCache.instance;

      final responses = await Future.wait([
        _client.authenticatedGet(
          majorMinorsUrl,
          acceptedStatusCodes: const <int>{200},
          cacheDuration: cacheDuration,
        ),
        _client.authenticatedGet(
          completedCoursesUrl,
          acceptedStatusCodes: const <int>{200},
          cacheDuration: cacheDuration,
        ),
        _client.authenticatedGet(
          curriculumUrl,
          acceptedStatusCodes: const <int>{200},
          cacheDuration: cacheDuration,
        ),
      ]);

      final resolved = await Future.wait<dynamic>([
        _resolveComponent(
          repo: repo,
          response: responses[0],
          dataKey: _majorMinorsCacheKey,
        ),
        _resolveComponent(
          repo: repo,
          response: responses[1],
          dataKey: _completedCoursesCacheKey,
        ),
        _resolveComponent(
          repo: repo,
          response: responses[2],
          dataKey: _curriculumCacheKey,
        ),
        _resolvePublicComponent(
          repo: repo,
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
      await repo.writeJson(_cacheKey, payload);
      await repo.writeJson(_summaryCacheKey, summary.toJson());
      return info;
    } catch (_) {
      return getProgress(fromFetch: true);
    }
  }

  Future<dynamic> _resolveComponent({
    required RepositoryCache repo,
    required dynamic response,
    required String dataKey,
  }) async {
    if (response.statusCode != 200) return null;
    try {
      final decoded = jsonDecode(response.body);
      await repo.writeJson(dataKey, decoded);
      return decoded;
    } catch (e) {
      return await _readCachedComponent(repo, dataKey);
    }
  }

  Future<dynamic> _resolvePublicComponent({
    required RepositoryCache repo,
    required List<String> urls,
    required String dataKey,
  }) async {
    for (final url in urls) {
      try {
        final response = await _client.publicGet(
          url,
          cacheDuration: const Duration(minutes: 10),
        );
        final decoded = jsonDecode(response.body);
        await repo.writeJson(dataKey, decoded);
        return decoded;
      } catch (_) {
        continue;
      }
    }
    final cached = await repo.readString(dataKey);
    if (cached == null || cached.trim().isEmpty) return null;
    return jsonDecode(cached);
  }

  Future<void> preloadCoursePrerequisites() async {
    final repo = RepositoryCache.instance;
    await _resolvePublicComponent(
      repo: repo,
      urls: _coursePrerequisitesUrls,
      dataKey: _coursePrerequisitesCacheKey,
    );
  }

  Future<dynamic> _readCachedComponent(
    RepositoryCache repo,
    String dataKey,
  ) async {
    final cached = await repo.readString(dataKey);
    if (cached == null || cached.trim().isEmpty) return null;
    try {
      return jsonDecode(cached);
    } catch (_) {
      return null;
    }
  }

  Future<ProgressInfo?> getProgress({bool fromFetch = false}) async {
    return RepositoryCache.instance.readJsonMapWithFallback<ProgressInfo>(
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
    return RepositoryCache.instance.readJsonMapWithFallback<ProgressSummary>(
      key: _summaryCacheKey,
      fromFetch: fromFetch,
      decoder: ProgressSummary.fromJson,
      onCacheMiss: () async {
        await fetchProgress(fromGet: true);
        return RepositoryCache.instance
            .readJsonMap(_summaryCacheKey)
            .then(
              (value) => value == null ? null : ProgressSummary.fromJson(value),
            );
      },
    );
  }
}
