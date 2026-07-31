import 'package:preconnect/tools/time_utils.dart';

class SeatTimetable {
  const SeatTimetable({required this.startTime, required this.endTime});

  final String startTime;
  final String endTime;

  String get label =>
      '${BracuTime.format(startTime)} - ${BracuTime.format(endTime)}';
  bool get isNotEmpty => startTime.isNotEmpty && endTime.isNotEmpty;
  bool get isEmpty => startTime.isEmpty && endTime.isEmpty;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SeatTimetable &&
          startTime == other.startTime &&
          endTime == other.endTime;

  @override
  int get hashCode => Object.hash(startTime, endTime);

  @override
  String toString() => label;
}
