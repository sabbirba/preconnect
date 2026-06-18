// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'custom_schedule.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

CustomSchedule _$CustomScheduleFromJson(Map<String, dynamic> json) =>
    CustomSchedule(
      itemId: (json['itemId'] as num).toInt(),
      kind: json['kind'] as String,
      title: json['title'] as String,
      courseCode: json['courseCode'] as String,
      sectionName: json['sectionName'] as String,
      startTime: DateTime.parse(json['startTime'] as String),
      endTime: json['endTime'] == null
          ? null
          : DateTime.parse(json['endTime'] as String),
      reminderAt: json['reminderAt'] == null
          ? null
          : DateTime.parse(json['reminderAt'] as String),
      notes: json['notes'] as String,
      isDone: json['isDone'] as bool,
      createdAt: DateTime.parse(json['createdAt'] as String),
      updatedAt: DateTime.parse(json['updatedAt'] as String),
    );

Map<String, dynamic> _$CustomScheduleToJson(CustomSchedule instance) =>
    <String, dynamic>{
      'itemId': instance.itemId,
      'kind': instance.kind,
      'title': instance.title,
      'courseCode': instance.courseCode,
      'sectionName': instance.sectionName,
      'startTime': instance.startTime.toIso8601String(),
      'endTime': instance.endTime?.toIso8601String(),
      'reminderAt': instance.reminderAt?.toIso8601String(),
      'notes': instance.notes,
      'isDone': instance.isDone,
      'createdAt': instance.createdAt.toIso8601String(),
      'updatedAt': instance.updatedAt.toIso8601String(),
    };
