import 'dart:convert';

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
  final String sectionType;
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
    required this.sectionType,
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
      sectionId: json['sectionId'],
      advisingSectionId: json['advisingSectionId'],
      parentSectionId: json['parentSectionId'],
      courseId: json['courseId'],
      courseCode: json['courseCode'],
      name: json['name'],
      sectionName: json['sectionName'],
      semesterSessionId: json['semesterSessionId'],
      courseCredit: json['courseCredit'],
      studentPortfolioId: json['studentPortfolioId'],
      capacity: json['capacity'],
      consumedSeat: json['consumedSeat'],
      sectionSchedule: SectionSchedule.fromJson(
        jsonDecode(json['sectionSchedule']),
      ),
      sectionType: json['sectionType'],
      faculties: json['faculties'],
      roomName: json['roomName'],
      roomNumber: json['roomNumber'],
      prerequisiteCourses: json['prerequisiteCourses'],
      isReserve: json['isReserve'],
      courseType: json['courseType'],
      prerequisiteIncompleteGrade: json['prerequisiteIncompleteGrade'],
      prerequisiteResultPublished: json['prerequisiteResultPublished'],
    );
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

  SectionSchedule({
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

  factory SectionSchedule.fromJson(Map<String, dynamic> json) {
    return SectionSchedule(
      finalExamDate: json['finalExamDate'],
      finalExamStartTime: json['finalExamStartTime'],
      finalExamEndTime: json['finalExamEndTime'],
      midExamDate: json['midExamDate'],
      midExamStartTime: json['midExamStartTime'],
      midExamEndTime: json['midExamEndTime'],
      finalExamDetail: json['finalExamDetail'],
      midExamDetail: json['midExamDetail'],
      classStartDate: json['classStartDate'],
      classEndDate: json['classEndDate'],
      classSchedules: (json['classSchedules'] as List)
          .map((e) => ClassSchedule.fromJson(e))
          .toList(),
    );
  }
}

class ClassSchedule {
  final String startTime;
  final String endTime;
  final String day;

  ClassSchedule({
    required this.startTime,
    required this.endTime,
    required this.day,
  });

  factory ClassSchedule.fromJson(Map<String, dynamic> json) {
    return ClassSchedule(
      startTime: json['startTime'],
      endTime: json['endTime'],
      day: json['day'],
    );
  }
}
