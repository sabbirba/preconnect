import 'dart:convert';
import 'package:preconnect/tools/string_utils.dart';

class SectionFaculty {
  final String id;
  final String staffName;
  final String shortName;
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
  bool operator ==(Object other) =>
      identical(this, other) || other is SectionFaculty && id == other.id;

  @override
  int get hashCode => id.hashCode;

  factory SectionFaculty.fromJson(Map<String, dynamic> json) {
    return SectionFaculty(
      id: json['id'] as String? ?? '',
      staffName: json['staffName'] as String? ?? '',
      shortName: json['shortName'] as String? ?? '',
      email: json['email'] as String? ?? '',
      imgUrl: json['imgUrl'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id,
      'staffName': staffName,
      'shortName': shortName,
      'email': email,
      'imgUrl': imgUrl,
    };
  }
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

class SectionSchedule {
  final String? finalExamDate;
  final String? finalExamStartTime;
  final String? finalExamEndTime;
  final String? midExamDate;
  final String? midExamStartTime;
  final String? midExamEndTime;
  final String? finalExamDetail;
  final String? midExamDetail;
  final String classStartDate;
  final String classEndDate;
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
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SectionSchedule &&
          classStartDate == other.classStartDate &&
          classEndDate == other.classEndDate &&
          classSchedules == other.classSchedules;

  @override
  int get hashCode => Object.hash(classStartDate, classEndDate, classSchedules);

  factory SectionSchedule.fromJson(Map<String, dynamic> json) {
    final list = json['classSchedules'] as List?;
    final classSchedulesList = list != null
        ? list
              .map((e) => ClassSchedule.fromJson(e as Map<String, dynamic>))
              .toList()
        : <ClassSchedule>[];

    return SectionSchedule(
      finalExamDate: json['finalExamDate'] as String?,
      finalExamStartTime: json['finalExamStartTime'] as String?,
      finalExamEndTime: json['finalExamEndTime'] as String?,
      midExamDate: json['midExamDate'] as String?,
      midExamStartTime: json['midExamStartTime'] as String?,
      midExamEndTime: json['midExamEndTime'] as String?,
      finalExamDetail: json['finalExamDetail'] as String?,
      midExamDetail: json['midExamDetail'] as String?,
      classStartDate: json['classStartDate'] as String? ?? '',
      classEndDate: json['classEndDate'] as String? ?? '',
      classSchedules: classSchedulesList,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'finalExamDate': finalExamDate,
      'finalExamStartTime': finalExamStartTime,
      'finalExamEndTime': finalExamEndTime,
      'midExamDate': midExamDate,
      'midExamStartTime': midExamStartTime,
      'midExamEndTime': midExamEndTime,
      'finalExamDetail': finalExamDetail,
      'midExamDetail': midExamDetail,
      'classStartDate': classStartDate,
      'classEndDate': classEndDate,
      'classSchedules': classSchedules.map((e) => e.toJson()).toList(),
    };
  }
}

class ClassSchedule {
  final String startTime;
  final String endTime;
  final String day;

  const ClassSchedule({
    required this.startTime,
    required this.endTime,
    required this.day,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ClassSchedule &&
          startTime == other.startTime &&
          endTime == other.endTime &&
          day == other.day;

  @override
  int get hashCode => Object.hash(startTime, endTime, day);

  factory ClassSchedule.fromJson(Map<String, dynamic> json) {
    return ClassSchedule(
      startTime: json['startTime'] as String? ?? '',
      endTime: json['endTime'] as String? ?? '',
      day: json['day'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'startTime': startTime,
      'endTime': endTime,
      'day': day,
    };
  }
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
