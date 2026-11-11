import 'dart:math';
import 'package:intl/intl.dart';

class AppTime {
  AppTime._();

  static final List<DateFormat> _dateFormats = <DateFormat>[
    DateFormat('yyyy-MM-dd'),
    DateFormat('yyyy/MM/dd'),
    DateFormat('yyyy.MM.dd'),
    DateFormat('dd-MM-yyyy'),
    DateFormat('dd/MM/yyyy'),
    DateFormat('d/M/yyyy'),
    DateFormat('d MMM yyyy'),
    DateFormat('d MMMM yyyy'),
    DateFormat('d MMM, yyyy'),
    DateFormat('d MMMM, yyyy'),
    DateFormat('d-MMM-yyyy'),
    DateFormat('MMM d, yyyy'),
    DateFormat('MMMM d, yyyy'),
    DateFormat('EEE, d MMM yyyy'),
    DateFormat('EEE, d MMMM yyyy'),
    DateFormat('EEE, d MMM, yyyy'),
    DateFormat('EEE, d MMMM, yyyy'),
    DateFormat('EEEE, d MMM yyyy'),
    DateFormat('EEEE, d MMMM yyyy'),
    DateFormat('EEEE, d MMM, yyyy'),
    DateFormat('EEEE, d MMMM, yyyy'),
  ];

  static final List<DateFormat> _timeFormats = <DateFormat>[
    DateFormat('HH:mm'),
    DateFormat('H:mm'),
    DateFormat('HH:mm:ss'),
    DateFormat('H:mm:ss'),
    DateFormat('hh:mm a'),
    DateFormat('h:mm a'),
    DateFormat('hh:mm:ss a'),
    DateFormat('h:mm:ss a'),
  ];

  static DateTime? parseTime(String? raw) {
    if (raw == null) return null;
    final cleaned = raw.trim();
    if (cleaned.isEmpty) return null;

    final match = RegExp(
      r'^(\d{1,2}):(\d{2})(?::\d{2})?\s*(AM|PM)?$',
      caseSensitive: false,
    ).firstMatch(cleaned);
    if (match != null) {
      var hour = int.tryParse(match.group(1) ?? '');
      final minute = int.tryParse(match.group(2) ?? '');
      final meridiem = match.group(3)?.toUpperCase();
      if (hour != null && minute != null && hour <= 23 && minute <= 59) {
        if (meridiem != null) {
          if (hour == 12) {
            hour = meridiem == 'AM' ? 0 : 12;
          } else if (meridiem == 'PM') {
            hour += 12;
          }
        }
        return DateTime(0, 1, 1, hour, minute);
      }
    }

    final normalized = cleaned.toUpperCase();
    for (final f in _timeFormats) {
      try {
        final parsed = f.parseStrict(normalized);
        return DateTime(0, 1, 1, parsed.hour, parsed.minute);
      } catch (_) {}
    }
    return null;
  }

  static DateTime? parseDate(String? raw) {
    if (raw == null) return null;
    final cleaned = raw.trim();
    if (cleaned.isEmpty) return null;

    final fastParsed = DateTime.tryParse(cleaned);
    if (fastParsed != null) return fastParsed;

    for (final f in _dateFormats) {
      try {
        return f.parseStrict(cleaned);
      } catch (_) {}
    }
    return null;
  }

  static String formatDate(String? raw, {String pattern = 'd MMMM, y'}) {
    if (raw == null || raw.trim().isEmpty) return '';
    final cleaned = raw.trim();
    final parsed = parseDate(cleaned);
    return parsed == null ? cleaned : DateFormat(pattern).format(parsed);
  }

  static DateTime? parseDateTime(String? date, String? time) {
    final datePart = parseDate(date);
    if (datePart == null) return null;
    if (time == null || time.trim().isEmpty) {
      return DateTime(datePart.year, datePart.month, datePart.day);
    }
    final timePart = parseTime(time);
    if (timePart == null) {
      return DateTime(datePart.year, datePart.month, datePart.day);
    }
    return DateTime(
      datePart.year,
      datePart.month,
      datePart.day,
      timePart.hour,
      timePart.minute,
    );
  }

  static const List<String> weekdayNames = <String>[
    'MONDAY',
    'TUESDAY',
    'WEDNESDAY',
    'THURSDAY',
    'FRIDAY',
    'SATURDAY',
    'SUNDAY',
  ];

  static int? weekdayFromName(String? day) {
    final index = weekdayNames.indexOf(day?.trim().toUpperCase() ?? '');
    return index < 0 ? null : index + DateTime.monday;
  }

  static int shiftWeekday(int weekday, int offset) {
    if (weekday < DateTime.monday || weekday > DateTime.sunday) {
      return weekday;
    }
    final zeroBased = weekday - DateTime.monday;
    return ((zeroBased + offset) % DateTime.daysPerWeek) + DateTime.monday;
  }

  static (int hour, int minute)? parseHourMinute(String? raw) {
    final parsed = parseTime(raw);
    if (parsed == null) return null;
    return (parsed.hour, parsed.minute);
  }

  static int? toMinutes(String? raw) {
    final hm = parseHourMinute(raw);
    if (hm == null) return null;
    return hm.$1 * 60 + hm.$2;
  }

  static bool isCurrentOrNextSlot(
    String? start,
    String? end,
    Iterable<(String?, String?)> daySlots, {
    DateTime? now,
  }) {
    final current = now ?? DateTime.now();
    final currentMinutes = current.hour * 60 + current.minute;
    final slots = [
      for (final (slotStart, slotEnd) in daySlots)
        if ((toMinutes(slotStart), toMinutes(slotEnd)) case (
          final int from,
          final int to,
        ) when from < to)
          (from, to),
    ];
    final startMinutes = toMinutes(start);
    final endMinutes = toMinutes(end);
    if (startMinutes == null || endMinutes == null) return false;
    bool isRunning((int, int) slot) =>
        currentMinutes >= slot.$1 && currentMinutes < slot.$2;
    if (slots.any(isRunning)) return isRunning((startMinutes, endMinutes));
    final upcomingStarts = slots
        .map((slot) => slot.$1)
        .where((minutes) => minutes > currentMinutes);
    return upcomingStarts.isNotEmpty &&
        startMinutes == upcomingStarts.reduce(min);
  }

  static String format(String? raw) {
    if (raw == null || raw.trim().isEmpty) return '';
    final parsed = parseTime(raw);
    if (parsed == null) return raw.trim().toUpperCase();
    return DateFormat('h:mm a').format(parsed);
  }

  static String range(String? start, String? end) {
    final s = format(start);
    final e = format(end);
    if (s.isEmpty && e.isEmpty) return '';
    if (e.isEmpty) return s;
    if (s.isEmpty) return e;
    return '$s - $e';
  }

  static String formatDateTime(DateTime dt) {
    return DateFormat('h:mm a').format(dt.toLocal());
  }

  static String formatHourMinute(int hour, int minute) {
    return DateFormat('h:mm a').format(DateTime(0, 1, 1, hour, minute));
  }

  static String weekdayName(DateTime date) {
    return DateFormat('EEEE').format(date);
  }

  static String formatLongDate(DateTime date) {
    return DateFormat('d MMMM, yyyy').format(date);
  }

  static String formatDayMonth(DateTime date) {
    return DateFormat('d MMMM').format(date);
  }

  static const Duration campusUtcOffset = Duration(hours: 6);

  static DateTime toCampusTime(DateTime value) =>
      value.isUtc ? value.add(campusUtcOffset) : value;

  static String formatCampusTime(String? raw, String pattern) {
    final parsed = DateTime.tryParse((raw ?? '').trim());
    return parsed == null
        ? ''
        : DateFormat(pattern).format(toCampusTime(parsed));
  }

  static String formatDayMonthYear(DateTime date) {
    return DateFormat('d MMMM y').format(date);
  }

  static String monthName(DateTime date) {
    return DateFormat('MMMM').format(date);
  }
}
