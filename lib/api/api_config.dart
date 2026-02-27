import 'dart:convert';

class ApiConfig {
  ApiConfig._();
  static const String playIntegrityCloudProjectNumberEnv =
      String.fromEnvironment('PLAY_INTEGRITY_CLOUD_PROJECT_NUMBER');
  static const String _seatWorkerWsUrl = 'wss://seatstatus.preconnect.app';

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

  static const Map<String, String> apiHeaders = {
    'X-REALM': 'bracu',
    'Accept': 'application/json',
  };

  static int? get playIntegrityCloudProjectNumber {
    final value = playIntegrityCloudProjectNumberEnv.trim();
    if (value.isEmpty) return null;
    return int.tryParse(value);
  }

  static String? get seatWorkerWsUrl {
    final value = _seatWorkerWsUrl.trim();
    if (value.isEmpty) return null;
    return value.endsWith('/') ? value.substring(0, value.length - 1) : value;
  }

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

  static const String authUrl =
      '$authEndpoint'
      '?client_id=$clientId'
      '&redirect_uri=https%3A%2F%2Fconnect.bracu.ac.bd%2F'
      '&response_type=code'
      '&response_mode=query'
      '&scope=openid offline_access';

  static String? photoUrl(String? filePath) {
    if (filePath == null || filePath.isEmpty) return null;
    final encoded = base64Url.encode(utf8.encode(filePath)).replaceAll('=', '');
    return '$cdnBase/img/thumb/$encoded.jpg';
  }
}
