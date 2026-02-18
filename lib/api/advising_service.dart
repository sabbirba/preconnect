import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:preconnect/api/api_config.dart';
import 'package:preconnect/api/api_client.dart';

class AdvisingService {
  static final AdvisingService _instance = AdvisingService._internal();
  factory AdvisingService() => _instance;
  AdvisingService._internal();

  final ApiClient _client = ApiClient();

  static const List<String> cacheKeys = [
    'advisingStartDate',
    'advisingEndDate',
    'activeSemesterSessionId',
    'advisingPhase',
    'totalCredit',
    'earnedCredit',
    'noOfSemester',
  ];

  Future<Map<String, String?>?> fetchAdvisingInfo({
    bool fromGet = false,
  }) async {
    final asyncPrefs = SharedPreferencesAsync();
    final String? studentId = await asyncPrefs.getString('studentId');
    if (studentId == null || studentId.isEmpty) {
      if (fromGet) return null;
      return getAdvisingInfo(fromFetch: true);
    }

    final url = ApiConfig.advisingUrl(studentId);

    return _client.fetchWithFallback<Map<String, String?>>(
      url: url,
      fromGet: fromGet,
      cacheResponse: (response) async {
        final data = jsonDecode(response.body)[0];
        await asyncPrefs.setString('advisingStartDate', data['startDate']);
        await asyncPrefs.setString('advisingEndDate', data['endDate']);
        await asyncPrefs.setString(
          'activeSemesterSessionId',
          data['activeSemesterSessionId'].toString(),
        );
        await asyncPrefs.setString('advisingPhase', data['advisingPhase']);
        await asyncPrefs.setString(
          'totalCredit',
          data['totalCredit'].toString(),
        );
        await asyncPrefs.setString(
          'earnedCredit',
          data['earnedCredit'].toString(),
        );
        await asyncPrefs.setString(
          'noOfSemester',
          data['noOfSemester'].toString(),
        );
      },
      readCache: ({required bool fromFetch}) =>
          getAdvisingInfo(fromFetch: fromFetch),
    );
  }

  Future<Map<String, String?>?> getAdvisingInfo({
    bool fromFetch = false,
  }) async {
    final prefsWithCache = await SharedPreferencesWithCache.create(
      cacheOptions: SharedPreferencesWithCacheOptions(
        allowList: cacheKeys.toSet(),
      ),
    );

    if (fromFetch) await prefsWithCache.reloadCache();

    final Map<String, String?> advisingData = {};
    for (final key in cacheKeys) {
      advisingData[key] = prefsWithCache.getString(key);
    }

    bool isIncomplete = advisingData.values.any(
      (value) => value == null || value == '',
    );
    if (isIncomplete) {
      if (fromFetch) return null;
      return await fetchAdvisingInfo(fromGet: true);
    }
    return advisingData;
  }
}
