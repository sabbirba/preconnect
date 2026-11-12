import 'dart:convert';
import 'package:preconnect/model/advising_phase.dart';
import 'package:preconnect/tools/runtime_stub.dart'
    if (dart.library.js_interop) 'package:preconnect/tools/runtime_web.dart';
import 'package:preconnect/tools/origin_stub.dart'
    if (dart.library.js_interop) 'package:preconnect/tools/origin_web.dart';

const bool _kIsWeb = identical(0, 0.0);

class ApiConfig {
  ApiConfig._();

  static const String ssoRealm = 'https://sso.bracu.ac.bd/realms/bracu';
  static const String ssoBase = '$ssoRealm/protocol/openid-connect';
  static const String accountSecurityUrl =
      '$ssoRealm/account/account-security/device-activity';
  static const String pocketBaseUrl = String.fromEnvironment(
    'POCKETBASE_URL',
    defaultValue: 'https://pb.preconnect.app',
  );
  static const String chatSessionUrl = '$pocketBaseUrl/api/chat/session';
  static String get _webProxyBase {
    final origin = getWebAppOrigin();
    if (origin.contains('localhost') || origin.contains('127.0.0.1')) {
      return websiteBase;
    }
    return origin;
  }

  static String get tokenEndpoint {
    if (_kIsWeb && !isChromeRuntimeAvailable()) {
      return '$_webProxyBase/sso/token';
    }
    return '$ssoBase/token';
  }

  static String get logoutEndpoint {
    if (_kIsWeb && !isChromeRuntimeAvailable()) {
      return '$_webProxyBase/sso/logout';
    }
    return '$ssoBase/logout';
  }

  static String get authEndpoint => '$ssoBase/auth';

  static const String realtimeApiBase = 'https://api.preconnect.app';
  static const String seatStatusDataUrl = '$realtimeApiBase/connect.json';
  static const String seatStreamUrl = '$realtimeApiBase/seat-status/stream';
  static const String busStreamUrl = '$realtimeApiBase/bus/stream';
  static const String freeLabsDataUrl = '$realtimeApiBase/freelabs.json';
  static const String dspaceDataUrl = '$realtimeApiBase/dspace.json';
  static String dspaceItemUrl(String handle) =>
      'https://dspace.bracu.ac.bd/handle/$handle';
  static const String examMapIndexUrl = '$realtimeApiBase/exammap.json';
  static const String announcementFeedUrl =
      '$realtimeApiBase/announcements.json';
  static const String newsFeedUrl = '$realtimeApiBase/news.json';
  static const String academicDatesUrl = '$realtimeApiBase/academic-dates.json';
  static const String campusMapUrl = '$realtimeApiBase/map.json';
  static const String transportUrl = '$realtimeApiBase/transport.json';
  static const String holidayStatusUrl = '$realtimeApiBase/holiday.json';
  static const String ramadanStatusUrl = '$realtimeApiBase/ramadan.json';
  static const String coursePrerequisitesUrl =
      '$realtimeApiBase/course-prerequisites.json';
  static const String materialsUrl = '$realtimeApiBase/materials';
  static const String materialsIndexUrl = '$materialsUrl.json';

  static String materialsSourceUrl(String source) =>
      '$materialsUrl/${Uri.encodeComponent(source)}';

  static String materialsDetailUrl(String source, String code) =>
      '$materialsUrl/${Uri.encodeComponent(source)}/${Uri.encodeComponent(code)}';

  static String get connectApiBase {
    if (_kIsWeb && !isChromeRuntimeAvailable()) {
      return '$_webProxyBase/api';
    }
    return 'https://connect.bracu.ac.bd/api';
  }

  static String get connectCdnBase {
    if (_kIsWeb && !isChromeRuntimeAvailable()) {
      return '$_webProxyBase/cdn';
    }
    return 'https://connect.bracu.ac.bd/cdn';
  }

  static const String connectOrigin = 'https://connect.bracu.ac.bd';
  static String get connectMercureHubUrl =>
      'https://connect.bracu.ac.bd/.well-known/mercure?topic=${Uri.encodeComponent('http://pr/{group}/{id}')}';
  static const String connectMercureLoginPath = '/ns/mercure/login';
  static const String connectMercureLogoutPath = '/ns/mercure/logout';
  static const String websiteBase = 'https://preconnect.app';
  static const String fundingUrl = '$websiteBase/funding';
  static const String androidPackageName = 'com.sabbirba.preconnect';
  static const String appStoreId = '6791423431';

  static const String appStoreBaseUrl =
      'https://apps.apple.com/us/app/preconnect-bracu-student-app/id';
  static const String appStoreUrl = '$appStoreBaseUrl$appStoreId';
  static const String playStoreBaseUrl =
      'https://play.google.com/store/apps/details?id=';
  static const String playStoreUrl = '$playStoreBaseUrl$androidPackageName';
  static const String storeLinksText =
      'Play Store: $playStoreUrl\nApp Store: $appStoreUrl';

  static const String clientId = 'slm';
  static String get redirectUri => _kIsWeb
      ? '${getWebAppOrigin()}/student/profile/overview'
      : 'https://connect.bracu.ac.bd/student/profile/overview';

  static const String profilePath = '/mds/v1/portfolios';
  static const String allPortfoliosPath =
      '/mds/v1/portfolios?includeInactive=true';
  static const String miscellaneousInfoPath =
      '/adp/v1/students/miscellaneous-info';
  static const String studentPath = '/mds/v1/student/info';

  static String paymentPath(String portfolioId) =>
      '/fin/v1/payment/portfolio/$portfolioId';

  static String advisingPath(String studentId) =>
      '/adv/v1/advising/$studentId/active-advising-sessions';

  static String selfRegistrationSessionPath(
    String studentId,
    String sessionKey,
  ) =>
      '/adv/v1/advising/$studentId/self-registration-session?sessionKey=$sessionKey';

  static String advisingStudentCoursesPath(AdvisingPhase phase) =>
      phase == AdvisingPhase.selfRegistration
      ? '/adv/v1/student-courses'
      : '/adv/v1/student-courses/${phase.pathSegment}';

  static String advisingSectionsPath(
    String portfolioId, {
    required AdvisingPhase phase,
  }) =>
      '/adv/v1/advising/sections?studentPortfolioId=$portfolioId&phase=${phase.queryValue}';

  static String advisingConfirmPath(String portfolioId) =>
      '/adv/v1/student-courses/$portfolioId/confirm';

  static String connectAdvisingUrl(String pageSegment) =>
      '$connectOrigin/student/advising/$pageSegment';

  static const String wishlistPageSegment = 'wish-list';

  static String wishlistPath(String studentId) =>
      '/adv/v1/advising/$studentId/active-wishlist-sessions';

  static String wishlistSessionPath(String portfolioId, String publicKey) =>
      '/adv/v1/advising/$portfolioId/wishlist-session?publicKey=$publicKey';

  static String wishlistCoursesPath(String portfolioId) =>
      '/adv/v1/wishlists/$portfolioId';

  static String wishlistOfferedCoursesPath(String portfolioId) =>
      '/adv/v1/wishlists/$portfolioId/offered-courses';

  static String wishlistStatusPath(String portfolioId) =>
      '/adv/v1/wishlists/$portfolioId/status';

  static String wishlistConfirmPath(String portfolioId) =>
      '/adv/v1/wishlists/$portfolioId/confirm';

  static const String wishlistMutationPath = '/adv/v1/wishlists';

  static String schedulePath(String portfolioId, {int? semesterSessionId}) {
    final semesterQuery = semesterSessionId == null
        ? ''
        : '&semesterSessionId=$semesterSessionId';
    return '/adv/v1/student-courses/schedules?studentPortfolioId=$portfolioId$semesterQuery';
  }

  static String sessionsPath(String portfolioId) =>
      '/adv/v1/student-courses/sessions?studentPortfolioId=$portfolioId';

  static String relatedLabSectionsPath(
    String portfolioId, {
    String phase = 'PHASE_ONE',
  }) =>
      '/adv/v1/advising/sections/student/$portfolioId/related-lab-sections'
      '?phase=$phase';

  static String studentCoursesForPhasePath(
    String portfolioId,
    AdvisingPhase phase,
  ) => phase == AdvisingPhase.selfRegistration
      ? '/adv/v1/student-courses/$portfolioId'
      : '/adv/v1/student-courses/$portfolioId/${phase.pathSegment}';

  static String attendancePath(String portfolioId) =>
      '/exc/v1/student-courses/$portfolioId/current-semester-attendance';

  static String majorMinorsPath(String portfolioId) =>
      '/reg/v1/student-portfolio/$portfolioId/major-minors';

  static String completedCoursesPath(String portfolioId) =>
      '/exc/v1/student-completed-taken-courses/$portfolioId';

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
  static String userNotificationsPath(int offset, int limit) =>
      '/ns/notifications/user?offset=$offset&limit=$limit';

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

  static String payslipDetailUrl(String payslipNo) =>
      '$connectApiBase/fin/v1/payment/payslip/$payslipNo';

  static String get bankConfigurationsUrl =>
      '$connectApiBase/fin/v1/configuration/banks/get-bank-configurations?active=true';

  static String get pdfPrintUrl => '$connectApiBase/pdf/v1.0/print';

  static const List<String> advisingPhases = [
    'PHASE_ONE',
    'PHASE_TWO',
    'SELF_REGISTRATION',
  ];

  static String advisingUrl(String studentId) {
    final phasesQuery = advisingPhases.map((p) => 'advisingPhase=$p').join('&');
    return '$connectApiBase${advisingPath(studentId)}?$phasesQuery';
  }

  static String wishlistUrl(String studentId) {
    return '$connectApiBase${wishlistPath(studentId)}';
  }

  static String authUrlWithPkce(String codeChallenge) {
    return pkceAuthUrl(
      endpoint: authEndpoint,
      clientId: clientId,
      redirectUri: redirectUri,
      codeChallenge: codeChallenge,
    );
  }

  static String pkceAuthUrl({
    required String endpoint,
    required String clientId,
    required String redirectUri,
    required String codeChallenge,
  }) {
    return '$endpoint'
        '?client_id=$clientId'
        '&redirect_uri=${Uri.encodeQueryComponent(redirectUri)}'
        '&response_type=code'
        '&response_mode=query'
        '&scope=openid offline_access'
        '&code_challenge=${Uri.encodeQueryComponent(codeChallenge)}'
        '&code_challenge_method=S256';
  }

  static String? photoUrl(String? filePath) {
    if (filePath == null || filePath.isEmpty) return null;
    final encoded = base64Url.encode(utf8.encode(filePath)).replaceAll('=', '');
    return '$connectCdnBase/img/thumb/$encoded.jpg';
  }
}
