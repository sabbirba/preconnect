import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:preconnect/api/bracu_auth_manager.dart';
import 'package:preconnect/model/section_info.dart';
import 'package:preconnect/pages/ui_kit.dart';

class ExamSchedule extends StatefulWidget {
  const ExamSchedule({super.key});

  @override
  State<ExamSchedule> createState() => _ExamScheduleState();
}

class _ExamScheduleState extends State<ExamSchedule> {
  late Future<List<Section>> _future;

  @override
  void initState() {
    super.initState();
    unawaited(BracuAuthManager().fetchStudentSchedule());
    _future = _fetchExamSections();
  }

  DateTime? _parseExamDateTime(String? date, String? time) {
    if (date == null || date.trim().isEmpty) return null;
    final rawDate = date.trim();
    final dateFormats = <DateFormat>[
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

    DateTime? datePart;
    for (final f in dateFormats) {
      try {
        datePart = f.parseStrict(rawDate);
        break;
      } catch (_) {}
    }
    datePart ??= DateTime.tryParse(rawDate);
    if (datePart == null) return null;

    if (time == null || time.trim().isEmpty) {
      return DateTime(datePart.year, datePart.month, datePart.day);
    }

    final rawTime = time.trim().toUpperCase();
    final timeFormats = <DateFormat>[
      DateFormat('HH:mm'),
      DateFormat('H:mm'),
      DateFormat('HH:mm:ss'),
      DateFormat('H:mm:ss'),
      DateFormat('hh:mm a'),
      DateFormat('h:mm a'),
      DateFormat('hh:mm:ss a'),
      DateFormat('h:mm:ss a'),
    ];
    DateTime? timePart;
    for (final f in timeFormats) {
      try {
        timePart = f.parseStrict(rawTime);
        break;
      } catch (_) {}
    }
    timePart ??= DateTime.tryParse(rawTime);

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

  Future<List<Section>> _fetchExamSections({bool forceRefresh = false}) async {
    if (forceRefresh) {
      await BracuAuthManager().fetchStudentSchedule();
    } else {
      unawaited(BracuAuthManager().fetchStudentSchedule());
    }
    final jsonString = await BracuAuthManager().getStudentSchedule();
    if (jsonString == null || jsonString.trim().isEmpty) {
      return const [];
    }

    final decoded = jsonDecode(jsonString) as List<dynamic>;
    return decoded.map((e) => Section.fromJson(e)).toList();
  }

  Future<void> _handleRefresh() async {
    setState(() {
      _future = _fetchExamSections(forceRefresh: true);
    });
    await _future;
  }

  @override
  Widget build(BuildContext context) {
    return BracuPageScaffold(
      title: 'Exam Schedule',
      subtitle: 'Mid & Final Dates',
      icon: Icons.school_outlined,
      body: FutureBuilder<List<Section>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return RefreshIndicator(
              onRefresh: _handleRefresh,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
                physics: const AlwaysScrollableScrollPhysics(),
                children: const [
                  SizedBox(height: 160),
                  BracuLoading(label: 'Loading exams...'),
                ],
              ),
            );
          } else if (snapshot.hasError) {
            return RefreshIndicator(
              onRefresh: _handleRefresh,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
                physics: const AlwaysScrollableScrollPhysics(),
                children: [
                  const SizedBox(height: 160),
                  BracuEmptyState(message: 'Error: ${snapshot.error}'),
                ],
              ),
            );
          } else if (!snapshot.hasData || snapshot.data!.isEmpty) {
            return RefreshIndicator(
              onRefresh: _handleRefresh,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
                physics: const AlwaysScrollableScrollPhysics(),
                children: const [
                  SizedBox(height: 160),
                  BracuEmptyState(message: 'No exam data available'),
                ],
              ),
            );
          }

          final sections = snapshot.data!;
          final midExams = sections
              .where(
            (s) =>
                s.sectionSchedule.midExamDate != null &&
                s.sectionSchedule.midExamStartTime != null,
          )
              .toList();
          final finalExams = sections
              .where(
            (s) =>
                s.sectionSchedule.finalExamDate != null &&
                s.sectionSchedule.finalExamStartTime != null,
          )
              .toList();

          midExams.sort((a, b) {
            final aTime = _parseExamDateTime(
              a.sectionSchedule.midExamDate,
              a.sectionSchedule.midExamStartTime,
            );
            final bTime = _parseExamDateTime(
              b.sectionSchedule.midExamDate,
              b.sectionSchedule.midExamStartTime,
            );
            if (aTime == null && bTime == null) return 0;
            if (aTime == null) return 1;
            if (bTime == null) return -1;
            return aTime.compareTo(bTime);
          });

          finalExams.sort((a, b) {
            final aTime = _parseExamDateTime(
              a.sectionSchedule.finalExamDate,
              a.sectionSchedule.finalExamStartTime,
            );
            final bTime = _parseExamDateTime(
              b.sectionSchedule.finalExamDate,
              b.sectionSchedule.finalExamStartTime,
            );
            if (aTime == null && bTime == null) return 0;
            if (aTime == null) return 1;
            if (bTime == null) return -1;
            return aTime.compareTo(bTime);
          });

          if (midExams.isEmpty && finalExams.isEmpty) {
            return RefreshIndicator(
              onRefresh: _handleRefresh,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
                physics: const AlwaysScrollableScrollPhysics(),
                children: const [
                  SizedBox(height: 160),
                  BracuEmptyState(message: 'No exams scheduled'),
                ],
              ),
            );
          }

          final now = DateTime.now();
          DateTime? nextExamTime;
          String? nextExamKey;
          DateTime? ongoingExamEnd;
          String? ongoingExamKey;
          for (final s in sections) {
            final midTime = _parseExamDateTime(
              s.sectionSchedule.midExamDate,
              s.sectionSchedule.midExamStartTime,
            );
            final midEndTime = _parseExamDateTime(
              s.sectionSchedule.midExamDate,
              s.sectionSchedule.midExamEndTime,
            );
            if (midTime != null) {
              if (midEndTime != null &&
                  now.isAfter(midTime) &&
                  now.isBefore(midEndTime)) {
                if (ongoingExamEnd == null ||
                    midEndTime.isBefore(ongoingExamEnd)) {
                  ongoingExamEnd = midEndTime;
                  ongoingExamKey = '${s.sectionId}-mid';
                }
              } else if (midTime.isAfter(now)) {
                if (nextExamTime == null || midTime.isBefore(nextExamTime)) {
                  nextExamTime = midTime;
                  nextExamKey = '${s.sectionId}-mid';
                }
              }
            }
            final finalTime = _parseExamDateTime(
              s.sectionSchedule.finalExamDate,
              s.sectionSchedule.finalExamStartTime,
            );
            final finalEndTime = _parseExamDateTime(
              s.sectionSchedule.finalExamDate,
              s.sectionSchedule.finalExamEndTime,
            );
            if (finalTime != null) {
              if (finalEndTime != null &&
                  now.isAfter(finalTime) &&
                  now.isBefore(finalEndTime)) {
                if (ongoingExamEnd == null ||
                    finalEndTime.isBefore(ongoingExamEnd)) {
                  ongoingExamEnd = finalEndTime;
                  ongoingExamKey = '${s.sectionId}-final';
                }
              } else if (finalTime.isAfter(now)) {
                if (nextExamTime == null || finalTime.isBefore(nextExamTime)) {
                  nextExamTime = finalTime;
                  nextExamKey = '${s.sectionId}-final';
                }
              }
            }
          }

          final highlightedKey = ongoingExamKey ?? nextExamKey;

          final children = <Widget>[];

          if (midExams.isNotEmpty) {
            children.add(const BracuSectionTitle(title: 'Midterm'));
            children.add(const SizedBox(height: 10));
            children.addAll(
              midExams.map((section) {
                final schedule = section.sectionSchedule;
                final isHighlighted =
                    highlightedKey == '${section.sectionId}-mid';
                return Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        formatDate(schedule.midExamDate),
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: BracuPalette.textSecondary(context),
                        ),
                      ),
                      const SizedBox(height: 8),
                      BracuCard(
                        isHighlighted: isHighlighted,
                        highlightColor: BracuPalette.primary,
                        child: Row(
                          children: [
                            Container(
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(
                                color: BracuPalette.primary.withValues(
                                  alpha: 0.12,
                                ),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              alignment: Alignment.center,
                              child: Text(
                                formatSectionBadge(section.sectionName),
                                style: const TextStyle(
                                  color: BracuPalette.primary,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              flex: 7,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    section.courseCode,
                                    style: const TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    formatTimeRange(
                                      schedule.midExamStartTime,
                                      schedule.midExamEndTime,
                                    ),
                                    style: TextStyle(
                                      color: BracuPalette.textSecondary(
                                        context,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              flex: 4,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Text(
                                    section.roomNumber.isNotEmpty
                                        ? section.roomNumber
                                        : '--',
                                    textAlign: TextAlign.right,
                                    style: TextStyle(
                                      color: BracuPalette.textPrimary(context),
                                      fontSize: 14,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                if (section.faculties.trim().isNotEmpty &&
                                    section.faculties.trim().toUpperCase() !=
                                        'OTHER') ...[
                                    const SizedBox(height: 2),
                                    Text(
                                      section.faculties,
                                      textAlign: TextAlign.right,
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: BracuPalette.textSecondary(
                                          context,
                                        ),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              }),
            );
            children.add(const SizedBox(height: 6));
          }

          if (finalExams.isNotEmpty) {
            children.add(const BracuSectionTitle(title: 'Final'));
            children.add(const SizedBox(height: 10));
            children.addAll(
              finalExams.map((section) {
                final schedule = section.sectionSchedule;
                final isHighlighted =
                    highlightedKey == '${section.sectionId}-final';
                return Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        formatDate(schedule.finalExamDate),
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: BracuPalette.textSecondary(context),
                        ),
                      ),
                      const SizedBox(height: 8),
                      BracuCard(
                        isHighlighted: isHighlighted,
                        highlightColor: BracuPalette.primary,
                        child: Row(
                          children: [
                            Container(
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(
                                color: BracuPalette.accent.withValues(
                                  alpha: 0.12,
                                ),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              alignment: Alignment.center,
                              child: Text(
                                formatSectionBadge(section.sectionName),
                                style: const TextStyle(
                                  color: BracuPalette.accent,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              flex: 7,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    section.courseCode,
                                    style: const TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    formatTimeRange(
                                      schedule.finalExamStartTime,
                                      schedule.finalExamEndTime,
                                    ),
                                    style: TextStyle(
                                      color: BracuPalette.textSecondary(
                                        context,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              flex: 4,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Text(
                                    section.roomNumber.isNotEmpty
                                        ? section.roomNumber
                                        : '--',
                                    textAlign: TextAlign.right,
                                    style: TextStyle(
                                      color: BracuPalette.textPrimary(context),
                                      fontSize: 14,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                if (section.faculties.trim().isNotEmpty &&
                                    section.faculties.trim().toUpperCase() !=
                                        'OTHER') ...[
                                    const SizedBox(height: 2),
                                    Text(
                                      section.faculties,
                                      textAlign: TextAlign.right,
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: BracuPalette.textSecondary(
                                          context,
                                        ),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              }),
            );
          }

          children.add(const SizedBox(height: 8));

          return RefreshIndicator(
            onRefresh: _handleRefresh,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
              children: children,
            ),
          );
        },
      ),
    );
  }
}
