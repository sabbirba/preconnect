import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:preconnect/api/api_client.dart';
import 'package:preconnect/api/api_config.dart';
import 'package:preconnect/api/profile_service.dart';
import 'package:preconnect/model/progress_info.dart';

class ProgressService {
  ProgressService._internal();
  static final ProgressService _instance = ProgressService._internal();
  factory ProgressService() => _instance;

  static const String _cacheKey = 'StudentProgramProgress';
  static const String _summaryCacheKey = 'StudentProgramProgressSummary';
  static const String _majorMinorsCacheKey =
      'StudentProgramProgressMajorMinors';
  static const String _completedCoursesCacheKey =
      'StudentProgramProgressCompletedCourses';
  static const String _curriculumCacheKey = 'StudentProgramProgressCurriculum';
  static const String _majorMinorsEtagKey = 'StudentProgramProgressMajorEtag';
  static const String _completedCoursesEtagKey =
      'StudentProgramProgressCompletedEtag';
  static const String _curriculumEtagKey = 'StudentProgramProgressCurrEtag';
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
    final asyncPrefs = SharedPreferencesAsync();
    String? portfolioId = await asyncPrefs.getString('id');
    if (portfolioId == null || portfolioId.isEmpty) {
      await ProfileService().fetchProfile(fromGet: true);
      portfolioId = await asyncPrefs.getString('id');
    }

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

      final majorEtag = await asyncPrefs.getString(_majorMinorsEtagKey);
      final completedEtag = await asyncPrefs.getString(
        _completedCoursesEtagKey,
      );
      final curriculumEtag = await asyncPrefs.getString(_curriculumEtagKey);

      final responses = await Future.wait([
        _client.authenticatedGet(
          majorMinorsUrl,
          additionalHeaders: _ifNoneMatchHeader(majorEtag),
          acceptedStatusCodes: const <int>{200, 304},
        ),
        _client.authenticatedGet(
          completedCoursesUrl,
          additionalHeaders: _ifNoneMatchHeader(completedEtag),
          acceptedStatusCodes: const <int>{200, 304},
        ),
        _client.authenticatedGet(
          curriculumUrl,
          additionalHeaders: _ifNoneMatchHeader(curriculumEtag),
          acceptedStatusCodes: const <int>{200, 304},
        ),
      ]);

      final majorMinors = await _resolveComponent(
        prefs: asyncPrefs,
        response: responses[0],
        dataKey: _majorMinorsCacheKey,
        etagKey: _majorMinorsEtagKey,
      );
      final completedCourses = await _resolveComponent(
        prefs: asyncPrefs,
        response: responses[1],
        dataKey: _completedCoursesCacheKey,
        etagKey: _completedCoursesEtagKey,
      );
      final curriculum = await _resolveComponent(
        prefs: asyncPrefs,
        response: responses[2],
        dataKey: _curriculumCacheKey,
        etagKey: _curriculumEtagKey,
      );

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
      };
      final info = ProgressInfo.fromPayload(payload);
      final summary = ProgressSummary.fromProgressInfo(info);
      await asyncPrefs.setString(_cacheKey, jsonEncode(payload));
      await asyncPrefs.setString(
        _summaryCacheKey,
        jsonEncode(summary.toJson()),
      );
      return info;
    } catch (_) {
      if (fromGet) return null;
      return getProgress(fromFetch: true);
    }
  }

  Future<dynamic> _resolveComponent({
    required SharedPreferencesAsync prefs,
    required dynamic response,
    required String dataKey,
    required String etagKey,
  }) async {
    if (response.statusCode == 304) {
      final cached = await prefs.getString(dataKey);
      if (cached == null || cached.trim().isEmpty) return null;
      return jsonDecode(cached);
    }
    if (response.statusCode != 200) return null;
    final decoded = jsonDecode(response.body);
    await prefs.setString(dataKey, jsonEncode(decoded));
    final etag = _extractEtag(response.headers);
    if (etag != null && etag.isNotEmpty) {
      await prefs.setString(etagKey, etag);
    }
    return decoded;
  }

  Map<String, String> _ifNoneMatchHeader(String? etag) {
    final value = (etag ?? '').trim();
    if (value.isEmpty) return const <String, String>{};
    return <String, String>{'If-None-Match': value};
  }

  String? _extractEtag(Map<String, String> headers) {
    for (final entry in headers.entries) {
      if (entry.key.toLowerCase() == 'etag') {
        final value = entry.value.trim();
        if (value.isNotEmpty) return value;
      }
    }
    return null;
  }

  Future<ProgressInfo?> getProgress({bool fromFetch = false}) async {
    final prefsWithCache = await SharedPreferencesWithCache.create(
      cacheOptions: const SharedPreferencesWithCacheOptions(
        allowList: <String>{_cacheKey},
      ),
    );

    if (fromFetch) {
      await prefsWithCache.reloadCache();
    }

    final cached = prefsWithCache.getString(_cacheKey) ?? '';
    if (cached.isEmpty) {
      if (fromFetch) return null;
      return fetchProgress(fromGet: true);
    }

    try {
      final payload = jsonDecode(cached);
      if (payload is! Map<String, dynamic>) {
        if (fromFetch) return null;
        return fetchProgress(fromGet: true);
      }
      return ProgressInfo.fromPayload(payload);
    } catch (_) {
      if (fromFetch) return null;
      return fetchProgress(fromGet: true);
    }
  }

  Future<ProgressSummary?> getProgressSummary({bool fromFetch = false}) async {
    final prefsWithCache = await SharedPreferencesWithCache.create(
      cacheOptions: const SharedPreferencesWithCacheOptions(
        allowList: <String>{_summaryCacheKey},
      ),
    );

    if (fromFetch) {
      await prefsWithCache.reloadCache();
    }

    final cached = prefsWithCache.getString(_summaryCacheKey) ?? '';
    if (cached.isEmpty) {
      if (fromFetch) return null;
      await fetchProgress(fromGet: true);
      return getProgressSummary(fromFetch: true);
    }

    try {
      final decoded = jsonDecode(cached);
      if (decoded is! Map<String, dynamic>) return null;
      return ProgressSummary.fromJson(decoded);
    } catch (_) {
      return null;
    }
  }
}
