import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'package:connectivity_plus/connectivity_plus.dart';

class BracuAuthManager {
  static final BracuAuthManager _instance = BracuAuthManager._internal();
  factory BracuAuthManager() => _instance;
  BracuAuthManager._internal();

  final FlutterSecureStorage _storage = const FlutterSecureStorage();

  Future<void> login(BuildContext context) async {
    Navigator.pushNamed(context, '/login');
  }

  Future<void> logout() async {
    const endSessionEndpoint =
        'https://sso.bracu.ac.bd/realms/bracu/protocol/openid-connect/logout';

    try {
      final refreshToken = await _storage.read(key: 'refresh_token');

      if (refreshToken != null && refreshToken.isNotEmpty) {
        final response = await http.post(
          Uri.parse(endSessionEndpoint),
          headers: {'Content-Type': 'application/x-www-form-urlencoded'},
          body: {'client_id': 'slm', 'refresh_token': refreshToken},
        );

        if (response.statusCode != 204) {}
      }

      await _storage.deleteAll();

      final SharedPreferencesAsync asyncPrefs = SharedPreferencesAsync();
      await asyncPrefs.clear();
    } catch (e) {
      return;
    }
  }

  Future<bool> refreshToken() async {
    final tokenEndpoint =
        'https://sso.bracu.ac.bd/realms/bracu/protocol/openid-connect/token';
    try {
      final refreshToken = await _storage.read(key: 'refresh_token');
      if (refreshToken == null || refreshToken.isEmpty) {
        return false;
      }

      final response = await http.post(
        Uri.parse(tokenEndpoint),
        headers: {'Content-Type': 'application/x-www-form-urlencoded'},
        body: {
          'grant_type': 'refresh_token',
          'refresh_token': refreshToken,
          'client_id': 'slm',
        },
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);

        final newAccessToken = data['access_token'];
        final newRefreshToken = data['refresh_token'];

        await _storage.write(key: 'access_token', value: newAccessToken);
        await _storage.write(key: 'refresh_token', value: newRefreshToken);

        return true;
      } else if (response.statusCode == 400) {
        return false;
      } else {
        return false;
      }
    } catch (e) {
      return false;
    }
  }

  Future<bool> isLoggedIn() async {
    final token = await _storage.read(key: 'access_token');
    return token != null && token.isNotEmpty;
  }

  Future<bool> ensureSignedIn() async {
    final accessToken = await _storage.read(key: 'access_token');
    if (accessToken == null || accessToken.isEmpty) return false;

    final expired = await isTokenExpired();
    if (!expired) return true;

    final refreshed = await refreshToken();
    if (refreshed) return true;

    await logout();
    return false;
  }

  Future<DateTime> getTokenExpiryTime() async {
    final token = await _storage.read(key: 'access_token');

    if (token == null || token.isEmpty) {
      return DateTime.fromMillisecondsSinceEpoch(0);
    }

    try {
      final parts = token.split('.');

      if (parts.length != 3) {
        return DateTime.fromMillisecondsSinceEpoch(0);
      }

      final payload = json.decode(
        utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))),
      );
      final exp = payload['exp'];
      if (exp == null) {
        return DateTime.fromMillisecondsSinceEpoch(0);
      }

      return DateTime.fromMillisecondsSinceEpoch(exp * 1000);
    } catch (e) {
      return DateTime.fromMillisecondsSinceEpoch(0);
    }
  }

  Future<bool> isTokenExpired() async {
    final expiryTime = await getTokenExpiryTime();
    return DateTime.now().isAfter(expiryTime);
  }

  Future<Map<String, String?>?> fetchProfile({
    bool fromGet = false,
    bool retrying = false,
  }) async {
    final profileUrl = 'https://connect.bracu.ac.bd/api/mds/v1/portfolios';

    final List<ConnectivityResult> connectivityResult = await (Connectivity()
        .checkConnectivity());
    if (connectivityResult.contains(ConnectivityResult.none)) {
      if (fromGet) {
        return null;
      }
      return await getProfile(fromFetch: true);
    }
    final SharedPreferencesAsync asyncPrefs = SharedPreferencesAsync();
    final accessToken = await _storage.read(key: 'access_token');
    if (accessToken == null) {
      if (fromGet) {
        return null;
      }
      return await getProfile(fromFetch: true);
    }

    final headers = {
      'Authorization': 'Bearer $accessToken',
      'X-REALM': 'bracu',
      'Accept': 'application/json',
    };

    try {
      final response = await http.get(Uri.parse(profileUrl), headers: headers);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data is List && data.isNotEmpty) {
          final profile = data[0];

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

          return getProfile(fromFetch: true);
        }
      } else if (response.statusCode == 401) {
        if (retrying) {
          await logout();
          return fromGet ? null : getProfile(fromFetch: true);
        }

        final refreshed = await refreshToken();
        if (!refreshed) {
          await logout();
          return fromGet ? null : getProfile(fromFetch: true);
        }

        return await fetchProfile(fromGet: fromGet, retrying: true);
      }
    } catch (e) {
      return fromGet ? null : getProfile(fromFetch: true);
    }
    if (fromGet) {
      return null;
    }
    return getProfile(fromFetch: true);
  }

  Future<Map<String, String?>?> getProfile({bool fromFetch = false}) async {
    final keys = [
      'studentId',
      'fullName',
      'email',
      'program',
      'currentSemester',
      'cgpa',
      'earnedCredit',
      'attemptedCredit',
      'enrolledSessionSemesterId',
      'enrolledSemester',
      'departmentName',
      'bloodGroup',
      'mobileNo',
      'shortCode',
      'photoFilePath',
    ];

    final SharedPreferencesWithCache prefsWithCache =
        await SharedPreferencesWithCache.create(
          cacheOptions: const SharedPreferencesWithCacheOptions(
            allowList: <String>{
              'studentId',
              'fullName',
              'email',
              'program',
              'currentSemester',
              'cgpa',
              'earnedCredit',
              'attemptedCredit',
              'enrolledSessionSemesterId',
              'enrolledSemester',
              'departmentName',
              'bloodGroup',
              'mobileNo',
              'shortCode',
              'photoFilePath',
            },
          ),
        );

    final Map<String, String?> profileData = {};

    if (fromFetch) {
      await prefsWithCache.reloadCache();
    }
    for (final key in keys) {
      profileData[key] = prefsWithCache.getString(key);
    }

    return profileData;
  }

  Future<String?> fetchPaymentInfo({
    bool fromGet = false,
    bool retrying = false,
  }) async {
    final SharedPreferencesAsync asyncPrefs = SharedPreferencesAsync();
    final String? id = await asyncPrefs.getString('id');
    final paymentUrl =
        'https://connect.bracu.ac.bd/api/fin/v1/payment/portfolio/$id?paymentTypes=ADMISSION_FEE&paymentTypes=REGISTRATION_FEE&paymentTypes=MAKEUP_EXAM_FEE&paymentTypes=DEPARTMENT_CHANGE_FEE&paymentTypes=ACCOMMODATION_FEE&paymentTypes=PRE_UNIVERSITY_FEE&paymentTypes=LIBRARY_FINE_FEE&paymentTypes=SHORT_COURSE_FEE&paymentTypes=CERTIFICATE_COURSE_FEE&paymentTypes=VISITING_STUDENT_ADMISSION_FEE&paymentTypes=ADDED_COURSE_FEE&paymentTypes=OTHER_FEE';

    final List<ConnectivityResult> connectivityResult = await (Connectivity()
        .checkConnectivity());
    if (connectivityResult.contains(ConnectivityResult.none)) {
      if (fromGet) {
        return null;
      }
      return await getPaymentInfo(fromFetch: true);
    }

    final accessToken = await _storage.read(key: 'access_token');
    if (accessToken == null) {
      if (fromGet) {
        return null;
      }
      return await getPaymentInfo(fromFetch: true);
    }

    final headers = {
      'Authorization': 'Bearer $accessToken',
      'X-REALM': 'bracu',
      'Accept': 'application/json',
    };

    try {
      final response = await http.get(Uri.parse(paymentUrl), headers: headers);

      if (response.statusCode == 200) {
        await asyncPrefs.setString('SemesterPaymentInfo', response.body);

        return getPaymentInfo(fromFetch: true);
      } else if (response.statusCode == 401) {
        if (retrying) {
          await logout();
          return fromGet ? null : getPaymentInfo(fromFetch: true);
        }

        final refreshed = await refreshToken();
        if (!refreshed) {
          await logout();
          return fromGet ? null : getPaymentInfo(fromFetch: true);
        }

        return await fetchPaymentInfo(fromGet: fromGet, retrying: true);
      }
    } catch (e) {
      return fromGet ? null : getPaymentInfo(fromFetch: true);
    }
    if (fromGet) {
      return null;
    }
    return getPaymentInfo(fromFetch: true);
  }

  Future<String?> getPaymentInfo({bool fromFetch = false}) async {
    final SharedPreferencesWithCache prefsWithCache =
        await SharedPreferencesWithCache.create(
          cacheOptions: const SharedPreferencesWithCacheOptions(
            allowList: <String>{'SemesterPaymentInfo'},
          ),
        );

    if (fromFetch) {
      await prefsWithCache.reloadCache();
    }
    final String paymentInfo =
        prefsWithCache.getString('SemesterPaymentInfo') ?? '';

    if (paymentInfo == '') {
      if (fromFetch) {
        return null;
      }

      return await fetchPaymentInfo(fromGet: true);
    }
    return paymentInfo;
  }

  Future<Map<String, String?>?> fetchAdvisingInfo({
    bool fromGet = false,
    bool retrying = false,
  }) async {
    final SharedPreferencesAsync asyncPrefs = SharedPreferencesAsync();
    final String? studentId = await asyncPrefs.getString('studentId');
    final advisingUrl =
        'https://connect.bracu.ac.bd/api/adv/v1/advising/$studentId/active-advising-sessions?advisingPhase=PHASE_ONE&advisingPhase=PHASE_TWO&advisingPhase=SELF_REGISTRATION';

    final List<ConnectivityResult> connectivityResult = await (Connectivity()
        .checkConnectivity());
    if (connectivityResult.contains(ConnectivityResult.none)) {
      if (fromGet) {
        return null;
      }
      return await getAdvisingInfo(fromFetch: true);
    }

    final accessToken = await _storage.read(key: 'access_token');
    if (accessToken == null) {
      if (fromGet) {
        return null;
      }
      return await getAdvisingInfo(fromFetch: true);
    }

    final headers = {
      'Authorization': 'Bearer $accessToken',
      'X-REALM': 'bracu',
      'Accept': 'application/json',
    };

    try {
      final response = await http.get(Uri.parse(advisingUrl), headers: headers);

      if (response.statusCode == 200) {
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

        return getAdvisingInfo(fromFetch: true);
      } else if (response.statusCode == 401) {
        if (retrying) {
          await logout();
          return fromGet ? null : getAdvisingInfo(fromFetch: true);
        }

        final refreshed = await refreshToken();
        if (!refreshed) {
          await logout();
          return fromGet ? null : getAdvisingInfo(fromFetch: true);
        }

        return await fetchAdvisingInfo(fromGet: fromGet, retrying: true);
      }
    } catch (e) {
      return fromGet ? null : getAdvisingInfo(fromFetch: true);
    }
    if (fromGet) {
      return null;
    }
    return getAdvisingInfo(fromFetch: true);
  }

  Future<Map<String, String?>?> getAdvisingInfo({
    bool fromFetch = false,
  }) async {
    final keys = [
      'advisingStartDate',
      'advisingEndDate',
      'activeSemesterSessionId',
      'advisingPhase',
      'totalCredit',
      'earnedCredit',
      'noOfSemester',
    ];
    final SharedPreferencesWithCache prefsWithCache =
        await SharedPreferencesWithCache.create(
          cacheOptions: const SharedPreferencesWithCacheOptions(
            allowList: <String>{
              'advisingStartDate',
              'advisingEndDate',
              'activeSemesterSessionId',
              'advisingPhase',
              'totalCredit',
              'earnedCredit',
              'noOfSemester',
            },
          ),
        );

    final Map<String, String?> advisingData = {};
    if (fromFetch) {
      await prefsWithCache.reloadCache();
    }
    for (final key in keys) {
      advisingData[key] = prefsWithCache.getString(key);
    }

    bool isIncomplete = advisingData.values.any(
      (value) => value == null || value == '',
    );
    if (isIncomplete) {
      if (fromFetch) {
        return null;
      }

      return await fetchAdvisingInfo(fromGet: true);
    }
    return advisingData;
  }

  Future<String?> getStudentSchedule({bool fromFetch = false}) async {
    final SharedPreferencesWithCache prefsWithCache =
        await SharedPreferencesWithCache.create(
          cacheOptions: const SharedPreferencesWithCacheOptions(
            allowList: <String>{'StudentSchedule'},
          ),
        );

    if (fromFetch) {
      await prefsWithCache.reloadCache();
    }

    final String scheduleJson =
        prefsWithCache.getString('StudentSchedule') ?? '';

    if (scheduleJson == '') {
      if (fromFetch) return null;

      return await fetchStudentSchedule(fromGet: true);
    }
    return scheduleJson;
  }

  Future<String?> fetchStudentSchedule({
    bool fromGet = false,
    bool retrying = false,
  }) async {
    final SharedPreferencesAsync asyncPrefs = SharedPreferencesAsync();
    String? id = await asyncPrefs.getString('id');

    while (id == null) {
      await fetchProfile();
      id = await asyncPrefs.getString('id');
    }

    final String url =
        'https://connect.bracu.ac.bd/api/adv/v1/student-courses/schedules?studentPortfolioId=$id';

    final List<ConnectivityResult> connectivityResult = await Connectivity()
        .checkConnectivity();
    if (connectivityResult.contains(ConnectivityResult.none)) {
      if (fromGet) return null;
      return await getStudentSchedule(fromFetch: true);
    }

    final accessToken = await _storage.read(key: 'access_token');
    if (accessToken == null) {
      if (fromGet) return null;
      return await getStudentSchedule(fromFetch: true);
    }

    final headers = {
      'Authorization': 'Bearer $accessToken',
      'X-REALM': 'bracu',
      'Accept': 'application/json',
    };

    try {
      final response = await http.get(Uri.parse(url), headers: headers);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);

        await asyncPrefs.setString('StudentSchedule', jsonEncode(data));

        return getStudentSchedule(fromFetch: true);
      } else if (response.statusCode == 401) {
        if (retrying) {
          await logout();
          return fromGet ? null : getStudentSchedule(fromFetch: true);
        }

        final refreshed = await refreshToken();
        if (!refreshed) {
          await logout();
          return fromGet ? null : getStudentSchedule(fromFetch: true);
        }

        return await fetchStudentSchedule(fromGet: fromGet, retrying: true);
      }
    } catch (e) {
      return fromGet ? null : getStudentSchedule(fromFetch: true);
    }

    if (fromGet) return null;
    return getStudentSchedule(fromFetch: true);
  }

  Future<String?> getAttendanceInfo({bool fromFetch = false}) async {
    final SharedPreferencesWithCache prefsWithCache =
        await SharedPreferencesWithCache.create(
          cacheOptions: const SharedPreferencesWithCacheOptions(
            allowList: <String>{'attendance'},
          ),
        );

    if (fromFetch) {
      await prefsWithCache.reloadCache();
    }

    final String attendanceJson = prefsWithCache.getString('attendance') ?? '';

    if (attendanceJson == '') {
      if (fromFetch) return null;

      return await fetchAttendanceInfo(fromGet: true);
    }
    return attendanceJson;
  }

  Future<String?> fetchAttendanceInfo({
    bool fromGet = false,
    bool retrying = false,
  }) async {
    final SharedPreferencesAsync asyncPrefs = SharedPreferencesAsync();
    String? id = await asyncPrefs.getString('id');

    while (id == null) {
      await fetchProfile();
      id = await asyncPrefs.getString('id');
    }

    final String url =
        'https://connect.bracu.ac.bd/api/exc/v1/student-courses/$id/current-semester-attendance';

    final List<ConnectivityResult> connectivityResult = await Connectivity()
        .checkConnectivity();
    if (connectivityResult.contains(ConnectivityResult.none)) {
      if (fromGet) return null;
      return await getAttendanceInfo(fromFetch: true);
    }

    final accessToken = await _storage.read(key: 'access_token');
    if (accessToken == null) {
      if (fromGet) return null;
      return await getAttendanceInfo(fromFetch: true);
    }

    final headers = {
      'Authorization': 'Bearer $accessToken',
      'X-REALM': 'bracu',
      'Accept': 'application/json',
    };

    try {
      final response = await http.get(Uri.parse(url), headers: headers);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);

        await asyncPrefs.setString('attendance', jsonEncode(data));

        return getAttendanceInfo(fromFetch: true);
      } else if (response.statusCode == 401) {
        if (retrying) {
          await logout();
          return fromGet ? null : getAttendanceInfo(fromFetch: true);
        }

        final refreshed = await refreshToken();
        if (!refreshed) {
          await logout();
          return fromGet ? null : getAttendanceInfo(fromFetch: true);
        }

        return await fetchAttendanceInfo(fromGet: fromGet, retrying: true);
      }
    } catch (e) {
      return fromGet ? null : getAttendanceInfo(fromFetch: true);
    }

    if (fromGet) return null;
    return getAttendanceInfo(fromFetch: true);
  }
}
