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

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CustomSchedule &&
          itemId == other.itemId &&
          updatedAt == other.updatedAt;

  @override
  int get hashCode => Object.hash(itemId, updatedAt);

  factory CustomSchedule.fromJson(Map<String, dynamic> json) {
    return CustomSchedule(
      itemId: json['itemId'] as int? ?? 0,
      kind: json['kind'] as String? ?? '',
      title: json['title'] as String? ?? '',
      courseCode: json['courseCode'] as String? ?? '',
      sectionName: json['sectionName'] as String? ?? '',
      startTime: DateTime.parse(json['startTime'] as String),
      endTime: json['endTime'] != null
          ? DateTime.parse(json['endTime'] as String)
          : null,
      reminderAt: json['reminderAt'] != null
          ? DateTime.parse(json['reminderAt'] as String)
          : null,
      notes: json['notes'] as String? ?? '',
      isDone: json['isDone'] as bool? ?? false,
      createdAt: DateTime.parse(json['createdAt'] as String),
      updatedAt: DateTime.parse(json['updatedAt'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'itemId': itemId,
      'kind': kind,
      'title': title,
      'courseCode': courseCode,
      'sectionName': sectionName,
      'startTime': startTime.toIso8601String(),
      'endTime': endTime?.toIso8601String(),
      'reminderAt': reminderAt?.toIso8601String(),
      'notes': notes,
      'isDone': isDone,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
    };
  }

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
