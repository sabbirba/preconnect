import 'package:preconnect/tools/time_utils.dart';

class ExamVisibility {
  ExamVisibility._();

  static bool isUpcomingOrOngoingDateTime(
    DateTime? examDateTime, {
    DateTime? now,
  }) {
    if (examDateTime == null) return false;
    final current = now ?? DateTime.now();
    return !examDateTime.isBefore(current);
  }

  static bool isUpcomingOrOngoingSchedule({
    required String? date,
    required String? start,
    required String? end,
    DateTime? now,
  }) {
    final current = now ?? DateTime.now();
    final startTime = BracuTime.parseDateTime(date, start);
    if (startTime == null) return false;

    final endTime = BracuTime.parseDateTime(date, end);
    if (endTime != null) {
      return !endTime.isBefore(current);
    }
    return !startTime.isBefore(current);
  }
}
