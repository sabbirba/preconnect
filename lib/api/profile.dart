import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:preconnect/tools/app_storage.dart';
import 'package:preconnect/api/api_config.dart';
import 'package:preconnect/api/api_client.dart';
import 'package:preconnect/api/repository_cache.dart';
import 'package:preconnect/tools/storage_keys.dart';
import 'package:preconnect/tools/cache_durations.dart';
import 'package:preconnect/tools/app_log.dart';
import 'package:preconnect/tools/preload_cache.dart';
import 'package:preconnect/tools/string_utils.dart';
import 'package:preconnect/tools/time_utils.dart';

part 'profile_sections/profile_models.dart';

void _recordProfileError(String operation, Object error) {
  unawaited(AppLog.write('$operation failed: $error'));
}

class ProfileService {
  static final ProfileService _instance = ProfileService._();
  factory ProfileService() => _instance;
  ProfileService._();

  final ApiClient _client = ApiClient();
  final Map<bool, PreloadCache<Map<String, String?>?>> _profileFetches =
      <bool, PreloadCache<Map<String, String?>?>>{};
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
  static const Set<String> _miscDataKeys = {
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
  static const Set<String> _studentKeys = {
    'dateOfBirth',
    'nationalIdNo',
    'passportNo',
    'birthCertificateNo',
    'emergencyContactNo',
    'emergencyContactName',
  };
  static const Set<String> _yesNoKeys = {'isBothAddressSame', 'hasDisability'};
  static const Set<String> _miscKeys = {..._miscDataKeys, ..._studentKeys};
  static const Set<String> _profileKeys = {
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
    ..._miscKeys,
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

  static Map<String, String?> storedProfileSync() {
    final storage = AppStorage.instance;
    return <String, String?>{
      'fullName': storage.getStringSync(StorageKeys.fullName),
      'studentId': storage.getStringSync(StorageKeys.studentId),
      'studentEmail': storage.getStringSync(StorageKeys.studentEmail),
      'shortCode': storage.getStringSync(StorageKeys.shortCode),
      'program': storage.getStringSync(StorageKeys.program),
      'departmentName': storage.getStringSync(StorageKeys.departmentName),
      'currentSemester': storage.getStringSync(StorageKeys.currentSemester),
      'currentSessionSemesterId': storage.getStringSync(
        StorageKeys.currentSessionSemesterId,
      ),
      'cgpa': storage.getStringSync(StorageKeys.cgpa),
      'earnedCredit': storage.getStringSync(StorageKeys.earnedCredit),
      'mobileNo': storage.getStringSync(StorageKeys.mobileNo),
      'photoFilePath': storage.getStringSync(StorageKeys.photoFilePath),
    };
  }

  Future<Map<String, String?>?> fetchProfile({bool fromGet = false}) {
    return _profileFetches
        .putIfAbsent(fromGet, PreloadCache<Map<String, String?>?>.new)
        .share(() => _fetchProfileInternal(fromGet: fromGet));
  }

  bool _hasMissingMiscFields(Map<String, String?>? profile) {
    if (profile == null) return true;
    return _miscKeys.any((key) {
      final value = profile[key];
      return value == null || value.isEmpty;
    });
  }

  Future<dynamic> _fetchProfileJson(String path, String operation) async {
    try {
      final response = await _client.authenticatedGet(
        '${ApiConfig.connectApiBase}$path',
        cacheDuration: CacheDurations.profileOverview,
      );
      return jsonDecode(response.body);
    } catch (error) {
      _recordProfileError(operation, error);
      return null;
    }
  }

  Future<Map<String, String?>?> _fetchProfileInternal({
    required bool fromGet,
  }) async {
    final cachedProfile = await getProfile(fromFetch: true);
    final needsDetails = fromGet || _hasMissingMiscFields(cachedProfile);
    final miscFuture = needsDetails
        ? _fetchProfileJson(
            ApiConfig.miscellaneousInfoPath,
            'Profile miscellaneous data fetch',
          )
        : null;
    final studentFuture = needsDetails
        ? _fetchProfileJson(ApiConfig.studentPath, 'Student identity fetch')
        : null;

    await _syncPortfolios(fromGet: fromGet);

    final profile = await getProfile(fromFetch: true);
    if (profile == null) return null;

    if (miscFuture != null) {
      try {
        await _applyMiscData(await miscFuture, profile);
      } catch (error) {
        _recordProfileError('Profile miscellaneous data fetch', error);
      }
    }
    if (studentFuture != null) {
      try {
        await _applyStudentData(await studentFuture, profile);
      } catch (error) {
        _recordProfileError('Student identity fetch', error);
      }
    }
    return profile;
  }

  Future<void> _syncPortfolios({required bool fromGet}) async {
    final url = '${ApiConfig.connectApiBase}${ApiConfig.profilePath}';
    final repo = RepositoryCache.instance;

    try {
      final response = await ApiClient().authenticatedGet(
        url,
        cacheDuration: CacheDurations.profileOverview,
        bypassCache: fromGet,
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data is List && data.isNotEmpty) {
          await AppStorage.instance.setString(
            StorageKeys.portfolios,
            jsonEncode(data),
          );
          int parseSessionId(Map p) {
            final val =
                p['currentSessionSemesterId'] ??
                p['enrolledSessionSemesterId'] ??
                p['id'];
            if (val is num) return val.toInt();
            return int.tryParse(val?.toString() ?? '') ?? 0;
          }

          final portfolios = data.whereType<Map>().toList();
          if (portfolios.isNotEmpty) {
            portfolios.sort((a, b) {
              final isCurrA =
                  a['isCurrent'] == true ||
                  a['isCurrent'] == 'true' ||
                  a['isCurrent'] == 1;
              final isCurrB =
                  b['isCurrent'] == true ||
                  b['isCurrent'] == 'true' ||
                  b['isCurrent'] == 1;
              if (isCurrA != isCurrB) return isCurrB ? 1 : -1;

              final compA = a['hasCompleted'] == true ? 1 : 0;
              final compB = b['hasCompleted'] == true ? 1 : 0;
              if (compA != compB) return compA - compB;

              return parseSessionId(b).compareTo(parseSessionId(a));
            });
          }
          final profile = portfolios.isNotEmpty
              ? portfolios.first
              : <String, dynamic>{};
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
            'bloodGroup': profile['bloodGroup']?.toString() ?? '',
            'mobileNo': profile['mobileNo'] ?? '',
            'shortCode': profile['shortCode'] ?? '',
            'fullName': profile['fullName'] ?? '',
            'email': profile['studentEmail'] ?? '',
            'cgpa': profile['cgpa']?.toString() ?? '',
          });
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
  }

  Future<void> _applyMiscData(
    dynamic miscData,
    Map<String, String?> profile,
  ) async {
    if (miscData is! Map<String, dynamic>) return;
    final resolvedBloodGroup = _normalizeBloodType(
      bloodGroup: miscData['bloodGroup'],
      bloodGroupName: miscData['bloodGroupName'],
      bloodType: miscData['bloodType'],
    );
    await _storeDetails(profile, {
      if (resolvedBloodGroup.isNotEmpty) 'bloodGroup': resolvedBloodGroup,
      ..._pickDetails(miscData, _miscDataKeys),
    });
  }

  Future<void> _applyStudentData(
    dynamic studentData,
    Map<String, String?> profile,
  ) async {
    if (studentData is! Map<String, dynamic>) return;
    await _storeDetails(profile, _pickDetails(studentData, _studentKeys));
  }

  static Map<String, String> _pickDetails(
    Map<String, dynamic> data,
    Set<String> keys,
  ) => {
    for (final key in keys)
      key: _yesNoKeys.contains(key)
          ? _boolToYesNo(data[key])
          : data[key]?.toString() ?? '',
  };

  Future<void> _storeDetails(
    Map<String, String?> profile,
    Map<String, String> updates,
  ) async {
    await RepositoryCache.instance.writeStringMap(updates);
    profile.addAll(updates);
  }

  Future<Map<String, String?>?> getProfile({bool fromFetch = false}) async {
    final profileData = await RepositoryCache.instance
        .readStringMapWithFallback(
          keys: _profileKeys,
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
    if (!fromFetch && _miscKeys.any((key) => profileData[key] == null)) {
      unawaited(fetchProfile(fromGet: true));
    }
    return profileData;
  }
}

class AdvisingService {
  static final AdvisingService _instance = AdvisingService._();
  factory AdvisingService() => _instance;
  AdvisingService._();

  static String title(Map<String, String?> info) {
    final phase = info['advisingPhase'] ?? '';
    final semester = info['semesterSession'] ?? '';
    final phaseLabel = phase.isEmpty ? 'Advising' : titleCaseWords(phase);
    return semester.isEmpty ? phaseLabel : '$phaseLabel - $semester';
  }

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
    String? studentId = await asyncPrefs.getString(StorageKeys.studentId);
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
    final portfolioIds = <String>[];

    try {
      final response = await ApiClient().authenticatedGet(
        '${ApiConfig.connectApiBase}${ApiConfig.allPortfoliosPath}',
        cacheDuration: cacheDuration,
      );
      if (response.statusCode == 200) {
        final List data = jsonDecode(response.body);
        if (data.isNotEmpty) {
          await asyncPrefs.setString(
            StorageKeys.paymentPortfolios,
            response.body,
          );
        }
        for (final item in data) {
          if (item is Map && item['id'] != null) {
            portfolioIds.add(item['id'].toString());
          }
        }
      }
    } catch (error) {
      _recordProfileError('Payment portfolios fetch', error);
    }

    if (portfolioIds.isEmpty) {
      final rawPortfolios = await asyncPrefs.getString(StorageKeys.portfolios);
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
      var token = await ApiClient().getAccessToken();
      if (token == null || token.isEmpty) return null;

      Future<http.StreamedResponse> sendRequest(String authToken) async {
        final uri = Uri.parse(ApiConfig.pdfPrintUrl);
        final request = http.MultipartRequest('POST', uri);
        request.headers.addAll({
          'Authorization': 'Bearer $authToken',
          'X-REALM': 'bracu',
          'X-SOURCE': '3',
          'Accept': 'application/json, text/plain, */*',
        });

        request.fields['report'] = 'finance/payslip.html';
        request.fields['template'] = 'finance';
        request.fields['driver'] = 'weasy';

        request.fields['data'] = jsonEncode(detail.printData(banks));
        return request.send();
      }

      var streamedResponse = await sendRequest(token);
      if (streamedResponse.statusCode == 401) {
        token = await ApiClient().getAccessToken();
        if (token != null && token.isNotEmpty) {
          streamedResponse = await sendRequest(token);
        }
      }

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
    this.retakeOrRepeat = 'N/M',
  });

  final String courseCode;
  final String courseTitle;
  final num academicCredit;
  final num financialCredit;
  final double amount;
  final String? registrationDate;
  final String retakeOrRepeat;

  factory PayslipCourseItem.fromJson(Map<String, dynamic> json) {
    return PayslipCourseItem(
      courseCode: json['courseCode']?.toString() ?? '',
      courseTitle: json['courseTitle']?.toString() ?? '',
      academicCredit: (json['academicCredit'] as num?) ?? 0,
      financialCredit: (json['financialCredit'] as num?) ?? 0,
      amount: (json['amount'] as num?)?.toDouble() ?? 0.0,
      registrationDate: json['registrationDate']?.toString(),
      retakeOrRepeat: (json['retakeOrRepeat']?.toString().trim() ?? '').isEmpty
          ? 'N/M'
          : json['retakeOrRepeat'].toString().trim(),
    );
  }
}

class PayslipParticular {
  const PayslipParticular({required this.particular, this.amount, this.type});

  final String particular;
  final double? amount;
  final String? type;

  bool get isNetPayable => particular.toLowerCase().startsWith('net payable');

  bool get isEmphasized => type != 'NORMAL' || isNetPayable;

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
    this.academicDegree = '',
    this.installmentNumber,
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
  final String academicDegree;
  final int? installmentNumber;
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
      academicDegree: json['academicDegree']?.toString() ?? '',
      installmentNumber: (json['installmentNumber'] as num?)?.toInt(),
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

  String get deadlineFormatted =>
      AppTime.formatCampusTime(deadline, 'd MMMM y');

  static String _pdfAmount(num amount) =>
      NumberFormat.decimalPattern('en_US').format(amount.round());

  List<PayslipParticular> get shownParticulars {
    final shown = particulars
        .where(
          (p) =>
              p.isNetPayable || !(p.type == 'NORMAL' && (p.amount ?? 0) == 0),
        )
        .toList();
    final net = shown.where((p) => p.isNetPayable).lastOrNull;
    final words = shown
        .where((p) => p.type == 'WORDS' && p.particular.startsWith('In Words'))
        .lastOrNull;
    return [
      ...shown.where((p) => !identical(p, net) && !identical(p, words)),
      ?net,
      ?words,
    ];
  }

  List<Map<String, dynamic>> get printParticulars => [
    for (final p in shownParticulars)
      <String, dynamic>{
        'className': p.isEmphasized ? 'font-bold' : '',
        'colspan': p.type == 'WORDS' ? 2 : 1,
        'title': p.particular,
        if (p.amount != null) 'amount': _pdfAmount(p.amount!),
      },
  ];

  Map<String, dynamic> printData(List<BankConfig> banks) {
    final degree = titleCaseWords(academicDegree);
    final registeredOn = AppTime.formatCampusTime(
      payslipGenerationDate,
      'MM/dd/yyyy hh:mm a',
    );
    return <String, dynamic>{
      'copyForLabel': 'Student',
      'title': paySlipTitle,
      'subTitle':
          '$semesterSession ${degree.isEmpty ? 'Undergraduate' : degree} Programme',
      'studentId': studentId,
      'payslipNo': payslipNumber,
      'name': studentName,
      'generationDate': AppTime.formatCampusTime(
        payslipGenerationDate,
        'd-MMM-yyyy hh:mm a',
      ),
      'programCourseLabel': 'Programme',
      'programOrcourse': programOrCourseName,
      'contactNo': contactNo ?? '',
      'address': presentAddress ?? '',
      'registrationSlipColumns': true,
      'isCourseList': courseList.isNotEmpty,
      'totalFinancialCredits': totalFinancialCredits.toString(),
      'totalAcademicCredits': totalAcademicCredits.toString(),
      'totalCourseAmount': _pdfAmount(totalCourseAmount),
      'hasQuantity': false,
      'payslipCourseList': [
        for (final course in courseList)
          <String, dynamic>{
            'courseId': course.courseCode,
            'courseTitle': course.courseTitle,
            'academicCredits': course.academicCredit.toString(),
            'financialCredits': course.financialCredit.toString(),
            'regDate': registeredOn,
            'amount': _pdfAmount(course.amount),
            'rpRt': course.retakeOrRepeat,
          },
      ],
      'particularsList': printParticulars,
      'bankingInformationHint':
          'Please deposit the net payable amount to any of the above mentioned banks. Please avoid Cheque, PO, Agent Banking, CDM, BEFTN, RTGS, NPSB.',
      'bankingInformationList': [
        for (final bank in banks)
          <String, dynamic>{
            'bankName': bank.bankName,
            'accName': bank.accountName,
            'accNo': bank.accountNumber,
          },
      ],
      'deadLine': deadlineFormatted,
      'isPaid': isPaid,
      'expired': isPaid ? false : isExpired,
    };
  }
}
