import 'dart:async';
import 'dart:convert';
import 'package:preconnect/tools/app_storage.dart';
import 'package:preconnect/api/api_config.dart';
import 'package:preconnect/api/api_client.dart';
import 'package:preconnect/api/app_preferences_store.dart';
import 'package:preconnect/tools/storage_keys.dart';

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
          final store = AppPreferencesStore();
          await store.setStringMap(<String, String>{
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
              await store.setStringMap(<String, String>{
                if (resolvedBloodGroup.isNotEmpty)
                  'bloodGroup': resolvedBloodGroup,
                'permanentAddress':
                    miscData['permanentAddress']?.toString() ?? '',
                'presentAddress': miscData['presentAddress']?.toString() ?? '',
                'isBothAddressSame': _boolToYesNo(
                  miscData['isBothAddressSame'],
                ),
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
              });
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
          } catch (_) {}
        }
      },
      readCache: ({required bool fromFetch}) =>
          getProfile(fromFetch: fromFetch),
    );
  }

  Future<Map<String, String?>?> getProfile({bool fromFetch = false}) async {
    final profileData = await AppPreferencesStore().getStringMap(
      profileFields.toSet(),
    );

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

class AttendanceInfo {
  final int courseSectionId;
  final int studentPortfolioId;
  final String courseName;
  final String courseCode;
  final int attend;
  final int missed;
  final int remaining;
  final int totalClasses;

  AttendanceInfo({
    required this.courseSectionId,
    required this.studentPortfolioId,
    required this.courseName,
    required this.courseCode,
    required this.attend,
    required this.missed,
    required this.remaining,
    required this.totalClasses,
  });

  factory AttendanceInfo.fromJson(Map<String, dynamic> json) {
    return AttendanceInfo(
      courseSectionId: json['courseSectionId'] ?? 0,
      studentPortfolioId: json['studentPortfolioId'] ?? 0,
      courseName: json['courseName'] ?? '',
      courseCode: json['courseCode'] ?? '',
      attend: json['attend'] ?? 0,
      missed: json['missed'] ?? 0,
      remaining: json['remaining'] ?? 0,
      totalClasses: json['totalClasses'] ?? 0,
    );
  }
}

class PaymentInfo {
  final String paymentStatus;
  final String payslipNumber;
  final String paymentType;
  final DateTime requestDate;
  final DateTime dueDate;
  final double totalAmount;
  final int semesterSessionId;

  PaymentInfo({
    required this.paymentStatus,
    required this.payslipNumber,
    required this.paymentType,
    required this.requestDate,
    required this.dueDate,
    required this.totalAmount,
    required this.semesterSessionId,
  });

  factory PaymentInfo.fromJson(Map<String, dynamic> json) {
    return PaymentInfo(
      paymentStatus: '${json['paymentStatus'] ?? ''}',
      payslipNumber: '${json['payslipNumber'] ?? ''}',
      paymentType: '${json['paymentType'] ?? ''}',
      requestDate:
          DateTime.tryParse('${json['requestDate'] ?? ''}') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      dueDate:
          DateTime.tryParse('${json['dueDate'] ?? ''}') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      totalAmount: _toDouble(json['totalAmount']),
      semesterSessionId: _toInt(json['semesterSessionId']),
    );
  }
}

double _toDouble(dynamic value) {
  if (value is num) return value.toDouble();
  return double.tryParse('$value') ?? 0.0;
}

int _toInt(dynamic value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse('$value') ?? 0;
}

class AdvisingService {
  static final AdvisingService _instance = AdvisingService._internal();
  factory AdvisingService() => _instance;
  AdvisingService._internal();

  final ApiClient _client = ApiClient();

  static const List<String> storedProfileKeys = [
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
    final asyncPrefs = AppStorage.instance;
    String? studentId = await AppPreferencesStore().getString('studentId');
    studentId ??= await asyncPrefs.getString('studentId');
    if (studentId == null || studentId.isEmpty) {
      final profile = await ProfileService().getProfile(fromFetch: true);
      studentId = profile?['studentId'];
    }
    if (studentId == null || studentId.isEmpty) {
      if (fromGet) return null;
      return getAdvisingInfo(fromFetch: true);
    }

    final url = ApiConfig.advisingUrl(studentId);

    return _client.fetchWithFallback<Map<String, String?>>(
      url: url,
      fromGet: fromGet,
      cacheResponse: (response) async {
        try {
          final decoded = jsonDecode(response.body);
          final dataList = decoded is List ? decoded : <dynamic>[];
          if (dataList.isEmpty) return;

          final data = dataList.first is Map
              ? dataList.first as Map<String, dynamic>
              : null;
          if (data == null) return;

          await AppPreferencesStore().setStringMap(<String, String>{
            'advisingStartDate': '${data['startDate'] ?? ''}',
            'advisingEndDate': '${data['endDate'] ?? ''}',
            'activeSemesterSessionId':
                '${data['activeSemesterSessionId'] ?? ''}',
            'advisingPhase': '${data['advisingPhase'] ?? ''}',
            'totalCredit': '${data['totalCredit'] ?? ''}',
            'earnedCredit': '${data['earnedCredit'] ?? ''}',
            'noOfSemester': '${data['noOfSemester'] ?? ''}',
          });
        } catch (_) {}
      },
      readCache: ({required bool fromFetch}) =>
          getAdvisingInfo(fromFetch: fromFetch),
    );
  }

  Future<Map<String, String?>?> getAdvisingInfo({
    bool fromFetch = false,
  }) async {
    final data = await AppPreferencesStore().getStringMap(
      storedProfileKeys.toSet(),
    );
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

  final ApiClient _client = ApiClient();

  static const String _attendanceKey = 'attendance';

  Future<String?> fetchAttendanceInfo({bool fromGet = false}) async {
    final asyncPrefs = AppStorage.instance;
    final id = await resolvePortfolioId(
      prefs: asyncPrefs,
      refreshProfile: () => ProfileService().fetchProfile(fromGet: true),
    );
    if (id == null || id.isEmpty) {
      if (fromGet) return null;
      return getAttendanceInfo(fromFetch: true);
    }

    final url = '${ApiConfig.connectApiBase}${ApiConfig.attendancePath(id)}';

    return _client.fetchWithFallback<String>(
      url: url,
      fromGet: fromGet,
      cacheResponse: (response) async {
        await AppPreferencesStore().setString(_attendanceKey, response.body);
      },
      readCache: ({required bool fromFetch}) =>
          getAttendanceInfo(fromFetch: fromFetch),
    );
  }

  Future<String?> getAttendanceInfo({bool fromFetch = false}) async {
    final value = await AppPreferencesStore().getString(_attendanceKey);
    if (value != null && value.isNotEmpty) return value;
    if (fromFetch) return null;
    return fetchAttendanceInfo(fromGet: true);
  }
}

class PaymentService {
  static final PaymentService _instance = PaymentService._internal();
  factory PaymentService() => _instance;
  PaymentService._internal();

  final ApiClient _client = ApiClient();

  static const String _paymentInfoKey = 'SemesterPaymentInfo';

  Future<String?> fetchPaymentInfo({bool fromGet = false}) async {
    final asyncPrefs = AppStorage.instance;
    final id = await resolvePortfolioId(
      prefs: asyncPrefs,
      refreshProfile: () => ProfileService().fetchProfile(fromGet: true),
    );
    if (id == null || id.isEmpty) {
      if (fromGet) return null;
      return getPaymentInfo(fromFetch: true);
    }

    final url = ApiConfig.paymentUrl(id);

    return _client.fetchWithFallback<String>(
      url: url,
      fromGet: fromGet,
      cacheResponse: (response) async {
        await AppPreferencesStore().setString(_paymentInfoKey, response.body);
      },
      readCache: ({required bool fromFetch}) =>
          getPaymentInfo(fromFetch: fromFetch),
    );
  }

  Future<String?> getPaymentInfo({bool fromFetch = false}) async {
    final value = await AppPreferencesStore().getString(_paymentInfoKey);
    if (value != null && value.isNotEmpty) return value;
    if (fromFetch) return null;
    return fetchPaymentInfo(fromGet: true);
  }
}
