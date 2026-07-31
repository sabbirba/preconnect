part of '../free_labs.dart';

class _OccupiedClass {
  const _OccupiedClass({
    required this.courseCode,
    required this.sectionName,
    required this.facultyInitial,
    required this.startTime,
    required this.endTime,
    required this.roomNumber,
    required this.consumedSeat,
    required this.courseType,
  });

  final String courseCode;
  final String sectionName;
  final String facultyInitial;
  final String startTime;
  final String endTime;
  final String roomNumber;
  final int consumedSeat;
  final String courseType;
}

class _FreeRoomSlot {
  const _FreeRoomSlot({
    required this.roomNumber,
    required this.roomName,
    required this.courseTitlesLabel,
    required this.dominantProgramCode,
    required this.startTime,
    required this.endTime,
    required this.statusLabel,
    required this.occupiedClasses,
  });

  final String roomNumber;
  final String roomName;
  final String courseTitlesLabel;
  final String dominantProgramCode;
  final String startTime;
  final String endTime;
  final String statusLabel;
  final List<_OccupiedClass> occupiedClasses;
}

class _BusySlotDetails {
  const _BusySlotDetails({
    required this.start,
    required this.end,
    required this.courseCode,
    required this.sectionName,
    required this.facultyInitial,
    required this.roomNumber,
    required this.consumedSeat,
    required this.courseType,
  });

  final TimeOfDay start;
  final TimeOfDay end;
  final String courseCode;
  final String sectionName;
  final String facultyInitial;
  final String roomNumber;
  final int consumedSeat;
  final String courseType;
}

class _RoomSeed {
  _RoomSeed({required this.roomNumber, required this.roomName});

  final String roomNumber;
  final String roomName;
  final Map<String, int> programCounts = <String, int>{};
  final List<_BusySlotDetails> busySlots = <_BusySlotDetails>[];
  final Set<String> courseTitles = <String>{};
}

class _TimeSlot {
  const _TimeSlot({required this.start, required this.end});

  final TimeOfDay start;
  final TimeOfDay end;
}

class _FreeRoomTime {
  static TimeOfDay parse(String value) {
    final parsed = BracuTime.parseTime(value);
    if (parsed != null) {
      return TimeOfDay(hour: parsed.hour, minute: parsed.minute);
    }
    return const TimeOfDay(hour: 0, minute: 0);
  }
}

enum _RoomFilter {
  classes('Classes'),
  labs('Labs'),
  theater('Theaters');

  const _RoomFilter(this.label);

  final String label;
}
