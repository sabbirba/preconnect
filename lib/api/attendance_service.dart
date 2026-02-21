import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:preconnect/api/api_config.dart';
import 'package:preconnect/api/api_client.dart';
import 'package:preconnect/api/profile_service.dart';

class AttendanceService {
  static final AttendanceService _instance = AttendanceService._internal();
  factory AttendanceService() => _instance;
  AttendanceService._internal();

  final ApiClient _client = ApiClient();

  static const String _cacheKey = 'attendance';

  Future<String?> fetchAttendanceInfo({bool fromGet = false}) async {
    final asyncPrefs = SharedPreferencesAsync();
    String? id = await asyncPrefs.getString('id');
    if (id == null || id.isEmpty) {
      await ProfileService().fetchProfile(fromGet: true);
      id = await asyncPrefs.getString('id');
    }
    if (id == null || id.isEmpty) {
      if (fromGet) return null;
      return getAttendanceInfo(fromFetch: true);
    }

    final url = '${ApiConfig.connectApiBase}${ApiConfig.attendancePath(id)}';

    return _client.fetchWithFallback<String>(
      url: url,
      fromGet: fromGet,
      cacheResponse: (response) async {
        final data = jsonDecode(response.body);
        await asyncPrefs.setString(_cacheKey, jsonEncode(data));
      },
      readCache: ({required bool fromFetch}) =>
          getAttendanceInfo(fromFetch: fromFetch),
    );
  }

  Future<String?> getAttendanceInfo({bool fromFetch = false}) async {
    final prefsWithCache = await SharedPreferencesWithCache.create(
      cacheOptions: const SharedPreferencesWithCacheOptions(
        allowList: <String>{_cacheKey},
      ),
    );

    if (fromFetch) await prefsWithCache.reloadCache();

    final String attendanceJson = prefsWithCache.getString(_cacheKey) ?? '';
    if (attendanceJson == '') {
      if (fromFetch) return null;
      return await fetchAttendanceInfo(fromGet: true);
    }
    return attendanceJson;
  }
}
