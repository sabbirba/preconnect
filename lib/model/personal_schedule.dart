class PersonalSchedule {
  const PersonalSchedule({
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

  factory PersonalSchedule.fromJson(Map<String, dynamic> json) {
    return PersonalSchedule(
      itemId: (json['itemId'] as num?)?.toInt() ?? 0,
      kind: (json['kind'] as String? ?? '').trim().toLowerCase(),
      title: (json['title'] as String? ?? '').trim(),
      courseCode: (json['courseCode'] as String? ?? '').trim(),
      sectionName: (json['sectionName'] as String? ?? '').trim(),
      startTime:
          DateTime.tryParse((json['startTime'] as String? ?? '').trim()) ??
          DateTime.fromMillisecondsSinceEpoch(0),
      endTime: DateTime.tryParse((json['endTime'] as String? ?? '').trim()),
      reminderAt: DateTime.tryParse(
        (json['reminderAt'] as String? ?? '').trim(),
      ),
      notes: (json['notes'] as String? ?? '').trim(),
      isDone: json['isDone'] == true,
      createdAt:
          DateTime.tryParse((json['createdAt'] as String? ?? '').trim()) ??
          DateTime.fromMillisecondsSinceEpoch(0),
      updatedAt:
          DateTime.tryParse((json['updatedAt'] as String? ?? '').trim()) ??
          DateTime.fromMillisecondsSinceEpoch(0),
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'itemId': itemId,
      'kind': kind,
      'title': title,
      'courseCode': courseCode,
      'sectionName': sectionName,
      'startTime': startTime.toUtc().toIso8601String(),
      'endTime': endTime?.toUtc().toIso8601String(),
      'reminderAt': reminderAt?.toUtc().toIso8601String(),
      'notes': notes,
      'isDone': isDone,
      'createdAt': createdAt.toUtc().toIso8601String(),
      'updatedAt': updatedAt.toUtc().toIso8601String(),
    };
  }

  PersonalSchedule copyWith({
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
    return PersonalSchedule(
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
