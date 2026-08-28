import 'dart:async';
import 'dart:convert';
import 'package:preconnect/api/api_client.dart';
import 'package:preconnect/api/api_config.dart';
import 'package:preconnect/api/repository_cache.dart';
import 'package:preconnect/api/schedule.dart';
import 'package:preconnect/model/section_info.dart';
import 'package:preconnect/tools/app_storage.dart';
import 'package:preconnect/tools/storage_keys.dart';

class ExamMapService {
  static final ExamMapService _instance = ExamMapService._();
  factory ExamMapService() => _instance;
  ExamMapService._();

  final ApiClient _client = ApiClient();
  final RepositoryCache _repo = RepositoryCache.instance;

  static const Duration _indexCacheTtl = Duration(days: 30);
  static const Duration _examJsonCacheTtl = Duration(days: 3650);
  static const String _indexCacheKey = 'exammap_index_v1';

  static String sectionKey({
    required String courseCode,
    required String sectionName,
  }) {
    final course = courseCode.trim().toUpperCase();
    final section = _normalizeSection(sectionName);
    if (course.isEmpty || section.isEmpty) return '';
    return '$course|$section';
  }

  final Map<int, Future<Map<String, ExamScheduleOverride>>>
  _inFlightSemesterFetches = {};

  Future<Map<String, ExamScheduleOverride>> getOverridesForSemester({
    required int semesterSessionId,
    bool forceRefresh = false,
  }) async {
    final parsedKey = 'exammap_parsed_${semesterSessionId}_v1';
    if (!forceRefresh) {
      final cachedParsed = AppStorage.instance.getStringSync(parsedKey);
      if (cachedParsed != null && cachedParsed.isNotEmpty) {
        try {
          final decodedJson = jsonDecode(cachedParsed);
          if (decodedJson is Map) {
            final decoded = <String, ExamScheduleOverride>{};
            for (final entry in decodedJson.entries) {
              if (entry.value is Map) {
                decoded[entry.key.toString()] = ExamScheduleOverride.fromJson(
                  (entry.value as Map).cast<String, dynamic>(),
                );
              }
            }
            if (decoded.isNotEmpty) return decoded;
          }
        } catch (_) {}
      }
    }

    if (!forceRefresh &&
        _inFlightSemesterFetches.containsKey(semesterSessionId)) {
      return _inFlightSemesterFetches[semesterSessionId]!;
    }

    final future = _fetchAndMergeOverridesForSemester(
      semesterSessionId: semesterSessionId,
      forceRefresh: forceRefresh,
      parsedKey: parsedKey,
    );

    _inFlightSemesterFetches[semesterSessionId] = future;
    try {
      return await future;
    } finally {
      _inFlightSemesterFetches.remove(semesterSessionId);
    }
  }

  Future<Map<String, ExamScheduleOverride>> _fetchAndMergeOverridesForSemester({
    required int semesterSessionId,
    required bool forceRefresh,
    required String parsedKey,
  }) async {
    var semesterLabel = _semesterLabelFromSessionId(semesterSessionId);
    if (semesterLabel.isEmpty) {
      final sessionItem = await ScheduleService().resolveSemesterSessionItem(
        semesterSessionId,
      );
      if (sessionItem != null && sessionItem.description.isNotEmpty) {
        semesterLabel = sessionItem.description;
      }
    }
    if (semesterLabel.isEmpty) return const <String, ExamScheduleOverride>{};

    final indexJson = await _fetchJsonWithCache(
      url: ApiConfig.examMapIndexUrl,
      cacheKey: _indexCacheKey,
      ttl: _indexCacheTtl,
      forceRefresh: forceRefresh,
    );

    final indexList = indexJson is List ? indexJson : const <dynamic>[];
    final midRow = _pickExamRow(
      indexList,
      examType: 'Mid',
      semesterLabel: semesterLabel,
    );
    final finalRow = _pickExamRow(
      indexList,
      examType: 'Final',
      semesterLabel: semesterLabel,
    );

    final midUrl = midRow != null ? _clean(midRow['url']) : null;
    final finalUrl = finalRow != null ? _clean(finalRow['url']) : null;

    final List<dynamic>? midPdfUrls = midRow != null
        ? midRow['pdf_urls'] as List<dynamic>?
        : null;
    final List<dynamic>? finalPdfUrls = finalRow != null
        ? finalRow['pdf_urls'] as List<dynamic>?
        : null;

    final merged = <String, ExamScheduleOverride>{};

    if (midUrl != null && midUrl.isNotEmpty) {
      final midJson = await _fetchJsonWithCache(
        url: midUrl,
        cacheKey: 'exammap_mid_${semesterSessionId}_v1',
        ttl: _examJsonCacheTtl,
        forceRefresh: forceRefresh,
      );
      _mergeExamRows(merged, midJson, examTypeHint: 'Mid', pdfUrls: midPdfUrls);
    }

    if (finalUrl != null && finalUrl.isNotEmpty) {
      final finalJson = await _fetchJsonWithCache(
        url: finalUrl,
        cacheKey: 'exammap_final_${semesterSessionId}_v1',
        ttl: _examJsonCacheTtl,
        forceRefresh: forceRefresh,
      );
      _mergeExamRows(
        merged,
        finalJson,
        examTypeHint: 'Final',
        pdfUrls: finalPdfUrls,
      );
    }

    if (merged.isNotEmpty) {
      final jsonToWrite = merged.map(
        (key, value) => MapEntry(key, value.toJson()),
      );
      await _repo.writeJson(parsedKey, jsonToWrite);
      await AppStorage.instance.setString(parsedKey, jsonEncode(jsonToWrite));
    }

    return merged;
  }

  Future<dynamic> _fetchJsonWithCache({
    required String url,
    required String cacheKey,
    required Duration ttl,
    required bool forceRefresh,
  }) async {
    final cached = await _repo.readJsonMap(cacheKey);
    final cachedData = cached?['data'];

    if (!forceRefresh && cachedData != null) {
      if (!(cachedData is List &&
          cachedData.isEmpty &&
          cacheKey == _indexCacheKey)) {
        final ts = cached?['ts'];
        if (ts is int) {
          final age = DateTime.now().difference(
            DateTime.fromMillisecondsSinceEpoch(ts),
          );
          if (age <= ttl) {
            return cachedData;
          }
        }
      }
    }

    try {
      final response = await _client.publicGet(
        url,
        cacheDuration: forceRefresh
            ? Duration.zero
            : const Duration(seconds: 30),
      );
      final decoded = jsonDecode(response.body);
      await _repo.writeJson(cacheKey, <String, dynamic>{
        'ts': DateTime.now().millisecondsSinceEpoch,
        'data': decoded,
      });
      return decoded;
    } catch (_) {
      return cachedData;
    }
  }

  void _mergeExamRows(
    Map<String, ExamScheduleOverride> out,
    dynamic payload, {
    required String examTypeHint,
    List<dynamic>? pdfUrls,
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
      final rawCourse = _firstString(row, const <String>[
        'Course',
        'course',
        'Course Code',
        'courseCode',
        'course_code',
      ]).trim().toUpperCase();

      final parts = rawCourse.split(RegExp(r'\s+'));
      final course = parts.isNotEmpty ? parts.first : '';
      final studentIdInRow = parts.length > 1 ? parts[1] : '';

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

      final sectionKey = '$course|$section';
      final studentKey = studentIdInRow.isNotEmpty
          ? '$course|$studentIdInRow|$section'
          : '';
      final altStudentKey = studentIdInRow.isNotEmpty
          ? '$course|$studentIdInRow'
          : '';

      final date = examType == 'MID'
          ? _firstString(row, const <String>[
              'Mid Date',
              'midDate',
              'mid_date',
              'Date',
              'date',
            ])
          : _firstString(row, const <String>[
              'Final Date',
              'finalDate',
              'final_date',
              'Date',
              'date',
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

      final pdfUrl = _findPdfUrl(pdfUrls, course);

      _applyOverrideEntry(
        out,
        key: sectionKey,
        date: date,
        start: start,
        end: end,
        room: room,
        pdfUrl: pdfUrl,
        examType: examType,
      );

      if (studentKey.isNotEmpty) {
        _applyOverrideEntry(
          out,
          key: studentKey,
          date: date,
          start: start,
          end: end,
          room: room,
          pdfUrl: pdfUrl,
          examType: examType,
        );
      }

      if (altStudentKey.isNotEmpty) {
        _applyOverrideEntry(
          out,
          key: altStudentKey,
          date: date,
          start: start,
          end: end,
          room: room,
          pdfUrl: pdfUrl,
          examType: examType,
        );
      }
    }
  }

  void _applyOverrideEntry(
    Map<String, ExamScheduleOverride> out, {
    required String key,
    required String date,
    required String start,
    required String end,
    required String room,
    required String? pdfUrl,
    required String examType,
  }) {
    final existing = out[key] ?? const ExamScheduleOverride();
    if (examType == 'MID') {
      out[key] = existing.copyWith(
        midDate: date.isNotEmpty ? date : existing.midDate,
        midStartTime: start.isNotEmpty ? start : existing.midStartTime,
        midEndTime: end.isNotEmpty ? end : existing.midEndTime,
        midRoomNumber: room.isNotEmpty ? room : existing.midRoomNumber,
        midPdfUrl: pdfUrl ?? existing.midPdfUrl,
      );
    } else {
      out[key] = existing.copyWith(
        finalDate: date.isNotEmpty ? date : existing.finalDate,
        finalStartTime: start.isNotEmpty ? start : existing.finalStartTime,
        finalEndTime: end.isNotEmpty ? end : existing.finalEndTime,
        finalRoomNumber: room.isNotEmpty ? room : existing.finalRoomNumber,
        finalPdfUrl: pdfUrl ?? existing.finalPdfUrl,
      );
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

  Map? _pickExamRow(
    List<dynamic> indexRows, {
    required String examType,
    required String semesterLabel,
  }) {
    final parts = semesterLabel.split(' ');
    final term = parts.isNotEmpty ? parts.first.toLowerCase() : '';
    final year = parts.length > 1 ? parts.last.toLowerCase() : '';
    final isMid = examType.toUpperCase() == 'MID';

    for (final item in indexRows.whereType<Map>()) {
      final row = item.cast<String, dynamic>();
      final name = _clean(row['exam_name']).toLowerCase();
      final url = _clean(row['url']);
      if (url.isEmpty) continue;

      final matchesTerm = name.contains(term);
      final matchesYear = name.contains(year);
      final hasMid = name.contains('mid');
      final hasFinal = name.contains('final');

      final matchesType = isMid ? (hasMid && !hasFinal) : (hasFinal || !hasMid);

      if (matchesTerm && matchesYear && matchesType) {
        return row;
      }
    }

    for (final item in indexRows.whereType<Map>()) {
      final row = item.cast<String, dynamic>();
      final name = _clean(row['exam_name']).toLowerCase();
      final url = _clean(row['url']);
      if (url.isEmpty) continue;

      if (name.contains(term) && name.contains(year)) {
        return row;
      }
    }

    return null;
  }

  static String? _findPdfUrl(List<dynamic>? pdfUrls, String courseCode) {
    if (pdfUrls == null || pdfUrls.isEmpty) return null;
    final code = courseCode.trim().toUpperCase();
    final isLawCourse = code.startsWith('LAW') || code.startsWith('LLB');

    final cleanedUrls = <String>[];
    for (final item in pdfUrls) {
      final cleaned = _cleanPdfUrl(_clean(item));
      if (cleaned != null && cleaned.isNotEmpty) {
        cleanedUrls.add(cleaned);
      }
    }
    if (cleanedUrls.isEmpty) return null;

    for (final url in cleanedUrls) {
      final unescaped = _fullyDecodeUrl(url).toUpperCase();
      final filename = unescaped.split('/').last;
      if (filename.contains(code)) {
        return url;
      }
    }

    if (isLawCourse) {
      for (final url in cleanedUrls) {
        final unescaped = _fullyDecodeUrl(url).toUpperCase();
        final filename = unescaped.split('/').last;
        if (filename.contains('LLB') || filename.contains('LAW')) {
          return url;
        }
      }
    } else {
      for (final url in cleanedUrls) {
        final unescaped = _fullyDecodeUrl(url).toUpperCase();
        final filename = unescaped.split('/').last;
        if (!filename.contains('LLB') && !filename.contains('LAW')) {
          return url;
        }
      }
    }

    return cleanedUrls.first;
  }

  static String _fullyDecodeUrl(String raw) {
    var str = raw;
    try {
      str = Uri.decodeComponent(str);
      str = Uri.decodeComponent(str);
    } catch (_) {}
    return str;
  }

  static String? _cleanPdfUrl(String raw) {
    var url = _clean(raw);
    if (url.isEmpty) return null;
    if (!url.startsWith('http://') && !url.startsWith('https://')) {
      final base = Uri.parse(ApiConfig.examMapIndexUrl);
      if (url.startsWith('/')) {
        url =
            '${base.scheme}://${base.host}${base.hasPort ? ':${base.port}' : ''}$url';
      } else {
        url =
            '${base.scheme}://${base.host}${base.hasPort ? ':${base.port}' : ''}/$url';
      }
    }
    return url;
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
    this.midPdfUrl,
    this.finalDate,
    this.finalStartTime,
    this.finalEndTime,
    this.finalRoomNumber,
    this.finalPdfUrl,
  });

  final String? midDate;
  final String? midStartTime;
  final String? midEndTime;
  final String? midRoomNumber;
  final String? midPdfUrl;

  final String? finalDate;
  final String? finalStartTime;
  final String? finalEndTime;
  final String? finalRoomNumber;
  final String? finalPdfUrl;

  ExamScheduleOverride copyWith({
    String? midDate,
    String? midStartTime,
    String? midEndTime,
    String? midRoomNumber,
    String? midPdfUrl,
    String? finalDate,
    String? finalStartTime,
    String? finalEndTime,
    String? finalRoomNumber,
    String? finalPdfUrl,
  }) {
    return ExamScheduleOverride(
      midDate: midDate ?? this.midDate,
      midStartTime: midStartTime ?? this.midStartTime,
      midEndTime: midEndTime ?? this.midEndTime,
      midRoomNumber: midRoomNumber ?? this.midRoomNumber,
      midPdfUrl: midPdfUrl ?? this.midPdfUrl,
      finalDate: finalDate ?? this.finalDate,
      finalStartTime: finalStartTime ?? this.finalStartTime,
      finalEndTime: finalEndTime ?? this.finalEndTime,
      finalRoomNumber: finalRoomNumber ?? this.finalRoomNumber,
      finalPdfUrl: finalPdfUrl ?? this.finalPdfUrl,
    );
  }

  factory ExamScheduleOverride.fromJson(Map<String, dynamic> json) {
    return ExamScheduleOverride(
      midDate: json['midDate'] as String?,
      midStartTime: json['midStartTime'] as String?,
      midEndTime: json['midEndTime'] as String?,
      midRoomNumber: json['midRoomNumber'] as String?,
      midPdfUrl: json['midPdfUrl'] as String?,
      finalDate: json['finalDate'] as String?,
      finalStartTime: json['finalStartTime'] as String?,
      finalEndTime: json['finalEndTime'] as String?,
      finalRoomNumber: json['finalRoomNumber'] as String?,
      finalPdfUrl: json['finalPdfUrl'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'midDate': midDate,
      'midStartTime': midStartTime,
      'midEndTime': midEndTime,
      'midRoomNumber': midRoomNumber,
      'midPdfUrl': midPdfUrl,
      'finalDate': finalDate,
      'finalStartTime': finalStartTime,
      'finalEndTime': finalEndTime,
      'finalRoomNumber': finalRoomNumber,
      'finalPdfUrl': finalPdfUrl,
    };
  }
}

class ExamSectionResolved {
  const ExamSectionResolved({
    required this.midDate,
    required this.midStartTime,
    required this.midEndTime,
    required this.midRoomNumber,
    required this.midPdfUrl,
    required this.finalDate,
    required this.finalStartTime,
    required this.finalEndTime,
    required this.finalRoomNumber,
    required this.finalPdfUrl,
  });

  final String? midDate;
  final String? midStartTime;
  final String? midEndTime;
  final String? midRoomNumber;
  final String? midPdfUrl;
  final String? finalDate;
  final String? finalStartTime;
  final String? finalEndTime;
  final String? finalRoomNumber;
  final String? finalPdfUrl;
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

  Map<String, ExamScheduleOverride> getOverridesForSemesterSync(
    int semesterSessionId,
  ) {
    try {
      final raw = AppStorage.instance.getStringSync(
        'exammap_parsed_${semesterSessionId}_v1',
      );
      if (raw == null || raw.isEmpty) {
        return const <String, ExamScheduleOverride>{};
      }
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        final map = <String, ExamScheduleOverride>{};
        for (final entry in decoded.entries) {
          if (entry.value is Map) {
            map[entry.key.toString()] = ExamScheduleOverride.fromJson(
              (entry.value as Map).cast<String, dynamic>(),
            );
          }
        }
        return map;
      }
    } catch (_) {}
    return const <String, ExamScheduleOverride>{};
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
    String? studentId,
  }) {
    final userStudentId =
        (studentId ??
                AppStorage.instance.getStringSync(StorageKeys.studentId) ??
                '')
            .trim();
    final course = section.courseCode.trim().toUpperCase();
    final sec = ExamMapService._normalizeSection(section.sectionName);

    ExamScheduleOverride? override;
    if (userStudentId.isNotEmpty) {
      override =
          overrides['$course|$userStudentId|$sec'] ??
          overrides['$course|$userStudentId'];
    }
    override ??= overrides['$course|$sec'];

    final midRoom = _pickRoom(override?.midRoomNumber);
    final finalRoom = _pickRoom(override?.finalRoomNumber);
    return ExamSectionResolved(
      midDate: override?.midDate ?? section.sectionSchedule.midExamDate,
      midStartTime:
          override?.midStartTime ?? section.sectionSchedule.midExamStartTime,
      midEndTime:
          override?.midEndTime ?? section.sectionSchedule.midExamEndTime,
      midRoomNumber: midRoom,
      midPdfUrl: override?.midPdfUrl,
      finalDate: override?.finalDate ?? section.sectionSchedule.finalExamDate,
      finalStartTime:
          override?.finalStartTime ??
          section.sectionSchedule.finalExamStartTime,
      finalEndTime:
          override?.finalEndTime ?? section.sectionSchedule.finalExamEndTime,
      finalRoomNumber: finalRoom,
      finalPdfUrl: override?.finalPdfUrl,
    );
  }

  String? _pickRoom(String? preferred) {
    final selected = (preferred ?? '').trim();
    if (selected.isNotEmpty) return selected;
    return null;
  }
}
