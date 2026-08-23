import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:preconnect/api/api_client.dart';
import 'package:preconnect/api/api_config.dart';
import 'package:preconnect/api/seat_status.dart';
import 'package:preconnect/model/advising_phase.dart';
import 'package:preconnect/tools/app_storage.dart';

enum TargetSectionStatus {
  idle,
  watching,
  adding,
  added,
  failed,
  skippedZeroSeats,
}

class AdvisingSessionInfo {
  final String id;
  final int semesterSessionId;
  final String phase;
  final String? title;

  const AdvisingSessionInfo({
    required this.id,
    required this.semesterSessionId,
    required this.phase,
    this.title,
  });

  factory AdvisingSessionInfo.fromJson(Map<String, dynamic> json) {
    final rawId = json['id'] ?? json['sessionId'] ?? json['advisingSessionId'];
    final rawSemesterId = json['semesterSessionId'] ?? json['sessionId'];
    final id = (rawId ?? '').toString();
    final semesterId = rawSemesterId is num
        ? rawSemesterId.toInt()
        : int.tryParse(rawSemesterId?.toString() ?? '') ?? 0;
    final phase =
        (json['advisingPhase'] ??
                json['phase'] ??
                json['advisingPhaseName'] ??
                'PHASE_TWO')
            .toString();
    final title =
        (json['title'] ??
                json['description'] ??
                json['semesterSessionName'] ??
                '')
            .toString();

    return AdvisingSessionInfo(
      id: id,
      semesterSessionId: semesterId,
      phase: phase,
      title: title.isEmpty ? null : title,
    );
  }
}

class AdvisingSectionRecord {
  final int sectionId;
  final int? advisingSectionId;
  final int? courseId;
  final String courseCode;
  final String? courseName;
  final String sectionName;
  final int capacity;
  final int consumedSeat;
  final int courseCredit;
  final String? faculty;
  final String? roomNumber;
  final int? labSectionId;
  final String? labSectionName;

  const AdvisingSectionRecord({
    required this.sectionId,
    this.advisingSectionId,
    this.courseId,
    required this.courseCode,
    this.courseName,
    required this.sectionName,
    required this.capacity,
    required this.consumedSeat,
    required this.courseCredit,
    this.faculty,
    this.roomNumber,
    this.labSectionId,
    this.labSectionName,
  });

  int get remainingSeats => (capacity - consumedSeat).clamp(0, 9999);

  factory AdvisingSectionRecord.fromJson(Map<String, dynamic> json) {
    final rawSectionId = json['sectionId'] ?? json['id'];
    final sectionId = rawSectionId is num
        ? rawSectionId.toInt()
        : int.tryParse(rawSectionId?.toString() ?? '') ?? 0;

    final rawAdvId = json['advisingSectionId'] ?? json['studentCourseId'];
    final advisingSectionId = rawAdvId is num
        ? rawAdvId.toInt()
        : int.tryParse(rawAdvId?.toString() ?? '');

    final rawCourseId = json['courseId'];
    final courseId = rawCourseId is num
        ? rawCourseId.toInt()
        : int.tryParse(rawCourseId?.toString() ?? '');

    final rawCap = json['capacity'] ?? 0;
    final capacity = rawCap is num
        ? rawCap.toInt()
        : int.tryParse(rawCap.toString()) ?? 0;

    final rawConsumed = json['consumedSeat'] ?? 0;
    final consumedSeat = rawConsumed is num
        ? rawConsumed.toInt()
        : int.tryParse(rawConsumed.toString()) ?? 0;

    final rawCredit = json['courseCredit'] ?? json['credit'] ?? 3;
    final courseCredit = rawCredit is num
        ? rawCredit.toInt()
        : int.tryParse(rawCredit.toString()) ?? 3;

    final rawLabId = json['labSectionId'];
    final labSectionId = rawLabId is num
        ? rawLabId.toInt()
        : int.tryParse(rawLabId?.toString() ?? '');

    return AdvisingSectionRecord(
      sectionId: sectionId,
      advisingSectionId: advisingSectionId,
      courseId: courseId,
      courseCode: (json['courseCode'] ?? json['code'] ?? '').toString(),
      courseName: (json['courseName'] ?? json['name'])?.toString(),
      sectionName: (json['sectionName'] ?? json['section'] ?? '').toString(),
      capacity: capacity,
      consumedSeat: consumedSeat,
      courseCredit: courseCredit,
      faculty: (json['faculties'] ?? json['faculty'])?.toString(),
      roomNumber: (json['roomNumber'] ?? json['roomName'])?.toString(),
      labSectionId: labSectionId,
      labSectionName: json['labSectionName']?.toString(),
    );
  }
}

class TargetSectionItem {
  final int sectionId;
  final int? courseId;
  final String courseCode;
  final String? courseName;
  final String sectionName;
  final int capacity;
  final int consumedSeat;
  final int courseCredit;
  final int? labSectionId;
  final String? labSectionName;
  TargetSectionStatus status;
  DateTime? lastAttempt;
  String? message;

  TargetSectionItem({
    required this.sectionId,
    this.courseId,
    required this.courseCode,
    this.courseName,
    required this.sectionName,
    required this.capacity,
    required this.consumedSeat,
    required this.courseCredit,
    this.labSectionId,
    this.labSectionName,
    this.status = TargetSectionStatus.idle,
    this.lastAttempt,
    this.message,
  });

  int get remainingSeats => (capacity - consumedSeat).clamp(0, 9999);
}

class AdvisingHelperService {
  static final AdvisingHelperService _instance =
      AdvisingHelperService._internal();
  factory AdvisingHelperService() => _instance;
  AdvisingHelperService._internal();

  final ApiClient _client = ApiClient();

  Future<String> buildCookieHeader() async {
    final connectJson = await AppStorage.instance.getString(
      'preconnect.cookies.connect',
    );
    final ssoJson = await AppStorage.instance.getString(
      'preconnect.cookies.sso',
    );

    final parts = <String>[];
    void extractCookies(String? raw) {
      if (raw == null || raw.trim().isEmpty) return;
      try {
        final decoded = jsonDecode(raw);
        if (decoded is List) {
          for (final item in decoded) {
            if (item is Map) {
              final name = '${item['name'] ?? ''}'.trim();
              final val = '${item['value'] ?? ''}'.trim();
              if (name.isNotEmpty) {
                parts.add('$name=$val');
              }
            }
          }
        }
      } catch (_) {}
    }

    extractCookies(connectJson);
    extractCookies(ssoJson);
    return parts.join('; ');
  }

  Future<Map<String, String>> buildRequestHeaders({
    String? publicKey,
    String? phasePathSegment,
  }) async {
    final cookie = await buildCookieHeader();
    final refererSegment = phasePathSegment ?? 'phase-two';

    return <String, String>{
      'Content-Type': 'application/json',
      'Accept': 'application/json, text/plain, */*',
      'X-REALM': 'bracu',
      'X-SOURCE': '3',
      if (!kIsWeb) 'Origin': ApiConfig.connectOrigin,
      if (!kIsWeb)
        'Referer':
            'https://connect.bracu.ac.bd/student/advising/$refererSegment',
      if (!kIsWeb)
        'User-Agent':
            'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/134.0.0.0 Safari/537.36',
      if (!kIsWeb && cookie.isNotEmpty) 'Cookie': cookie,
      if (publicKey != null && publicKey.isNotEmpty)
        'X-Advising-Session': publicKey,
    };
  }

  Future<List<AdvisingSessionInfo>> fetchActiveSessions(
    String studentId, {
    AdvisingPhase? phase,
  }) async {
    final query = phase != null
        ? 'advisingPhase=${phase.queryValue}'
        : 'advisingPhase=PHASE_ONE&advisingPhase=PHASE_TWO&advisingPhase=SELF_REGISTRATION';
    final url =
        '${ApiConfig.connectApiBase}${ApiConfig.advisingPath(studentId)}?$query';

    final headers = await buildRequestHeaders();
    final res = await _client.authenticatedGet(
      url,
      additionalHeaders: headers,
      bypassCache: true,
    );

    if (res.statusCode == 200) {
      final decoded = jsonDecode(res.body);
      if (decoded is List) {
        return decoded
            .whereType<Map>()
            .map((e) => AdvisingSessionInfo.fromJson(e.cast<String, dynamic>()))
            .toList();
      }
    }
    return const <AdvisingSessionInfo>[];
  }

  Future<bool> startSession(
    String sessionId,
    String publicKey, {
    String? phasePathSegment,
  }) async {
    final url =
        '${ApiConfig.connectApiBase}${ApiConfig.advisingSessionStartPath(sessionId, publicKey: publicKey)}';
    final headers = await buildRequestHeaders(
      publicKey: publicKey,
      phasePathSegment: phasePathSegment,
    );

    try {
      final res = await _client.authenticatedRequest(
        'POST',
        url,
        body: '',
        additionalHeaders: headers,
      );
      return res.statusCode == 200 ||
          res.statusCode == 201 ||
          res.statusCode == 204;
    } catch (_) {
      return false;
    }
  }

  Future<List<AdvisingSectionRecord>> fetchAdvisedSections(
    String portfolioId, {
    AdvisingPhase phase = AdvisingPhase.phaseTwo,
    String? publicKey,
  }) async {
    final url =
        '${ApiConfig.connectApiBase}${ApiConfig.studentCoursesForPhasePath(portfolioId, phase)}';
    final headers = await buildRequestHeaders(
      publicKey: publicKey,
      phasePathSegment: phase.pathSegment,
    );

    final res = await _client.authenticatedGet(
      url,
      additionalHeaders: headers,
      bypassCache: true,
    );

    if (res.statusCode == 200) {
      final decoded = jsonDecode(res.body);
      List<dynamic>? list;
      if (decoded is List) {
        list = decoded;
      } else if (decoded is Map && decoded['courses'] is List) {
        list = decoded['courses'];
      } else if (decoded is Map && decoded['sections'] is List) {
        list = decoded['sections'];
      }
      if (list != null) {
        return list
            .whereType<Map>()
            .map(
              (e) => AdvisingSectionRecord.fromJson(e.cast<String, dynamic>()),
            )
            .toList();
      }
    }
    return const <AdvisingSectionRecord>[];
  }

  Future<bool> addSection({
    required String portfolioId,
    required int sectionId,
    int? courseId,
    int? labSectionId,
    int? courseCredit,
    required String publicKey,
    AdvisingPhase phase = AdvisingPhase.phaseTwo,
    void Function(String)? onError,
  }) async {
    final headers = await buildRequestHeaders(
      publicKey: publicKey,
      phasePathSegment: phase.pathSegment,
    );

    final parsedPortfolioId = int.tryParse(portfolioId);
    final payload = <String, dynamic>{
      'sectionId': sectionId,
      'studentPortfolioId': parsedPortfolioId ?? portfolioId,
      'courseId': ?courseId,
      'labSectionId': ?labSectionId,
      'courseCredit': ?courseCredit,
    };

    final url =
        '${ApiConfig.connectApiBase}${ApiConfig.studentCoursesActionPath(phase)}';

    try {
      final res = await _client.authenticatedRequest(
        'POST',
        url,
        body: jsonEncode(payload),
        additionalHeaders: headers,
        acceptedStatusCodes: const <int>{
          200,
          201,
          204,
          400,
          403,
          404,
          409,
          422,
        },
      );
      if (res.statusCode == 200 ||
          res.statusCode == 201 ||
          res.statusCode == 204) {
        return true;
      }
      final msg = _extractErrorMessage(res.body);
      if (onError != null) {
        onError(
          msg.isNotEmpty ? msg : 'Status ${res.statusCode}: ${res.body.trim()}',
        );
      }
    } catch (e) {
      if (onError != null) onError('$e');
    }
    return false;
  }

  String _extractErrorMessage(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map<String, dynamic>) {
        final msg =
            decoded['message'] ??
            decoded['error'] ??
            decoded['description'] ??
            decoded['title'] ??
            decoded['detail'];
        if (msg != null && msg.toString().trim().isNotEmpty) {
          return msg.toString().trim();
        }
      }
    } catch (_) {}
    return '';
  }

  Future<bool> dropSection({
    required String portfolioId,
    required int sectionId,
    int? advisingSectionId,
    required String publicKey,
    AdvisingPhase phase = AdvisingPhase.phaseTwo,
  }) async {
    final headers = await buildRequestHeaders(
      publicKey: publicKey,
      phasePathSegment: phase.pathSegment,
    );

    final parsedPortfolioId = int.tryParse(portfolioId);
    final payload = <String, dynamic>{
      'sectionId': sectionId,
      'studentPortfolioId': parsedPortfolioId ?? portfolioId,
      'advisingSectionId': ?advisingSectionId,
    };

    final url =
        '${ApiConfig.connectApiBase}${ApiConfig.studentCoursesActionPath(phase)}';

    try {
      final res = await _client.authenticatedRequest(
        'DELETE',
        url,
        body: jsonEncode(payload),
        additionalHeaders: headers,
        acceptedStatusCodes: const <int>{
          200,
          201,
          204,
          400,
          403,
          404,
          409,
          422,
        },
      );
      if (res.statusCode == 200 ||
          res.statusCode == 204 ||
          res.statusCode == 201) {
        return true;
      }
    } catch (_) {}
    return false;
  }

  Future<bool> confirmAdvising({
    required String portfolioId,
    required String sessionId,
    required String publicKey,
    AdvisingPhase phase = AdvisingPhase.phaseTwo,
  }) async {
    final headers = await buildRequestHeaders(
      publicKey: publicKey,
      phasePathSegment: phase.pathSegment,
    );

    final parsedPortfolioId = int.tryParse(portfolioId);
    final payload = jsonEncode(<String, dynamic>{
      'studentPortfolioId': parsedPortfolioId ?? portfolioId,
      'sessionId': sessionId,
    });

    final url =
        '${ApiConfig.connectApiBase}${ApiConfig.advisingConfirmPath(sessionId)}';

    try {
      final res = await _client.authenticatedRequest(
        'POST',
        url,
        body: payload,
        additionalHeaders: headers,
        acceptedStatusCodes: const <int>{
          200,
          201,
          204,
          400,
          403,
          404,
          409,
          422,
        },
      );
      if (res.statusCode == 200 ||
          res.statusCode == 201 ||
          res.statusCode == 204) {
        return true;
      }
    } catch (_) {}
    return false;
  }
}

class AdvisingAutoEngine extends ChangeNotifier {
  final List<TargetSectionItem> targetSections = <TargetSectionItem>[];
  final List<String> activityLogs = <String>[];

  bool isRunning = false;
  bool _isTicking = false;
  Timer? _loopTimer;
  String? portfolioId;
  String? sessionId;
  String? publicKey;
  AdvisingPhase phase = AdvisingPhase.phaseTwo;

  void addLog(String text) {
    final timeStr = DateTime.now().toIso8601String().substring(11, 19);
    final formatted = '[$timeStr] $text';
    activityLogs.insert(0, formatted);
    if (activityLogs.length > 200) {
      activityLogs.removeLast();
    }
    notifyListeners();
  }

  void addSectionToQueue(TargetSectionItem item) {
    if (targetSections.any((e) => e.sectionId == item.sectionId)) return;
    targetSections.add(item);
    addLog('Queued: ${item.courseCode} Section ${item.sectionName}');
    notifyListeners();
  }

  void removeSectionFromQueue(int sectionId) {
    final index = targetSections.indexWhere((e) => e.sectionId == sectionId);
    if (index != -1) {
      final item = targetSections.removeAt(index);
      addLog('Removed: ${item.courseCode} Section ${item.sectionName}');
      notifyListeners();
    }
  }

  void clearQueue() {
    targetSections.clear();
    addLog('Queue cleared');
    notifyListeners();
  }

  void start({
    required String portfolioId,
    required String sessionId,
    required String publicKey,
    AdvisingPhase phase = AdvisingPhase.phaseTwo,
  }) {
    if (isRunning) return;
    this.portfolioId = portfolioId;
    this.sessionId = sessionId;
    this.publicKey = publicKey;
    this.phase = phase;
    isRunning = true;
    addLog('Advising Helper started');
    notifyListeners();

    _loopTimer?.cancel();
    _loopTimer = Timer.periodic(const Duration(milliseconds: 1000), (_) {
      unawaited(_tick());
    });
    unawaited(_tick());
  }

  void stop() {
    if (!isRunning) return;
    isRunning = false;
    _loopTimer?.cancel();
    _loopTimer = null;
    for (final item in targetSections) {
      if (item.status == TargetSectionStatus.watching ||
          item.status == TargetSectionStatus.adding) {
        item.status = TargetSectionStatus.idle;
      }
    }
    addLog('Advising Helper stopped');
    notifyListeners();
  }

  Future<void> _tick() async {
    if (!isRunning || _isTicking || portfolioId == null || publicKey == null) {
      return;
    }
    _isTicking = true;

    try {
      final pending = targetSections
          .where(
            (s) =>
                s.status != TargetSectionStatus.added &&
                s.status != TargetSectionStatus.adding,
          )
          .toList();

      if (pending.isEmpty) return;

      Map<int, SeatStatusDetailsResponse>? detailsMap;
      try {
        detailsMap = await SeatStatusService().preloadData(forceRefresh: true);
      } catch (_) {
        detailsMap = SeatStatusService().cachedDetails;
      }

      for (final item in pending) {
        if (!isRunning ||
            !targetSections.any((e) => e.sectionId == item.sectionId)) {
          continue;
        }

        final detail = detailsMap?[item.sectionId];
        final currentCap = detail?.capacity ?? item.capacity;
        final currentConsumed = detail?.consumedSeat ?? item.consumedSeat;
        final remaining = currentCap - currentConsumed;

        if (remaining <= 0) {
          item.status = TargetSectionStatus.skippedZeroSeats;
          item.message = '0 seats remaining (Checked)';
          notifyListeners();
          continue;
        }

        item.status = TargetSectionStatus.adding;
        item.lastAttempt = DateTime.now();
        item.message =
            '$remaining seat${remaining == 1 ? '' : 's'} available! Adding...';
        addLog(
          'Seat opened: ${item.courseCode} Sec ${item.sectionName} ($remaining seats). Attempting add...',
        );
        notifyListeners();

        String? serverError;
        try {
          final success = await AdvisingHelperService().addSection(
            portfolioId: portfolioId!,
            sectionId: item.sectionId,
            courseId: item.courseId,
            labSectionId: item.labSectionId,
            courseCredit: item.courseCredit,
            publicKey: publicKey!,
            phase: phase,
            onError: (err) => serverError = err,
          );

          if (!targetSections.any((e) => e.sectionId == item.sectionId)) {
            continue;
          }

          if (success) {
            item.status = TargetSectionStatus.added;
            item.message = 'Successfully added!';
            addLog(
              'Success: ${item.courseCode} Sec ${item.sectionName} enrolled',
            );
          } else {
            item.status = TargetSectionStatus.failed;
            final failReason = serverError ?? 'Add request failed';
            item.message = failReason;
            addLog(
              'Failed to add ${item.courseCode} Sec ${item.sectionName}: $failReason',
            );
          }
        } catch (e) {
          if (!targetSections.any((e) => e.sectionId == item.sectionId)) {
            continue;
          }
          item.status = TargetSectionStatus.failed;
          item.message = 'Error: $e';
          addLog('Error adding ${item.courseCode}: $e');
        }
        notifyListeners();
      }
    } finally {
      _isTicking = false;
    }
  }

  @override
  void dispose() {
    _loopTimer?.cancel();
    super.dispose();
  }
}
