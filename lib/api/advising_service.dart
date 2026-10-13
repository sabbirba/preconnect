import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:preconnect/api/api_client.dart';
import 'package:preconnect/api/api_config.dart';
import 'package:preconnect/api/seat_status.dart';
import 'package:preconnect/model/advising_phase.dart';
import 'package:preconnect/tools/advising_background.dart';
import 'package:preconnect/tools/app_storage.dart';
import 'package:preconnect/tools/storage_keys.dart';

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
  if (error is TimeoutException) return 'Connect request timed out';
  final message = '$error';
  if (message.contains('Failed to fetch') ||
      message.contains('ClientException') ||
      message.contains('SocketException') ||
      message.contains('Failed host lookup') ||
      message.contains('Connection refused') ||
      message.contains('Connection timed out')) {
    return 'Could not reach the Connect API';
  }
  return message.replaceAll(RegExp(r'https?://\S+'), 'Connect API');
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
      sectionId: _nullableInt(json, 'sectionId') ?? _requiredInt(json, 'id'),
      advisingSectionId: _nullableInt(json, 'advisingSectionId'),
      courseId: _nullableInt(json, 'courseId'),
      courseCode:
          _nullableString(json, 'courseCode') ?? _requiredString(json, 'code'),
      courseName:
          _nullableString(json, 'name') ?? _nullableString(json, 'courseName'),
      sectionName:
          _nullableString(json, 'sectionName') ??
          _requiredString(json, 'section'),
      capacity: _nullableInt(json, 'capacity') ?? 0,
      consumedSeat: _nullableInt(json, 'consumedSeat') ?? 0,
      courseCredit: _nullableInt(json, 'courseCredit') ?? 0,
      faculty: () {
        final v = json['faculties'] ?? json['faculty'];
        if (v is Map) {
          final m = v.cast<String, dynamic>();
          final s = '${m['shortName'] ?? ''}'.trim();
          if (s.isNotEmpty) return s;
          final n = '${m['staffName'] ?? m['name'] ?? ''}'.trim();
          return n.isEmpty ? null : n;
        }
        final s = v?.toString().trim();
        return (s == null || s.isEmpty) ? null : s;
      }(),
      roomNumber:
          _nullableString(json, 'roomNumber') ??
          _nullableString(json, 'roomName'),
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
  final AdvisingReplacementSource? replacement;
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
    this.replacement,
    this.status = TargetSectionStatus.idle,
    this.lastAttempt,
    this.message,
  });

  int get remainingSeats => capacity - consumedSeat;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'sectionId': sectionId,
    'courseId': courseId,
    'courseCode': courseCode,
    if (courseName != null) 'courseName': courseName,
    'sectionName': sectionName,
    'capacity': capacity,
    'consumedSeat': consumedSeat,
    'courseCredit': courseCredit,
    if (labSectionId != null) 'labSectionId': labSectionId,
    if (labSectionName != null) 'labSectionName': labSectionName,
    if (replacement != null) 'replacement': replacement!.toJson(),
  };

  factory TargetSectionItem.fromJson(Map<String, dynamic> json) {
    final rep = json['replacement'];
    final repMap = rep is Map ? rep.cast<String, dynamic>() : null;
    return TargetSectionItem(
      sectionId: _requiredInt(json, 'sectionId'),
      courseId: _requiredInt(json, 'courseId'),
      courseCode: _requiredString(json, 'courseCode'),
      courseName: _nullableString(json, 'courseName'),
      sectionName: _requiredString(json, 'sectionName'),
      capacity: _nullableInt(json, 'capacity') ?? 0,
      consumedSeat: _nullableInt(json, 'consumedSeat') ?? 0,
      courseCredit: _nullableInt(json, 'courseCredit') ?? 0,
      labSectionId: _nullableInt(json, 'labSectionId'),
      labSectionName: _nullableString(json, 'labSectionName'),
      replacement: repMap != null
          ? AdvisingReplacementSource.fromJson(repMap)
          : null,
    );
  }
}

class AdvisingReplacementSource {
  const AdvisingReplacementSource({
    required this.sectionId,
    required this.courseCode,
    required this.sectionName,
  });

  final int sectionId;
  final String courseCode;
  final String sectionName;

  String get groupKey => 'replace:$sectionId';

  Map<String, dynamic> toJson() => <String, dynamic>{
    'sectionId': sectionId,
    'courseCode': courseCode,
    'sectionName': sectionName,
  };

  factory AdvisingReplacementSource.fromJson(Map<String, dynamic> json) {
    return AdvisingReplacementSource(
      sectionId: _requiredInt(json, 'sectionId'),
      courseCode: _requiredString(json, 'courseCode'),
      sectionName: _requiredString(json, 'sectionName'),
    );
  }
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
  final list = switch (decoded) {
    final List<dynamic> value => value,
    final Map<dynamic, dynamic> value when value['sections'] is List =>
      value['sections'] as List<dynamic>,
    final Map<dynamic, dynamic> value when value['courses'] is List =>
      value['courses'] as List<dynamic>,
    final Map<dynamic, dynamic> value when value['data'] is List =>
      value['data'] as List<dynamic>,
    _ => throw const FormatException('Invalid advised sections response.'),
  };
  final sections = <int, AdvisingSectionRecord>{};
  for (final item in list) {
    if (item is! Map) continue;
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
  for (final item in decoded) {
    if (item is! Map) {
      throw const FormatException('Invalid active advising session record.');
    }
    final json = item.cast<String, dynamic>();
    final responsePhase = _requiredString(json, 'advisingPhase').toUpperCase();
    if (responsePhase != phase.queryValue) continue;
    final id = _requiredString(json, 'id');
    return id;
  }
  return null;
}

class AdvisingHelperService {
  static final AdvisingHelperService _instance =
      AdvisingHelperService._internal();
  factory AdvisingHelperService() => _instance;
  AdvisingHelperService._internal();

  final ApiClient _client = ApiClient();

  Future<Map<String, String>> buildRequestHeaders({
    String? publicKey,
    required AdvisingPhase phase,
  }) async {
    return <String, String>{
      'Content-Type': 'application/json',
      'Accept': 'application/json, text/plain, */*',
      'x-realm': 'bracu',
      'x-source': '3',
      if (publicKey != null && publicKey.isNotEmpty)
        'x-advising-session': publicKey,
    };
  }

  Future<String?> fetchActiveSessionId(
    String studentId, {
    required AdvisingPhase phase,
  }) async {
    if (phase == AdvisingPhase.selfRegistration) {
      final sessionKey = DateTime.now().millisecondsSinceEpoch.toString();
      final url =
          '${ApiConfig.connectApiBase}${ApiConfig.selfRegistrationSessionPath(studentId, sessionKey)}';
      try {
        final res = await _client.authenticatedRequest(
          'POST',
          url,
          body: '',
          additionalHeaders: const <String, String>{
            'Content-Type': 'text/plain',
            'x-realm': 'bracu',
            'x-source': '3',
          },
          acceptedStatusCodes: const <int>{200, 201},
        );
        if (res.statusCode == 200 || res.statusCode == 201) {
          return sessionKey;
        }
      } catch (_) {}
      return null;
    }

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

  Future<Map<int, SeatStatusDetailsResponse>> fetchRealtimeSections({
    String? portfolioId,
    AdvisingPhase? phase,
    String? publicKey,
  }) async {
    if (portfolioId != null && phase != null) {
      try {
        final url =
            '${ApiConfig.connectApiBase}${ApiConfig.advisingSectionsPath(portfolioId, phase: phase)}';
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
          final decoded = jsonDecode(res.body);
          final list = switch (decoded) {
            final List<dynamic> value => value,
            final Map<dynamic, dynamic> value when value['sections'] is List =>
              value['sections'] as List<dynamic>,
            final Map<dynamic, dynamic> value when value['data'] is List =>
              value['data'] as List<dynamic>,
            _ => null,
          };
          if (list != null) {
            final result = <int, SeatStatusDetailsResponse>{};
            for (final item in list.whereType<Map>()) {
              try {
                final parsed = SeatStatusDetailsResponse.fromJson(
                  item.cast<String, dynamic>(),
                );
                result[parsed.sectionId] = parsed;
              } catch (_) {}
            }
            if (result.isNotEmpty) return result;
          }
        }
      } catch (_) {}
    }
    return SeatStatusService().preloadData(forceRefresh: false);
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
    required String publicKey,
    required AdvisingPhase phase,
  }) async {
    final headers = await buildRequestHeaders(
      publicKey: publicKey,
      phase: phase,
    );
    headers['Content-Type'] = 'text/plain';

    final url =
        '${ApiConfig.connectApiBase}${ApiConfig.advisingConfirmPath(portfolioId)}';

    await _client.authenticatedRequest(
      'POST',
      url,
      body: '',
      additionalHeaders: headers,
      acceptedStatusCodes: const <int>{200, 201, 204},
    );
  }
}

class AdvisingAutoEngine extends ChangeNotifier {
  static final AdvisingAutoEngine _instance = AdvisingAutoEngine._internal();
  factory AdvisingAutoEngine() => _instance;
  AdvisingAutoEngine._internal();

  static AdvisingAutoEngine get instance => _instance;

  final AdvisingHelperService _service = AdvisingHelperService();
  final List<TargetSectionItem> targetSections = <TargetSectionItem>[];
  final List<String> activityLogs = <String>[];
  List<AdvisingSectionRecord> enrolledSections = <AdvisingSectionRecord>[];

  bool isRunning = false;
  bool _isTicking = false;
  String? _lastOfferedSectionsError;
  Map<int, SeatStatusDetailsResponse>? _lastKnownDetails;
  int _runGeneration = 0;
  Timer? _loopTimer;
  String? portfolioId;
  String? publicKey;
  Future<void> Function()? onSectionAdded;
  VoidCallback? onReplacementCompleted;
  late AdvisingPhase phase;

  bool get hasCompletedQueue =>
      targetSections.isNotEmpty &&
      targetSections.every((item) => item.status == TargetSectionStatus.added);

  bool clearCompletedQueue() {
    if (!hasCompletedQueue) return false;
    if (isRunning) stop();
    unawaited(saveQueueToStorage());
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

  Future<void> saveQueueToStorage([AdvisingPhase? targetPhase]) async {
    final p = targetPhase ?? (tryPhase);
    if (p == null) return;
    try {
      final key = StorageKeys.advisingTargetSections(p.name);
      final jsonList = targetSections.map((e) => e.toJson()).toList();
      await AppStorage.instance.setString(key, jsonEncode(jsonList));
    } catch (_) {}
  }

  Future<void> loadQueueFromStorage(AdvisingPhase targetPhase) async {
    if (isRunning) return;
    try {
      phase = targetPhase;
      final key = StorageKeys.advisingTargetSections(targetPhase.name);
      final raw = await AppStorage.instance.getString(key);
      if (raw == null || raw.trim().isEmpty) return;
      final decoded = jsonDecode(raw);
      if (decoded is! List) return;
      targetSections.clear();
      for (final entry in decoded) {
        if (entry is Map<String, dynamic>) {
          targetSections.add(TargetSectionItem.fromJson(entry));
        } else if (entry is Map) {
          targetSections.add(
            TargetSectionItem.fromJson(entry.cast<String, dynamic>()),
          );
        }
      }
      notifyListeners();
    } catch (_) {}
  }

  AdvisingPhase? get tryPhase {
    try {
      return phase;
    } catch (_) {
      return null;
    }
  }

  void addSectionToQueue(TargetSectionItem item) {
    if (targetSections.any((e) => e.sectionId == item.sectionId)) return;
    targetSections.add(item);
    final replacement = item.replacement;
    if (replacement == null) {
      addLog('Queued: ${item.courseCode} Section ${item.sectionName}');
    } else {
      addLog(
        'Queued replacement priority ${_replacementPriority(item)}: '
        '${replacement.courseCode} Sec ${replacement.sectionName} → '
        '${item.courseCode} Sec ${item.sectionName}',
      );
    }
    unawaited(saveQueueToStorage());
  }

  int _replacementPriority(TargetSectionItem item) {
    final groupKey = item.replacement?.groupKey;
    if (groupKey == null) return 0;
    return targetSections
            .where((entry) => entry.replacement?.groupKey == groupKey)
            .toList()
            .indexOf(item) +
        1;
  }

  void moveSectionPriority(int sectionId, int offset) {
    final index = targetSections.indexWhere((e) => e.sectionId == sectionId);
    if (index == -1) return;
    final item = targetSections[index];
    final groupKey = item.replacement?.groupKey;
    if (groupKey == null) return;
    final group = targetSections
        .where((entry) => entry.replacement?.groupKey == groupKey)
        .toList();
    final groupIndex = group.indexOf(item);
    final nextGroupIndex = groupIndex + offset;
    if (nextGroupIndex < 0 || nextGroupIndex >= group.length) return;
    final other = group[nextGroupIndex];
    final otherIndex = targetSections.indexOf(other);
    targetSections[index] = other;
    targetSections[otherIndex] = item;
    addLog(
      '${item.courseCode} Sec ${item.sectionName} moved to replacement '
      'priority ${nextGroupIndex + 1}',
    );
    unawaited(saveQueueToStorage());
  }

  void removeSectionFromQueue(int sectionId) {
    final index = targetSections.indexWhere((e) => e.sectionId == sectionId);
    if (index != -1) {
      final item = targetSections.removeAt(index);
      addLog('Removed: ${item.courseCode} Section ${item.sectionName}');
      unawaited(saveQueueToStorage());
    }
  }

  void clearQueue() {
    targetSections.clear();
    addLog('Queue cleared');
    unawaited(saveQueueToStorage());
    notifyListeners();
  }

  void clearActivityLogs() {
    activityLogs.clear();
    notifyListeners();
  }

  void reset({bool keepQueue = false}) {
    _runGeneration++;
    isRunning = false;
    _loopTimer?.cancel();
    _loopTimer = null;
    _lastOfferedSectionsError = null;
    _lastKnownDetails = null;
    portfolioId = null;
    publicKey = null;
    onSectionAdded = null;
    onReplacementCompleted = null;
    if (keepQueue) {
      for (final item in targetSections) {
        if (item.status == TargetSectionStatus.watching ||
            item.status == TargetSectionStatus.adding) {
          item.status = TargetSectionStatus.idle;
        }
      }
    } else {
      targetSections.clear();
      unawaited(saveQueueToStorage());
    }
    activityLogs.clear();
    unawaited(AdvisingBackground.stop());
    unawaited(AdvisingBackground.setKeepAwake(false));
    notifyListeners();
  }

  void start({
    required String portfolioId,
    required String publicKey,
    required AdvisingPhase phase,
    Future<void> Function()? onSectionAdded,
    VoidCallback? onReplacementCompleted,
  }) {
    if (isRunning) return;
    _runGeneration++;
    this.portfolioId = portfolioId;
    this.publicKey = publicKey;
    this.phase = phase;
    this.onSectionAdded = onSectionAdded;
    this.onReplacementCompleted = onReplacementCompleted;
    _lastOfferedSectionsError = null;
    isRunning = true;
    addLog('Advising Helper started');
    unawaited(
      AdvisingBackground.start(
        title: 'Advising Helper Active',
        message: 'Monitoring ${targetSections.length} target section(s)',
      ),
    );
    unawaited(AdvisingBackground.setKeepAwake(true));
    unawaited(AdvisingBackground.requestBatteryOptimizationExemptionIfNeeded());

    _loopTimer?.cancel();
    _loopTimer = Timer.periodic(const Duration(milliseconds: 250), (_) {
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
    unawaited(AdvisingBackground.stop());
    unawaited(AdvisingBackground.setKeepAwake(false));
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
        detailsMap = await _service.fetchRealtimeSections(
          portfolioId: portfolioId,
          phase: phase,
          publicKey: publicKey,
        );
        _lastKnownDetails = detailsMap;
      } catch (error) {
        if (!isRunning || runGeneration != _runGeneration) return;
        final message = advisingErrorMessage(error);
        if (_lastOfferedSectionsError != message) {
          _lastOfferedSectionsError = message;
          addLog('Realtime Connect refresh warning: $message');
        }
        detailsMap = _lastKnownDetails;
        if (detailsMap == null) {
          for (final item in pending) {
            item.status = TargetSectionStatus.watching;
            item.message = message;
          }
          notifyListeners();
          return;
        }
      }
      if (!isRunning || runGeneration != _runGeneration) return;
      _lastOfferedSectionsError = null;

      final handledReplacementGroups = <String>{};
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

        final replacementGroup = item.replacement?.groupKey;
        if (replacementGroup != null &&
            !handledReplacementGroups.add(replacementGroup)) {
          continue;
        }

        TargetSectionItem candidate = item;
        if (replacementGroup != null) {
          final alternatives = pending
              .where((entry) => entry.replacement?.groupKey == replacementGroup)
              .toList();
          final available = alternatives.where((entry) {
            final current = detailsMap![entry.sectionId];
            return current != null &&
                current.capacity - current.consumedSeat > 0;
          });
          if (available.isNotEmpty) candidate = available.first;
        }

        if (candidate.sectionId != item.sectionId) {
          await _attemptSection(candidate, detailsMap, runGeneration);
          continue;
        }

        if (remaining <= 0) {
          item.status = TargetSectionStatus.skippedZeroSeats;
          item.message = null;
          notifyListeners();
          continue;
        }

        await _attemptSection(item, detailsMap, runGeneration);
      }
    } finally {
      _isTicking = false;
    }
  }

  Future<void> _attemptSection(
    TargetSectionItem item,
    Map<int, SeatStatusDetailsResponse> detailsMap,
    int runGeneration,
  ) async {
    final detail = detailsMap[item.sectionId];
    if (detail == null) return;
    final remaining = detail.capacity - detail.consumedSeat;
    if (remaining <= 0) return;

    item.status = TargetSectionStatus.adding;
    item.lastAttempt = DateTime.now();
    item.message =
        '$remaining seat${remaining == 1 ? '' : 's'} available! Adding...';
    addLog(
      'Seat opened: ${item.courseCode} Sec ${item.sectionName} ($remaining seats). Attempting add...',
    );
    notifyListeners();

    try {
      var replacement = item.replacement;
      if (replacement == null) {
        if (enrolledSections.isEmpty &&
            portfolioId != null &&
            publicKey != null) {
          try {
            enrolledSections = await _service.fetchAdvisedSections(
              portfolioId!,
              phase: phase,
              publicKey: publicKey!,
            );
          } catch (_) {}
        }
        final existing = enrolledSections
            .cast<AdvisingSectionRecord?>()
            .firstWhere(
              (entry) =>
                  entry != null &&
                  entry.sectionId != item.sectionId &&
                  entry.courseCode.trim().toUpperCase() ==
                      item.courseCode.trim().toUpperCase(),
              orElse: () => null,
            );
        if (existing != null) {
          replacement = AdvisingReplacementSource(
            sectionId: existing.sectionId,
            courseCode: existing.courseCode,
            sectionName: existing.sectionName,
          );
        }
      }

      var sourceWasDropped = false;
      if (replacement != null && replacement.sectionId > 0) {
        addLog(
          'Dropping ${replacement.courseCode} Sec '
          '${replacement.sectionName} for replacement',
        );
        try {
          await _service.dropSection(
            portfolioId: portfolioId!,
            sectionId: replacement.sectionId,
            publicKey: publicKey!,
            phase: phase,
          );
          sourceWasDropped = true;
        } catch (_) {}
      }

      var addSucceeded = false;
      Object? lastAddError;
      for (var addAttempt = 1; addAttempt <= 3; addAttempt++) {
        try {
          await _service.addSection(
            portfolioId: portfolioId!,
            sectionId: item.sectionId,
            publicKey: publicKey!,
            phase: phase,
          );
          addSucceeded = true;
          break;
        } catch (error) {
          lastAddError = error;
          if (await _waitForEnrollment(item.sectionId)) {
            addSucceeded = true;
            break;
          }
          if (addAttempt < 3) {
            await Future<void>.delayed(const Duration(milliseconds: 30));
          }
        }
      }

      if (!addSucceeded) {
        if (sourceWasDropped &&
            replacement != null &&
            replacement.sectionId > 0) {
          await _restoreReplacementSource(replacement);
        }
        if (lastAddError != null) {
          throw lastAddError;
        }
        throw StateError('Connect did not confirm the new enrollment');
      }

      if (!targetSections.any((e) => e.sectionId == item.sectionId)) {
        return;
      }

      await _recordSuccess(item, replacement: replacement);
      await _refreshEnrolledAfterMutation();
    } catch (e) {
      if (!targetSections.any((e) => e.sectionId == item.sectionId)) {
        return;
      }
      item.status = TargetSectionStatus.failed;
      final message = advisingErrorMessage(e);
      item.message = 'Error: $message';
      addLog('Error adding ${item.courseCode}: $message');
    }
    notifyListeners();
    clearCompletedQueue();
  }

  Future<bool> _waitForEnrollment(int sectionId) async {
    for (var attempt = 0; attempt < 3; attempt++) {
      final enrolled = await _service.fetchAdvisedSections(
        portfolioId!,
        phase: phase,
        publicKey: publicKey!,
      );
      if (enrolled.any((entry) => entry.sectionId == sectionId)) return true;
      if (attempt < 2) {
        await Future<void>.delayed(const Duration(milliseconds: 40));
      }
    }
    return false;
  }

  Future<void> _recordSuccess(
    TargetSectionItem item, {
    AdvisingReplacementSource? replacement,
  }) async {
    final rep = item.replacement ?? replacement;
    if (rep == null) {
      item.status = TargetSectionStatus.added;
      item.message = 'Successfully added!';
      addLog('Success: ${item.courseCode} Sec ${item.sectionName} enrolled');
    } else {
      await _completeReplacement(item, rep);
    }
  }

  Future<void> _refreshEnrolledAfterMutation() async {
    final refreshEnrolled = onSectionAdded;
    if (refreshEnrolled == null) return;
    try {
      await refreshEnrolled();
    } catch (error) {
      addLog('Enrolled list refresh failed: $error');
    }
  }

  Future<void> _completeReplacement(
    TargetSectionItem item, [
    AdvisingReplacementSource? replacement,
  ]) async {
    final rep = replacement ?? item.replacement!;
    addLog(
      'Success: ${rep.courseCode} Sec ${rep.sectionName} '
      'replaced with ${item.courseCode} Sec ${item.sectionName}',
    );
    targetSections.removeWhere(
      (entry) =>
          entry.sectionId == item.sectionId ||
          entry.replacement?.groupKey == rep.groupKey,
    );
    unawaited(saveQueueToStorage());
    onReplacementCompleted?.call();
    if (targetSections.isEmpty) stop();
    notifyListeners();
  }

  Future<void> _restoreReplacementSource(
    AdvisingReplacementSource replacement,
  ) async {
    addLog(
      'Add failed; aggressively restoring ${replacement.courseCode} '
      'Sec ${replacement.sectionName}',
    );
    for (var attempt = 1; attempt <= 5; attempt++) {
      try {
        await _service.addSection(
          portfolioId: portfolioId!,
          sectionId: replacement.sectionId,
          publicKey: publicKey!,
          phase: phase,
        );
        addLog(
          'Restored ${replacement.courseCode} Sec ${replacement.sectionName}',
        );
        return;
      } catch (error) {
        if (attempt == 5) {
          addLog(
            'URGENT: Could not restore ${replacement.courseCode} Sec '
            '${replacement.sectionName}: ${advisingErrorMessage(error)}',
          );
          return;
        }
      }
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
  }

  @override
  void dispose() {
    _loopTimer?.cancel();
    super.dispose();
  }
}
