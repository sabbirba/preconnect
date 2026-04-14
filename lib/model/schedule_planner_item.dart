class SchedulePlannerItem {
  const SchedulePlannerItem({
    required this.itemId,
    required this.kind,
    required this.title,
    required this.courseCode,
    required this.sectionName,
    required this.dueAt,
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
  final DateTime dueAt;
  final DateTime? reminderAt;
  final String notes;
  final bool isDone;
  final DateTime createdAt;
  final DateTime updatedAt;

  factory SchedulePlannerItem.fromJson(Map<String, dynamic> json) {
    return SchedulePlannerItem(
      itemId: (json['itemId'] as num?)?.toInt() ?? 0,
      kind: (json['kind'] as String? ?? '').trim().toLowerCase(),
      title: (json['title'] as String? ?? '').trim(),
      courseCode: (json['courseCode'] as String? ?? '').trim(),
      sectionName: (json['sectionName'] as String? ?? '').trim(),
      dueAt:
          DateTime.tryParse((json['dueAt'] as String? ?? '').trim()) ??
          DateTime.fromMillisecondsSinceEpoch(0),
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
      'dueAt': dueAt.toUtc().toIso8601String(),
      'reminderAt': reminderAt?.toUtc().toIso8601String(),
      'notes': notes,
      'isDone': isDone,
      'createdAt': createdAt.toUtc().toIso8601String(),
      'updatedAt': updatedAt.toUtc().toIso8601String(),
    };
  }

  SchedulePlannerItem copyWith({
    String? kind,
    String? title,
    String? courseCode,
    String? sectionName,
    DateTime? dueAt,
    DateTime? reminderAt,
    bool? clearReminderAt,
    String? notes,
    bool? isDone,
  }) {
    return SchedulePlannerItem(
      itemId: itemId,
      kind: kind ?? this.kind,
      title: title ?? this.title,
      courseCode: courseCode ?? this.courseCode,
      sectionName: sectionName ?? this.sectionName,
      dueAt: dueAt ?? this.dueAt,
      reminderAt: clearReminderAt == true
          ? null
          : reminderAt ?? this.reminderAt,
      notes: notes ?? this.notes,
      isDone: isDone ?? this.isDone,
      createdAt: createdAt,
      updatedAt: DateTime.now().toUtc(),
    );
  }

  bool get isOverdue => !isDone && dueAt.isBefore(DateTime.now());

  bool get isDueSoon {
    if (isDone) return false;
    final now = DateTime.now();
    return !dueAt.isBefore(now) &&
        dueAt.difference(now) <= const Duration(days: 2);
  }
}
