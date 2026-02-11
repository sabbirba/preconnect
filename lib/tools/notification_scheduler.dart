import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:preconnect/api/bracu_auth_manager.dart';
import 'package:preconnect/model/section_info.dart';
import 'package:preconnect/tools/local_notifications.dart';

class NotificationScheduler {
  NotificationScheduler._();

  static Future<void> syncSchedules() async {
    try {
      await LocalNotificationsService.instance.initialize();
      final prefs = await SharedPreferences.getInstance();
      final allEnabled = prefs.getBool('notif_all') ?? false;
      final classReminders = prefs.getBool('notif_class') ?? false;
      final examUpdates = prefs.getBool('notif_exam') ?? false;

      final classIds = prefs.getStringList('notif_ids_class') ?? const [];
      final examIds = prefs.getStringList('notif_ids_exam') ?? const [];
      final idsToCancel = [
        ...classIds.map(int.parse),
        ...examIds.map(int.parse),
      ];
      await LocalNotificationsService.instance.cancel(idsToCancel);

      final scheduleJson = await BracuAuthManager().getStudentSchedule();
      if (scheduleJson == null || scheduleJson.trim().isEmpty) {
        await prefs.setStringList('notif_ids_class', []);
        await prefs.setStringList('notif_ids_exam', []);
        return;
      }

      final sections = (jsonDecode(scheduleJson) as List<dynamic>)
          .map((e) => Section.fromJson(e))
          .toList();

      if (allEnabled && classReminders) {
        final classIdsNew = await _scheduleClassReminders(sections);
        await prefs.setStringList(
          'notif_ids_class',
          classIdsNew.map((e) => e.toString()).toList(),
        );
      } else {
        await prefs.setStringList('notif_ids_class', []);
      }

      if (allEnabled && examUpdates) {
        final examIdsNew = await _scheduleExamReminders(sections);
        await prefs.setStringList(
          'notif_ids_exam',
          examIdsNew.map((e) => e.toString()).toList(),
        );
      } else {
        await prefs.setStringList('notif_ids_exam', []);
      }
    } catch (_) {}
  }

  static Future<List<int>> _scheduleClassReminders(
    List<Section> sections,
  ) async {
    const lead = Duration(minutes: 30);
    final now = DateTime.now();
    final ids = <int>[];

    for (final section in sections) {
      final schedule = section.sectionSchedule;
      final start = DateTime.tryParse(schedule.classStartDate);
      final end = DateTime.tryParse(schedule.classEndDate);
      for (final cls in schedule.classSchedules) {
        final weekday = _weekdayFromName(cls.day);
        if (weekday == null) continue;
        for (var i = 0; i <= 7; i++) {
          final date = now.add(Duration(days: i));
          if (date.weekday != weekday) continue;
          if (start != null && date.isBefore(start)) continue;
          if (end != null && date.isAfter(end)) continue;
          final time = _parseTime(cls.startTime);
          if (time == null) continue;
          final scheduledAt = DateTime(
            date.year,
            date.month,
            date.day,
            time.hour,
            time.minute,
          ).subtract(lead);
          if (scheduledAt.isBefore(now)) continue;
          final id = _buildId(section.sectionId, 'class', scheduledAt);
          await LocalNotificationsService.instance.scheduleNotification(
            id: id,
            scheduledAt: scheduledAt,
            title: '${section.courseCode} Class',
            body: 'Starts at ${cls.startTime} in ${section.roomNumber}.',
          );
          ids.add(id);
        }
      }
    }
    return ids;
  }

  static Future<List<int>> _scheduleExamReminders(
    List<Section> sections,
  ) async {
    final now = DateTime.now();
    final ids = <int>[];

    for (final section in sections) {
      final schedule = section.sectionSchedule;
      final mid = _parseExamDateTime(
        schedule.midExamDate,
        schedule.midExamStartTime,
      );
      final fin = _parseExamDateTime(
        schedule.finalExamDate,
        schedule.finalExamStartTime,
      );
      final times = <DateTime?>[mid, fin];
      for (final examTime in times) {
        if (examTime == null || examTime.isBefore(now)) continue;
        var scheduledAt = examTime.subtract(const Duration(hours: 24));
        if (scheduledAt.isBefore(now)) {
          scheduledAt = examTime.subtract(const Duration(hours: 1));
        }
        if (scheduledAt.isBefore(now)) continue;
        final id = _buildId(section.sectionId, 'exam', scheduledAt);
        final title = '${section.courseCode} Exam';
        final body = 'Exam at ${_formatTimeOnly(examTime)}';
        await LocalNotificationsService.instance.scheduleNotification(
          id: id,
          scheduledAt: scheduledAt,
          title: title,
          body: body,
        );
        ids.add(id);
      }
    }
    return ids;
  }

  static int _buildId(int sectionId, String type, DateTime time) {
    final base = time.millisecondsSinceEpoch ~/ 60000;
    final typeHash = type == 'exam' ? 2 : 1;
    return ((sectionId * 1000003) + base + typeHash) % 1000000000;
  }

  static int? _weekdayFromName(String day) {
    switch (day.toUpperCase()) {
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

  static DateTime? _parseTime(String? raw) {
    if (raw == null) return null;
    final cleaned = raw.trim();
    if (cleaned.isEmpty) return null;
    final parts = cleaned.split(':');
    if (parts.length < 2) return null;
    final hour = int.tryParse(parts[0]);
    final minute = int.tryParse(parts[1]);
    if (hour == null || minute == null) return null;
    return DateTime(0, 1, 1, hour, minute);
  }

  static DateTime? _parseExamDateTime(String? date, String? time) {
    if (date == null || time == null) return null;
    final dateParsed = DateTime.tryParse(date.trim());
    if (dateParsed == null) return null;
    final timeParsed = _parseTime(time);
    if (timeParsed == null) return null;
    return DateTime(
      dateParsed.year,
      dateParsed.month,
      dateParsed.day,
      timeParsed.hour,
      timeParsed.minute,
    );
  }

  static String _formatTimeOnly(DateTime input) {
    final hour = input.hour % 12 == 0 ? 12 : input.hour % 12;
    final minute = input.minute.toString().padLeft(2, '0');
    final suffix = input.hour >= 12 ? 'PM' : 'AM';
    return '$hour:$minute $suffix';
  }
}
