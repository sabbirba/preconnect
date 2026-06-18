// ignore: depend_on_referenced_packages
import 'package:json_annotation/json_annotation.dart';


part 'custom_schedule.g.dart';

@JsonSerializable()
class CustomSchedule {
  const CustomSchedule({
    required this.itemId,
    required this.kind,
    required this.title,
    required this.courseCode,
    required this.sectionName,
    required this.startTime,
    required this.endTime,
    required this.reminderAt,
    required this.notes,
    required this.isDone,
    required this.createdAt,
    required this.updatedAt,
  });

  final int itemId;
  final String kind;
  final String title;
  final String courseCode;
  final String sectionName;
  final DateTime startTime;
  final DateTime? endTime;
  final DateTime? reminderAt;
  final String notes;
  final bool isDone;
  final DateTime createdAt;
  final DateTime updatedAt;

  factory CustomSchedule.fromJson(Map<String, dynamic> json) =>
      _$CustomScheduleFromJson(json);

  Map<String, dynamic> toJson() => _$CustomScheduleToJson(this);

  CustomSchedule copyWith({
    String? kind,
    String? title,
    String? courseCode,
    String? sectionName,
    DateTime? startTime,
    DateTime? endTime,
    bool? clearEndTime,
    DateTime? reminderAt,
    bool? clearReminderAt,
    String? notes,
    bool? isDone,
  }) {
    return CustomSchedule(
      itemId: itemId,
      kind: kind ?? this.kind,
      title: title ?? this.title,
      courseCode: courseCode ?? this.courseCode,
      sectionName: sectionName ?? this.sectionName,
      startTime: startTime ?? this.startTime,
      endTime: clearEndTime == true ? null : endTime ?? this.endTime,
      reminderAt: clearReminderAt == true
          ? null
          : reminderAt ?? this.reminderAt,
      notes: notes ?? this.notes,
      isDone: isDone ?? this.isDone,
      createdAt: createdAt,
      updatedAt: DateTime.now().toUtc(),
    );
  }

  bool get isOverdue => !isDone && startTime.isBefore(DateTime.now());

  bool get isDueSoon {
    if (isDone) return false;
    final now = DateTime.now();
    return !startTime.isBefore(now) &&
        startTime.difference(now) <= const Duration(days: 2);
  }
}
