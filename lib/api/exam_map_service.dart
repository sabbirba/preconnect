import 'dart:convert';

import 'package:preconnect/api/api_client.dart';
import 'package:preconnect/api/api_config.dart';
import 'package:preconnect/api/app_preferences_store.dart';
import 'package:preconnect/model/section_info.dart';

class ExamMapService {
  ExamMapService._internal();
  static final ExamMapService _instance = ExamMapService._internal();
  factory ExamMapService() => _instance;

  final ApiClient _client = ApiClient();
  final AppPreferencesStore _store = AppPreferencesStore();

  static const Duration _indexCacheTtl = Duration(hours: 6);
  static const Duration _examJsonCacheTtl = Duration(hours: 12);
  static const String _indexCacheKey = 'exammap_index_v4';

  static String sectionKeyForSection(Section section) {
    return sectionKey(
      courseCode: section.courseCode,
      sectionName: section.sectionName,
    );
  }

  static String sectionKey({
    required String courseCode,
    required String sectionName,
  }) {
    final course = courseCode.trim().toUpperCase();
    final section = _normalizeSection(sectionName);
    if (course.isEmpty || section.isEmpty) return '';
    return '$course|$section';
  }

  Future<Map<String, ExamScheduleOverride>> getOverridesForSemester({
    required int semesterSessionId,
    bool forceRefresh = false,
  }) async {
    final semesterLabel = _semesterLabelFromSessionId(semesterSessionId);
    if (semesterLabel.isEmpty) return const <String, ExamScheduleOverride>{};

    final indexJson = await _fetchJsonWithCache(
      url: ApiConfig.examMapIndexUrl,
      cacheKey: _indexCacheKey,
      ttl: _indexCacheTtl,
      forceRefresh: forceRefresh,
    );

    final indexList = indexJson is List ? indexJson : const <dynamic>[];
    final midUrl = _pickExamJsonUrl(
      indexList,
      examType: 'Mid',
      semesterLabel: semesterLabel,
    );
    final finalUrl = _pickExamJsonUrl(
      indexList,
      examType: 'Final',
      semesterLabel: semesterLabel,
    );

    final merged = <String, ExamScheduleOverride>{};

    if (midUrl != null) {
      final midJson = await _fetchJsonWithCache(
        url: midUrl,
        cacheKey: 'exammap_mid_${semesterSessionId}_v3',
        ttl: _examJsonCacheTtl,
        forceRefresh: forceRefresh,
      );
      _mergeExamRows(merged, midJson, examTypeHint: 'Mid');
    }

    if (finalUrl != null) {
      final finalJson = await _fetchJsonWithCache(
        url: finalUrl,
        cacheKey: 'exammap_final_${semesterSessionId}_v3',
        ttl: _examJsonCacheTtl,
        forceRefresh: forceRefresh,
      );
      _mergeExamRows(merged, finalJson, examTypeHint: 'Final');
    }

    return merged;
  }

  Future<dynamic> _fetchJsonWithCache({
    required String url,
    required String cacheKey,
    required Duration ttl,
    required bool forceRefresh,
  }) async {
    if (!forceRefresh) {
      final cached = await _store.getJsonMap(cacheKey);
      final ts = cached?['ts'];
      final data = cached?['data'];
      if (ts is int && data != null) {
        final age = DateTime.now().difference(
          DateTime.fromMillisecondsSinceEpoch(ts),
        );
        if (age <= ttl) {
          if (!(data is List && data.isEmpty && cacheKey == _indexCacheKey)) {
            return data;
          }
        }
      }
    }

    try {
      final response = await _client.publicGet(url);
      final decoded = jsonDecode(response.body);
      await _store.setJson(cacheKey, <String, dynamic>{
        'ts': DateTime.now().millisecondsSinceEpoch,
        'data': decoded,
      });
      return decoded;
    } catch (e) {
      final cached = await _store.getJsonMap(cacheKey);
      return cached?['data'];
    }
  }

  void _mergeExamRows(
    Map<String, ExamScheduleOverride> out,
    dynamic payload, {
    required String examTypeHint,
  }) {
    final root = payload is Map<String, dynamic>
        ? payload
        : payload is Map
        ? payload.cast<String, dynamic>()
        : null;
    if (root == null) return;

    final metadata = root['metadata'];
    final metaType = metadata is Map<String, dynamic>
        ? _clean(metadata['exam_type'])
        : null;
    final examType = ((metaType ?? examTypeHint).trim().toUpperCase());

    final rows = root['exams'] ?? root['rows'] ?? root['data'] ?? root['items'];
    final rowList = rows is List
        ? rows
        : rows is Map
        ? rows.values.toList()
        : null;
    if (rowList == null) return;

    for (final raw in rowList.whereType<Map>()) {
      final row = raw.cast<String, dynamic>();
      final course = _firstString(row, const <String>[
        'Course',
        'course',
        'Course Code',
        'courseCode',
        'course_code',
      ]).toUpperCase();
      final section = _normalizeSection(
        _firstString(row, const <String>[
          'Section',
          'section',
          'Section Number',
          'sectionNumber',
          'section_number',
        ]),
      );
      if (course.isEmpty || section.isEmpty) continue;
      final key = '$course|$section';

      final date = examType == 'MID'
          ? _firstString(row, const <String>['Mid Date', 'midDate', 'mid_date'])
          : _firstString(row, const <String>[
              'Final Date',
              'finalDate',
              'final_date',
            ]);
      final start = _firstString(row, const <String>[
        'Start Time',
        'startTime',
        'start_time',
      ]);
      final end = _firstString(row, const <String>[
        'End Time',
        'endTime',
        'end_time',
      ]);
      final room = _firstString(row, const <String>[
        'Room.',
        'Room',
        'room',
        'roomNumber',
        'room_number',
      ]);

      final existing = out[key] ?? const ExamScheduleOverride();

      if (examType == 'MID') {
        out[key] = existing.copyWith(
          midDate: date.isEmpty ? existing.midDate : date,
          midStartTime: start.isEmpty ? existing.midStartTime : start,
          midEndTime: end.isEmpty ? existing.midEndTime : end,
          midRoomNumber: room.isEmpty ? existing.midRoomNumber : room,
        );
      } else {
        out[key] = existing.copyWith(
          finalDate: date.isEmpty ? existing.finalDate : date,
          finalStartTime: start.isEmpty ? existing.finalStartTime : start,
          finalEndTime: end.isEmpty ? existing.finalEndTime : end,
          finalRoomNumber: room.isEmpty ? existing.finalRoomNumber : room,
        );
      }
    }
  }

  String _semesterLabelFromSessionId(int sessionId) {
    final year = sessionId ~/ 10;
    final code = sessionId % 10;
    final term = switch (code) {
      1 => 'Spring',
      2 => 'Summer',
      3 => 'Fall',
      _ => '',
    };
    if (term.isEmpty) return '';
    return '$term $year';
  }

  String? _pickExamJsonUrl(
    List<dynamic> indexRows, {
    required String examType,
    required String semesterLabel,
  }) {
    final wanted = '$examType $semesterLabel'.toLowerCase();

    for (final item in indexRows.whereType<Map>()) {
      final row = item.cast<String, dynamic>();
      final name = _clean(row['exam_name']).toLowerCase();
      final url = _clean(row['url']);
      if (name == wanted && url.isNotEmpty) return url;
    }

    for (final item in indexRows.whereType<Map>()) {
      final row = item.cast<String, dynamic>();
      final name = _clean(row['exam_name']).toLowerCase();
      final url = _clean(row['url']);
      if (url.isEmpty) continue;
      if (name.contains(examType.toLowerCase()) &&
          name.contains(semesterLabel.toLowerCase())) {
        return url;
      }
    }

    return null;
  }

  static String _clean(dynamic value) => value?.toString().trim() ?? '';

  static String _firstString(Map<String, dynamic> row, List<String> keys) {
    for (final key in keys) {
      final value = _clean(row[key]);
      if (value.isNotEmpty) return value;
    }
    return '';
  }

  static String _normalizeSection(String raw) {
    final match = RegExp(r'\d+').firstMatch(raw.trim());
    if (match == null) return '';
    final parsed = int.tryParse(match.group(0)!);
    if (parsed == null) return match.group(0)!;
    return parsed.toString();
  }
}

class ExamScheduleOverride {
  const ExamScheduleOverride({
    this.midDate,
    this.midStartTime,
    this.midEndTime,
    this.midRoomNumber,
    this.finalDate,
    this.finalStartTime,
    this.finalEndTime,
    this.finalRoomNumber,
  });

  final String? midDate;
  final String? midStartTime;
  final String? midEndTime;
  final String? midRoomNumber;

  final String? finalDate;
  final String? finalStartTime;
  final String? finalEndTime;
  final String? finalRoomNumber;

  ExamScheduleOverride copyWith({
    String? midDate,
    String? midStartTime,
    String? midEndTime,
    String? midRoomNumber,
    String? finalDate,
    String? finalStartTime,
    String? finalEndTime,
    String? finalRoomNumber,
  }) {
    return ExamScheduleOverride(
      midDate: midDate ?? this.midDate,
      midStartTime: midStartTime ?? this.midStartTime,
      midEndTime: midEndTime ?? this.midEndTime,
      midRoomNumber: midRoomNumber ?? this.midRoomNumber,
      finalDate: finalDate ?? this.finalDate,
      finalStartTime: finalStartTime ?? this.finalStartTime,
      finalEndTime: finalEndTime ?? this.finalEndTime,
      finalRoomNumber: finalRoomNumber ?? this.finalRoomNumber,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'midDate': midDate,
      'midStartTime': midStartTime,
      'midEndTime': midEndTime,
      'midRoomNumber': midRoomNumber,
      'finalDate': finalDate,
      'finalStartTime': finalStartTime,
      'finalEndTime': finalEndTime,
      'finalRoomNumber': finalRoomNumber,
    };
  }

  factory ExamScheduleOverride.fromJson(Map<String, dynamic> json) {
    return ExamScheduleOverride(
      midDate: json['midDate']?.toString(),
      midStartTime: json['midStartTime']?.toString(),
      midEndTime: json['midEndTime']?.toString(),
      midRoomNumber: json['midRoomNumber']?.toString(),
      finalDate: json['finalDate']?.toString(),
      finalStartTime: json['finalStartTime']?.toString(),
      finalEndTime: json['finalEndTime']?.toString(),
      finalRoomNumber: json['finalRoomNumber']?.toString(),
    );
  }
}

class ExamSectionResolved {
  const ExamSectionResolved({
    required this.midDate,
    required this.midStartTime,
    required this.midEndTime,
    required this.midRoomNumber,
    required this.finalDate,
    required this.finalStartTime,
    required this.finalEndTime,
    required this.finalRoomNumber,
  });

  final String? midDate;
  final String? midStartTime;
  final String? midEndTime;
  final String? midRoomNumber;
  final String? finalDate;
  final String? finalStartTime;
  final String? finalEndTime;
  final String? finalRoomNumber;
}

class ExamScheduleService {
  ExamScheduleService._internal();
  static final ExamScheduleService _instance = ExamScheduleService._internal();
  factory ExamScheduleService() => _instance;

  Future<Map<String, ExamScheduleOverride>> getOverridesForSections(
    List<Section> sections, {
    bool forceRefresh = false,
    int? forcedSemesterSessionId,
  }) async {
    if (sections.isEmpty) return const <String, ExamScheduleOverride>{};
    final semesterSessionId =
        forcedSemesterSessionId ?? resolveSemesterSessionId(sections);
    if (semesterSessionId == null) {
      return const <String, ExamScheduleOverride>{};
    }
    return ExamMapService().getOverridesForSemester(
      semesterSessionId: semesterSessionId,
      forceRefresh: forceRefresh,
    );
  }

  int? resolveSemesterSessionId(List<Section> sections) {
    if (sections.isEmpty) return null;
    final counts = <int, int>{};
    for (final section in sections) {
      counts.update(
        section.semesterSessionId,
        (value) => value + 1,
        ifAbsent: () => 1,
      );
    }
    int? selectedId;
    var maxCount = -1;
    for (final entry in counts.entries) {
      if (entry.value > maxCount) {
        maxCount = entry.value;
        selectedId = entry.key;
      }
    }
    return selectedId;
  }

  ExamSectionResolved resolveSection({
    required Section section,
    required Map<String, ExamScheduleOverride> overrides,
  }) {
    final override = overrides[ExamMapService.sectionKeyForSection(section)];
    final midRoom = _pickRoom(override?.midRoomNumber);
    final finalRoom = _pickRoom(override?.finalRoomNumber) ?? midRoom;
    return ExamSectionResolved(
      midDate: override?.midDate ?? section.sectionSchedule.midExamDate,
      midStartTime:
          override?.midStartTime ?? section.sectionSchedule.midExamStartTime,
      midEndTime:
          override?.midEndTime ?? section.sectionSchedule.midExamEndTime,
      midRoomNumber: midRoom,
      finalDate: override?.finalDate ?? section.sectionSchedule.finalExamDate,
      finalStartTime:
          override?.finalStartTime ??
          section.sectionSchedule.finalExamStartTime,
      finalEndTime:
          override?.finalEndTime ?? section.sectionSchedule.finalExamEndTime,
      finalRoomNumber: finalRoom,
    );
  }

  String? _pickRoom(String? preferred) {
    final selected = (preferred ?? '').trim();
    if (selected.isNotEmpty) return selected;
    return null;
  }
}
