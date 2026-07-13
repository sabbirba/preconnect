// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'seat_status.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

SeatStatusSchedule _$SeatStatusScheduleFromJson(Map<String, dynamic> json) =>
    SeatStatusSchedule(
      classSchedules:
          (json['classSchedules'] as List<dynamic>?)
              ?.map(
                (e) =>
                    SeatStatusClassSchedule.fromJson(e as Map<String, dynamic>),
              )
              .toList() ??
          [],
      midExamDate: json['midExamDate'] as String?,
      midExamStartTime: json['midExamStartTime'] as String?,
      midExamEndTime: json['midExamEndTime'] as String?,
      finalExamDate: json['finalExamDate'] as String?,
      finalExamStartTime: json['finalExamStartTime'] as String?,
      finalExamEndTime: json['finalExamEndTime'] as String?,
    );

Map<String, dynamic> _$SeatStatusScheduleToJson(SeatStatusSchedule instance) =>
    <String, dynamic>{
      'classSchedules': instance.classSchedules,
      'midExamDate': instance.midExamDate,
      'midExamStartTime': instance.midExamStartTime,
      'midExamEndTime': instance.midExamEndTime,
      'finalExamDate': instance.finalExamDate,
      'finalExamStartTime': instance.finalExamStartTime,
      'finalExamEndTime': instance.finalExamEndTime,
    };

SeatStatusClassSchedule _$SeatStatusClassScheduleFromJson(
  Map<String, dynamic> json,
) => SeatStatusClassSchedule(
  day: json['day'] as String? ?? '',
  startTime: json['startTime'] as String? ?? '',
  endTime: json['endTime'] as String? ?? '',
);

Map<String, dynamic> _$SeatStatusClassScheduleToJson(
  SeatStatusClassSchedule instance,
) => <String, dynamic>{
  'day': instance.day,
  'startTime': instance.startTime,
  'endTime': instance.endTime,
};
