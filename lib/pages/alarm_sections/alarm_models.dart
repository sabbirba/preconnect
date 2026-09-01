part of '../alarms.dart';

class _AlarmData {
  const _AlarmData({
    required this.sections,
    required this.examEntries,
    required this.isRamadan,
    required this.customSchedules,
    required this.advisingInfo,
    this.examOverrides = const <String, ExamScheduleOverride>{},
  });

  final List<Section> sections;
  final List<_ExamAlarmEntry> examEntries;
  final bool isRamadan;
  final List<CustomSchedule> customSchedules;
  final Map<String, String?>? advisingInfo;
  final Map<String, ExamScheduleOverride> examOverrides;
}

class _ExamAlarmEntry {
  const _ExamAlarmEntry({
    required this.id,
    required this.type,
    required this.courseCode,
    required this.sectionName,
    required this.roomNumber,
    required this.faculties,
    required this.consumedSeat,
    required this.startTime,
    required this.endTime,
    required this.dateTime,
  });

  final String id;
  final String type;
  final String courseCode;
  final String sectionName;
  final String roomNumber;
  final String faculties;
  final int consumedSeat;
  final String? startTime;
  final String? endTime;
  final DateTime dateTime;

  DateTime? get endDateTime {
    final parsed = BracuTime.parseHourMinute(endTime);
    if (parsed == null) return null;
    return DateTime(
      dateTime.year,
      dateTime.month,
      dateTime.day,
      parsed.$1,
      parsed.$2,
    );
  }

  bool get isPassed => (endDateTime ?? dateTime).isBefore(DateTime.now());

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id,
      'type': type,
      'courseCode': courseCode,
      'sectionName': sectionName,
      'roomNumber': roomNumber,
      'faculties': faculties,
      'consumedSeat': consumedSeat,
      'startTime': startTime,
      'endTime': endTime,
      'dateTime': dateTime.millisecondsSinceEpoch,
    };
  }

  factory _ExamAlarmEntry.fromJson(Map<String, dynamic> json) {
    return _ExamAlarmEntry(
      id: json['id']?.toString() ?? '',
      type: json['type']?.toString() ?? '',
      courseCode: json['courseCode']?.toString() ?? '',
      sectionName: json['sectionName']?.toString() ?? '',
      roomNumber: json['roomNumber']?.toString() ?? '',
      faculties: json['faculties']?.toString() ?? '',
      consumedSeat: (json['consumedSeat'] as num?)?.toInt() ?? 0,
      startTime: json['startTime']?.toString(),
      endTime: json['endTime']?.toString(),
      dateTime: DateTime.fromMillisecondsSinceEpoch(
        (json['dateTime'] as num?)?.toInt() ?? 0,
      ),
    );
  }
}
