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
  final ApiClient _client = ApiClient();

  Future<ProgressInfo?> fetchProgress({bool fromGet = false}) async {
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

      final responses = await Future.wait([
        _client.authenticatedGet(majorMinorsUrl),
        _client.authenticatedGet(completedCoursesUrl),
        _client.authenticatedGet(curriculumUrl),
      ]);

      final payload = {
        'majorMinors': jsonDecode(responses[0].body),
        'completedCourses': jsonDecode(responses[1].body),
        'curriculum': jsonDecode(responses[2].body),
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
