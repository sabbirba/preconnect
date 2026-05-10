import 'package:flutter/material.dart';
import 'package:preconnect/api/seat_status_service.dart';
import 'package:preconnect/pages/ui_kit.dart';
import 'package:preconnect/tools/time_utils.dart';

class FreeLabsRoomBuilder {
  const FreeLabsRoomBuilder();

  List<FreeRoomSlot> buildSlots(
    List<SeatStatusDetailsResponse> details, {
    required String day,
  }) {
    final grouped = <String, _RoomSeed>{};
    final seenBusyKeys = <String>{};

    for (final detailsEntry in details) {
      _seedRoomOccupancy(
        grouped: grouped,
        seenBusyKeys: seenBusyKeys,
        roomNumber: detailsEntry.roomNumber,
        roomName: detailsEntry.roomName,
        courseCode: detailsEntry.courseCode,
        courseTitle: detailsEntry.courseName,
        schedules: detailsEntry.sectionSchedule.classSchedules,
        day: day,
      );
      if (detailsEntry.labRoomName != null &&
          detailsEntry.labRoomName!.trim().isNotEmpty) {
        _seedRoomOccupancy(
          grouped: grouped,
          seenBusyKeys: seenBusyKeys,
          roomNumber: detailsEntry.labRoomName!,
          roomName: detailsEntry.labName ?? detailsEntry.labRoomName!,
          courseCode: detailsEntry.labCourseCode ?? '',
          courseTitle: detailsEntry.labName ?? detailsEntry.labCourseCode ?? '',
          schedules: detailsEntry.labSchedules,
          day: day,
        );
      }
    }

    final slots = <FreeRoomSlot>[];
    for (final room in grouped.values) {
      final freeSlots = _freeWithinDay(_mergeSlots(room.busySlots));
      for (final free in freeSlots) {
        slots.add(
          FreeRoomSlot(
            roomNumber: room.roomNumber,
            roomName: room.roomName.isEmpty ? 'Room' : room.roomName,
            courseTitlesLabel: (room.courseTitles.toList()..sort()).join(', '),
            dominantProgramCode: _dominantProgramCode(room),
            startTime: _formatTimeOfDay(free.start),
            endTime: _formatTimeOfDay(free.end),
            statusLabel: _statusLabel(free.start, free.end),
          ),
        );
      }
    }

    slots.sort((a, b) {
      final startCompare = (_minutesFromString(a.startTime) ?? 0).compareTo(
        _minutesFromString(b.startTime) ?? 0,
      );
      if (startCompare != 0) return startCompare;
      return a.roomNumber.compareTo(b.roomNumber);
    });
    return slots;
  }

  Map<String, List<FreeRoomSlot>> groupByTime(List<FreeRoomSlot> slots) {
    final groupedSlots = <String, List<FreeRoomSlot>>{};
    for (final slot in slots) {
      final key = '${slot.startTime}|${slot.endTime}';
      groupedSlots.putIfAbsent(key, () => <FreeRoomSlot>[]).add(slot);
    }
    return groupedSlots;
  }

  int? highlightIndex(List<FreeRoomSlot> slots) {
    if (slots.isEmpty) return null;
    final nowMinutes = _minutesOfDay(TimeOfDay.now());
    for (var i = 0; i < slots.length; i++) {
      final slot = slots[i];
      final start = _minutesFromString(slot.startTime);
      final end = _minutesFromString(slot.endTime);
      if (start != null &&
          end != null &&
          nowMinutes >= start &&
          nowMinutes < end) {
        return i;
      }
    }
    for (var i = 0; i < slots.length; i++) {
      final start = _minutesFromString(slots[i].startTime);
      if (start != null && nowMinutes < start) return i;
    }
    return 0;
  }

  List<FreeRoomSlot> visibleSlots(
    List<FreeRoomSlot> roomSlots, {
    required bool futureDate,
  }) {
    if (futureDate) return roomSlots;
    final nowMinutes = _minutesOfDay(TimeOfDay.now());
    return roomSlots.where((item) {
      final end = _minutesFromString(item.endTime);
      return end != null && end > nowMinutes;
    }).toList();
  }

  bool matchesFilter(String roomNumber, RoomFilter filter) {
    final suffix = _roomSuffix(roomNumber);
    if (suffix.isEmpty) return false;
    return switch (filter) {
      RoomFilter.classes => suffix.endsWith('C'),
      RoomFilter.labs => suffix.endsWith('L'),
      RoomFilter.theater => suffix.endsWith('T'),
    };
  }

  bool isGreenProgram(FreeRoomSlot slot) {
    final program = slot.dominantProgramCode.trim().toUpperCase();
    final isLab = _roomSuffix(slot.roomNumber).endsWith('L');
    return isLab && (program == 'CSE' || program == 'EEE');
  }

  String roomTypeLabel(String roomNumber) {
    final suffix = _roomSuffix(roomNumber);
    if (suffix.endsWith('L')) return 'Lab Room';
    if (suffix.endsWith('T')) return 'Theater Room';
    if (suffix.endsWith('C')) return 'Class Room';
    return 'Room';
  }

  String roomTypeShortLabel(String roomNumber) {
    final suffix = _roomSuffix(roomNumber);
    if (suffix.endsWith('L')) return 'Lab';
    if (suffix.endsWith('T')) return 'Theater';
    if (suffix.endsWith('C')) return 'Class';
    return '';
  }

  String roomHeaderSubtitle(FreeRoomSlot slot) {
    final parts = <String>[];
    final roomName = slot.roomName.trim();
    if (roomName.isNotEmpty && roomName != slot.roomNumber.trim()) {
      parts.add(roomName);
    }
    final courses = slot.courseTitlesLabel.trim();
    if (courses.isNotEmpty) {
      parts.add(courses);
    }
    return parts.join(' • ');
  }

  String roomProgramLabel(FreeRoomSlot slot) {
    final program = slot.dominantProgramCode.trim().toUpperCase();
    if (program.isEmpty) {
      return slot.roomName;
    }
    return program;
  }

  String roomProgramLabelForSpan(FreeRoomSlot slot) {
    final program = roomProgramLabel(slot);
    final roomType = roomTypeShortLabel(slot.roomNumber);
    if (program == slot.roomName || roomType.isEmpty) {
      return program;
    }
    return '$program $roomType';
  }

  String roomTimelineLabel({
    required bool viewingFutureDate,
    required String activeDayName,
  }) {
    if (viewingFutureDate) {
      return formatWeekdayTitle(activeDayName);
    }
    return 'Today';
  }

  Color roomCardHighlightColor(FreeRoomSlot slot) {
    return isGreenProgram(slot)
        ? const Color(0xFF22C55E)
        : const Color(0xFF1E6BE3);
  }

  String displayRoomTitle(FreeRoomSlot slot) {
    return '${slot.roomNumber} • ${roomTypeLabel(slot.roomNumber)}';
  }

  String _roomSuffix(String roomNumber) {
    return roomNumber.trim().toUpperCase();
  }

  void _seedRoomOccupancy({
    required Map<String, _RoomSeed> grouped,
    required Set<String> seenBusyKeys,
    required String roomNumber,
    required String roomName,
    required String courseCode,
    required String courseTitle,
    required List<SeatStatusClassSchedule> schedules,
    required String day,
  }) {
    final normalizedRoomNumber = roomNumber.trim();
    if (normalizedRoomNumber.isEmpty || schedules.isEmpty) return;
    final room = grouped.putIfAbsent(
      normalizedRoomNumber,
      () => _RoomSeed(
        roomNumber: normalizedRoomNumber,
        roomName: roomName.trim(),
      ),
    );
    final normalizedCourseCode = courseCode.trim().toUpperCase();
    if (normalizedCourseCode.isNotEmpty) {
      final program = _courseProgramCode(normalizedCourseCode);
      if (program.isNotEmpty) {
        room.programCounts[program] = (room.programCounts[program] ?? 0) + 1;
      }
    }
    final normalizedCourseTitle = courseTitle.trim();
    if (normalizedCourseTitle.isNotEmpty && normalizedCourseCode.isNotEmpty) {
      room.courseTitles.add('$normalizedCourseTitle ($normalizedCourseCode)');
    } else if (normalizedCourseTitle.isNotEmpty) {
      room.courseTitles.add(normalizedCourseTitle);
    } else if (normalizedCourseCode.isNotEmpty) {
      room.courseTitles.add(normalizedCourseCode);
    }
    for (final slot in schedules) {
      if (_normalizeDay(slot.day) != day) continue;
      final key =
          '$normalizedRoomNumber|${slot.day}|${slot.startTime}|${slot.endTime}';
      if (!seenBusyKeys.add(key)) continue;
      room.busySlots.add(
        _TimeSlot.fromStrings(startTime: slot.startTime, endTime: slot.endTime),
      );
    }
  }

  String _dominantProgramCode(_RoomSeed room) {
    if (room.programCounts.isEmpty) return '';
    final sorted = room.programCounts.entries.toList()
      ..sort((a, b) {
        final countCompare = b.value.compareTo(a.value);
        if (countCompare != 0) return countCompare;
        return a.key.compareTo(b.key);
      });
    return sorted.first.key;
  }

  String _courseProgramCode(String courseCode) {
    final match = RegExp(
      r'^[A-Z]+',
    ).firstMatch(courseCode.trim().toUpperCase());
    return match?.group(0) ?? '';
  }

  String _normalizeDay(String value) {
    final trimmed = value.trim().toLowerCase();
    if (trimmed.isEmpty) return '';
    return trimmed[0].toUpperCase() + trimmed.substring(1);
  }

  List<_TimeSlot> _mergeSlots(List<_TimeSlot> slots) {
    if (slots.isEmpty) return const <_TimeSlot>[];
    final sorted = [
      ...slots,
    ]..sort((a, b) => _minutesOfDay(a.start).compareTo(_minutesOfDay(b.start)));
    final merged = <_TimeSlot>[];
    for (final slot in sorted) {
      if (merged.isEmpty) {
        merged.add(slot);
        continue;
      }
      final last = merged.last;
      if (_minutesOfDay(slot.start) <= _minutesOfDay(last.end)) {
        if (_minutesOfDay(slot.end) > _minutesOfDay(last.end)) {
          merged[merged.length - 1] = _TimeSlot(
            start: last.start,
            end: slot.end,
          );
        }
      } else {
        merged.add(slot);
      }
    }
    return merged;
  }

  List<_TimeSlot> _freeWithinDay(List<_TimeSlot> busy) {
    const dayStart = TimeOfDay(hour: 8, minute: 0);
    const dayEnd = TimeOfDay(hour: 20, minute: 0);
    if (busy.isEmpty) {
      return const <_TimeSlot>[_TimeSlot(start: dayStart, end: dayEnd)];
    }
    final free = <_TimeSlot>[];
    var current = dayStart;
    for (final slot in busy) {
      if (_minutesOfDay(current) < _minutesOfDay(slot.start)) {
        free.add(_TimeSlot(start: current, end: slot.start));
      }
      if (_minutesOfDay(slot.end) > _minutesOfDay(current)) {
        current = slot.end;
      }
    }
    if (_minutesOfDay(current) < _minutesOfDay(dayEnd)) {
      free.add(_TimeSlot(start: current, end: dayEnd));
    }
    return free
        .where((slot) => _minutesOfDay(slot.start) < _minutesOfDay(slot.end))
        .toList();
  }

  String _statusLabel(TimeOfDay start, TimeOfDay end) {
    final nowMinutes = _minutesOfDay(TimeOfDay.now());
    final startMinutes = _minutesOfDay(start);
    final endMinutes = _minutesOfDay(end);
    if (nowMinutes >= startMinutes && nowMinutes < endMinutes) {
      return 'Available';
    }
    if (nowMinutes < startMinutes) {
      return 'Upcoming';
    }
    return '';
  }

  int _minutesOfDay(TimeOfDay time) => time.hour * 60 + time.minute;

  int? _minutesFromString(String value) => BracuTime.toMinutes(value);

  String _formatTimeOfDay(TimeOfDay time) {
    final normalizedHour = time.hourOfPeriod == 0 ? 12 : time.hourOfPeriod;
    final minute = time.minute.toString().padLeft(2, '0');
    final suffix = time.period == DayPeriod.am ? 'AM' : 'PM';
    return '$normalizedHour:$minute $suffix';
  }
}

class FreeRoomSlot {
  const FreeRoomSlot({
    required this.roomNumber,
    required this.roomName,
    required this.courseTitlesLabel,
    required this.dominantProgramCode,
    required this.startTime,
    required this.endTime,
    required this.statusLabel,
  });

  final String roomNumber;
  final String roomName;
  final String courseTitlesLabel;
  final String dominantProgramCode;
  final String startTime;
  final String endTime;
  final String statusLabel;
}

enum RoomFilter {
  classes('Classes'),
  labs('Labs'),
  theater('Theaters');

  const RoomFilter(this.label);

  final String label;
}

class _RoomSeed {
  _RoomSeed({required this.roomNumber, required this.roomName});

  final String roomNumber;
  final String roomName;
  final Map<String, int> programCounts = <String, int>{};
  final List<_TimeSlot> busySlots = <_TimeSlot>[];
  final Set<String> courseTitles = <String>{};
}

class _TimeSlot {
  const _TimeSlot({required this.start, required this.end});

  _TimeSlot.fromStrings({required String startTime, required String endTime})
    : start = _FreeRoomTime.parse(startTime),
      end = _FreeRoomTime.parse(endTime);

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
