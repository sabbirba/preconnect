import 'package:json_annotation/json_annotation.dart';
import 'package:equatable/equatable.dart';

part 'calendar_info.g.dart';

@JsonSerializable()
class CalendarFeed extends Equatable {
  const CalendarFeed({
    required this.rangeStart,
    required this.rangeEnd,
    required this.sourceFingerprint,
    required this.items,
  });

  @JsonKey(defaultValue: '')
  final String rangeStart;
  @JsonKey(defaultValue: '')
  final String rangeEnd;
  @JsonKey(defaultValue: '')
  final String sourceFingerprint;
  @JsonKey(defaultValue: <CalendarEntry>[])
  final List<CalendarEntry> items;

  @override
  List<Object?> get props => [rangeStart, rangeEnd, sourceFingerprint, items];

  Map<String, dynamic> toJson() => _$CalendarFeedToJson(this);

  factory CalendarFeed.fromJson(Map<String, dynamic> json) =>
      _$CalendarFeedFromJson(json);
}

@JsonSerializable()
class CalendarEntry extends Equatable {
  const CalendarEntry({
    required this.id,
    required this.label,
    required this.typeKey,
    required this.date,
    required this.startDate,
    required this.endDate,
    required this.startTime,
    required this.endTime,
    required this.place,
    required this.isRepeatable,
    required this.isCancelled,
    required this.ref,
    required this.roomName,
    required this.roomNumber,
    required this.sessionLabel,
    required this.building,
    required this.faculty,
    required this.department,
    required this.actor,
  });

  @JsonKey(defaultValue: '')
  final String id;
  @JsonKey(defaultValue: '')
  final String label;
  @JsonKey(defaultValue: '')
  final String typeKey;
  @JsonKey(defaultValue: '')
  final String date;
  @JsonKey(defaultValue: '')
  final String startDate;
  @JsonKey(defaultValue: '')
  final String endDate;
  @JsonKey(defaultValue: '')
  final String startTime;
  @JsonKey(defaultValue: '')
  final String endTime;
  @JsonKey(defaultValue: '')
  final String place;
  @JsonKey(defaultValue: false)
  final bool isRepeatable;
  @JsonKey(defaultValue: false)
  final bool isCancelled;
  @JsonKey(defaultValue: '')
  final String ref;
  @JsonKey(defaultValue: '')
  final String roomName;
  @JsonKey(defaultValue: '')
  final String roomNumber;
  @JsonKey(defaultValue: '')
  final String sessionLabel;
  @JsonKey(defaultValue: '')
  final String building;
  @JsonKey(defaultValue: '')
  final String faculty;
  @JsonKey(defaultValue: '')
  final String department;
  @JsonKey(defaultValue: '')
  final String actor;

  String get primaryDate => date.isNotEmpty ? date : startDate;

  @override
  List<Object?> get props => [
    id,
    label,
    typeKey,
    date,
    startDate,
    endDate,
    startTime,
    endTime,
    place,
    isRepeatable,
    isCancelled,
    ref,
    roomName,
    roomNumber,
    sessionLabel,
    building,
    faculty,
    department,
    actor,
  ];

  Map<String, dynamic> toJson() => _$CalendarEntryToJson(this);

  factory CalendarEntry.fromJson(Map<String, dynamic> json) =>
      _$CalendarEntryFromJson(json);
}
