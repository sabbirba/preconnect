import 'dart:convert';

class SeatStatusDetailsResponse {
  SeatStatusDetailsResponse({
    required this.section,
    required this.childSection,
  });

  final SeatStatusSection section;
  final SeatStatusSection? childSection;

  factory SeatStatusDetailsResponse.fromJson(Map<String, dynamic> json) {
    final childSectionJson = _asStringDynamicMap(json['childSection']);
    return SeatStatusDetailsResponse(
      section: SeatStatusSection.fromJson(
        _asStringDynamicMap(json['section']) ?? const <String, dynamic>{},
      ),
      childSection: childSectionJson == null
          ? null
          : SeatStatusSection.fromJson(childSectionJson),
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'section': section.toJson(),
      'childSection': childSection?.toJson(),
    };
  }
}

class SeatStatusSection {
  SeatStatusSection({
    required this.sectionId,
    required this.courseCode,
    required this.sectionName,
    required this.name,
    required this.courseCredit,
    required this.capacity,
    required this.consumedSeat,
    required this.faculties,
    required this.roomName,
    required this.roomNumber,
    required this.sectionSchedule,
  });

  final int sectionId;
  final String courseCode;
  final String sectionName;
  final String name;
  final int courseCredit;
  final int capacity;
  final int consumedSeat;
  final String faculties;
  final String roomName;
  final String roomNumber;
  final SeatStatusSchedule sectionSchedule;

  factory SeatStatusSection.fromJson(Map<String, dynamic> json) {
    final rawSchedule = json['sectionSchedule'];
    final scheduleJson = switch (rawSchedule) {
      String s when s.trim().isNotEmpty =>
        _asStringDynamicMap(jsonDecode(s)) ?? const <String, dynamic>{},
      Map m => m.cast<String, dynamic>(),
      _ => const <String, dynamic>{},
    };

    return SeatStatusSection(
      sectionId: _toInt(json['sectionId']),
      courseCode: _toString(json['courseCode']),
      sectionName: _toString(json['sectionName']),
      name: _toString(json['name']),
      courseCredit: _toInt(json['courseCredit']),
      capacity: _toInt(json['capacity']),
      consumedSeat: _toInt(json['consumedSeat']),
      faculties: _toFacultyInitial(json),
      roomName: _toString(json['roomName']),
      roomNumber: _toString(json['roomNumber']),
      sectionSchedule: SeatStatusSchedule.fromJson(scheduleJson),
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'sectionId': sectionId,
      'courseCode': courseCode,
      'sectionName': sectionName,
      'name': name,
      'courseCredit': courseCredit,
      'capacity': capacity,
      'consumedSeat': consumedSeat,
      'faculties': faculties,
      'roomName': roomName,
      'roomNumber': roomNumber,
      'sectionSchedule': sectionSchedule.toJson(),
    };
  }
}

class SeatStatusSchedule {
  SeatStatusSchedule({
    required this.classSchedules,
    this.midExamDate,
    this.midExamStartTime,
    this.midExamEndTime,
    this.finalExamDate,
    this.finalExamStartTime,
    this.finalExamEndTime,
  });

  final List<SeatStatusClassSchedule> classSchedules;
  final String? midExamDate;
  final String? midExamStartTime;
  final String? midExamEndTime;
  final String? finalExamDate;
  final String? finalExamStartTime;
  final String? finalExamEndTime;

  factory SeatStatusSchedule.fromJson(Map<String, dynamic> json) {
    final rawSchedules = json['classSchedules'];
    final classSchedules = rawSchedules is List
        ? rawSchedules
              .whereType<Map>()
              .map(
                (item) => SeatStatusClassSchedule.fromJson(
                  item.cast<String, dynamic>(),
                ),
              )
              .toList()
        : const <SeatStatusClassSchedule>[];

    return SeatStatusSchedule(
      classSchedules: classSchedules,
      midExamDate: _toNullableString(json['midExamDate']),
      midExamStartTime: _toNullableString(json['midExamStartTime']),
      midExamEndTime: _toNullableString(json['midExamEndTime']),
      finalExamDate: _toNullableString(json['finalExamDate']),
      finalExamStartTime: _toNullableString(json['finalExamStartTime']),
      finalExamEndTime: _toNullableString(json['finalExamEndTime']),
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'classSchedules': classSchedules.map((e) => e.toJson()).toList(),
      'midExamDate': midExamDate,
      'midExamStartTime': midExamStartTime,
      'midExamEndTime': midExamEndTime,
      'finalExamDate': finalExamDate,
      'finalExamStartTime': finalExamStartTime,
      'finalExamEndTime': finalExamEndTime,
    };
  }
}

class SeatStatusClassSchedule {
  SeatStatusClassSchedule({
    required this.day,
    required this.startTime,
    required this.endTime,
  });

  final String day;
  final String startTime;
  final String endTime;

  factory SeatStatusClassSchedule.fromJson(Map<String, dynamic> json) {
    return SeatStatusClassSchedule(
      day: _toString(json['day']),
      startTime: _toString(json['startTime']),
      endTime: _toString(json['endTime']),
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'day': day,
      'startTime': startTime,
      'endTime': endTime,
    };
  }
}

class SeatStatusStaffInfo {
  const SeatStatusStaffInfo({
    required this.staffId,
    required this.shortName,
    required this.staffName,
    required this.email,
    required this.departmentId,
    required this.designationId,
  });

  final int staffId;
  final String shortName;
  final String staffName;
  final String email;
  final int? departmentId;
  final int? designationId;

  factory SeatStatusStaffInfo.fromJson(Map<String, dynamic> json) {
    return SeatStatusStaffInfo(
      staffId: int.tryParse('${json['staffId'] ?? 0}') ?? 0,
      shortName: '${json['shortName'] ?? ''}'.trim(),
      staffName: '${json['staffName'] ?? ''}'.trim(),
      email: '${json['email'] ?? ''}'.trim(),
      departmentId: int.tryParse('${json['departmentId'] ?? ''}'),
      designationId: int.tryParse('${json['designationId'] ?? ''}'),
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'staffId': staffId,
      'shortName': shortName,
      'staffName': staffName,
      'email': email,
      'departmentId': departmentId,
      'designationId': designationId,
    };
  }
}

class SeatAlertConfig {
  const SeatAlertConfig({
    required this.sectionId,
    this.notifyOnAvailable = false,
    this.availableOneTime = true,
    this.thresholdSeats,
    this.thresholdOneTime = true,
    this.notifyOnAnyChange = false,
    this.changeCooldownMinutes = 0,
    this.lastChangeNotifiedAtMs,
  });

  final int sectionId;
  final bool notifyOnAvailable;
  final bool availableOneTime;
  final int? thresholdSeats;
  final bool thresholdOneTime;
  final bool notifyOnAnyChange;
  final int changeCooldownMinutes;
  final int? lastChangeNotifiedAtMs;

  bool get hasAnyRule =>
      notifyOnAvailable || thresholdSeats != null || notifyOnAnyChange;

  factory SeatAlertConfig.fromJson(int sectionId, Map<String, dynamic> json) {
    return SeatAlertConfig(
      sectionId: sectionId,
      notifyOnAvailable: json['notifyOnAvailable'] == true,
      availableOneTime: json['availableOneTime'] != false,
      thresholdSeats: int.tryParse('${json['thresholdSeats'] ?? ''}'),
      thresholdOneTime: json['thresholdOneTime'] != false,
      notifyOnAnyChange: json['notifyOnAnyChange'] == true,
      changeCooldownMinutes:
          int.tryParse('${json['changeCooldownMinutes'] ?? ''}') ?? 0,
      lastChangeNotifiedAtMs: int.tryParse(
        '${json['lastChangeNotifiedAtMs'] ?? ''}',
      ),
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'notifyOnAvailable': notifyOnAvailable,
      'availableOneTime': availableOneTime,
      'thresholdSeats': thresholdSeats,
      'thresholdOneTime': thresholdOneTime,
      'notifyOnAnyChange': notifyOnAnyChange,
      'changeCooldownMinutes': changeCooldownMinutes,
      'lastChangeNotifiedAtMs': lastChangeNotifiedAtMs,
    };
  }

  SeatAlertConfig copyWith({
    bool? notifyOnAvailable,
    bool? availableOneTime,
    Object? thresholdSeats = _seatAlertSentinel,
    bool? thresholdOneTime,
    bool? notifyOnAnyChange,
    int? changeCooldownMinutes,
    Object? lastChangeNotifiedAtMs = _seatAlertSentinel,
  }) {
    return SeatAlertConfig(
      sectionId: sectionId,
      notifyOnAvailable: notifyOnAvailable ?? this.notifyOnAvailable,
      availableOneTime: availableOneTime ?? this.availableOneTime,
      thresholdSeats: identical(thresholdSeats, _seatAlertSentinel)
          ? this.thresholdSeats
          : thresholdSeats as int?,
      thresholdOneTime: thresholdOneTime ?? this.thresholdOneTime,
      notifyOnAnyChange: notifyOnAnyChange ?? this.notifyOnAnyChange,
      changeCooldownMinutes:
          changeCooldownMinutes ?? this.changeCooldownMinutes,
      lastChangeNotifiedAtMs:
          identical(lastChangeNotifiedAtMs, _seatAlertSentinel)
          ? this.lastChangeNotifiedAtMs
          : lastChangeNotifiedAtMs as int?,
    );
  }
}

const Object _seatAlertSentinel = Object();

int _toInt(dynamic value) {
  if (value is int) return value;
  return int.tryParse('$value') ?? 0;
}

String _toString(dynamic value) {
  if (value == null) return '';
  return '$value'.trim();
}

Map<String, dynamic>? _asStringDynamicMap(dynamic value) {
  if (value is Map<String, dynamic>) return value;
  if (value is Map) return value.cast<String, dynamic>();
  return null;
}

String? _toNullableString(dynamic value) {
  final parsed = _toString(value);
  if (parsed.isEmpty || parsed.toUpperCase() == 'NULL') return null;
  return parsed;
}

String _toFacultyInitial(Map<String, dynamic> json) {
  const directKeys = <String>[
    'faculties',
    'faculty',
    'facultyInitial',
    'instructorInitial',
    'teacherInitial',
    'shortName',
    'initial',
  ];
  for (final key in directKeys) {
    final value = _toString(json[key]);
    if (_isMeaningfulFacultyToken(value)) return value;
  }

  const listKeys = <String>[
    'facultyDetails',
    'facultyProfiles',
    'instructors',
    'teachers',
    'sectionFacultyProfiles',
  ];
  for (final key in listKeys) {
    final raw = json[key];
    if (raw is! List) continue;
    for (final item in raw.whereType<Map>()) {
      final map = item.cast<dynamic, dynamic>();
      for (final tokenKey in directKeys) {
        final value = _toString(map[tokenKey]);
        if (_isMeaningfulFacultyToken(value)) return value;
      }
    }
  }
  return 'TBA';
}

bool _isMeaningfulFacultyToken(String value) {
  if (value.isEmpty) return false;
  final normalized = value.trim().toUpperCase();
  if (normalized == 'NULL') return false;
  if (normalized == 'N/A') return false;
  if (normalized == 'TBA') return false;
  if (normalized == '--') return false;
  return true;
}
