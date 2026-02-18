import 'dart:convert';

class ApiConfig {
  ApiConfig._();

  static const String ssoBase =
      'https://sso.bracu.ac.bd/realms/bracu/protocol/openid-connect';
  static const String tokenEndpoint = '$ssoBase/token';
  static const String logoutEndpoint = '$ssoBase/logout';
  static const String authEndpoint = '$ssoBase/auth';

  static const String connectApiBase = 'https://connect.bracu.ac.bd/api';
  static const String cdnBase = 'https://connect.bracu.ac.bd/cdn';

  static const String clientId = 'slm';
  static const String redirectUri = 'https://connect.bracu.ac.bd/';

  static const String profilePath = '/mds/v1/portfolios';

  static String paymentPath(String portfolioId) =>
      '/fin/v1/payment/portfolio/$portfolioId';

  static String advisingPath(String studentId) =>
      '/adv/v1/advising/$studentId/active-advising-sessions';

  static String schedulePath(String portfolioId) =>
      '/adv/v1/student-courses/schedules?studentPortfolioId=$portfolioId';

  static String attendancePath(String portfolioId) =>
      '/exc/v1/student-courses/$portfolioId/current-semester-attendance';

  static const Map<String, String> apiHeaders = {
    'X-REALM': 'bracu',
    'Accept': 'application/json',
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
    final phasesQuery =
        advisingPhases.map((p) => 'advisingPhase=$p').join('&');
    return '$connectApiBase${advisingPath(studentId)}?$phasesQuery';
  }

  static const String authUrl = '$authEndpoint'
      '?client_id=$clientId'
      '&redirect_uri=https%3A%2F%2Fconnect.bracu.ac.bd%2F'
      '&response_type=code'
      '&response_mode=query'
      '&scope=openid offline_access';

  static String? photoUrl(String? filePath) {
    if (filePath == null || filePath.isEmpty) return null;
    final encoded =
        base64Url.encode(utf8.encode(filePath)).replaceAll('=', '');
    return '$cdnBase/img/thumb/$encoded.jpg';
  }
}
