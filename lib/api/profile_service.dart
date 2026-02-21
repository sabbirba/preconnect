import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:preconnect/api/api_config.dart';
import 'package:preconnect/api/api_client.dart';

class ProfileService {
  static final ProfileService _instance = ProfileService._internal();
  factory ProfileService() => _instance;
  ProfileService._internal();

  final ApiClient _client = ApiClient();

  static const List<String> cacheKeys = [
    'id',
    'studentId',
    'fullName',
    'email',
    'studentEmail',
    'program',
    'programOrCourse',
    'currentSemester',
    'cgpa',
    'earnedCredit',
    'attemptedCredit',
    'enrolledSessionSemesterId',
    'currentSessionSemesterId',
    'enrolledSemester',
    'departmentName',
    'academicType',
    'bloodGroup',
    'mobileNo',
    'shortCode',
    'filePath',
    'photoFilePath',
  ];

  static const Set<String> _requiredKeys = {
    'studentId',
    'fullName',
    'program',
    'currentSemester',
    'enrolledSessionSemesterId',
    'enrolledSemester',
    'mobileNo',
    'photoFilePath',
  };

  Future<Map<String, String?>?> fetchProfile({bool fromGet = false}) async {
    final url = '${ApiConfig.connectApiBase}${ApiConfig.profilePath}';

    return _client.fetchWithFallback<Map<String, String?>>(
      url: url,
      fromGet: fromGet,
      cacheResponse: (response) async {
        final data = jsonDecode(response.body);
        if (data is List && data.isNotEmpty) {
          final profile = data[0];
          final asyncPrefs = SharedPreferencesAsync();
          await asyncPrefs.setString('id', profile['id']?.toString() ?? '');
          await asyncPrefs.setString(
            'studentId',
            profile['studentId']?.toString() ?? '',
          );
          await asyncPrefs.setString(
            'program',
            profile['programOrCourse'] ?? '',
          );
          await asyncPrefs.setString(
            'programOrCourse',
            profile['programOrCourse'] ?? '',
          );
          await asyncPrefs.setString(
            'currentSemester',
            profile['currentSemester'] ?? '',
          );
          await asyncPrefs.setString(
            'earnedCredit',
            profile['earnedCredit']?.toString() ?? '',
          );
          await asyncPrefs.setString(
            'photoFilePath',
            profile['filePath'] ?? '',
          );
          await asyncPrefs.setString('filePath', profile['filePath'] ?? '');
          await asyncPrefs.setString(
            'academicType',
            profile['academicType'] ?? '',
          );
          await asyncPrefs.setString(
            'attemptedCredit',
            profile['attemptedCredit']?.toString() ?? '',
          );
          await asyncPrefs.setString(
            'enrolledSessionSemesterId',
            profile['enrolledSessionSemesterId']?.toString() ?? '',
          );
          await asyncPrefs.setString(
            'currentSessionSemesterId',
            profile['currentSessionSemesterId']?.toString() ?? '',
          );
          await asyncPrefs.setString(
            'enrolledSemester',
            profile['enrolledSemester'] ?? '',
          );
          await asyncPrefs.setString(
            'departmentName',
            profile['departmentName'] ?? '',
          );
          await asyncPrefs.setString(
            'studentEmail',
            profile['studentEmail'] ?? '',
          );
          await asyncPrefs.setString(
            'bloodGroup',
            (profile['bloodGroup'] ?? profile['bloodGroupName'])?.toString() ??
                '',
          );
          await asyncPrefs.setString('mobileNo', profile['mobileNo'] ?? '');
          await asyncPrefs.setString('shortCode', profile['shortCode'] ?? '');
          await asyncPrefs.setString('fullName', profile['fullName'] ?? '');
          await asyncPrefs.setString('email', profile['studentEmail'] ?? '');
          await asyncPrefs.setString('cgpa', profile['cgpa']?.toString() ?? '');
        }
      },
      readCache: ({required bool fromFetch}) =>
          getProfile(fromFetch: fromFetch),
    );
  }

  Future<Map<String, String?>?> getProfile({bool fromFetch = false}) async {
    final prefsWithCache = await SharedPreferencesWithCache.create(
      cacheOptions: SharedPreferencesWithCacheOptions(
        allowList: cacheKeys.toSet(),
      ),
    );

    if (fromFetch) await prefsWithCache.reloadCache();

    final Map<String, String?> profileData = {};
    for (final key in cacheKeys) {
      profileData[key] = prefsWithCache.getString(key);
    }

    final anyRequiredMissing = _requiredKeys.any((key) {
      final value = profileData[key];
      return value == null || value.isEmpty;
    });

    if (anyRequiredMissing && !fromFetch) {
      return await fetchProfile(fromGet: true);
    }
    return profileData;
  }
}
