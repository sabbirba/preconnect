import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:gap/gap.dart';
import 'package:preconnect/api/api_config.dart';
import 'package:preconnect/api/auth.dart';
import 'package:preconnect/api/schedule.dart';
import 'package:preconnect/api/exam_map.dart';
import 'package:preconnect/model/friend_schedule.dart';
import 'package:preconnect/model/section_info.dart' as section;
import 'package:preconnect/pages/friend_sections/compare_schedules.dart';
import 'package:preconnect/pages/friend_sections/friend_header.dart';
import 'package:preconnect/pages/shared_widgets/scroll_helper.dart';
import 'package:preconnect/features/schedule/application/session_resolver.dart';
import 'package:preconnect/pages/shared_widgets/exam_card.dart';
import 'package:preconnect/pages/shared_widgets/entry_card.dart';
import 'package:preconnect/pages/ui_kit.dart';
import 'package:preconnect/tools/app_storage.dart';
import 'package:preconnect/tools/ramadan.dart';
import 'package:preconnect/tools/storage_keys.dart';
import 'package:preconnect/tools/time_utils.dart';
import 'package:preconnect/tools/string_utils.dart';

class FriendDetailPage extends StatefulWidget {
  const FriendDetailPage({
    super.key,
    required this.friend,
    this.displayName,
    this.isFavorite = false,
    this.isRamadan = false,
    required this.onToggleFavorite,
    required this.onEditNickname,
    required this.onDelete,
  });

  final FriendSchedule friend;
  final String? displayName;
  final bool isFavorite;
  final bool isRamadan;
  final Future<void> Function() onToggleFavorite;
  final Future<String?> Function() onEditNickname;
  final Future<bool> Function() onDelete;

  @override
  State<FriendDetailPage> createState() => _FriendDetailPageState();
}

class _FriendDetailPageState extends State<FriendDetailPage> {
  late bool _isFavorite = widget.isFavorite;
  late String? _displayName = widget.displayName?.trim().isNotEmpty == true
      ? widget.displayName
      : null;
  final ScrollController _scrollController = ScrollController();
  late final HighlightScrollCoordinator _highlightScroll =
      HighlightScrollCoordinator(scrollController: _scrollController);
  String _currentSemester = '';
  Map<String, ExamScheduleOverride> _examOverrides = {};
  bool _loadingExamOverrides = true;

  @override
  void initState() {
    super.initState();
    _loadCurrentSemester();
    _loadExamOverrides();
  }

  Future<void> _loadExamOverrides() async {
    try {
      if (!await AuthService().isLoggedIn()) {
        if (mounted) {
          setState(() => _loadingExamOverrides = false);
        }
        return;
      }
      final semesterSessionId =
          await resolveCurrentSessionSemesterIdWithRetry();
      if (semesterSessionId != null) {
        final overrides = await ExamScheduleService().getOverridesForSections(
          widget.friend.courses
              .map(
                (course) =>
                    course.toSection(semesterSessionId: semesterSessionId),
              )
              .toList(),
          forcedSemesterSessionId: semesterSessionId,
        );
        if (mounted) {
          setState(() {
            _examOverrides = overrides;
            _loadingExamOverrides = false;
          });
        }
      } else {
        if (mounted) {
          setState(() => _loadingExamOverrides = false);
        }
      }
    } catch (_) {
      if (mounted) {
        setState(() => _loadingExamOverrides = false);
      }
    }
  }

  Future<void> _loadCurrentSemester() async {
    final semester =
        await AppStorage.instance.getString(StorageKeys.currentSemester) ?? '';
    if (mounted && semester.isNotEmpty) {
      setState(() {
        _currentSemester = semester;
      });
    }
  }

  String _getSemesterName(FriendSchedule friend) {
    final sem = friend.semester?.trim() ?? '';
    if (sem.isNotEmpty) return formatSemesterTitle(sem);
    return formatSemesterTitle(_currentSemester);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<List<Course>?> _loadMyCourses() async {
    if (!await AuthService().isLoggedIn()) return null;
    final semesterSessionId = await resolveCurrentSessionSemesterIdWithRetry();
    if (semesterSessionId == null) return null;
    final jsonString = await ScheduleService().getStudentScheduleForSemester(
      semesterSessionId: semesterSessionId,
    );
    if (jsonString == null || jsonString.isEmpty) return null;
    final parsed = jsonDecode(jsonString);
    final coursesData = parsed is Map ? parsed['courses'] : parsed;
    return (coursesData as List<dynamic>? ?? [])
        .map((e) => Course.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<void> _openCompare() async {
    final navigator = Navigator.of(context);
    try {
      final myCourses = await _loadMyCourses();
      if (!mounted) return;
      if (myCourses == null || myCourses.isEmpty) {
        showAppSnackBar(context, 'Please log in to compare schedules');
        return;
      }
      final myPhotoPath =
          (await AppStorage.instance.getString(StorageKeys.photoFilePath) ?? '')
              .trim();
      final myPhotoUrl = ApiConfig.photoUrl(myPhotoPath);
      navigator.push(
        MaterialPageRoute(
          builder: (context) => CompareSchedulesPage(
            personalSchedule: myCourses,
            friendItem: widget.friend,
            myPhotoUrl: myPhotoUrl,
            isRamadan: widget.isRamadan,
          ),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      showAppSnackBar(context, 'Could not parse schedule data.');
    }
  }

  String? _pickHighlightedEntryKey(List<Map<String, dynamic>> flatEntries) {
    final now = DateTime.now();
    DateTime? nextStart;
    String? nextKey;

    for (final entry in flatEntries) {
      final day = entry['day']?.toString() ?? '';
      final start = _timeToMinutes(entry['startTime']?.toString());
      final end = _timeToMinutes(entry['endTime']?.toString());
      final key = entry['entryKey']?.toString();
      final weekday = BracuTime.weekdayFromName(day);
      if (key == null || weekday == null || start == null || end == null) {
        continue;
      }

      final occurrence = nextWeeklyOccurrence(
        weekday: weekday,
        startMinutes: start,
        endMinutes: end,
        now: now,
      );
      if (occurrence != null &&
          (nextStart == null || occurrence.isBefore(nextStart))) {
        nextStart = occurrence;
        nextKey = key;
      }
    }

    return nextKey;
  }

  @override
  void didUpdateWidget(covariant FriendDetailPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.isFavorite != widget.isFavorite) {
      _isFavorite = widget.isFavorite;
    }
    if (oldWidget.displayName != widget.displayName) {
      _displayName = widget.displayName?.trim().isNotEmpty == true
          ? widget.displayName
          : null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final textPrimary = BracuPalette.textPrimary(context);
    final textSecondary = BracuPalette.textSecondary(context);
    final nameToShow = _displayName?.trim().isNotEmpty == true
        ? _displayName!
        : widget.friend.name;
    final uniqueCodes = widget.friend.courses
        .map((c) {
          final code = c.courseCode.trim().toUpperCase();
          if (code.endsWith('L') && code.length > 1) {
            return code.substring(0, code.length - 1);
          }
          return code;
        })
        .where((code) => code.isNotEmpty)
        .toSet();
    final courseCount = uniqueCodes.length;
    final headerTitle =
        '$courseCount ${courseCount == 1 ? 'Course' : 'Courses'}';

    return BracuPageScaffold(
      title: headerTitle,
      subtitle: 'Schedule',
      icon: Icons.person_rounded,
      actions: [
        IconButton(
          tooltip: _isFavorite ? 'Remove from favorites' : 'Add to favorites',
          onPressed: () async {
            setState(() => _isFavorite = !_isFavorite);
            await widget.onToggleFavorite();
          },
          icon: Icon(
            _isFavorite ? Icons.star_rounded : Icons.star_outline_rounded,
            color: _isFavorite ? BracuPalette.favorite : null,
          ),
        ),
        IconButton(
          tooltip: 'Edit nickname',
          onPressed: () async {
            final updated = await widget.onEditNickname();
            if (!mounted || updated == null) return;
            setState(() => _displayName = updated);
          },
          icon: const Icon(Icons.edit_outlined),
        ),
        IconButton(
          tooltip: 'Remove schedule',
          onPressed: () async {
            final navigator = Navigator.of(context);
            final deleted = await widget.onDelete();
            if (!mounted || !deleted) return;
            navigator.maybePop();
          },
          icon: const Icon(Icons.delete_outline_rounded),
        ),
      ],
      body: ListView(
        controller: _scrollController,
        padding: const EdgeInsets.all(20),
        children: [
          BracuCard(
            child: Row(
              children: [
                FriendAvatar(
                  name: widget.friend.name,
                  photoUrl: widget.friend.photoUrl,
                ),
                const Gap(12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        nameToShow,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: textPrimary,
                        ),
                      ),
                      (() {
                        final semesterName = _getSemesterName(
                          widget.friend,
                        ).toUpperCase();
                        final subtitleText = [
                          if (widget.friend.id.isNotEmpty) widget.friend.id,
                          if (semesterName.isNotEmpty) semesterName,
                        ].join(' · ');
                        if (subtitleText.isNotEmpty) {
                          return Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Text(
                              subtitleText,
                              style: TextStyle(
                                fontSize: 11,
                                color: textSecondary,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          );
                        }
                        return const SizedBox.shrink();
                      })(),
                    ],
                  ),
                ),
                if (widget.friend.courses.isNotEmpty)
                  IconButton(
                    tooltip: 'Compare schedules',
                    style: bracuCompactIconButtonStyle(
                      foregroundColor: BracuPalette.primary,
                      borderColor: BracuPalette.primary.withValues(alpha: 0.6),
                      borderRadius: 12,
                    ),
                    onPressed: _openCompare,
                    icon: const Icon(Icons.compare_arrows_rounded),
                  ),
              ],
            ),
          ),
          const Gap(16),
          if (widget.friend.courses.isEmpty)
            BracuCard(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  'No schedule shared.',
                  style: TextStyle(color: textSecondary),
                ),
              ),
            )
          else ...[
            ..._buildScheduleByDay(context),
            ..._buildExamSchedule(context),
          ],
        ],
      ),
    );
  }

  List<Widget> _buildScheduleByDay(BuildContext context) {
    final Map<String, List<Map<String, dynamic>>> grouped = {};
    final flatEntries = <Map<String, dynamic>>[];

    for (final course in widget.friend.courses) {
      for (final schedule in course.schedule) {
        final adjusted = RamadanTiming.adjustRange(
          schedule.startTime,
          schedule.endTime,
          isRamadan: widget.isRamadan,
        );
        final day = schedule.day.trim().isEmpty
            ? schedule.day
            : schedule.day[0].toUpperCase() +
                  schedule.day.substring(1).toLowerCase();
        grouped.putIfAbsent(day, () => []).add({
          'course': course,
          'schedule': schedule,
          'day': day,
          'courseCode': course.courseCode,
          'sectionName': course.sectionName,
          'roomNumber': course.roomNumber,
          'faculties': course.faculties,
          'startTime': adjusted.startTime,
          'endTime': adjusted.endTime,
          'entryKey':
              '$day|${course.courseCode}|${adjusted.startTime}|${adjusted.endTime}',
        });
        flatEntries.add({
          'course': course,
          'schedule': schedule,
          'day': day,
          'startTime': adjusted.startTime,
          'endTime': adjusted.endTime,
          'entryKey':
              '$day|${course.courseCode}|${adjusted.startTime}|${adjusted.endTime}',
        });
      }
    }

    final weekdayNames = [
      'Monday',
      'Tuesday',
      'Wednesday',
      'Thursday',
      'Friday',
      'Saturday',
      'Sunday',
    ];

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final renderedSections = <(String, DateTime)>[];
    for (var dayOffset = 0; dayOffset < 7; dayOffset++) {
      final date = today.add(Duration(days: dayOffset));
      final day = weekdayNames[date.weekday - 1];
      if (!grouped.containsKey(day)) continue;
      renderedSections.add((day, date));
    }

    final widgets = <Widget>[];
    final highlightedEntryKey = _pickHighlightedEntryKey(flatEntries);
    final targetIndex = highlightedEntryKey == null
        ? null
        : flatEntries.indexWhere(
            (entry) => entry['entryKey'] == highlightedEntryKey,
          );
    _highlightScroll.clearHighlightKey();
    for (final sectionInfo in renderedSections) {
      final day = sectionInfo.$1;
      final dayDate = sectionInfo.$2;
      final dayDateLabel = formatLongDate(dayDate);
      final entries = grouped[day]!;
      entries.sort((a, b) {
        final aStart = _timeToMinutes(a['startTime']?.toString()) ?? 24 * 60;
        final bStart = _timeToMinutes(b['startTime']?.toString()) ?? 24 * 60;
        if (aStart != bStart) return aStart.compareTo(bStart);
        final aEnd = _timeToMinutes(a['endTime']?.toString()) ?? 24 * 60;
        final bEnd = _timeToMinutes(b['endTime']?.toString()) ?? 24 * 60;
        if (aEnd != bEnd) return aEnd.compareTo(bEnd);
        return (a['courseCode']?.toString() ?? '').compareTo(
          b['courseCode']?.toString() ?? '',
        );
      });
      widgets.add(
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                BracuSectionTitle(title: day),
                if (dayDateLabel.isNotEmpty)
                  Text(
                    dayDateLabel,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: BracuPalette.textPrimary(context),
                    ),
                  ),
              ],
            ),
            const Gap(12),
            ...entries.map((entry) {
              final isHighlighted = entry['entryKey'] == highlightedEntryKey;
              _highlightScroll.markHighlighted(isHighlighted);
              final section.Section course = entry['course'];
              final section.ClassSchedule schedule = entry['schedule'];
              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: ScheduleEntryCard(
                  key: isHighlighted ? _highlightScroll.highlightKey : null,
                  sectionName: course.sectionName,
                  courseCode: course.courseCode,
                  schedule: schedule,
                  isRamadan: widget.isRamadan,
                  roomNumber: course.roomNumber,
                  faculties: course.faculties,
                  consumedSeat: course.consumedSeat,
                  courseType: course.courseType,
                  highlighted: isHighlighted,
                  highlightColor: BracuPalette.primary,
                ),
              );
            }),
            const Gap(6),
          ],
        ),
      );
    }
    if (highlightedEntryKey != null) {
      unawaited(
        _highlightScroll.scrollToTarget(
          targetToken: highlightedEntryKey,
          targetIndex: targetIndex,
          itemCount: flatEntries.length,
          onRetryBuild: () {
            if (mounted) {
              setState(() {});
            }
          },
        ),
      );
    }
    return widgets;
  }

  int? _timeToMinutes(String? raw) {
    return BracuTime.toMinutes(raw);
  }

  List<Widget> _buildExamSchedule(BuildContext context) {
    if (_loadingExamOverrides) {
      return const [Gap(16), Center(child: BracuSpinner())];
    }
    final midExams = <(Course, ExamSectionResolved)>[];
    final finalExams = <(Course, ExamSectionResolved)>[];
    for (final course in widget.friend.courses) {
      final resolved = ExamScheduleService().resolveSection(
        section: course.toSection(),
        overrides: _examOverrides,
      );
      if (resolved.midDate != null && resolved.midDate!.trim().isNotEmpty) {
        midExams.add((course, resolved));
      }
      if (resolved.finalDate != null && resolved.finalDate!.trim().isNotEmpty) {
        finalExams.add((course, resolved));
      }
    }

    midExams.sort((a, b) {
      final aTime = BracuTime.parseDateTime(a.$2.midDate, a.$2.midStartTime);
      final bTime = BracuTime.parseDateTime(b.$2.midDate, b.$2.midStartTime);
      return ExamSorting.compareExamEntries(
        typeA: 'Midterm',
        typeB: 'Midterm',
        dateTimeA: aTime,
        dateTimeB: bTime,
        courseCodeA: a.$1.courseCode,
        courseCodeB: b.$1.courseCode,
        sectionNameA: a.$1.sectionName,
        sectionNameB: b.$1.sectionName,
      );
    });
    finalExams.sort((a, b) {
      final aTime = BracuTime.parseDateTime(
        a.$2.finalDate,
        a.$2.finalStartTime,
      );
      final bTime = BracuTime.parseDateTime(
        b.$2.finalDate,
        b.$2.finalStartTime,
      );
      return ExamSorting.compareExamEntries(
        typeA: 'Final',
        typeB: 'Final',
        dateTimeA: aTime,
        dateTimeB: bTime,
        courseCodeA: a.$1.courseCode,
        courseCodeB: b.$1.courseCode,
        sectionNameA: a.$1.sectionName,
        sectionNameB: b.$1.sectionName,
      );
    });

    if (midExams.isEmpty && finalExams.isEmpty) {
      return const [];
    }
    final widgets = <Widget>[];
    if (midExams.isNotEmpty) {
      for (final item in midExams) {
        final course = item.$1;
        final resolved = item.$2;
        widgets.add(
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        BracuExamCard.formatExamDate(resolved.midDate),
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: BracuPalette.textPrimary(context),
                        ),
                      ),
                    ),
                    Text(
                      'Midterm',
                      textAlign: TextAlign.right,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: BracuPalette.textPrimary(context),
                      ),
                    ),
                  ],
                ),
                const Gap(6),
                BracuExamCard(
                  courseCode: course.courseCode,
                  sectionName: course.sectionName,
                  startTime: resolved.midStartTime,
                  endTime: resolved.midEndTime,
                  roomNumber: resolved.midRoomNumber,
                  faculties: course.faculties,
                  consumedSeat: course.consumedSeat,
                ),
              ],
            ),
          ),
        );
      }
    }
    if (finalExams.isNotEmpty) {
      for (final item in finalExams) {
        final course = item.$1;
        final resolved = item.$2;
        widgets.add(
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        BracuExamCard.formatExamDate(resolved.finalDate),
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: BracuPalette.textPrimary(context),
                        ),
                      ),
                    ),
                    Text(
                      'Final',
                      textAlign: TextAlign.right,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: BracuPalette.textPrimary(context),
                      ),
                    ),
                  ],
                ),
                const Gap(6),
                BracuExamCard(
                  courseCode: course.courseCode,
                  sectionName: course.sectionName,
                  startTime: resolved.finalStartTime,
                  endTime: resolved.finalEndTime,
                  roomNumber: resolved.finalRoomNumber,
                  faculties: course.faculties,
                  consumedSeat: course.consumedSeat,
                ),
              ],
            ),
          ),
        );
      }
    }
    return widgets;
  }
}
