import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:preconnect/tools/app_storage.dart';
import 'package:preconnect/api/api_config.dart';
import 'package:preconnect/api/api_client.dart';
import 'package:preconnect/api/repository_cache.dart';
import 'package:preconnect/tools/storage_keys.dart';
import 'package:preconnect/tools/preconnect_constants.dart';
import 'package:preconnect/tools/token_storage.dart';
import 'package:preconnect/tools/cache_durations.dart';
import 'package:preconnect/tools/app_log.dart';

part 'profile_sections/profile_models.dart';

void _recordProfileError(String operation, Object error) {
  unawaited(AppLog.write('$operation failed: $error'));
}

class ProfileService {
  static final ProfileService _instance = ProfileService._();
  factory ProfileService() => _instance;
  ProfileService._();

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

  static const List<String> profileFields = [
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
    'dateOfBirth',
    'nationalIdNo',
    'passportNo',
    'birthCertificateNo',
    'emergencyContactNo',
    'emergencyContactName',
  ];

  static const Set<String> _requiredKeys = {
    'studentId',
    'fullName',
    'program',
    'currentSemester',
    'enrolledSessionSemesterId',
    'currentSessionSemesterId',
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
    'dateOfBirth',
    'nationalIdNo',
    'passportNo',
    'birthCertificateNo',
    'emergencyContactNo',
    'emergencyContactName',
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
    final repo = RepositoryCache.instance;

    try {
      final response = await ApiClient().authenticatedGet(
        url,
        cacheDuration: CacheDurations.profileOverview,
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data is List && data.isNotEmpty) {
          await AppStorage.instance.setString(
            StorageKeys.portfolios,
            jsonEncode(data),
          );
          final activeProfile = data.firstWhere(
            (p) =>
                p is Map &&
                (p['hasCompleted'] == false || p['isCurrent'] == true),
            orElse: () =>
                data.lastWhere((p) => p is Map, orElse: () => data[0]),
          );
          final profile = activeProfile is Map ? activeProfile : data[0];
          await repo.writeStringMap(<String, String>{
            'id': profile['id']?.toString() ?? '',
            'studentId': profile['studentId']?.toString() ?? '',
            'program': profile['programOrCourse'] ?? '',
            'programOrCourse': profile['programOrCourse'] ?? '',
            'currentSemester': profile['currentSemester'] ?? '',
            'earnedCredit': profile['earnedCredit']?.toString() ?? '',
            'photoFilePath': profile['filePath'] ?? '',
            'filePath': profile['filePath'] ?? '',
            'academicType': profile['academicType'] ?? '',
            'attemptedCredit': profile['attemptedCredit']?.toString() ?? '',
            'enrolledSessionSemesterId':
                profile['enrolledSessionSemesterId']?.toString() ?? '',
            'currentSessionSemesterId':
                profile['currentSessionSemesterId']?.toString() ?? '',
            'enrolledSemester': profile['enrolledSemester'] ?? '',
            'departmentName': profile['departmentName'] ?? '',
            'studentEmail': profile['studentEmail'] ?? '',
            'bloodGroup': _normalizeBloodType(
              bloodGroup: profile['bloodGroup'],
              bloodGroupName: profile['bloodGroupName'],
              bloodType: profile['bloodType'],
            ),
            'mobileNo': profile['mobileNo'] ?? '',
            'shortCode': profile['shortCode'] ?? '',
            'fullName': profile['fullName'] ?? '',
            'email': profile['studentEmail'] ?? '',
            'cgpa': profile['cgpa']?.toString() ?? '',
          });
          await AppStorage.instance.setString(
            StorageKeys.studentId,
            profile['studentId']?.toString() ?? '',
          );
          await AppStorage.instance.setString(
            StorageKeys.fullName,
            profile['fullName'] ?? '',
          );
          await AppStorage.instance.setString(
            StorageKeys.studentEmail,
            profile['studentEmail'] ?? '',
          );
          await AppStorage.instance.setString(
            StorageKeys.shortCode,
            profile['shortCode']?.toString() ?? '',
          );
          await AppStorage.instance.setString(
            StorageKeys.program,
            profile['programOrCourse']?.toString() ?? '',
          );
          await AppStorage.instance.setString(
            StorageKeys.departmentName,
            profile['departmentName']?.toString() ?? '',
          );
          await AppStorage.instance.setString(
            StorageKeys.currentSemester,
            profile['currentSemester']?.toString() ?? '',
          );
          await AppStorage.instance.setString(
            StorageKeys.cgpa,
            profile['cgpa']?.toString() ?? '',
          );
          await AppStorage.instance.setString(
            StorageKeys.earnedCredit,
            profile['earnedCredit']?.toString() ?? '',
          );
          await AppStorage.instance.setString(
            StorageKeys.attemptedCredit,
            profile['attemptedCredit']?.toString() ?? '',
          );
          await AppStorage.instance.setString(
            StorageKeys.photoFilePath,
            profile['filePath']?.toString() ?? '',
          );
          await AppStorage.instance.setString(
            StorageKeys.mobileNo,
            profile['mobileNo']?.toString() ?? '',
          );
          await AppStorage.instance.setString(
            StorageKeys.bloodGroup,
            profile['bloodGroup']?.toString() ?? '',
          );
          final currentSessionSemesterId =
              profile['currentSessionSemesterId']?.toString().trim() ?? '';
          if (currentSessionSemesterId.isNotEmpty) {
            await AppStorage.instance.setString(
              StorageKeys.currentSessionSemesterId,
              currentSessionSemesterId,
            );
          }
        }
      }
    } catch (error) {
      _recordProfileError('Profile fetch', error);
    }

    final profile = await getProfile(fromFetch: true);

    if (profile == null) return null;

    final anyMiscMissing = _miscKeys.any((key) {
      final value = profile[key];
      return value == null || value.isEmpty;
    });

    if (anyMiscMissing || fromGet) {
      try {
        final miscUrl =
            '${ApiConfig.connectApiBase}${ApiConfig.miscellaneousInfoPath}';
        final miscResponse = await _client.authenticatedGet(
          miscUrl,
          cacheDuration: CacheDurations.profileOverview,
        );
        final miscData = jsonDecode(miscResponse.body);
        if (miscData is Map<String, dynamic>) {
          final resolvedBloodGroup = _normalizeBloodType(
            bloodGroup: miscData['bloodGroup'],
            bloodGroupName: miscData['bloodGroupName'],
            bloodType: miscData['bloodType'],
          );
          final updates = <String, String>{
            if (resolvedBloodGroup.isNotEmpty) 'bloodGroup': resolvedBloodGroup,
            'permanentAddress': miscData['permanentAddress']?.toString() ?? '',
            'presentAddress': miscData['presentAddress']?.toString() ?? '',
            'isBothAddressSame': _boolToYesNo(miscData['isBothAddressSame']),
            'permanentUpazilaName':
                miscData['permanentUpazilaName']?.toString() ?? '',
            'presentUpazilaName':
                miscData['presentUpazilaName']?.toString() ?? '',
            'fatherName': miscData['fatherName']?.toString() ?? '',
            'fatherMobileNo': miscData['fatherMobileNo']?.toString() ?? '',
            'fatherEmail': miscData['fatherEmail']?.toString() ?? '',
            'motherName': miscData['motherName']?.toString() ?? '',
            'motherMobileNo': miscData['motherMobileNo']?.toString() ?? '',
            'motherEmail': miscData['motherEmail']?.toString() ?? '',
            'localGuardianName':
                miscData['localGuardianName']?.toString() ?? '',
            'localGuardianMobileNo':
                miscData['localGuardianMobileNo']?.toString() ?? '',
            'localGuardianEmail':
                miscData['localGuardianEmail']?.toString() ?? '',
            'sponsoredBy': miscData['sponsoredBy']?.toString() ?? '',
            'countryName': miscData['countryName']?.toString() ?? '',
            'hobbies': miscData['hobbies']?.toString() ?? '',
            'awards': miscData['awards']?.toString() ?? '',
            'hasDisability': _boolToYesNo(miscData['hasDisability']),
            'disabilityDetails':
                miscData['disabilityDetails']?.toString() ?? '',
          };
          await repo.writeStringMap(updates);
          for (final entry in updates.entries) {
            profile[entry.key] = entry.value;
          }
          await AppStorage.instance.setString(
            StorageKeys.permanentAddress,
            miscData['permanentAddress']?.toString() ?? '',
          );
          await AppStorage.instance.setString(
            StorageKeys.presentAddress,
            miscData['presentAddress']?.toString() ?? '',
          );
          await AppStorage.instance.setString(
            StorageKeys.isBothAddressSame,
            _boolToYesNo(miscData['isBothAddressSame']),
          );
          await AppStorage.instance.setString(
            StorageKeys.permanentUpazilaName,
            miscData['permanentUpazilaName']?.toString() ?? '',
          );
          await AppStorage.instance.setString(
            StorageKeys.presentUpazilaName,
            miscData['presentUpazilaName']?.toString() ?? '',
          );
          await AppStorage.instance.setString(
            StorageKeys.fatherName,
            miscData['fatherName']?.toString() ?? '',
          );
          await AppStorage.instance.setString(
            StorageKeys.fatherMobileNo,
            miscData['fatherMobileNo']?.toString() ?? '',
          );
          await AppStorage.instance.setString(
            StorageKeys.fatherEmail,
            miscData['fatherEmail']?.toString() ?? '',
          );
          await AppStorage.instance.setString(
            StorageKeys.motherName,
            miscData['motherName']?.toString() ?? '',
          );
          await AppStorage.instance.setString(
            StorageKeys.motherMobileNo,
            miscData['motherMobileNo']?.toString() ?? '',
          );
          await AppStorage.instance.setString(
            StorageKeys.motherEmail,
            miscData['motherEmail']?.toString() ?? '',
          );
          await AppStorage.instance.setString(
            StorageKeys.localGuardianName,
            miscData['localGuardianName']?.toString() ?? '',
          );
          await AppStorage.instance.setString(
            StorageKeys.localGuardianMobileNo,
            miscData['localGuardianMobileNo']?.toString() ?? '',
          );
          await AppStorage.instance.setString(
            StorageKeys.localGuardianEmail,
            miscData['localGuardianEmail']?.toString() ?? '',
          );
          await AppStorage.instance.setString(
            StorageKeys.sponsoredBy,
            miscData['sponsoredBy']?.toString() ?? '',
          );
          await AppStorage.instance.setString(
            StorageKeys.countryName,
            miscData['countryName']?.toString() ?? '',
          );
          await AppStorage.instance.setString(
            StorageKeys.hobbies,
            miscData['hobbies']?.toString() ?? '',
          );
          await AppStorage.instance.setString(
            StorageKeys.awards,
            miscData['awards']?.toString() ?? '',
          );
          await AppStorage.instance.setString(
            StorageKeys.hasDisability,
            _boolToYesNo(miscData['hasDisability']),
          );
          await AppStorage.instance.setString(
            StorageKeys.disabilityDetails,
            miscData['disabilityDetails']?.toString() ?? '',
          );
        }
      } catch (error) {
        _recordProfileError('Profile miscellaneous data fetch', error);
      }

      try {
        final studentUrl =
            '${ApiConfig.connectApiBase}${ApiConfig.studentPath}';
        final studentResponse = await _client.authenticatedGet(
          studentUrl,
          cacheDuration: CacheDurations.profileOverview,
        );
        final studentData = jsonDecode(studentResponse.body);
        if (studentData is Map<String, dynamic>) {
          final updates = <String, String>{
            'dateOfBirth': studentData['dateOfBirth']?.toString() ?? '',
            'nationalIdNo': studentData['nationalIdNo']?.toString() ?? '',
            'passportNo': studentData['passportNo']?.toString() ?? '',
            'birthCertificateNo':
                studentData['birthCertificateNo']?.toString() ?? '',
            'emergencyContactNo':
                studentData['emergencyContactNo']?.toString() ?? '',
            'emergencyContactName':
                studentData['emergencyContactName']?.toString() ?? '',
          };
          await repo.writeStringMap(updates);
          for (final entry in updates.entries) {
            profile[entry.key] = entry.value;
          }
          await AppStorage.instance.setString(
            StorageKeys.dateOfBirth,
            studentData['dateOfBirth']?.toString() ?? '',
          );
          await AppStorage.instance.setString(
            StorageKeys.nationalIdNo,
            studentData['nationalIdNo']?.toString() ?? '',
          );
          await AppStorage.instance.setString(
            StorageKeys.passportNo,
            studentData['passportNo']?.toString() ?? '',
          );
          await AppStorage.instance.setString(
            StorageKeys.birthCertificateNo,
            studentData['birthCertificateNo']?.toString() ?? '',
          );
          await AppStorage.instance.setString(
            StorageKeys.emergencyContactNo,
            studentData['emergencyContactNo']?.toString() ?? '',
          );
          await AppStorage.instance.setString(
            StorageKeys.emergencyContactName,
            studentData['emergencyContactName']?.toString() ?? '',
          );
        }
      } catch (error) {
        _recordProfileError('Student identity fetch', error);
      }
    }

    return profile;
  }

  Future<Map<String, String?>?> getProfile({bool fromFetch = false}) async {
    final profileData = await RepositoryCache.instance
        .readStringMapWithFallback(
          keys: profileFields.toSet(),
          fromFetch: fromFetch,
          decoder: (value) => value,
          onCacheMiss: () async {
            final fetched = await fetchProfile(fromGet: true);
            return fetched;
          },
        );
    if (profileData == null) return null;
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
        unawaited(fetchProfile(fromGet: true));
      }
    }
    return profileData;
  }
}

class AdvisingService {
  static final AdvisingService _instance = AdvisingService._();
  factory AdvisingService() => _instance;
  AdvisingService._();

  static const List<String> storedProfileKeys = [
    'advisingStartDate',
    'advisingEndDate',
    'activeSemesterSessionId',
    'advisingPhase',
    'totalCredit',
    'earnedCredit',
    'noOfSemester',
    'semesterSession',
  ];

  Future<Map<String, String?>?> fetchAdvisingInfo({
    bool fromGet = false,
    Duration cacheDuration = CacheDurations.short,
  }) async {
    final asyncPrefs = AppStorage.instance;
    final repo = RepositoryCache.instance;
    String? studentId = await repo.readString('studentId');
    studentId ??= await asyncPrefs.getString('studentId');
    if (studentId == null || studentId.isEmpty) {
      final profile = await ProfileService().getProfile(fromFetch: true);
      studentId = profile?['studentId'];
    }
    if (studentId == null || studentId.isEmpty) {
      return getAdvisingInfo(fromFetch: true);
    }

    try {
      final advisingUrl = ApiConfig.advisingUrl(studentId);
      final response = await ApiClient().authenticatedGet(
        advisingUrl,
        cacheDuration: cacheDuration,
      );

      dynamic data;
      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body);
        final dataList = decoded is List ? decoded : <dynamic>[];
        if (dataList.isNotEmpty) {
          data = dataList.first;
        }
      }

      if (data == null) {
        final wishlistUrl = ApiConfig.wishlistUrl(studentId);
        final wlResponse = await ApiClient().authenticatedGet(
          wishlistUrl,
          cacheDuration: cacheDuration,
        );
        if (wlResponse.statusCode == 200) {
          final wlDecoded = jsonDecode(wlResponse.body);
          final wlDataList = wlDecoded is List ? wlDecoded : <dynamic>[];
          if (wlDataList.isNotEmpty) {
            data = wlDataList.first;
          }
        }
      }

      if (data is Map) {
        final mapData = <String, String>{
          'advisingStartDate': '${data['startDate'] ?? ''}',
          'advisingEndDate': '${data['endDate'] ?? ''}',
          'activeSemesterSessionId': '${data['activeSemesterSessionId'] ?? ''}',
          'advisingPhase': '${data['advisingPhase'] ?? ''}',
          'totalCredit': '${data['totalCredit'] ?? ''}',
          'earnedCredit': '${data['earnedCredit'] ?? ''}',
          'noOfSemester': '${data['noOfSemester'] ?? ''}',
          'semesterSession': '${data['semesterSession'] ?? ''}',
        };
        await repo.writeStringMap(mapData);
        return mapData;
      }
    } catch (error) {
      _recordProfileError('Advising fetch', error);
    }

    return getAdvisingInfo(fromFetch: true);
  }

  Future<Map<String, String?>?> getAdvisingInfo({
    bool fromFetch = false,
  }) async {
    final data = await RepositoryCache.instance.readStringMapWithFallback(
      keys: storedProfileKeys.toSet(),
      fromFetch: fromFetch,
      decoder: (value) => value,
      onCacheMiss: () async {
        final fetched = await fetchAdvisingInfo(fromGet: true);
        return fetched;
      },
    );
    if (data == null) return null;
    final isIncomplete = data.values.any(
      (value) => value == null || value == '',
    );
    if (isIncomplete) {
      if (fromFetch) return null;
      return fetchAdvisingInfo(fromGet: true);
    }
    return data;
  }
}

class AttendanceService {
  static final AttendanceService _instance = AttendanceService._internal();
  factory AttendanceService() => _instance;
  AttendanceService._internal();

  static const String _attendanceKey = 'attendance';

  Future<String?> fetchAttendanceInfo({
    bool fromGet = false,
    Duration cacheDuration = CacheDurations.short,
  }) async {
    final asyncPrefs = AppStorage.instance;
    final id = await resolvePortfolioId(
      prefs: asyncPrefs,
      refreshProfile: () => ProfileService().fetchProfile(fromGet: true),
    );
    if (id == null || id.isEmpty) {
      return getAttendanceInfo(fromFetch: true);
    }

    final url = '${ApiConfig.connectApiBase}${ApiConfig.attendancePath(id)}';

    final repo = RepositoryCache.instance;
    try {
      final response = await ApiClient().authenticatedGet(
        url,
        cacheDuration: cacheDuration,
      );
      if (response.statusCode == 200) {
        await repo.writeString(_attendanceKey, response.body);
        return response.body;
      }
    } catch (error) {
      _recordProfileError('Attendance fetch', error);
    }

    return getAttendanceInfo(fromFetch: true);
  }

  Future<String?> getAttendanceInfo({bool fromFetch = false}) async {
    return RepositoryCache.instance.readStringWithFallback<String>(
      key: _attendanceKey,
      fromFetch: fromFetch,
      decoder: (value) => value,
      onCacheMiss: () => fetchAttendanceInfo(fromGet: true),
    );
  }
}

class PaymentService {
  static final PaymentService _instance = PaymentService._internal();
  factory PaymentService() => _instance;
  PaymentService._internal();

  static const String _paymentInfoKey = 'SemesterPaymentInfo';

  Future<String?> fetchPaymentInfo({
    bool fromGet = false,
    Duration cacheDuration = CacheDurations.short,
  }) async {
    final asyncPrefs = AppStorage.instance;
    final rawPortfolios = await asyncPrefs.getString(StorageKeys.portfolios);
    final portfolioIds = <String>[];

    if (rawPortfolios != null && rawPortfolios.isNotEmpty) {
      try {
        final List decoded = jsonDecode(rawPortfolios);
        for (final item in decoded) {
          if (item is Map && item['id'] != null) {
            portfolioIds.add(item['id'].toString());
          }
        }
      } catch (error) {
        _recordProfileError('Portfolio cache decode', error);
      }
    }

    if (portfolioIds.isEmpty) {
      final singleId = await resolvePortfolioId(
        prefs: asyncPrefs,
        refreshProfile: () => ProfileService().fetchProfile(fromGet: true),
      );
      if (singleId != null && singleId.isNotEmpty) {
        portfolioIds.add(singleId);
      }
    }

    if (portfolioIds.isEmpty) {
      return getPaymentInfo(fromFetch: true);
    }

    final repo = RepositoryCache.instance;
    final allPayslips = <Map<String, dynamic>>[];
    final seenPayslips = <String>{};

    try {
      final responses = await Future.wait(
        portfolioIds.map(
          (id) => ApiClient().authenticatedGet(
            ApiConfig.paymentUrl(id),
            cacheDuration: cacheDuration,
          ),
        ),
      );

      for (final response in responses) {
        if (response.statusCode == 200) {
          final List list = jsonDecode(response.body);
          for (final item in list) {
            if (item is Map<String, dynamic>) {
              final payslipNo = item['payslipNumber']?.toString() ?? '';
              final key = payslipNo.isNotEmpty
                  ? payslipNo
                  : '${item['requestId']}_${item['semesterSessionId']}';
              if (!seenPayslips.contains(key)) {
                seenPayslips.add(key);
                allPayslips.add(item);
              }
            }
          }
        }
      }

      if (allPayslips.isNotEmpty) {
        final jsonResult = jsonEncode(allPayslips);
        await repo.writeString(_paymentInfoKey, jsonResult);
        return jsonResult;
      }
    } catch (error) {
      _recordProfileError('Payment information fetch', error);
    }

    return getPaymentInfo(fromFetch: true);
  }

  Future<String?> getPaymentInfo({bool fromFetch = false}) async {
    return RepositoryCache.instance.readStringWithFallback<String>(
      key: _paymentInfoKey,
      fromFetch: fromFetch,
      decoder: (value) => value,
      onCacheMiss: () => fetchPaymentInfo(fromGet: true),
    );
  }

  Future<PayslipDetail?> fetchPayslipDetail(
    String payslipNo, {
    Duration cacheDuration = Duration.zero,
  }) async {
    try {
      final response = await ApiClient().authenticatedGet(
        ApiConfig.payslipDetailUrl(payslipNo),
        cacheDuration: cacheDuration,
      );
      if (response.statusCode == 200) {
        final Map<String, dynamic> data = jsonDecode(response.body);
        return PayslipDetail.fromJson(data);
      }
    } catch (error) {
      _recordProfileError('Payslip detail fetch', error);
    }
    return null;
  }

  Future<List<BankConfig>> fetchBankConfigurations() async {
    try {
      final response = await ApiClient().authenticatedGet(
        ApiConfig.bankConfigurationsUrl,
        cacheDuration: CacheDurations.profileOverview,
      );
      if (response.statusCode == 200) {
        final List list = jsonDecode(response.body);
        return list
            .whereType<Map<String, dynamic>>()
            .map(BankConfig.fromJson)
            .toList();
      }
    } catch (error) {
      _recordProfileError('Bank configuration fetch', error);
    }
    return const [];
  }

  Future<List<int>?> generatePayslipPdfBytes({
    required PayslipDetail detail,
    required List<BankConfig> banks,
  }) async {
    try {
      final token = await TokenStorage.instance.read(
        key: PreConnectStorageKeys.accessToken,
      );
      if (token == null || token.isEmpty) return null;

      final uri = Uri.parse(ApiConfig.pdfPrintUrl);
      final request = http.MultipartRequest('POST', uri);
      request.headers.addAll({
        'Authorization': 'Bearer $token',
        'X-REALM': 'bracu',
        'X-SOURCE': '3',
        'Accept': 'application/json, text/plain, */*',
      });

      request.fields['report'] = 'finance/payslip.html';
      request.fields['template'] = 'finance';
      request.fields['driver'] = 'weasy';

      String formatPdfAmount(double val) {
        final s = val.toStringAsFixed(0);
        final buf = StringBuffer();
        final len = s.length;
        for (int i = 0; i < len; i++) {
          if (i > 0 && (len - i) % 3 == 0) {
            buf.write(',');
          }
          buf.write(s[i]);
        }
        return buf.toString();
      }

      final dataMap = <String, dynamic>{
        'copyForLabel': 'Student',
        'title': detail.paySlipTitle,
        'subTitle': '${detail.semesterSession} Undergraduate Programme',
        'studentId': detail.studentId,
        'payslipNo': detail.payslipNumber,
        'name': detail.studentName,
        'generationDate': detail.payslipGenerationDate ?? '',
        'programCourseLabel': 'Programme',
        'programOrcourse': detail.programOrCourseName,
        'contactNo': detail.contactNo ?? '',
        'address': detail.presentAddress ?? '',
        'registrationSlipColumns': true,
        'isCourseList': detail.courseList.isNotEmpty,
        'totalFinancialCredits': detail.totalFinancialCredits.toString(),
        'totalAcademicCredits': detail.totalAcademicCredits.toString(),
        'totalCourseAmount': formatPdfAmount(detail.totalCourseAmount),
        'hasQuantity': false,
        'payslipCourseList': detail.courseList
            .map(
              (c) => <String, dynamic>{
                'courseId': c.courseCode,
                'courseTitle': c.courseTitle,
                'academicCredits': c.academicCredit.toString(),
                'financialCredits': c.financialCredit.toString(),
                'regDate': c.registrationDate ?? '',
                'amount': formatPdfAmount(c.amount),
                'rpRt': 'N/M',
              },
            )
            .toList(),
        'particularsList': detail.particulars.map((p) {
          final m = <String, dynamic>{
            'className': p.type == 'AGGREGATION' || p.type == 'WORDS'
                ? 'font-bold'
                : '',
            'colspan': p.type == 'WORDS' ? 2 : 1,
            'title': p.particular,
          };
          if (p.amount != null) {
            m['amount'] = formatPdfAmount(p.amount!);
          }
          return m;
        }).toList(),
        'bankingInformationHint':
            'Please deposit the net payable amount to any of the above mentioned banks. Please avoid Cheque, PO, Agent Banking, CDM, BEFTN, RTGS, NPSB.',
        'bankingInformationList': banks
            .map(
              (b) => <String, dynamic>{
                'bankName': b.bankName,
                'accName': b.accountName,
                'accNo': b.accountNumber,
              },
            )
            .toList(),
        'deadLine': detail.deadlineFormatted,
        'isPaid': detail.isPaid,
        'expired': detail.isPaid ? false : detail.isExpired,
      };

      request.fields['data'] = jsonEncode(dataMap);

      final streamedResponse = await request.send();
      if (streamedResponse.statusCode == 200) {
        return await streamedResponse.stream.toBytes();
      }
    } catch (error) {
      _recordProfileError('Payslip PDF generation', error);
    }
    return null;
  }
}

class PayslipItem {
  const PayslipItem({
    required this.payslipNumber,
    required this.paymentType,
    required this.paymentStatus,
    required this.semesterSessionId,
    required this.totalAmount,
    required this.totalPayable,
    required this.totalReceivable,
    this.dueDate,
    this.requestDate,
    this.requestId,
  });

  final String payslipNumber;
  final String paymentType;
  final String paymentStatus;
  final int semesterSessionId;
  final double totalAmount;
  final double totalPayable;
  final double totalReceivable;
  final String? dueDate;
  final String? requestDate;
  final String? requestId;

  factory PayslipItem.fromJson(Map<String, dynamic> json) {
    return PayslipItem(
      payslipNumber: json['payslipNumber']?.toString() ?? '',
      paymentType: json['paymentType']?.toString() ?? '',
      paymentStatus: json['paymentStatus']?.toString() ?? '',
      semesterSessionId: (json['semesterSessionId'] as num?)?.toInt() ?? 0,
      totalAmount: (json['totalAmount'] as num?)?.toDouble() ?? 0.0,
      totalPayable: (json['totalPayable'] as num?)?.toDouble() ?? 0.0,
      totalReceivable: (json['totalReceivable'] as num?)?.toDouble() ?? 0.0,
      dueDate: json['dueDate']?.toString(),
      requestDate: json['requestDate']?.toString(),
      requestId: json['requestId']?.toString(),
    );
  }

  String get formattedType {
    return paymentType
        .replaceAll('_', ' ')
        .toLowerCase()
        .split(' ')
        .map(
          (w) => w.isNotEmpty ? '${w[0].toUpperCase()}${w.substring(1)}' : '',
        )
        .join(' ');
  }

  bool get isPaid => paymentStatus.toUpperCase() == 'PAID';
}

class PayslipCourseItem {
  const PayslipCourseItem({
    required this.courseCode,
    required this.courseTitle,
    required this.academicCredit,
    required this.financialCredit,
    required this.amount,
    this.registrationDate,
  });

  final String courseCode;
  final String courseTitle;
  final num academicCredit;
  final num financialCredit;
  final double amount;
  final String? registrationDate;

  factory PayslipCourseItem.fromJson(Map<String, dynamic> json) {
    return PayslipCourseItem(
      courseCode: json['courseCode']?.toString() ?? '',
      courseTitle: json['courseTitle']?.toString() ?? '',
      academicCredit: (json['academicCredit'] as num?) ?? 0,
      financialCredit: (json['financialCredit'] as num?) ?? 0,
      amount: (json['amount'] as num?)?.toDouble() ?? 0.0,
      registrationDate: json['registrationDate']?.toString(),
    );
  }
}

class PayslipParticular {
  const PayslipParticular({required this.particular, this.amount, this.type});

  final String particular;
  final double? amount;
  final String? type;

  factory PayslipParticular.fromJson(Map<String, dynamic> json) {
    return PayslipParticular(
      particular: json['particular']?.toString() ?? '',
      amount: (json['amount'] as num?)?.toDouble(),
      type: json['type']?.toString(),
    );
  }
}

class BankConfig {
  const BankConfig({
    required this.bankId,
    required this.bankName,
    required this.branch,
    required this.routingNumber,
    required this.accountName,
    required this.accountNumber,
    required this.refName,
    required this.active,
  });

  final int bankId;
  final String bankName;
  final String branch;
  final String routingNumber;
  final String accountName;
  final String accountNumber;
  final String refName;
  final bool active;

  factory BankConfig.fromJson(Map<String, dynamic> json) {
    return BankConfig(
      bankId: (json['bankId'] as num?)?.toInt() ?? 0,
      bankName: json['bankName']?.toString() ?? '',
      branch: json['branch']?.toString() ?? '',
      routingNumber: json['routingNumber']?.toString() ?? '',
      accountName: json['accountName']?.toString() ?? '',
      accountNumber: json['accountNumber']?.toString() ?? '',
      refName: json['refName']?.toString() ?? '',
      active: json['active'] == true,
    );
  }
}

class PayslipDetail {
  const PayslipDetail({
    required this.payslipNumber,
    required this.studentId,
    required this.studentName,
    required this.programOrCourseName,
    required this.semesterSession,
    required this.paySlipTitle,
    required this.paymentStatus,
    required this.isPaid,
    required this.isExpired,
    this.deadline,
    this.contactNo,
    this.presentAddress,
    this.payslipGenerationDate,
    required this.courseList,
    required this.particulars,
  });

  final String payslipNumber;
  final String studentId;
  final String studentName;
  final String programOrCourseName;
  final String semesterSession;
  final String paySlipTitle;
  final String paymentStatus;
  final bool isPaid;
  final bool isExpired;
  final String? deadline;
  final String? contactNo;
  final String? presentAddress;
  final String? payslipGenerationDate;
  final List<PayslipCourseItem> courseList;
  final List<PayslipParticular> particulars;

  factory PayslipDetail.fromJson(Map<String, dynamic> json) {
    final coursesRaw = json['courseList'];
    final particularsRaw = json['particulars'];

    return PayslipDetail(
      payslipNumber: json['payslipNumber']?.toString() ?? '',
      studentId: json['studentId']?.toString() ?? '',
      studentName: json['studentName']?.toString() ?? '',
      programOrCourseName:
          json['programOrCourseName']?.toString() ??
          json['program']?.toString() ??
          '',
      semesterSession: json['semesterSession']?.toString() ?? '',
      paySlipTitle: json['paySlipTitle']?.toString() ?? '',
      paymentStatus: json['paymentStatus']?.toString() ?? '',
      isPaid: json['paymentStatus']?.toString().toUpperCase() == 'PAID',
      isExpired: json['isExpired'] == true,
      deadline: json['deadline']?.toString(),
      contactNo: json['contactNo']?.toString(),
      presentAddress: json['presentAddress']?.toString(),
      payslipGenerationDate: json['payslipGenerationDate']?.toString(),
      courseList: coursesRaw is List
          ? coursesRaw
                .whereType<Map<String, dynamic>>()
                .map(PayslipCourseItem.fromJson)
                .toList()
          : const [],
      particulars: particularsRaw is List
          ? particularsRaw
                .whereType<Map<String, dynamic>>()
                .map(PayslipParticular.fromJson)
                .toList()
          : const [],
    );
  }

  num get totalAcademicCredits =>
      courseList.fold(0, (sum, item) => sum + item.academicCredit);

  num get totalFinancialCredits =>
      courseList.fold(0, (sum, item) => sum + item.financialCredit);

  double get totalCourseAmount =>
      courseList.fold(0.0, (sum, item) => sum + item.amount);

  String get deadlineFormatted {
    if (deadline == null || deadline!.isEmpty) return '';
    try {
      final dt = DateTime.parse(deadline!);
      final months = [
        'January',
        'February',
        'March',
        'April',
        'May',
        'June',
        'July',
        'August',
        'September',
        'October',
        'November',
        'December',
      ];
      return '${dt.day} ${months[dt.month - 1]} ${dt.year}';
    } catch (_) {
      return deadline!;
    }
  }
}
