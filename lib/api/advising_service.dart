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

bool isMissingAdvisingPhaseResponse(ApiException error) {
  return const <int>{400, 404, 412}.contains(error.statusCode);
}

String advisingErrorMessage(Object error) {
  if (error is TimeoutException) return 'BRACU Connect request timed out';
  final message = '$error';
  if (message.contains('Failed to fetch')) {
    return 'Browser could not reach the BRACU Connect API';
  }
  return message.replaceAll(RegExp(r'https?://\S+'), 'BRACU Connect API');
}

Map<String, dynamic> advisingSectionMutationPayload({
  required String portfolioId,
  required int sectionId,
}) => <String, dynamic>{
  'studentPortfolioId': int.parse(portfolioId),
  'sectionId': sectionId,
};

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

  int get remainingSeats => capacity - consumedSeat;

  factory AdvisingSectionRecord.fromJson(Map<String, dynamic> json) {
    return AdvisingSectionRecord(
      sectionId: _requiredInt(json, 'sectionId'),
      advisingSectionId: _nullableInt(json, 'advisingSectionId'),
      courseId: _nullableInt(json, 'courseId'),
      courseCode: _requiredString(json, 'courseCode'),
      courseName: _nullableString(json, 'name'),
      sectionName: _requiredString(json, 'sectionName'),
      capacity: _requiredInt(json, 'capacity'),
      consumedSeat: _requiredInt(json, 'consumedSeat'),
      courseCredit: _requiredInt(json, 'courseCredit'),
      faculty: _nullableString(json, 'faculties'),
      roomNumber: _nullableString(json, 'roomNumber'),
      labSectionId: _nullableInt(json, 'labSectionId'),
      labSectionName: _nullableString(json, 'labSectionName'),
    );
  }
}

class TargetSectionItem {
  final int sectionId;
  final int courseId;
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
    required this.courseId,
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

  int get remainingSeats => capacity - consumedSeat;
}

int _requiredInt(Map<String, dynamic> json, String key) {
  final value = json[key];
  final parsed = value is num ? value.toInt() : int.tryParse('$value');
  if (parsed == null) throw FormatException('Missing or invalid $key.');
  return parsed;
}

int? _nullableInt(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value == null) return null;
  final parsed = value is num ? value.toInt() : int.tryParse('$value');
  if (parsed == null) throw FormatException('Invalid $key.');
  return parsed;
}

String _requiredString(Map<String, dynamic> json, String key) {
  final value = json[key]?.toString().trim() ?? '';
  if (value.isEmpty) throw FormatException('Missing or invalid $key.');
  return value;
}

String? _nullableString(Map<String, dynamic> json, String key) {
  final value = json[key]?.toString().trim();
  return value == null || value.isEmpty ? null : value;
}

List<AdvisingSectionRecord> parseAdvisedSectionsResponse(String body) {
  final decoded = jsonDecode(body);
  if (decoded is! List) {
    throw const FormatException('Invalid advised sections response.');
  }
  final sections = <int, AdvisingSectionRecord>{};
  for (final item in decoded) {
    if (item is! Map) {
      throw const FormatException('Invalid advised section record.');
    }
    final section = AdvisingSectionRecord.fromJson(
      item.cast<String, dynamic>(),
    );
    sections[section.sectionId] = section;
  }
  return sections.values.toList(growable: false);
}

String? parseActiveAdvisingSessionId(String body, AdvisingPhase phase) {
  final decoded = jsonDecode(body);
  if (decoded is! List) {
    throw const FormatException('Invalid active advising sessions response.');
  }
  String? sessionId;
  for (final item in decoded) {
    if (item is! Map) {
      throw const FormatException('Invalid active advising session record.');
    }
    final json = item.cast<String, dynamic>();
    final responsePhase = _requiredString(json, 'advisingPhase').toUpperCase();
    if (responsePhase != phase.queryValue) continue;
    final id = _requiredString(json, 'id');
    if (sessionId != null && sessionId != id) {
      throw const FormatException('Multiple active advising sessions found.');
    }
    sessionId = id;
  }
  return sessionId;
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
    if (connectJson == null || connectJson.trim().isEmpty) return '';
    final decoded = jsonDecode(connectJson);
    if (decoded is! List) {
      throw const FormatException('Invalid BRACU Connect cookie snapshot.');
    }
    return decoded
        .map((item) {
          if (item is! Map) {
            throw const FormatException('Invalid BRACU Connect cookie entry.');
          }
          final name = '${item['name'] ?? ''}'.trim();
          final value = '${item['value'] ?? ''}'.trim();
          if (name.isEmpty) {
            throw const FormatException(
              'BRACU Connect cookie name is missing.',
            );
          }
          return '$name=$value';
        })
        .join('; ');
  }

  Future<Map<String, String>> buildRequestHeaders({
    String? publicKey,
    required AdvisingPhase phase,
  }) async {
    final cookie = kIsWeb ? '' : await buildCookieHeader();

    return <String, String>{
      'Content-Type': 'application/json',
      'Accept': 'application/json, text/plain, */*',
      'X-REALM': 'bracu',
      'X-SOURCE': '3',
      if (!kIsWeb) 'Origin': ApiConfig.connectOrigin,
      if (!kIsWeb)
        'Referer':
            'https://connect.bracu.ac.bd/student/advising/${phase.pathSegment}',
      if (!kIsWeb)
        'User-Agent':
            'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/134.0.0.0 Safari/537.36',
      if (!kIsWeb && cookie.isNotEmpty) 'Cookie': cookie,
      if (publicKey != null && publicKey.isNotEmpty)
        'X-Advising-Session': publicKey,
    };
  }

  Future<String?> fetchActiveSessionId(
    String studentId, {
    required AdvisingPhase phase,
  }) async {
    final url =
        '${ApiConfig.connectApiBase}${ApiConfig.advisingPath(studentId)}'
        '?advisingPhase=${phase.queryValue}';
    final response = await _client.authenticatedGet(
      url,
      additionalHeaders: await buildRequestHeaders(phase: phase),
      bypassCache: true,
    );
    return parseActiveAdvisingSessionId(response.body, phase);
  }

  Future<List<AdvisingSectionRecord>> fetchAdvisedSections(
    String portfolioId, {
    required AdvisingPhase phase,
    required String publicKey,
  }) async {
    final url =
        '${ApiConfig.connectApiBase}${ApiConfig.studentCoursesForPhasePath(portfolioId, phase)}';
    final headers = await buildRequestHeaders(
      publicKey: publicKey,
      phase: phase,
    );

    final res = await _client.authenticatedGet(
      url,
      additionalHeaders: headers,
      bypassCache: true,
    );

    if (res.statusCode == 200) {
      return parseAdvisedSectionsResponse(res.body);
    }
    throw ApiException(res.statusCode, res.body);
  }

  Future<Map<int, SeatStatusDetailsResponse>> fetchRealtimeSections() {
    return SeatStatusService().fetchRealtimeSections();
  }

  Future<void> addSection({
    required String portfolioId,
    required int sectionId,
    required String publicKey,
    required AdvisingPhase phase,
  }) async {
    final headers = await buildRequestHeaders(
      publicKey: publicKey,
      phase: phase,
    );

    final payload = advisingSectionMutationPayload(
      portfolioId: portfolioId,
      sectionId: sectionId,
    );

    final url =
        '${ApiConfig.connectApiBase}${ApiConfig.advisingStudentCoursesPath(phase)}';

    await _client.authenticatedRequest(
      'POST',
      url,
      body: jsonEncode(payload),
      additionalHeaders: headers,
      acceptedStatusCodes: const <int>{200, 201},
    );
  }

  Future<void> dropSection({
    required String portfolioId,
    required int sectionId,
    required String publicKey,
    required AdvisingPhase phase,
  }) async {
    final headers = await buildRequestHeaders(
      publicKey: publicKey,
      phase: phase,
    );

    final payload = advisingSectionMutationPayload(
      portfolioId: portfolioId,
      sectionId: sectionId,
    );

    final url =
        '${ApiConfig.connectApiBase}${ApiConfig.advisingStudentCoursesPath(phase)}';

    await _client.authenticatedRequest(
      'DELETE',
      url,
      body: jsonEncode(payload),
      additionalHeaders: headers,
      acceptedStatusCodes: const <int>{200, 204},
    );
  }

  Future<void> confirmAdvising({
    required String portfolioId,
    required String sessionId,
    required String publicKey,
    required AdvisingPhase phase,
  }) async {
    final headers = await buildRequestHeaders(
      publicKey: publicKey,
      phase: phase,
    );

    final payload = jsonEncode(<String, dynamic>{
      'studentPortfolioId': int.parse(portfolioId),
      'sessionId': sessionId,
    });

    final url =
        '${ApiConfig.connectApiBase}${ApiConfig.advisingConfirmPath(sessionId)}';

    await _client.authenticatedRequest(
      'POST',
      url,
      body: payload,
      additionalHeaders: headers,
      acceptedStatusCodes: const <int>{200},
    );
  }
}

class AdvisingAutoEngine extends ChangeNotifier {
  final List<TargetSectionItem> targetSections = <TargetSectionItem>[];
  final List<String> activityLogs = <String>[];

  bool isRunning = false;
  bool _isTicking = false;
  String? _lastOfferedSectionsError;
  int _runGeneration = 0;
  Timer? _loopTimer;
  String? portfolioId;
  String? publicKey;
  Future<void> Function()? onSectionAdded;
  late AdvisingPhase phase;

  bool get hasCompletedQueue =>
      targetSections.isNotEmpty &&
      targetSections.every((item) => item.status == TargetSectionStatus.added);

  bool clearCompletedQueue() {
    if (!hasCompletedQueue) return false;
    if (isRunning) stop();
    targetSections.clear();
    notifyListeners();
    return true;
  }

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
  }

  void removeSectionFromQueue(int sectionId) {
    final index = targetSections.indexWhere((e) => e.sectionId == sectionId);
    if (index != -1) {
      final item = targetSections.removeAt(index);
      addLog('Removed: ${item.courseCode} Section ${item.sectionName}');
    }
  }

  void clearQueue() {
    targetSections.clear();
    addLog('Queue cleared');
    notifyListeners();
  }

  void clearActivityLogs() {
    activityLogs.clear();
    notifyListeners();
  }

  void reset() {
    _runGeneration++;
    isRunning = false;
    _loopTimer?.cancel();
    _loopTimer = null;
    _lastOfferedSectionsError = null;
    portfolioId = null;
    publicKey = null;
    onSectionAdded = null;
    targetSections.clear();
    activityLogs.clear();
    notifyListeners();
  }

  void start({
    required String portfolioId,
    required String publicKey,
    required AdvisingPhase phase,
    Future<void> Function()? onSectionAdded,
  }) {
    if (isRunning) return;
    _runGeneration++;
    this.portfolioId = portfolioId;
    this.publicKey = publicKey;
    this.phase = phase;
    this.onSectionAdded = onSectionAdded;
    _lastOfferedSectionsError = null;
    isRunning = true;
    addLog('Advising Helper started');

    _loopTimer?.cancel();
    _loopTimer = Timer.periodic(const Duration(milliseconds: 1000), (_) {
      unawaited(_tick());
    });
    unawaited(_tick());
  }

  void stop() {
    if (!isRunning) return;
    _runGeneration++;
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
  }

  Future<void> _tick() async {
    if (!isRunning || _isTicking || portfolioId == null || publicKey == null) {
      return;
    }
    _isTicking = true;
    final runGeneration = _runGeneration;

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
        detailsMap = await AdvisingHelperService().fetchRealtimeSections();
      } catch (error) {
        if (!isRunning || runGeneration != _runGeneration) return;
        final message = advisingErrorMessage(error);
        for (final item in pending) {
          item.status = TargetSectionStatus.failed;
          item.message = message;
        }
        if (_lastOfferedSectionsError != message) {
          _lastOfferedSectionsError = message;
          addLog('Failed to refresh realtime Connect sections: $message');
        } else {
          notifyListeners();
        }
        return;
      }
      if (!isRunning || runGeneration != _runGeneration) return;
      _lastOfferedSectionsError = null;

      for (final item in pending) {
        if (!isRunning ||
            !targetSections.any((e) => e.sectionId == item.sectionId)) {
          continue;
        }

        final detail = detailsMap[item.sectionId];
        if (detail == null) {
          item.status = TargetSectionStatus.failed;
          item.message = 'Section is not present in the realtime Connect data';
          notifyListeners();
          continue;
        }
        final currentCap = detail.capacity;
        final currentConsumed = detail.consumedSeat;
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

        try {
          await AdvisingHelperService().addSection(
            portfolioId: portfolioId!,
            sectionId: item.sectionId,
            publicKey: publicKey!,
            phase: phase,
          );

          if (!targetSections.any((e) => e.sectionId == item.sectionId)) {
            continue;
          }

          item.status = TargetSectionStatus.added;
          item.message = 'Successfully added!';
          addLog(
            'Success: ${item.courseCode} Sec ${item.sectionName} enrolled',
          );
          final refreshEnrolled = onSectionAdded;
          if (refreshEnrolled != null) {
            try {
              await refreshEnrolled();
            } catch (error) {
              addLog('Enrolled list refresh failed: $error');
            }
          }
        } catch (e) {
          if (!targetSections.any((e) => e.sectionId == item.sectionId)) {
            continue;
          }
          item.status = TargetSectionStatus.failed;
          final message = advisingErrorMessage(e);
          item.message = 'Error: $message';
          addLog('Error adding ${item.courseCode}: $message');
        }
        notifyListeners();
      }
      clearCompletedQueue();
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
