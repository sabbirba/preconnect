import 'dart:convert';

import 'package:preconnect/api/api_client.dart';
import 'package:preconnect/api/api_config.dart';
import 'package:preconnect/model/section_info.dart' show SectionFaculty;

class SeatStatusService {
  SeatStatusService._internal();
  static final SeatStatusService _instance = SeatStatusService._internal();
  factory SeatStatusService() => _instance;

  final ApiClient _client = ApiClient();

  static Map<int, SeatStatusDetailsResponse>? _cachedDetails;
  static Future<Map<int, SeatStatusDetailsResponse>>? _preloadFuture;

  Map<int, SeatStatusDetailsResponse>? get cachedDetails => _cachedDetails;

  static Future<void> preload() async {
    await _instance.preloadData();
  }

  Future<Map<int, SeatStatusDetailsResponse>> fetchAllSectionsDetailsFromApi({
    bool forceRefresh = false,
  }) async {
    return preloadData(forceRefresh: forceRefresh);
  }

  Future<Map<int, SeatStatusDetailsResponse>> preloadData({
    bool forceRefresh = false,
  }) async {
    if (!forceRefresh && _cachedDetails != null) {
      return _cachedDetails!;
    }
    if (!forceRefresh) {
      final inFlight = _preloadFuture;
      if (inFlight != null) {
        return inFlight;
      }
    }

    final future = _loadDetails(forceRefresh: forceRefresh);
    _preloadFuture = future;
    try {
      final details = await future;
      _cachedDetails = details;
      return details;
    } finally {
      if (identical(_preloadFuture, future)) {
        _preloadFuture = null;
      }
    }
  }

  Future<Map<int, SeatStatusDetailsResponse>> _loadDetails({
    bool forceRefresh = false,
  }) async {
    try {
      final raw = await _fetchJson(ApiConfig.seatStatusDataUrl);
      return _parseConnectJson(raw);
    } catch (_) {
      try {
        final raw = await _fetchJson(ApiConfig.seatStatusDataFallbackUrl);
        return _parseConnectJson(raw);
      } catch (_) {
        return const <int, SeatStatusDetailsResponse>{};
      }
    }
  }

  Future<dynamic> _fetchJson(String url) async {
    final response = await _client.publicGet(
      url,
      acceptedStatusCodes: const <int>{200},
    );
    try {
      return jsonDecode(response.body);
    } catch (e) {
      throw FormatException('Invalid JSON response from $url: $e');
    }
  }

  Map<int, SeatStatusDetailsResponse> _parseConnectJson(dynamic raw) {
    if (raw is! List) return const <int, SeatStatusDetailsResponse>{};
    final result = <int, SeatStatusDetailsResponse>{};
    for (final item in raw.whereType<Map>()) {
      final map = item.cast<String, dynamic>();
      try {
        final parsed = SeatStatusDetailsResponse.fromJson(map);
        result[parsed.sectionId] = parsed;
      } catch (_) {}
    }
    return result;
  }
}

class SeatStatusDetailsResponse {
  SeatStatusDetailsResponse({
    required this.sectionId,
    required this.courseId,
    required this.courseCode,
    required this.sectionName,
    required this.courseCredit,
    required this.capacity,
    required this.consumedSeat,
    required this.semesterSessionId,
    required this.parentSectionId,
    required this.faculty,
    required this.faculties,
    required this.roomName,
    required this.roomNumber,
    required this.courseType,
    required this.academicDegree,
    required this.sectionType,
    required this.courseName,
    required this.prerequisiteCourses,
    required this.sectionSchedule,
    required this.labSectionId,
    required this.labCourseCode,
    required this.labFaculties,
    required this.labName,
    required this.labRoomName,
    required this.labSchedules,
  });

  final int sectionId;
  final int courseId;
  final String courseCode;
  final String sectionName;
  final int courseCredit;
  final int capacity;
  final int consumedSeat;
  final int semesterSessionId;
  final int? parentSectionId;
  final SectionFaculty? faculty;
  final String faculties;
  final String roomName;
  final String roomNumber;
  final String courseType;
  final String academicDegree;
  final String sectionType;
  final String courseName;
  final String? prerequisiteCourses;
  final SeatStatusSchedule sectionSchedule;
  final int? labSectionId;
  final String? labCourseCode;
  final String? labFaculties;
  final String? labName;
  final String? labRoomName;
  final List<SeatStatusClassSchedule> labSchedules;

  factory SeatStatusDetailsResponse.fromJson(Map<String, dynamic> json) {
    final scheduleJson = _sectionScheduleMapFromJson(json['sectionSchedule']);
    final rawLabSchedules = json['labSchedules'];
    final labSchedules = rawLabSchedules is List
        ? rawLabSchedules
              .whereType<Map>()
              .map(
                (item) => SeatStatusClassSchedule.fromJson(
                  item.cast<String, dynamic>(),
                ),
              )
              .toList()
        : const <SeatStatusClassSchedule>[];

    return SeatStatusDetailsResponse(
      sectionId: _toInt(json['sectionId']),
      courseId: _toInt(json['courseId']),
      courseCode: _toString(json['courseCode']),
      sectionName: _toString(json['sectionName']),
      courseCredit: _toInt(json['courseCredit']),
      capacity: _toInt(json['capacity']),
      consumedSeat: _toInt(json['consumedSeat']),
      semesterSessionId: _toInt(json['semesterSessionId']),
      parentSectionId: _toNullableInt(json['parentSectionId']),
      faculty: _facultyFromJson(json['faculties']),
      faculties: _facultyLabel(json['faculties']),
      roomName: _toString(json['roomName']),
      roomNumber: _toString(json['roomNumber']),
      courseType: _toString(json['courseType']),
      academicDegree: _toString(json['academicDegree']),
      sectionType: _toString(json['sectionType']),
      courseName: _toString(json['courseName']),
      prerequisiteCourses: _toNullableString(json['prerequisiteCourses']),
      sectionSchedule: SeatStatusSchedule.fromJson(scheduleJson),
      labSectionId: _toNullableInt(json['labSectionId']),
      labCourseCode: _toNullableString(json['labCourseCode']),
      labFaculties: _toNullableString(json['labFaculties']),
      labName: _toNullableString(json['labName']),
      labRoomName: _toNullableString(json['labRoomName']),
      labSchedules: labSchedules,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'sectionId': sectionId,
      'courseId': courseId,
      'courseCode': courseCode,
      'sectionName': sectionName,
      'courseCredit': courseCredit,
      'capacity': capacity,
      'consumedSeat': consumedSeat,
      'semesterSessionId': semesterSessionId,
      'parentSectionId': parentSectionId,
      'faculty': faculty == null
          ? null
          : <String, dynamic>{
              'id': faculty!.id,
              'staffName': faculty!.staffName,
              'shortName': faculty!.shortName,
              'email': faculty!.email,
              'imgUrl': faculty!.imgUrl,
            },
      'faculties': faculties,
      'roomName': roomName,
      'roomNumber': roomNumber,
      'courseType': courseType,
      'academicDegree': academicDegree,
      'sectionType': sectionType,
      'courseName': courseName,
      'prerequisiteCourses': prerequisiteCourses,
      'sectionSchedule': sectionSchedule.toJson(),
      'labSectionId': labSectionId,
      'labCourseCode': labCourseCode,
      'labFaculties': labFaculties,
      'labName': labName,
      'labRoomName': labRoomName,
      'labSchedules': labSchedules.map((e) => e.toJson()).toList(),
    };
  }
}

class SeatStatusSchedule {
  SeatStatusSchedule({
    required this.classSchedules,
    this.midExamDate,
    this.midExamStartTime,
    this.midExamEndTime,
    this.finalExamDate,
    this.finalExamStartTime,
    this.finalExamEndTime,
  });

  final List<SeatStatusClassSchedule> classSchedules;
  final String? midExamDate;
  final String? midExamStartTime;
  final String? midExamEndTime;
  final String? finalExamDate;
  final String? finalExamStartTime;
  final String? finalExamEndTime;

  factory SeatStatusSchedule.fromJson(Map<String, dynamic> json) {
    final classSchedules = _classSchedulesFromJson(json['classSchedules']);

    return SeatStatusSchedule(
      classSchedules: classSchedules,
      midExamDate: _toNullableString(json['midExamDate']),
      midExamStartTime: _toNullableString(json['midExamStartTime']),
      midExamEndTime: _toNullableString(json['midExamEndTime']),
      finalExamDate: _toNullableString(json['finalExamDate']),
      finalExamStartTime: _toNullableString(json['finalExamStartTime']),
      finalExamEndTime: _toNullableString(json['finalExamEndTime']),
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'classSchedules': classSchedules.map((e) => e.toJson()).toList(),
      'midExamDate': midExamDate,
      'midExamStartTime': midExamStartTime,
      'midExamEndTime': midExamEndTime,
      'finalExamDate': finalExamDate,
      'finalExamStartTime': finalExamStartTime,
      'finalExamEndTime': finalExamEndTime,
    };
  }
}

List<SeatStatusClassSchedule> _classSchedulesFromJson(dynamic value) {
  final parsed = _jsonValue(value);
  if (parsed is! List) return const <SeatStatusClassSchedule>[];
  return parsed
      .whereType<Map>()
      .map(
        (item) =>
            SeatStatusClassSchedule.fromJson(item.cast<String, dynamic>()),
      )
      .toList(growable: false);
}

class SeatStatusClassSchedule {
  SeatStatusClassSchedule({
    required this.day,
    required this.startTime,
    required this.endTime,
  });

  final String day;
  final String startTime;
  final String endTime;

  factory SeatStatusClassSchedule.fromJson(Map<String, dynamic> json) {
    return SeatStatusClassSchedule(
      day: _toString(json['day']),
      startTime: _toString(json['startTime']),
      endTime: _toString(json['endTime']),
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'day': day,
      'startTime': startTime,
      'endTime': endTime,
    };
  }
}

int _toInt(dynamic value) {
  if (value is int) return value;
  return int.tryParse('$value') ?? 0;
}

int? _toNullableInt(dynamic value) {
  if (value == null) return null;
  if (value is int) return value;
  return int.tryParse('$value');
}

String _toString(dynamic value) {
  if (value == null) return '';
  return '$value'.trim();
}

Map<String, dynamic> _sectionScheduleMapFromJson(dynamic value) {
  final parsed = _jsonValue(value);
  if (parsed is Map) {
    return parsed.cast<String, dynamic>();
  }
  return const <String, dynamic>{};
}

dynamic _jsonValue(dynamic value) {
  if (value is String) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return const <String, dynamic>{};
    try {
      return jsonDecode(trimmed);
    } catch (_) {
      return value;
    }
  }
  return value;
}

String _facultyLabel(dynamic value) {
  if (value is Map) {
    final map = value.cast<String, dynamic>();
    final shortName = _toString(map['shortName']);
    if (shortName.isNotEmpty) return shortName;
    final staffName = _toString(map['staffName']);
    if (staffName.isNotEmpty) return staffName;
    return '';
  }
  return _toString(value);
}

SectionFaculty? _facultyFromJson(dynamic value) {
  if (value is! Map) return null;
  return SectionFaculty.fromJson(value.cast<String, dynamic>());
}

String? _toNullableString(dynamic value) {
  final parsed = _toString(value);
  if (parsed.isEmpty || parsed.toUpperCase() == 'NULL') return null;
  return parsed;
}
