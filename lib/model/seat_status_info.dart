import 'dart:convert';

class SeatStatusDetailsResponse {
  SeatStatusDetailsResponse({
    required this.section,
    required this.childSection,
  });

  final SeatStatusSection section;
  final SeatStatusSection? childSection;

  factory SeatStatusDetailsResponse.fromJson(Map<String, dynamic> json) {
    return SeatStatusDetailsResponse(
      section: SeatStatusSection.fromJson(
        (json['section'] as Map?)?.cast<String, dynamic>() ??
            const <String, dynamic>{},
      ),
      childSection: json['childSection'] is Map<String, dynamic>
          ? SeatStatusSection.fromJson(
              json['childSection'] as Map<String, dynamic>,
            )
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'section': section.toJson(),
      'childSection': childSection?.toJson(),
    };
  }
}

class SeatStatusSection {
  SeatStatusSection({
    required this.sectionId,
    required this.courseCode,
    required this.sectionName,
    required this.name,
    required this.courseCredit,
    required this.capacity,
    required this.consumedSeat,
    required this.faculties,
    required this.roomName,
    required this.roomNumber,
    required this.sectionSchedule,
  });

  final int sectionId;
  final String courseCode;
  final String sectionName;
  final String name;
  final int courseCredit;
  final int capacity;
  final int consumedSeat;
  final String faculties;
  final String roomName;
  final String roomNumber;
  final SeatStatusSchedule sectionSchedule;

  factory SeatStatusSection.fromJson(Map<String, dynamic> json) {
    final rawSchedule = json['sectionSchedule'];
    final scheduleJson = switch (rawSchedule) {
      String s when s.trim().isNotEmpty =>
        (jsonDecode(s) as Map?)?.cast<String, dynamic>() ??
            const <String, dynamic>{},
      Map<String, dynamic> m => m,
      _ => const <String, dynamic>{},
    };

    return SeatStatusSection(
      sectionId: _toInt(json['sectionId']),
      courseCode: _toString(json['courseCode']),
      sectionName: _toString(json['sectionName']),
      name: _toString(json['name']),
      courseCredit: _toInt(json['courseCredit']),
      capacity: _toInt(json['capacity']),
      consumedSeat: _toInt(json['consumedSeat']),
      faculties: _toString(json['faculties']),
      roomName: _toString(json['roomName']),
      roomNumber: _toString(json['roomNumber']),
      sectionSchedule: SeatStatusSchedule.fromJson(scheduleJson),
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'sectionId': sectionId,
      'courseCode': courseCode,
      'sectionName': sectionName,
      'name': name,
      'courseCredit': courseCredit,
      'capacity': capacity,
      'consumedSeat': consumedSeat,
      'faculties': faculties,
      'roomName': roomName,
      'roomNumber': roomNumber,
      'sectionSchedule': sectionSchedule.toJson(),
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
              .whereType<Map<String, dynamic>>()
              .map(SeatStatusClassSchedule.fromJson)
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

String _toString(dynamic value) {
  if (value == null) return '';
  return '$value'.trim();
}

String? _toNullableString(dynamic value) {
  final parsed = _toString(value);
  if (parsed.isEmpty || parsed.toUpperCase() == 'NULL') return null;
  return parsed;
}
