import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:preconnect/tools/string_utils.dart';
import 'package:preconnect/tools/time_utils.dart';
import 'package:gap/gap.dart';
import 'package:preconnect/api/seat_status.dart';
import 'package:preconnect/model/section_info.dart' as section;
import 'package:preconnect/model/seat_timetable.dart';
import 'package:preconnect/pages/friend_sections/friend_header.dart';
import 'package:preconnect/pages/shared_widgets/seat_blocks.dart';
import 'package:preconnect/pages/ui_kit.dart';
import 'package:preconnect/pages/shared_widgets/exam_card.dart';

String seatStatusFacultySummaryLabel(section.SectionFaculty? faculty) {
  if (faculty == null) return 'TBA';
  final shortName = faculty.shortName.trim();
  if (shortName.isNotEmpty && shortName.toUpperCase() != 'TBA') {
    return shortName;
  }
  final staffName = faculty.staffName.trim();
  if (staffName.isNotEmpty && staffName.toUpperCase() != 'TBA') {
    return staffName;
  }
  return 'TBA';
}

String seatStatusFacultyDetailLabel(section.SectionFaculty? faculty) {
  if (faculty == null) return '';
  final name = faculty.staffName.trim();
  final email = faculty.email.trim();
  if (name.isEmpty) return email;
  if (email.isEmpty) return name;
  return '$name $email';
}

String seatStatusFacultyMeta(section.SectionFaculty? faculty) {
  if (faculty == null) return '';
  return <String?>[faculty.gender, faculty.designation]
      .whereType<String>()
      .map((value) => value.trim())
      .where((value) => value.isNotEmpty)
      .join(' • ');
}

String seatStatusFacultySearchText(section.SectionFaculty? faculty) {
  final pieces = <String>[
    seatStatusFacultySummaryLabel(faculty),
    seatStatusFacultyDetailLabel(faculty),
  ];
  return pieces.where((value) => value.trim().isNotEmpty).join(' ').trim();
}

bool seatStatusFacultyHasVisuals(section.SectionFaculty? faculty) {
  if (faculty == null) return false;
  return faculty.shortName.trim().isNotEmpty ||
      faculty.staffName.trim().isNotEmpty ||
      faculty.email.trim().isNotEmpty ||
      faculty.imgUrl?.trim().isNotEmpty == true;
}

class SeatCard extends StatelessWidget {
  const SeatCard({
    super.key,
    required this.item,
    this.footer = const <Widget>[],
    this.highlighted = false,
    this.highlightColor = AppPalette.primary,
    this.onPinTap,
    this.pinned = false,
    this.onPlanTap,
    this.planned = false,
    this.onTap,
  });

  final SeatCardData item;
  final List<Widget> footer;
  final bool highlighted;
  final Color highlightColor;
  final VoidCallback? onPinTap;
  final bool pinned;
  final VoidCallback? onPlanTap;
  final bool planned;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final textPrimary = AppPalette.textPrimary(context);
    final textSecondary = AppPalette.textSecondary(context);
    final theoryLabel = titleCaseWords(item.courseType);
    final courseHeader = _headerLine(item.courseCode, item.sectionName);
    final faculty = item.faculty;
    final facultyName = faculty?.staffName.trim() ?? '';
    final facultyEmail = faculty?.email.trim() ?? '';
    final classLines = seatScheduleLines(item.classSchedule);
    final labLines = seatScheduleLines(item.labSchedule);
    final hasMidExam = hasExamSchedule(
      item.midExamDate,
      item.midExamStartTime,
      item.midExamEndTime,
    );
    final hasFinalExam = hasExamSchedule(
      item.finalExamDate,
      item.finalExamStartTime,
      item.finalExamEndTime,
    );

    final card = AppCard(
      isHighlighted: highlighted,
      highlightColor: highlightColor,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (courseHeader.isNotEmpty)
                      Text(
                        courseHeader,
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                          color: textPrimary,
                        ),
                      ),
                    if (item.courseName.trim().isNotEmpty) ...[
                      const Gap(2),
                      Text(
                        item.courseName.trim(),
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                          color: textSecondary,
                        ),
                      ),
                    ],
                    if (item.facultyInitial.trim().isNotEmpty ||
                        item.credits > 0) ...[
                      const Gap(2),
                      RichText(
                        text: TextSpan(
                          style: TextStyle(fontSize: 13, color: textSecondary),
                          children: [
                            if (item.facultyInitial.trim().isNotEmpty)
                              TextSpan(
                                text: item.facultyInitial,
                                style: TextStyle(
                                  color: textPrimary,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            if (item.facultyInitial.trim().isNotEmpty &&
                                item.credits > 0)
                              TextSpan(
                                text: ' • ',
                                style: TextStyle(
                                  color: textSecondary,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            if (item.credits > 0)
                              TextSpan(
                                text: '${item.credits} credits',
                                style: TextStyle(
                                  color: textSecondary,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (onPlanTap != null || onPinTap != null)
                Padding(
                  padding: const EdgeInsets.only(left: 8, top: 2),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (onPlanTap != null)
                        SeatIconButton(
                          active: planned,
                          activeColor: AppPalette.accent,
                          icon: planned
                              ? Icons.remove_circle_outline_rounded
                              : Icons.add_circle_outline_rounded,
                          tooltip: planned
                              ? 'Remove From Planner'
                              : 'Add To Planner',
                          onTap: onPlanTap!,
                        ),
                      if (onPinTap != null)
                        SeatIconButton(
                          active: pinned,
                          icon: pinned
                              ? Icons.notifications_rounded
                              : Icons.notifications_none_rounded,
                          tooltip: pinned ? 'Stop Seat Alerts' : 'Seat Alerts',
                          onTap: onPinTap!,
                        ),
                    ],
                  ),
                ),
            ],
          ),
          if (seatStatusFacultyHasVisuals(faculty)) ...[
            const Gap(12),
            Row(
              children: [
                if (faculty!.imgUrl?.trim().isNotEmpty == true) ...[
                  FriendAvatar(
                    name: facultyName,
                    photoUrl: faculty.imgUrl,
                    size: 40,
                    radius: 20,
                  ),
                  const Gap(12),
                ],
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (facultyName.isNotEmpty)
                        Text(
                          facultyName,
                          style: TextStyle(
                            color: textPrimary,
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      if (seatStatusFacultyMeta(faculty) case final meta
                          when meta.isNotEmpty) ...[
                        const Gap(2),
                        Text(
                          meta,
                          style: TextStyle(
                            color: textSecondary,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                      if (facultyEmail.isNotEmpty) ...[
                        const Gap(2),
                        InkWell(
                          borderRadius: BorderRadius.circular(6),
                          onTap: () => openMailComposer(context, facultyEmail),
                          child: Text(
                            facultyEmail,
                            style: TextStyle(
                              color: textSecondary,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ],

          if (classLines.isNotEmpty) ...[
            const Gap(12),
            SeatScheduleBlock(title: 'Class', lines: classLines),
          ],
          if (labLines.isNotEmpty) ...[
            const Gap(12),
            SeatScheduleBlock(title: 'Lab', lines: labLines),
          ],
          if (item.room.isNotEmpty || item.labRoom.isNotEmpty) ...[
            const Gap(12),
            SeatRoomBlock(
              theoryLabel: theoryLabel,
              theoryRoom: item.room,
              labRoom: item.labRoom,
            ),
          ],
          if (hasMidExam || hasFinalExam) ...[
            const Gap(12),
            Row(
              children: [
                Expanded(
                  child: SeatExamBlock(
                    label: 'Mid',
                    labelColor: ExamCard.typeColor(isFinal: false),
                    date: item.midExamDate,
                    start: item.midExamStartTime,
                    end: item.midExamEndTime,
                    textPrimary: textPrimary,
                    textSecondary: textSecondary,
                  ),
                ),
                const Gap(16),
                Expanded(
                  child: SeatExamBlock(
                    label: 'Final',
                    labelColor: ExamCard.typeColor(isFinal: true),
                    date: item.finalExamDate,
                    start: item.finalExamStartTime,
                    end: item.finalExamEndTime,
                    textPrimary: textPrimary,
                    textSecondary: textSecondary,
                  ),
                ),
              ],
            ),
          ],
          if (item.total >= 0 ||
              item.consumed >= 0 ||
              item.remaining != -1) ...[
            const Gap(12),
            Divider(color: textSecondary.withValues(alpha: 0.2), height: 1),
            const Gap(12),
            Row(
              children: [
                Expanded(
                  child: SeatMetric(
                    value: item.remaining,
                    label: 'Remaining',
                    color: item.remaining <= 0
                        ? AppPalette.danger
                        : textPrimary,
                  ),
                ),
                Expanded(
                  child: SeatMetric(
                    value: item.consumed,
                    label: 'Booked',
                    color: textPrimary,
                    trend: item.seatTrend,
                  ),
                ),
                Expanded(
                  child: SeatMetric(
                    value: item.total,
                    label: 'Total',
                    color: textPrimary,
                  ),
                ),
              ],
            ),
            if (onPlanTap != null && item.lastUpdatedAt != null) ...[
              const Gap(12),
              SeatUpdatedText(updatedAt: item.lastUpdatedAt!),
            ],
          ],
          if (footer.isNotEmpty) ...[const Gap(12), ...footer],
        ],
      ),
    );
    if (onTap == null) {
      return card;
    }
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: card,
      ),
    );
  }

  String _headerLine(String courseCode, String sectionName) {
    final code = courseCode.trim();
    final section = sectionName.trim();
    if (code.isEmpty && section.isEmpty) return '';
    if (code.isEmpty) return section;
    if (section.isEmpty) return code;
    return '$code - $section';
  }
}

class SeatIconButton extends StatelessWidget {
  const SeatIconButton({
    super.key,
    required this.active,
    this.activeColor = AppPalette.primary,
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  final bool active;
  final Color activeColor;
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: onTap,
      tooltip: tooltip,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints.tightFor(width: 44, height: 44),
      visualDensity: VisualDensity.compact,
      splashRadius: 22,
      icon: Icon(
        icon,
        size: 28,
        color: active ? activeColor : AppPalette.textSecondary(context),
      ),
    );
  }
}

class SeatCardData {
  const SeatCardData({
    required this.sectionId,
    required this.courseCode,
    required this.sectionName,
    required this.courseName,
    required this.faculty,
    required this.facultyInitial,
    required this.facultyMeta,
    required this.credits,
    required this.room,
    required this.courseType,
    required this.classSchedule,
    required this.labSchedule,
    required this.labRoom,
    required this.labCourseCode,
    required this.labName,
    required this.labFaculties,
    required this.labSectionId,
    required this.midExamDate,
    required this.midExamStartTime,
    required this.midExamEndTime,
    required this.finalExamDate,
    required this.finalExamStartTime,
    required this.finalExamEndTime,
    required this.remaining,
    required this.consumed,
    required this.total,
    required this.timetables,
    required this.searchToken,
    this.lastUpdatedAt,
    this.seatTrend = '',
  });

  final int sectionId;
  final String courseCode;
  final String sectionName;
  final String courseName;
  final section.SectionFaculty? faculty;
  final String facultyInitial;
  final String facultyMeta;
  final int credits;
  final String room;
  final String courseType;
  final List<SeatStatusClassSchedule> classSchedule;
  final List<SeatStatusClassSchedule> labSchedule;
  final List<SeatTimetable> timetables;
  final String labRoom;
  final String labCourseCode;
  final String labName;
  final String labFaculties;
  final int? labSectionId;
  final String? midExamDate;
  final String? midExamStartTime;
  final String? midExamEndTime;
  final String? finalExamDate;
  final String? finalExamStartTime;
  final String? finalExamEndTime;
  final int remaining;
  final int consumed;
  final int total;
  final String searchToken;
  final DateTime? lastUpdatedAt;
  final String seatTrend;

  factory SeatCardData.fromDetails(SeatStatusDetailsResponse details) {
    final sectionId = details.sectionId;
    final total = details.capacity;
    final resolvedRemaining = total - details.consumedSeat;
    final resolvedConsumed = details.consumedSeat;
    final facultySummaryLabel = seatStatusFacultySummaryLabel(details.faculty);
    final facultyDetailLabel = seatStatusFacultyDetailLabel(details.faculty);
    final facultySearchText = seatStatusFacultySearchText(details.faculty);
    final timetables = details.sectionSchedule.classSchedules
        .map(
          (data) =>
              SeatTimetable(startTime: data.startTime, endTime: data.endTime),
        )
        .toList();

    return SeatCardData(
      sectionId: sectionId,
      courseCode: details.courseCode,
      sectionName: details.sectionName,
      courseName: details.courseName,
      faculty: details.faculty,
      facultyInitial: facultySummaryLabel,
      facultyMeta: facultyDetailLabel,
      credits: details.courseCredit,
      room: details.roomNumber,
      courseType: details.courseType,
      classSchedule: details.sectionSchedule.classSchedules,
      labSchedule: details.labSchedules,
      labRoom: details.labRoomName ?? '',
      labCourseCode: details.labCourseCode ?? '',
      labName: details.labName ?? '',
      labFaculties: details.labFaculties ?? '',
      labSectionId: details.labSectionId,
      midExamDate: details.sectionSchedule.midExamDate,
      midExamStartTime: details.sectionSchedule.midExamStartTime,
      midExamEndTime: details.sectionSchedule.midExamEndTime,
      finalExamDate: details.sectionSchedule.finalExamDate,
      finalExamStartTime: details.sectionSchedule.finalExamStartTime,
      finalExamEndTime: details.sectionSchedule.finalExamEndTime,
      timetables: timetables,
      remaining: resolvedRemaining,
      consumed: resolvedConsumed,
      total: total,
      lastUpdatedAt: details.lastUpdatedAt,
      seatTrend: seatTrendOf(details.seatTrend, details.seatDelta),
      searchToken: _searchToken(
        sectionId: sectionId,
        courseCode: details.courseCode,
        sectionName: details.sectionName,
        courseName: details.courseName,
        facultySearchText: facultySearchText,
        room: details.roomNumber,
        courseType: details.courseType,
        labRoom: details.labRoomName ?? '',
        classSchedule: details.sectionSchedule.classSchedules,
        labSchedule: details.labSchedules,
        midExamDate: details.sectionSchedule.midExamDate,
        midExamStartTime: details.sectionSchedule.midExamStartTime,
        midExamEndTime: details.sectionSchedule.midExamEndTime,
        finalExamDate: details.sectionSchedule.finalExamDate,
        finalExamStartTime: details.sectionSchedule.finalExamStartTime,
        finalExamEndTime: details.sectionSchedule.finalExamEndTime,
        total: total,
        consumed: resolvedConsumed,
        remaining: resolvedRemaining,
        sectionType: details.sectionType,
        academicDegree: details.academicDegree,
        semesterSessionId: details.semesterSessionId,
        parentSectionId: details.parentSectionId,
        courseId: details.courseId,
        roomName: details.roomName,
        labCourseCode: details.labCourseCode ?? '',
        labName: details.labName ?? '',
        labFaculties: details.labFaculties ?? '',
        labSectionId: details.labSectionId,
      ),
    );
  }

  static String _searchToken({
    required int sectionId,
    required String courseCode,
    required String sectionName,
    required String courseName,
    required String facultySearchText,
    required String room,
    required String courseType,
    required String labRoom,
    required String sectionType,
    required String academicDegree,
    required int semesterSessionId,
    required int? parentSectionId,
    required int courseId,
    required String roomName,
    required String labCourseCode,
    required String labName,
    required String labFaculties,
    required int? labSectionId,
    required List<SeatStatusClassSchedule> classSchedule,
    required List<SeatStatusClassSchedule> labSchedule,
    required String? midExamDate,
    required String? midExamStartTime,
    required String? midExamEndTime,
    required String? finalExamDate,
    required String? finalExamStartTime,
    required String? finalExamEndTime,
    required int total,
    required int consumed,
    required int remaining,
  }) {
    final scheduleToken = _scheduleSearchToken(classSchedule, labSchedule);
    final examToken =
        '${midExamDate ?? ''} ${midExamStartTime ?? ''} ${midExamEndTime ?? ''} '
        '${finalExamDate ?? ''} ${finalExamStartTime ?? ''} ${finalExamEndTime ?? ''}';
    return '$courseCode $sectionName $courseName '
            '$facultySearchText '
            '$room $roomName $labRoom $labCourseCode $labName $labFaculties '
            '$sectionId $courseId $semesterSessionId $parentSectionId $labSectionId '
            '$courseType $sectionType $academicDegree '
            '$total $consumed $remaining '
            '$scheduleToken $examToken'
        .toLowerCase();
  }

  static String _scheduleSearchToken(
    List<SeatStatusClassSchedule> classSchedule,
    List<SeatStatusClassSchedule> labSchedule,
  ) {
    final chunks = <String>[];
    for (final item in <SeatStatusClassSchedule>[
      ...classSchedule,
      ...labSchedule,
    ]) {
      final dayRaw = item.day.trim();
      final dayPretty = formatWeekdayTitle(item.day);
      final startRaw = item.startTime.trim();
      final endRaw = item.endTime.trim();
      chunks.add('$dayRaw $dayPretty $startRaw $endRaw');
    }
    return chunks.join(' ');
  }

  SeatCardData copyWith({
    int? remaining,
    int? consumed,
    int? total,
    DateTime? lastUpdatedAt,
    String? seatTrend,
  }) {
    return SeatCardData(
      sectionId: sectionId,
      courseCode: courseCode,
      sectionName: sectionName,
      courseName: courseName,
      faculty: faculty,
      facultyInitial: facultyInitial,
      facultyMeta: facultyMeta,
      credits: credits,
      room: room,
      courseType: courseType,
      classSchedule: classSchedule,
      labSchedule: labSchedule,
      labRoom: labRoom,
      labCourseCode: labCourseCode,
      labName: labName,
      labFaculties: labFaculties,
      labSectionId: labSectionId,
      midExamDate: midExamDate,
      midExamStartTime: midExamStartTime,
      midExamEndTime: midExamEndTime,
      finalExamDate: finalExamDate,
      finalExamStartTime: finalExamStartTime,
      finalExamEndTime: finalExamEndTime,
      remaining: remaining ?? this.remaining,
      consumed: consumed ?? this.consumed,
      total: total ?? this.total,
      searchToken: searchToken,
      timetables: timetables,
      lastUpdatedAt: lastUpdatedAt ?? this.lastUpdatedAt,
      seatTrend: seatTrend ?? this.seatTrend,
    );
  }
}

String seatTrendOf(String? trend, int? delta) {
  final value = (trend ?? '').trim().toLowerCase();
  if (value == 'up' || value == 'down') return value;
  if (delta == null || delta == 0) return '';
  return delta > 0 ? 'up' : 'down';
}

String seatUpdatedAgo(DateTime updatedAt, DateTime now) {
  final elapsed = now.difference(updatedAt);
  if (elapsed.inSeconds < 60) {
    final seconds = elapsed.inSeconds < 1 ? 1 : elapsed.inSeconds;
    return '${_unit(seconds, 'second')} ago';
  }
  if (elapsed.inMinutes < 60) {
    return '${_unit(elapsed.inMinutes, 'minute')} ago';
  }
  if (elapsed.inHours < 24) {
    final minutes = elapsed.inMinutes % 60;
    final hours = _unit(elapsed.inHours, 'hour');
    return minutes == 0
        ? '$hours ago'
        : '$hours ${_unit(minutes, 'minute')} ago';
  }
  final hours = elapsed.inHours % 24;
  final days = _unit(elapsed.inDays, 'day');
  return hours == 0 ? '$days ago' : '$days ${_unit(hours, 'hour')} ago';
}

String _unit(int value, String name) =>
    '$value ${value == 1 ? name : '${name}s'}';

class SeatUpdatedText extends StatefulWidget {
  const SeatUpdatedText({super.key, required this.updatedAt});

  final DateTime updatedAt;

  @override
  State<SeatUpdatedText> createState() => _SeatUpdatedTextState();
}

class _SeatUpdatedTextState extends State<SeatUpdatedText> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _schedule();
  }

  @override
  void didUpdateWidget(SeatUpdatedText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.updatedAt != widget.updatedAt) _schedule();
  }

  void _schedule() {
    _timer?.cancel();
    final elapsed = DateTime.now().difference(widget.updatedAt);
    final interval = elapsed.inMinutes < 1
        ? const Duration(seconds: 1)
        : elapsed.inHours < 1
        ? const Duration(seconds: 15)
        : const Duration(minutes: 1);
    _timer = Timer(interval, () {
      if (!mounted) return;
      setState(() {});
      _schedule();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final textSecondary = AppPalette.textSecondary(context);
    return Tooltip(
      message: AppTime.formatDateTime(widget.updatedAt),
      triggerMode: TooltipTriggerMode.tap,
      child: Center(
        child: Text(
          'Seat updated ${seatUpdatedAgo(widget.updatedAt, DateTime.now())}',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: textSecondary,
            fontSize: 11,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    );
  }
}

void sortSeatCardsByUpdate(List<SeatCardData> cards, {required bool latest}) {
  final missing = latest ? 0 : 1 << 62;
  int stamp(SeatCardData card) =>
      card.lastUpdatedAt?.millisecondsSinceEpoch ?? missing;
  final order = {for (var i = 0; i < cards.length; i++) cards[i].sectionId: i};
  cards.sort((a, b) {
    final byStamp = latest
        ? stamp(b).compareTo(stamp(a))
        : stamp(a).compareTo(stamp(b));
    if (byStamp != 0) return byStamp;
    return order[a.sectionId]!.compareTo(order[b.sectionId]!);
  });
}

List<SeatCardData> seatCardsFromDetails(
  Iterable<SeatStatusDetailsResponse> details,
) => [for (final detail in details) SeatCardData.fromDetails(detail)];

int seatSectionOrder(String sectionName) {
  final number = RegExp(r'\d+').firstMatch(sectionName)?.group(0);
  if (number == null) return 9999;
  return int.tryParse(number) ?? 9999;
}

void sortSeatCardsByCourse(
  List<SeatCardData> cards, {
  required bool Function(int sectionId) isPinned,
}) {
  cards.sort((a, b) {
    final ap = isPinned(a.sectionId) ? 0 : 1;
    final bp = isPinned(b.sectionId) ? 0 : 1;
    if (ap != bp) return ap.compareTo(bp);
    final codeCmp = a.courseCode.compareTo(b.courseCode);
    if (codeCmp != 0) return codeCmp;
    final sectionCmp = seatSectionOrder(
      a.sectionName,
    ).compareTo(seatSectionOrder(b.sectionName));
    if (sectionCmp != 0) return sectionCmp;
    return a.sectionName.compareTo(b.sectionName);
  });
}
