
class CalendarFeed {
  const CalendarFeed({
    required this.rangeStart,
    required this.rangeEnd,
    required this.sourceFingerprint,
    required this.items,
  });

  final String rangeStart;
  final String rangeEnd;
  final String sourceFingerprint;
  final List<CalendarEntry> items;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CalendarFeed &&
          rangeStart == other.rangeStart &&
          rangeEnd == other.rangeEnd &&
          sourceFingerprint == other.sourceFingerprint;

  @override
  int get hashCode => Object.hash(rangeStart, rangeEnd, sourceFingerprint);

  factory CalendarFeed.fromJson(Map<String, dynamic> json) {
    final list = json['items'] as List?;
    final itemsList = list != null
        ? list
              .map((e) => CalendarEntry.fromJson(e as Map<String, dynamic>))
              .toList()
        : <CalendarEntry>[];

    return CalendarFeed(
      rangeStart: json['rangeStart'] as String? ?? '',
      rangeEnd: json['rangeEnd'] as String? ?? '',
      sourceFingerprint: json['sourceFingerprint'] as String? ?? '',
      items: itemsList,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'rangeStart': rangeStart,
      'rangeEnd': rangeEnd,
      'sourceFingerprint': sourceFingerprint,
      'items': items.map((e) => e.toJson()).toList(),
    };
  }
}

class CalendarEntry {
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

  final String id;
  final String label;
  final String typeKey;
  final String date;
  final String startDate;
  final String endDate;
  final String startTime;
  final String endTime;
  final String place;
  final bool isRepeatable;
  final bool isCancelled;
  final String ref;
  final String roomName;
  final String roomNumber;
  final String sessionLabel;
  final String building;
  final String faculty;
  final String department;
  final String actor;

  String get primaryDate => date.isNotEmpty ? date : startDate;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CalendarEntry &&
          id == other.id &&
          typeKey == other.typeKey &&
          date == other.date &&
          startTime == other.startTime &&
          endTime == other.endTime;

  @override
  int get hashCode => Object.hash(id, typeKey, date, startTime, endTime);

  factory CalendarEntry.fromJson(Map<String, dynamic> json) {
    return CalendarEntry(
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
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id,
      'label': label,
      'typeKey': typeKey,
      'date': date,
      'startDate': startDate,
      'endDate': endDate,
      'startTime': startTime,
      'endTime': endTime,
      'place': place,
      'isRepeatable': isRepeatable,
      'isCancelled': isCancelled,
      'ref': ref,
      'roomName': roomName,
      'roomNumber': roomNumber,
      'sessionLabel': sessionLabel,
      'building': building,
      'faculty': faculty,
      'department': department,
      'actor': actor,
    };
  }
}
