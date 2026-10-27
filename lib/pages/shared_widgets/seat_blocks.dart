import 'package:flutter/material.dart';
import 'package:gap/gap.dart';
import 'package:preconnect/api/seat_status.dart';
import 'package:preconnect/pages/ui_kit.dart';

bool hasExamSchedule(String? date, String? start, String? end) {
  return (date ?? '').trim().isNotEmpty ||
      (start ?? '').trim().isNotEmpty ||
      (end ?? '').trim().isNotEmpty;
}

String seatTitleCase(String value) {
  final cleaned = value
      .replaceAll(RegExp(r'[^a-z0-9]+', caseSensitive: false), ' ')
      .trim();
  if (cleaned.isEmpty) return '';
  return cleaned
      .split(RegExp(r'\s+'))
      .map((part) {
        if (part.isEmpty) return part;
        return part[0].toUpperCase() + part.substring(1).toLowerCase();
      })
      .join(' ');
}

List<String> seatScheduleLines(List<SeatStatusClassSchedule> schedules) {
  if (schedules.isEmpty) return const <String>[];
  final lines = schedules.map((entry) {
    final day = formatWeekdayTitle(entry.day);
    final time = formatTimeRange(entry.startTime, entry.endTime);
    return '$day $time'.trim();
  }).toList();
  return lines.where((line) => line.trim().isNotEmpty).toList();
}

class SeatRoomBlock extends StatelessWidget {
  const SeatRoomBlock({
    super.key,
    required this.theoryLabel,
    required this.theoryRoom,
    required this.labRoom,
  });

  final String theoryLabel;
  final String theoryRoom;
  final String labRoom;

  @override
  Widget build(BuildContext context) {
    final lines = <InlineSpan>[];
    if (theoryRoom.trim().isNotEmpty) {
      lines.add(
        TextSpan(
          text: '${theoryLabel.isEmpty ? 'Room' : theoryLabel}: ',
          style: TextStyle(
            color: AppPalette.textSecondary(context),
            fontWeight: FontWeight.w500,
          ),
        ),
      );
      lines.add(
        TextSpan(
          text: theoryRoom.trim(),
          style: TextStyle(
            color: AppPalette.textPrimary(context),
            fontWeight: FontWeight.w700,
          ),
        ),
      );
    }
    if (theoryRoom.trim().isNotEmpty && labRoom.trim().isNotEmpty) {
      lines.add(const TextSpan(text: '\n'));
    }
    if (labRoom.trim().isNotEmpty) {
      lines.add(
        TextSpan(
          text: 'Lab: ',
          style: TextStyle(
            color: AppPalette.textSecondary(context),
            fontWeight: FontWeight.w500,
          ),
        ),
      );
      lines.add(
        TextSpan(
          text: labRoom.trim(),
          style: TextStyle(
            color: AppPalette.textPrimary(context),
            fontWeight: FontWeight.w700,
          ),
        ),
      );
    }
    if (lines.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Room:',
          style: TextStyle(
            color: AppPalette.textSecondary(context),
            fontSize: 12,
            fontWeight: FontWeight.w500,
          ),
        ),
        const Gap(3),
        RichText(
          text: TextSpan(
            style: TextStyle(
              fontSize: 14,
              height: 1.25,
              color: AppPalette.textPrimary(context),
              fontWeight: FontWeight.w700,
            ),
            children: lines,
          ),
        ),
      ],
    );
  }
}

class SeatScheduleBlock extends StatelessWidget {
  const SeatScheduleBlock({
    super.key,
    required this.title,
    required this.lines,
  });

  final String title;
  final List<String> lines;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '$title:',
          style: TextStyle(
            color: AppPalette.textSecondary(context),
            fontSize: 12,
            fontWeight: FontWeight.w500,
          ),
        ),
        const Gap(3),
        for (final line in lines)
          Text(
            line,
            style: TextStyle(
              color: AppPalette.textPrimary(context),
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
          ),
      ],
    );
  }
}

class SeatMetric extends StatelessWidget {
  const SeatMetric({
    super.key,
    required this.value,
    required this.label,
    required this.color,
  });

  final int value;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          '$value',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w700,
            color: color,
          ),
        ),
        const Gap(3),
        Text(
          label,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: AppPalette.textSecondary(context),
            fontSize: 11.5,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

class SeatExamBlock extends StatelessWidget {
  const SeatExamBlock({
    super.key,
    required this.label,
    required this.date,
    required this.start,
    required this.end,
    required this.textPrimary,
    required this.textSecondary,
  });

  final String label;
  final String? date;
  final String? start;
  final String? end;
  final Color textPrimary;
  final Color textSecondary;

  @override
  Widget build(BuildContext context) {
    final dateLabel = formatDate(date);
    final timeLabel = formatTimeRange(start, end);
    final hasDate = dateLabel.isNotEmpty;
    final hasTime = timeLabel.isNotEmpty;
    if (!hasDate && !hasTime) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '$label:',
          style: TextStyle(
            color: textSecondary,
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
        const Gap(3),
        if (hasDate)
          Text(
            dateLabel,
            style: TextStyle(
              color: textPrimary,
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
            ),
          ),
        if (hasDate && hasTime) const Gap(1),
        if (hasTime)
          Text(
            timeLabel,
            style: TextStyle(color: textSecondary, fontSize: 11.5),
          ),
      ],
    );
  }
}
