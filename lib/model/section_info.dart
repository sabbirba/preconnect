import 'dart:convert';
import 'package:json_annotation/json_annotation.dart';
import 'package:equatable/equatable.dart';
import 'package:preconnect/tools/string_utils.dart';

part 'section_info.g.dart';

@JsonSerializable()
class SectionFaculty extends Equatable {
  @JsonKey(defaultValue: '')
  final String id;
  @JsonKey(defaultValue: '')
  final String staffName;
  @JsonKey(defaultValue: '')
  final String shortName;
  @JsonKey(defaultValue: '')
  final String email;
  final String? imgUrl;

  const SectionFaculty({
    required this.id,
    required this.staffName,
    required this.shortName,
    required this.email,
    required this.imgUrl,
  });

  @override
  List<Object?> get props => [id, staffName, shortName, email, imgUrl];

  factory SectionFaculty.fromJson(Map<String, dynamic> json) =>
      _$SectionFacultyFromJson(json);

  Map<String, dynamic> toJson() => _$SectionFacultyToJson(this);
}

class Section {
  final int sectionId;
  final int? advisingSectionId;
  final int? parentSectionId;
  final int courseId;
  final String courseCode;
  final String? name;
  final String sectionName;
  final int semesterSessionId;
  final int courseCredit;
  final int studentPortfolioId;
  final int capacity;
  final int consumedSeat;
  final SectionSchedule sectionSchedule;
  final SectionFaculty? faculty;
  final String faculties;
  final String roomName;
  final String roomNumber;
  final String? prerequisiteCourses;
  final bool? isReserve;
  final String courseType;
  final String? prerequisiteIncompleteGrade;
  final String? prerequisiteResultPublished;

  Section({
    required this.sectionId,
    this.advisingSectionId,
    this.parentSectionId,
    required this.courseId,
    required this.courseCode,
    this.name,
    required this.sectionName,
    required this.semesterSessionId,
    required this.courseCredit,
    required this.studentPortfolioId,
    required this.capacity,
    required this.consumedSeat,
    required this.sectionSchedule,
    this.faculty,
    required this.faculties,
    required this.roomName,
    required this.roomNumber,
    this.prerequisiteCourses,
    this.isReserve,
    required this.courseType,
    this.prerequisiteIncompleteGrade,
    this.prerequisiteResultPublished,
  });

  factory Section.fromJson(Map<String, dynamic> json) {
    return Section(
      sectionId: _intValue(json, 'sectionId'),
      advisingSectionId: _nullableIntValue(json, 'advisingSectionId'),
      parentSectionId: _nullableIntValue(json, 'parentSectionId'),
      courseId: _intValue(json, 'courseId'),
      courseCode: _stringValue(json, 'courseCode'),
      name: _stringValue(json, 'name'),
      sectionName: _stringValue(json, 'sectionName'),
      semesterSessionId: _intValue(json, 'semesterSessionId'),
      courseCredit: _intValue(json, 'courseCredit'),
      studentPortfolioId: _intValue(json, 'studentPortfolioId'),
      capacity: _intValue(json, 'capacity'),
      consumedSeat: _intValue(json, 'consumedSeat'),
      sectionSchedule: SectionSchedule.fromJson(
        _scheduleMapFromJson(json['sectionSchedule']),
      ),
      faculty: _facultyFromJson(json['faculties']),
      faculties: _facultyLabel(json['faculties']),
      roomName: _stringValue(json, 'roomName'),
      roomNumber: _stringValue(json, 'roomNumber'),
      prerequisiteCourses: json['prerequisiteCourses']?.toString(),
      isReserve: json['isReserve'],
      courseType: _stringValue(json, 'courseType'),
      prerequisiteIncompleteGrade: json['prerequisiteIncompleteGrade']
          ?.toString(),
      prerequisiteResultPublished: json['prerequisiteResultPublished']
          ?.toString(),
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'sectionId': sectionId,
      'advisingSectionId': advisingSectionId,
      'parentSectionId': parentSectionId,
      'courseId': courseId,
      'courseCode': courseCode,
      'name': name,
      'sectionName': sectionName,
      'semesterSessionId': semesterSessionId,
      'courseCredit': courseCredit,
      'studentPortfolioId': studentPortfolioId,
      'capacity': capacity,
      'consumedSeat': consumedSeat,
      'sectionSchedule': sectionSchedule.toJson(),
      'faculties': faculty?.toJson() ?? faculties,
      'roomName': roomName,
      'roomNumber': roomNumber,
      'prerequisiteCourses': prerequisiteCourses,
      'isReserve': isReserve,
      'courseType': courseType,
      'prerequisiteIncompleteGrade': prerequisiteIncompleteGrade,
      'prerequisiteResultPublished': prerequisiteResultPublished,
    };
  }
}

@JsonSerializable()
class SectionSchedule extends Equatable {
  final String? finalExamDate;
  final String? finalExamStartTime;
  final String? finalExamEndTime;
  final String? midExamDate;
  final String? midExamStartTime;
  final String? midExamEndTime;
  final String? finalExamDetail;
  final String? midExamDetail;
  @JsonKey(defaultValue: '')
  final String classStartDate;
  @JsonKey(defaultValue: '')
  final String classEndDate;
  @JsonKey(defaultValue: <ClassSchedule>[])
  final List<ClassSchedule> classSchedules;

  const SectionSchedule({
    this.finalExamDate,
    this.finalExamStartTime,
    this.finalExamEndTime,
    this.midExamDate,
    this.midExamStartTime,
    this.midExamEndTime,
    this.finalExamDetail,
    this.midExamDetail,
    required this.classStartDate,
    required this.classEndDate,
    required this.classSchedules,
  });

  @override
  List<Object?> get props => [
    finalExamDate,
    finalExamStartTime,
    finalExamEndTime,
    midExamDate,
    midExamStartTime,
    midExamEndTime,
    finalExamDetail,
    midExamDetail,
    classStartDate,
    classEndDate,
    classSchedules,
  ];

  factory SectionSchedule.fromJson(Map<String, dynamic> json) =>
      _$SectionScheduleFromJson(json);

  Map<String, dynamic> toJson() => _$SectionScheduleToJson(this);
}

@JsonSerializable()
class ClassSchedule extends Equatable {
  @JsonKey(defaultValue: '')
  final String startTime;
  @JsonKey(defaultValue: '')
  final String endTime;
  @JsonKey(defaultValue: '')
  final String day;

  const ClassSchedule({
    required this.startTime,
    required this.endTime,
    required this.day,
  });

  @override
  List<Object?> get props => [startTime, endTime, day];

  factory ClassSchedule.fromJson(Map<String, dynamic> json) =>
      _$ClassScheduleFromJson(json);

  Map<String, dynamic> toJson() => _$ClassScheduleToJson(this);
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

Map<String, dynamic> _scheduleMapFromJson(dynamic value) {
  final parsed = _jsonValue(value);
  if (parsed is Map) {
    return parsed.cast<String, dynamic>();
  }
  return const <String, dynamic>{};
}

String _stringValue(Map<String, dynamic> json, String key) {
  return '${json[key] ?? ''}'.trim();
}

int _intValue(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '') ?? 0;
}

int? _nullableIntValue(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value == null) return null;
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value.toString());
}

SectionFaculty? _facultyFromJson(dynamic value) {
  if (value is! Map) return null;
  final map = value.cast<String, dynamic>();
  return SectionFaculty.fromJson(map);
}

String _facultyLabel(dynamic value) {
  if (value is Map) {
    final map = value.cast<String, dynamic>();
    final shortName = '${map['shortName'] ?? ''}'.trim();
    if (shortName.isNotEmpty) return shortName;
    final staffName = '${map['staffName'] ?? ''}'.trim();
    if (staffName.isNotEmpty) return staffName;
    return '';
  }
  return '$value'.trim();
}

List<Section> parseSectionsFromScheduleJson(String? scheduleJson) {
  if (scheduleJson == null || scheduleJson.trim().isEmpty) {
    return const <Section>[];
  }
  try {
    final decoded = jsonDecode(scheduleJson);
    if (decoded is! List<dynamic>) return const <Section>[];
    final sections = <Section>[];
    final seen = <String>{};
    for (final raw in decoded.whereType<Map>().map(
      (e) => e.cast<String, dynamic>(),
    )) {
      final item = Section.fromJson(raw);
      final key =
          '${item.sectionId}|${item.courseCode}|${item.sectionName}|${item.roomNumber}';
      if (!seen.add(key)) continue;
      sections.add(item);
    }
    sections.sort((a, b) {
      final codeCmp = compareNaturalText(a.courseCode, b.courseCode);
      if (codeCmp != 0) return codeCmp;
      return compareNaturalText(a.sectionName, b.sectionName);
    });
    return sections;
  } catch (_) {
    return const <Section>[];
  }
}
