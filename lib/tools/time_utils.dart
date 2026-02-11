import 'package:intl/intl.dart';

class BracuTime {
  BracuTime._();

  static final List<DateFormat> _dateFormats = <DateFormat>[
    DateFormat('yyyy-MM-dd'),
    DateFormat('yyyy/MM/dd'),
    DateFormat('yyyy.MM.dd'),
    DateFormat('dd-MM-yyyy'),
    DateFormat('dd/MM/yyyy'),
    DateFormat('d/M/yyyy'),
    DateFormat('d MMM yyyy'),
    DateFormat('d MMM, yyyy'),
    DateFormat('d-MMM-yyyy'),
    DateFormat('MMM d, yyyy'),
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
    final normalized = cleaned.toUpperCase();

    for (final f in _timeFormats) {
      try {
        final parsed = f.parseStrict(normalized);
        return DateTime(0, 1, 1, parsed.hour, parsed.minute);
      } catch (_) {}
    }

    final match = RegExp(
      r'^(\d{1,2}):(\d{2})(?::\d{2})?\s*(AM|PM)?$',
      caseSensitive: false,
    ).firstMatch(cleaned);
    if (match == null) return null;

    var hour = int.tryParse(match.group(1) ?? '');
    final minute = int.tryParse(match.group(2) ?? '');
    final meridiem = match.group(3)?.toUpperCase();
    if (hour == null || minute == null || hour > 23 || minute > 59) {
      return null;
    }
    if (meridiem != null) {
      if (hour == 12) {
        hour = meridiem == 'AM' ? 0 : 12;
      } else if (meridiem == 'PM') {
        hour += 12;
      }
    }
    return DateTime(0, 1, 1, hour, minute);
  }

  static DateTime? parseDate(String? raw) {
    if (raw == null) return null;
    final cleaned = raw.trim();
    if (cleaned.isEmpty) return null;
    for (final f in _dateFormats) {
      try {
        return f.parseStrict(cleaned);
      } catch (_) {}
    }
    return DateTime.tryParse(cleaned);
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

  static int? weekdayFromName(String? day) {
    if (day == null) return null;
    switch (day.trim().toUpperCase()) {
      case 'MONDAY':
        return DateTime.monday;
      case 'TUESDAY':
        return DateTime.tuesday;
      case 'WEDNESDAY':
        return DateTime.wednesday;
      case 'THURSDAY':
        return DateTime.thursday;
      case 'FRIDAY':
        return DateTime.friday;
      case 'SATURDAY':
        return DateTime.saturday;
      case 'SUNDAY':
        return DateTime.sunday;
      default:
        return null;
    }
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
    return DateFormat('h:mm a').format(dt);
  }
}
