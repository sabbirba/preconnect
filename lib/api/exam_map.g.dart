// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'exam_map.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

ExamScheduleOverride _$ExamScheduleOverrideFromJson(
  Map<String, dynamic> json,
) => ExamScheduleOverride(
  midDate: json['midDate'] as String?,
  midStartTime: json['midStartTime'] as String?,
  midEndTime: json['midEndTime'] as String?,
  midRoomNumber: json['midRoomNumber'] as String?,
  finalDate: json['finalDate'] as String?,
  finalStartTime: json['finalStartTime'] as String?,
  finalEndTime: json['finalEndTime'] as String?,
  finalRoomNumber: json['finalRoomNumber'] as String?,
);

Map<String, dynamic> _$ExamScheduleOverrideToJson(
  ExamScheduleOverride instance,
) => <String, dynamic>{
  'midDate': instance.midDate,
  'midStartTime': instance.midStartTime,
  'midEndTime': instance.midEndTime,
  'midRoomNumber': instance.midRoomNumber,
  'finalDate': instance.finalDate,
  'finalStartTime': instance.finalStartTime,
  'finalEndTime': instance.finalEndTime,
  'finalRoomNumber': instance.finalRoomNumber,
};
