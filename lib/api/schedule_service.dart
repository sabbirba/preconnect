import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:preconnect/api/api_config.dart';
import 'package:preconnect/api/api_client.dart';
import 'package:preconnect/api/profile_service.dart';

class ScheduleService {
  static final ScheduleService _instance = ScheduleService._internal();
  factory ScheduleService() => _instance;
  ScheduleService._internal();

  final ApiClient _client = ApiClient();

  static const String _cacheKey = 'StudentSchedule';

  Future<String?> fetchStudentSchedule({bool fromGet = false}) async {
    final asyncPrefs = SharedPreferencesAsync();
    String? id = await asyncPrefs.getString('id');
    if (id == null || id.isEmpty) {
      await ProfileService().fetchProfile(fromGet: true);
      id = await asyncPrefs.getString('id');
    }
    if (id == null || id.isEmpty) {
      if (fromGet) return null;
      return getStudentSchedule(fromFetch: true);
    }

    final url = '${ApiConfig.connectApiBase}${ApiConfig.schedulePath(id)}';

    return _client.fetchWithFallback<String>(
      url: url,
      fromGet: fromGet,
      cacheResponse: (response) async {
        final data = jsonDecode(response.body);
        await asyncPrefs.setString(_cacheKey, jsonEncode(data));
      },
      readCache: ({required bool fromFetch}) =>
          getStudentSchedule(fromFetch: fromFetch),
    );
  }

  Future<String?> getStudentSchedule({bool fromFetch = false}) async {
    final prefsWithCache = await SharedPreferencesWithCache.create(
      cacheOptions: const SharedPreferencesWithCacheOptions(
        allowList: <String>{_cacheKey},
      ),
    );

    if (fromFetch) await prefsWithCache.reloadCache();

    final String scheduleJson = prefsWithCache.getString(_cacheKey) ?? '';
    if (scheduleJson == '') {
      if (fromFetch) return null;
      return await fetchStudentSchedule(fromGet: true);
    }
    return scheduleJson;
  }
}
