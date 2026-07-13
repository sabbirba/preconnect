// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'calendar_info.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

CalendarFeed _$CalendarFeedFromJson(Map<String, dynamic> json) => CalendarFeed(
  rangeStart: json['rangeStart'] as String? ?? '',
  rangeEnd: json['rangeEnd'] as String? ?? '',
  sourceFingerprint: json['sourceFingerprint'] as String? ?? '',
  items:
      (json['items'] as List<dynamic>?)
          ?.map((e) => CalendarEntry.fromJson(e as Map<String, dynamic>))
          .toList() ??
      [],
);

Map<String, dynamic> _$CalendarFeedToJson(CalendarFeed instance) =>
    <String, dynamic>{
      'rangeStart': instance.rangeStart,
      'rangeEnd': instance.rangeEnd,
      'sourceFingerprint': instance.sourceFingerprint,
      'items': instance.items,
    };

CalendarEntry _$CalendarEntryFromJson(Map<String, dynamic> json) =>
    CalendarEntry(
      id: json['id'] as String? ?? '',
      label: json['label'] as String? ?? '',
      typeKey: json['typeKey'] as String? ?? '',
      date: json['date'] as String? ?? '',
      startDate: json['startDate'] as String? ?? '',
      endDate: json['endDate'] as String? ?? '',
      startTime: json['startTime'] as String? ?? '',
      endTime: json['endTime'] as String? ?? '',
      place: json['place'] as String? ?? '',
      isRepeatable: json['isRepeatable'] as bool? ?? false,
      isCancelled: json['isCancelled'] as bool? ?? false,
      ref: json['ref'] as String? ?? '',
      roomName: json['roomName'] as String? ?? '',
      roomNumber: json['roomNumber'] as String? ?? '',
      sessionLabel: json['sessionLabel'] as String? ?? '',
      building: json['building'] as String? ?? '',
      faculty: json['faculty'] as String? ?? '',
      department: json['department'] as String? ?? '',
      actor: json['actor'] as String? ?? '',
    );

Map<String, dynamic> _$CalendarEntryToJson(CalendarEntry instance) =>
    <String, dynamic>{
      'id': instance.id,
      'label': instance.label,
      'typeKey': instance.typeKey,
      'date': instance.date,
      'startDate': instance.startDate,
      'endDate': instance.endDate,
      'startTime': instance.startTime,
      'endTime': instance.endTime,
      'place': instance.place,
      'isRepeatable': instance.isRepeatable,
      'isCancelled': instance.isCancelled,
      'ref': instance.ref,
      'roomName': instance.roomName,
      'roomNumber': instance.roomNumber,
      'sessionLabel': instance.sessionLabel,
      'building': instance.building,
      'faculty': instance.faculty,
      'department': instance.department,
      'actor': instance.actor,
    };
