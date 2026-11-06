import 'package:preconnect/tools/app_storage.dart';
import 'package:preconnect/api/api_client.dart';
import 'package:preconnect/api/api_config.dart';
import 'package:preconnect/api/profile.dart';
import 'package:preconnect/api/repository_cache.dart';
import 'package:preconnect/model/progress_info.dart';
import 'package:preconnect/tools/json_decode.dart';
import 'package:preconnect/tools/preload_cache.dart';

typedef _ProgressComponent = ({dynamic data, String raw});

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
    ApiConfig.coursePrerequisitesUrl,
  ];
  final ApiClient _client = ApiClient();
  final Map<bool, PreloadCache<ProgressInfo?>> _fetches =
      <bool, PreloadCache<ProgressInfo?>>{};

  Future<ProgressInfo?> fetchProgress({
    bool fromGet = false,
    Duration cacheDuration = const Duration(seconds: 30),
  }) {
    return _fetches
        .putIfAbsent(fromGet, PreloadCache<ProgressInfo?>.new)
        .share(
          () => _fetchProgressInternal(
            fromGet: fromGet,
            cacheDuration: cacheDuration,
          ),
        );
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
      final repo = RepositoryCache.instance;
      final prerequisitesFuture = _resolvePublicComponent(
        repo: repo,
        urls: _coursePrerequisitesUrls,
        dataKey: _coursePrerequisitesCacheKey,
      );
      final resolved = await Future.wait<_ProgressComponent?>([
        for (final (path, dataKey) in [
          (ApiConfig.majorMinorsPath(portfolioId), _majorMinorsCacheKey),
          (
            ApiConfig.completedCoursesPath(portfolioId),
            _completedCoursesCacheKey,
          ),
          (ApiConfig.programCurriculumsPath(portfolioId), _curriculumCacheKey),
        ])
          _resolveComponent(
            repo: repo,
            url: '${ApiConfig.connectApiBase}$path',
            cacheDuration: cacheDuration,
            dataKey: dataKey,
          ),
        prerequisitesFuture,
      ]);
      final majorMinors = resolved[0];
      final completedCourses = resolved[1];
      final curriculum = resolved[2];
      final coursePrerequisites = resolved[3];

      if (majorMinors == null ||
          completedCourses == null ||
          curriculum == null) {
        return await getProgress(fromFetch: true);
      }

      final info = ProgressInfo.fromPayload(<String, dynamic>{
        'majorMinors': majorMinors.data,
        'completedCourses': completedCourses.data,
        'curriculum': curriculum.data,
        'coursePrerequisites': coursePrerequisites?.data,
      });
      final summary = ProgressSummary.fromProgressInfo(info);
      await repo.writeString(
        _cacheKey,
        '{"majorMinors":${majorMinors.raw},'
        '"completedCourses":${completedCourses.raw},'
        '"curriculum":${curriculum.raw},'
        '"coursePrerequisites":${coursePrerequisites?.raw ?? 'null'}}',
      );
      await repo.writeJson(_summaryCacheKey, summary.toJson());
      return info;
    } catch (_) {
      return getProgress(fromFetch: true);
    }
  }

  Future<_ProgressComponent?> _resolveComponent({
    required RepositoryCache repo,
    required String url,
    required Duration cacheDuration,
    required String dataKey,
  }) async {
    final response = await _client.authenticatedGet(
      url,
      acceptedStatusCodes: const <int>{200},
      cacheDuration: cacheDuration,
    );
    try {
      final component = await _decodeComponent(response.body);
      await repo.writeString(dataKey, response.body);
      return component;
    } catch (_) {
      return _readCachedComponent(repo, dataKey);
    }
  }

  Future<_ProgressComponent?> _resolvePublicComponent({
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
        final component = await _decodeComponent(response.body);
        await repo.writeString(dataKey, response.body);
        return component;
      } catch (_) {
        continue;
      }
    }
    return _readCachedComponent(repo, dataKey);
  }

  Future<_ProgressComponent> _decodeComponent(String raw) async {
    return (data: await computeJsonDecode(raw), raw: raw);
  }

  Future<_ProgressComponent?> _readCachedComponent(
    RepositoryCache repo,
    String dataKey,
  ) async {
    final cached = await repo.readString(dataKey);
    if (cached == null || cached.trim().isEmpty) return null;
    try {
      return await _decodeComponent(cached);
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

  ProgressInfo? getProgressSync() {
    return RepositoryCache.instance.readJsonSync(
      _cacheKey,
      (decoded) => decoded is Map
          ? ProgressInfo.fromPayload(decoded.cast<String, dynamic>())
          : null,
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
