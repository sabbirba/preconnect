import 'dart:convert';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:preconnect/tools/web_origin_stub.dart'
    if (dart.library.html) 'package:preconnect/tools/web_origin_web.dart';


class ApiConfig {
  ApiConfig._();

  static const String ssoBase =
      'https://sso.bracu.ac.bd/realms/bracu/protocol/openid-connect';
  static const String tokenEndpoint = '$ssoBase/token';
  static const String logoutEndpoint = '$ssoBase/logout';
  static const String authEndpoint = '$ssoBase/auth';

  static const String cdnApiBase = 'https://cdn.preconnect.app/api';
  static const String realtimeApiBase = 'https://api.preconnect.app';
  static const String seatStatusProxyBase = realtimeApiBase;
  static const String publicJsonBase = cdnApiBase;
  static const String seatStatusDataUrl = '$cdnApiBase/connect.json';
  static const String busDataUrl = '$cdnApiBase/data/bus.json';
  static const String freeLabsDataUrl = '$cdnApiBase/freelabs.json';
  static const String examMapIndexUrl = '$cdnApiBase/data/exammap.json';
  static const String facultyReviewsDataUrl =
      '$cdnApiBase/data/facultyreviews.json';
  static const String announcementFeedUrl =
      '$cdnApiBase/data/announcements.json';
  static const String newsFeedUrl = '$cdnApiBase/data/news.json';
  static const String academicDatesUrl = '$cdnApiBase/data/academic-dates.json';
  static const String campusMapUrl = '$cdnApiBase/data/map.json';
  static const String transportUrl = '$cdnApiBase/data/transport.json';
  static const String connectApiBase = 'https://connect.bracu.ac.bd/api';
  static const String connectWebApiBase = 'https://connect.bracu.ac.bd/api';
  static const String connectCdnBase = 'https://connect.bracu.ac.bd/cdn';
  static const String connectOrigin = 'https://connect.bracu.ac.bd';
  static const String connectMercureLogoutPath = '/ns/mercure/logout';
  static String get websiteBase => kIsWeb ? getWebAppOrigin() : 'https://preconnect.app';
  static String get websiteMueenAvatarUrl =>
      '$websiteBase/Mueen-Ahmmed.jpeg';
  static const String filesBase = 'https://cdn.preconnect.app';

  static const String clientId = 'slm';
  static String get redirectUri => kIsWeb
      ? '${getWebAppOrigin()}/student/profile/overview'
      : 'https://connect.bracu.ac.bd/student/profile/overview';

  static const String profilePath = '/mds/v1/portfolios';
  static const String miscellaneousInfoPath =
      '/adp/v1/students/miscellaneous-info';

  static String paymentPath(String portfolioId) =>
      '/fin/v1/payment/portfolio/$portfolioId';

  static String advisingPath(String studentId) =>
      '/adv/v1/advising/$studentId/active-advising-sessions';

  static String schedulePath(String portfolioId, {int? semesterSessionId}) {
    final semesterQuery = semesterSessionId == null
        ? ''
        : '&semesterSessionId=$semesterSessionId';
    return '/adv/v1/student-courses/schedules?studentPortfolioId=$portfolioId$semesterQuery';
  }

  static String attendancePath(String portfolioId) =>
      '/exc/v1/student-courses/$portfolioId/current-semester-attendance';

  static String majorMinorsPath(String portfolioId) =>
      '/reg/v1/student-portfolio/$portfolioId/major-minors';

  static String completedCoursesPath(String portfolioId) =>
      '/exc/v1/student-completed-courses/$portfolioId';

  static String programCurriculumsPath(String portfolioId) =>
      '/reg/v1/student-portfolio/$portfolioId/program-curriculums';

  static String gradeSheetPath(String profileId) =>
      '/data/document/grade-sheet-web?id=$profileId';

  static const String recentNotificationsPath = '/ns/notifications/recent';

  static String calendarPath(
    int calendarId, {
    required String startDate,
    required String endDate,
  }) => '/reg/v1/calendar/$calendarId?startDate=$startDate&endDate=$endDate';

  static String notificationViewPath(int id) => '/ns/notifications/view/$id';

  static const Map<String, String> apiHeaders = {
    'X-REALM': 'bracu',
    'X-SOURCE': '3',
    'Accept': 'application/json, text/plain, */*',
    'Accept-Language': 'en-US,en;q=0.9',
  };

  static const List<String> paymentTypes = [
    'ADMISSION_FEE',
    'REGISTRATION_FEE',
    'MAKEUP_EXAM_FEE',
    'DEPARTMENT_CHANGE_FEE',
    'ACCOMMODATION_FEE',
    'PRE_UNIVERSITY_FEE',
    'LIBRARY_FINE_FEE',
    'SHORT_COURSE_FEE',
    'CERTIFICATE_COURSE_FEE',
    'VISITING_STUDENT_ADMISSION_FEE',
    'ADDED_COURSE_FEE',
    'OTHER_FEE',
  ];

  static String paymentUrl(String portfolioId) {
    final typesQuery = paymentTypes.map((t) => 'paymentTypes=$t').join('&');
    return '$connectApiBase${paymentPath(portfolioId)}?$typesQuery';
  }

  static const List<String> advisingPhases = [
    'PHASE_ONE',
    'PHASE_TWO',
    'SELF_REGISTRATION',
  ];

  static String advisingUrl(String studentId) {
    final phasesQuery = advisingPhases.map((p) => 'advisingPhase=$p').join('&');
    return '$connectApiBase${advisingPath(studentId)}?$phasesQuery';
  }

  static String get authUrl =>
      '$authEndpoint'
      '?client_id=$clientId'
      '&redirect_uri=${Uri.encodeQueryComponent(redirectUri)}'
      '&response_type=code'
      '&response_mode=query'
      '&scope=openid offline_access';

  static String authUrlWithPkce(String codeChallenge) {
    final encodedChallenge = Uri.encodeQueryComponent(codeChallenge);
    return '$authEndpoint'
        '?client_id=$clientId'
        '&redirect_uri=${Uri.encodeQueryComponent(redirectUri)}'
        '&response_type=code'
        '&response_mode=query'
        '&scope=openid offline_access'
        '&code_challenge=$encodedChallenge'
        '&code_challenge_method=S256';
  }

  static String? photoUrl(String? filePath) {
    if (filePath == null || filePath.isEmpty) return null;
    final encoded = base64Url.encode(utf8.encode(filePath)).replaceAll('=', '');
    return '$connectCdnBase/img/thumb/$encoded.jpg';
  }
}
