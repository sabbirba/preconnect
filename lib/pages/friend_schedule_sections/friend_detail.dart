import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:preconnect/api/api_config.dart';
import 'package:preconnect/api/profile_service.dart';
import 'package:preconnect/api/schedule_service.dart';
import 'package:preconnect/model/friend_schedule.dart';
import 'package:preconnect/pages/friend_schedule_sections/compare_schedules.dart';
import 'package:preconnect/pages/friend_schedule_sections/friend_header.dart';
import 'package:preconnect/pages/shared_widgets/current_session_helper.dart';
import 'package:preconnect/pages/ui_kit.dart';
import 'package:preconnect/tools/ramadan_timing.dart';
import 'package:preconnect/tools/time_utils.dart';

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
  GlobalKey? _highlightKey;
  String? _lastHighlightKey;
  bool _didScroll = false;
  bool _scrollRetry = false;

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<List<Course>?> _loadMyCourses() async {
    final semesterSessionId = await resolveCurrentSessionSemesterId();
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
      final myProfile = await ProfileService().getProfile();
      if (!mounted) return;
      final myPhotoUrl = ApiConfig.photoUrl(myProfile?['photoFilePath']);
      navigator.push(
        MaterialPageRoute(
          builder: (context) => CompareSchedulesPage(
            mySchedule: myCourses,
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

      if (weekday != now.weekday) {
        continue;
      }
      final startTime = DateTime(
        now.year,
        now.month,
        now.day,
        start ~/ 60,
        start % 60,
      );
      final endTime = DateTime(
        now.year,
        now.month,
        now.day,
        end ~/ 60,
        end % 60,
      );
      if (!now.isBefore(endTime)) {
        continue;
      }

      final effectiveStart = now.isBefore(startTime) ? startTime : now;
      if (nextStart == null || effectiveStart.isBefore(nextStart)) {
        nextStart = effectiveStart;
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
    final courseCount = widget.friend.courses.length;
    final headerTitle =
        '$courseCount ${courseCount == 1 ? 'Schedule' : 'Schedules'}';

    return Scaffold(
      body: BracuPageScaffold(
        title: headerTitle,
        subtitle: 'Shared Schedule',
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
                  const SizedBox(width: 12),
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
                        Text(
                          widget.friend.id.trim().isEmpty
                              ? ''
                              : 'ID: ${widget.friend.id}',
                          style: TextStyle(fontSize: 11, color: textSecondary),
                        ),
                      ],
                    ),
                  ),
                  if (widget.friend.courses.isNotEmpty)
                    IconButton(
                      tooltip: 'Compare schedules',
                      style: IconButton.styleFrom(
                        foregroundColor: BracuPalette.primary,
                        side: BorderSide(
                          color: BracuPalette.primary.withValues(alpha: 0.6),
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      onPressed: _openCompare,
                      icon: const Icon(Icons.compare_arrows_rounded),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 20),
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
            else
              ..._buildScheduleByDay(context),
          ],
        ),
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
          'day': day,
          'startTime': adjusted.startTime,
          'endTime': adjusted.endTime,
          'entryKey':
              '$day|${course.courseCode}|${adjusted.startTime}|${adjusted.endTime}',
        });
      }
    }

    const orderedDays = [
      'Saturday',
      'Sunday',
      'Monday',
      'Tuesday',
      'Wednesday',
      'Thursday',
      'Friday',
    ];
    final sortedDays = orderedDays.where(grouped.containsKey).toList();

    final widgets = <Widget>[];
    final highlightedEntryKey = _pickHighlightedEntryKey(flatEntries);
    _highlightKey = null;
    for (final day in sortedDays) {
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
            BracuSectionTitle(title: day),
            const SizedBox(height: 10),
            ...entries.map(
              (entry) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: BracuCard(
                  key: entry['entryKey'] == highlightedEntryKey
                      ? (_highlightKey ??= GlobalKey())
                      : null,
                  isHighlighted: entry['entryKey'] == highlightedEntryKey,
                  highlightColor: BracuPalette.primary,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SectionBadge(
                        label: formatSectionBadge(
                          entry['sectionName']?.toString(),
                        ),
                        color: BracuPalette.primary,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        flex: 7,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              entry['courseCode'] ?? '',
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              formatTimeRange(
                                entry['startTime']?.toString(),
                                entry['endTime']?.toString(),
                              ),
                              style: TextStyle(
                                color: BracuPalette.textSecondary(context),
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
                              entry['roomNumber']?.toString() ?? '--',
                              textAlign: TextAlign.right,
                              style: TextStyle(
                                color: BracuPalette.textPrimary(context),
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            if (entry['faculties'] != null &&
                                entry['faculties'].trim().isNotEmpty) ...[
                              const SizedBox(height: 2),
                              Text(
                                entry['faculties'],
                                textAlign: TextAlign.right,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: BracuPalette.textSecondary(context),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 6),
          ],
        ),
      );
    }
    if (highlightedEntryKey != null &&
        highlightedEntryKey != _lastHighlightKey) {
      _lastHighlightKey = highlightedEntryKey;
      _didScroll = false;
      _scrollRetry = false;
    }
    if (!_didScroll && highlightedEntryKey != null) {
      attemptScrollToHighlightedKey(
        highlightKey: _highlightKey,
        hasRetried: _scrollRetry,
        retry: () {
          _scrollRetry = true;
          if (mounted) {
            setState(() {});
          }
        },
        onScrolled: () {
          _didScroll = true;
        },
        alignment: 0.18,
      );
    }
    return widgets;
  }

  int? _timeToMinutes(String? raw) {
    return BracuTime.toMinutes(raw);
  }
}
