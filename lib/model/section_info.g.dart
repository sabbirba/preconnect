// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'section_info.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

SectionFaculty _$SectionFacultyFromJson(Map<String, dynamic> json) =>
    SectionFaculty(
      id: json['id'] as String? ?? '',
      staffName: json['staffName'] as String? ?? '',
      shortName: json['shortName'] as String? ?? '',
      email: json['email'] as String? ?? '',
      imgUrl: json['imgUrl'] as String?,
    );

Map<String, dynamic> _$SectionFacultyToJson(SectionFaculty instance) =>
    <String, dynamic>{
      'id': instance.id,
      'staffName': instance.staffName,
      'shortName': instance.shortName,
      'email': instance.email,
      'imgUrl': instance.imgUrl,
    };

SectionSchedule _$SectionScheduleFromJson(Map<String, dynamic> json) =>
    SectionSchedule(
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
      classSchedules:
          (json['classSchedules'] as List<dynamic>?)
              ?.map((e) => ClassSchedule.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
    );

Map<String, dynamic> _$SectionScheduleToJson(SectionSchedule instance) =>
    <String, dynamic>{
      'finalExamDate': instance.finalExamDate,
      'finalExamStartTime': instance.finalExamStartTime,
      'finalExamEndTime': instance.finalExamEndTime,
      'midExamDate': instance.midExamDate,
      'midExamStartTime': instance.midExamStartTime,
      'midExamEndTime': instance.midExamEndTime,
      'finalExamDetail': instance.finalExamDetail,
      'midExamDetail': instance.midExamDetail,
      'classStartDate': instance.classStartDate,
      'classEndDate': instance.classEndDate,
      'classSchedules': instance.classSchedules,
    };

ClassSchedule _$ClassScheduleFromJson(Map<String, dynamic> json) =>
    ClassSchedule(
      startTime: json['startTime'] as String? ?? '',
      endTime: json['endTime'] as String? ?? '',
      day: json['day'] as String? ?? '',
    );

Map<String, dynamic> _$ClassScheduleToJson(ClassSchedule instance) =>
    <String, dynamic>{
      'startTime': instance.startTime,
      'endTime': instance.endTime,
      'day': instance.day,
    };
