import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:preconnect/api/bracu_auth_manager.dart';
import 'package:preconnect/model/friend_schedule.dart';
import 'package:preconnect/pages/friend_schedule_sections/compare_schedules.dart';
import 'package:preconnect/pages/friend_schedule_sections/friend_header.dart';
import 'package:preconnect/pages/shared_widgets/section_badge.dart';
import 'package:preconnect/pages/ui_kit.dart';

class FriendDetailPage extends StatefulWidget {
  const FriendDetailPage({
    super.key,
    required this.friend,
    this.displayName,
    this.isFavorite = false,
    required this.onToggleFavorite,
    required this.onEditNickname,
    required this.onDelete,
  });

  final FriendSchedule friend;
  final String? displayName;
  final bool isFavorite;
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

  Future<List<Course>?> _loadMyCourses() async {
    final jsonString = await BracuAuthManager().getStudentSchedule();
    if (jsonString == null || jsonString.isEmpty) return null;
    final parsed = jsonDecode(jsonString);
    final coursesData = parsed is Map ? parsed['courses'] : parsed;
    return (coursesData as List<dynamic>? ?? [])
        .map((e) => Course.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<void> _openCompare() async {
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    try {
      final myCourses = await _loadMyCourses();
      if (myCourses == null || myCourses.isEmpty) {
        messenger.showSnackBar(
          const SnackBar(
            content: Text('Please log in to compare schedules'),
            duration: Duration(seconds: 2),
          ),
        );
        return;
      }
      final myProfile = await BracuAuthManager().getProfile();
      final myPhotoUrl = _buildPhotoUrl(myProfile?['photoFilePath']);
      navigator.push(
        MaterialPageRoute(
          builder: (context) => CompareSchedulesPage(
            mySchedule: myCourses,
            friendItem: widget.friend,
            myPhotoUrl: myPhotoUrl,
          ),
        ),
      );
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Could not parse schedule data.'),
          duration: Duration(seconds: 3),
        ),
      );
    }
  }

  String? _buildPhotoUrl(String? photoFilePath) {
    if (photoFilePath == null || photoFilePath.isEmpty) return null;
    final encoded = base64Url
        .encode(utf8.encode(photoFilePath))
        .replaceAll('=', '');
    return 'https://connect.bracu.ac.bd/cdn/img/thumb/$encoded.jpg';
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
                              ? 'ID: N/A'
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

    for (final course in widget.friend.courses) {
      for (final schedule in course.schedule) {
        final day = schedule.day.trim().isEmpty
            ? schedule.day
            : schedule.day[0].toUpperCase() +
                  schedule.day.substring(1).toLowerCase();
        grouped.putIfAbsent(day, () => []).add({
          'courseCode': course.courseCode,
          'sectionName': course.sectionName,
          'roomNumber': course.roomNumber,
          'faculties': course.faculties,
          'startTime': schedule.startTime,
          'endTime': schedule.endTime,
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
    for (final day in sortedDays) {
      final entries = grouped[day]!;
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
    return widgets;
  }
}
