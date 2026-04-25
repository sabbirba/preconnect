import 'dart:convert';

import 'package:preconnect/api/api_client.dart';
import 'package:preconnect/api/api_config.dart';

class SeatStatusService {
  SeatStatusService._internal();
  static final SeatStatusService _instance = SeatStatusService._internal();
  factory SeatStatusService() => _instance;

  final ApiClient _client = ApiClient();

  Future<Map<int, SeatStatusDetailsResponse>>
  fetchAllSectionsDetailsFromApi() async {
    final raw = await _fetchJson(ApiConfig.seatStatusDataUrl);
    return _parseConnectJson(raw);
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
    final rawSchedule = json['sectionSchedule'];
    final scheduleJson = switch (rawSchedule) {
      Map m => m.cast<String, dynamic>(),
      _ => const <String, dynamic>{},
    };
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
      faculties: _toString(json['faculties']),
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
    final rawSchedules = json['classSchedules'];
    final classSchedules = rawSchedules is List
        ? rawSchedules
              .whereType<Map>()
              .map(
                (item) => SeatStatusClassSchedule.fromJson(
                  item.cast<String, dynamic>(),
                ),
              )
              .toList()
        : const <SeatStatusClassSchedule>[];

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

String? _toNullableString(dynamic value) {
  final parsed = _toString(value);
  if (parsed.isEmpty || parsed.toUpperCase() == 'NULL') return null;
  return parsed;
}
