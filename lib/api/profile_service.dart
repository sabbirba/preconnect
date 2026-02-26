import 'dart:async';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:preconnect/api/api_config.dart';
import 'package:preconnect/api/api_client.dart';

class ProfileService {
  static final ProfileService _instance = ProfileService._internal();
  factory ProfileService() => _instance;
  ProfileService._internal();

  final ApiClient _client = ApiClient();
  final Map<String, Future<Map<String, String?>?>> _profileFetchInFlight =
      <String, Future<Map<String, String?>?>>{};
  static const Map<String, String> _bloodTypeIdToLabel = {
    '7157': 'A+',
    '7158': 'B+',
    '7159': 'AB+',
    '7160': 'O+',
    '7161': 'A-',
    '7162': 'B-',
    '7163': 'AB-',
    '7164': 'O-',
  };

  static String _normalizeBloodType({
    required dynamic bloodGroup,
    required dynamic bloodGroupName,
    required dynamic bloodType,
  }) {
    final candidates = <String>{
      bloodGroup?.toString().trim() ?? '',
      bloodGroupName?.toString().trim() ?? '',
      bloodType?.toString().trim() ?? '',
    };
    for (final candidate in candidates) {
      if (candidate.isEmpty) continue;
      final mapped = _bloodTypeIdToLabel[candidate];
      if (mapped != null) return mapped;
    }

    return '';
  }

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
    'permanentAddress',
    'presentAddress',
    'isBothAddressSame',
    'permanentUpazilaName',
    'presentUpazilaName',
    'fatherName',
    'fatherMobileNo',
    'fatherEmail',
    'motherName',
    'motherMobileNo',
    'motherEmail',
    'localGuardianName',
    'localGuardianMobileNo',
    'localGuardianEmail',
    'sponsoredBy',
    'countryName',
    'hobbies',
    'awards',
    'hasDisability',
    'disabilityDetails',
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
  static const Set<String> _miscKeys = {
    'permanentAddress',
    'presentAddress',
    'isBothAddressSame',
    'permanentUpazilaName',
    'presentUpazilaName',
    'fatherName',
    'fatherMobileNo',
    'fatherEmail',
    'motherName',
    'motherMobileNo',
    'motherEmail',
    'localGuardianName',
    'localGuardianMobileNo',
    'localGuardianEmail',
    'sponsoredBy',
    'countryName',
    'hobbies',
    'awards',
    'hasDisability',
    'disabilityDetails',
  };

  static String _boolToYesNo(dynamic value) {
    if (value == null) return '';
    if (value is bool) return value ? 'Yes' : 'No';
    final raw = value.toString().trim().toLowerCase();
    if (raw.isEmpty) return '';
    if (raw == 'true' || raw == '1') return 'Yes';
    if (raw == 'false' || raw == '0') return 'No';
    return value.toString();
  }

  Future<Map<String, String?>?> fetchProfile({bool fromGet = false}) async {
    final inFlightKey = 'profile|$fromGet';
    final inFlight = _profileFetchInFlight[inFlightKey];
    if (inFlight != null) {
      return await inFlight;
    }
    final request = _fetchProfileInternal(fromGet: fromGet);
    _profileFetchInFlight[inFlightKey] = request;
    try {
      return await request;
    } finally {
      _profileFetchInFlight.remove(inFlightKey);
    }
  }

  Future<Map<String, String?>?> _fetchProfileInternal({
    required bool fromGet,
  }) async {
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
            _normalizeBloodType(
              bloodGroup: profile['bloodGroup'],
              bloodGroupName: profile['bloodGroupName'],
              bloodType: profile['bloodType'],
            ),
          );
          await asyncPrefs.setString('mobileNo', profile['mobileNo'] ?? '');
          await asyncPrefs.setString('shortCode', profile['shortCode'] ?? '');
          await asyncPrefs.setString('fullName', profile['fullName'] ?? '');
          await asyncPrefs.setString('email', profile['studentEmail'] ?? '');
          await asyncPrefs.setString('cgpa', profile['cgpa']?.toString() ?? '');

          try {
            final miscUrl =
                '${ApiConfig.connectApiBase}${ApiConfig.miscellaneousInfoPath}';
            final miscResponse = await _client.authenticatedGet(miscUrl);
            final miscData = jsonDecode(miscResponse.body);
            if (miscData is Map<String, dynamic>) {
              final resolvedBloodGroup = _normalizeBloodType(
                bloodGroup: miscData['bloodGroup'],
                bloodGroupName: miscData['bloodGroupName'],
                bloodType: miscData['bloodType'],
              );
              if (resolvedBloodGroup.isNotEmpty) {
                await asyncPrefs.setString('bloodGroup', resolvedBloodGroup);
              }
              await asyncPrefs.setString(
                'permanentAddress',
                miscData['permanentAddress']?.toString() ?? '',
              );
              await asyncPrefs.setString(
                'presentAddress',
                miscData['presentAddress']?.toString() ?? '',
              );
              await asyncPrefs.setString(
                'isBothAddressSame',
                _boolToYesNo(miscData['isBothAddressSame']),
              );
              await asyncPrefs.setString(
                'permanentUpazilaName',
                miscData['permanentUpazilaName']?.toString() ?? '',
              );
              await asyncPrefs.setString(
                'presentUpazilaName',
                miscData['presentUpazilaName']?.toString() ?? '',
              );
              await asyncPrefs.setString(
                'fatherName',
                miscData['fatherName']?.toString() ?? '',
              );
              await asyncPrefs.setString(
                'fatherMobileNo',
                miscData['fatherMobileNo']?.toString() ?? '',
              );
              await asyncPrefs.setString(
                'fatherEmail',
                miscData['fatherEmail']?.toString() ?? '',
              );
              await asyncPrefs.setString(
                'motherName',
                miscData['motherName']?.toString() ?? '',
              );
              await asyncPrefs.setString(
                'motherMobileNo',
                miscData['motherMobileNo']?.toString() ?? '',
              );
              await asyncPrefs.setString(
                'motherEmail',
                miscData['motherEmail']?.toString() ?? '',
              );
              await asyncPrefs.setString(
                'localGuardianName',
                miscData['localGuardianName']?.toString() ?? '',
              );
              await asyncPrefs.setString(
                'localGuardianMobileNo',
                miscData['localGuardianMobileNo']?.toString() ?? '',
              );
              await asyncPrefs.setString(
                'localGuardianEmail',
                miscData['localGuardianEmail']?.toString() ?? '',
              );
              await asyncPrefs.setString(
                'sponsoredBy',
                miscData['sponsoredBy']?.toString() ?? '',
              );
              await asyncPrefs.setString(
                'countryName',
                miscData['countryName']?.toString() ?? '',
              );
              await asyncPrefs.setString(
                'hobbies',
                miscData['hobbies']?.toString() ?? '',
              );
              await asyncPrefs.setString(
                'awards',
                miscData['awards']?.toString() ?? '',
              );
              await asyncPrefs.setString(
                'hasDisability',
                _boolToYesNo(miscData['hasDisability']),
              );
              await asyncPrefs.setString(
                'disabilityDetails',
                miscData['disabilityDetails']?.toString() ?? '',
              );
            }
          } catch (_) {}
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
    if (!fromFetch) {
      final anyMiscMissing = _miscKeys.any((key) {
        final value = profileData[key];
        return value == null || value.isEmpty;
      });
      if (anyMiscMissing) {
        // Keep instant cached load, and silently backfill missing misc fields.
        unawaited(fetchProfile(fromGet: true));
      }
    }
    return profileData;
  }
}
