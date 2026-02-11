import 'package:flutter/material.dart';
import 'package:preconnect/api/bracu_auth_manager.dart';
import 'package:preconnect/model/friend_schedule.dart';
import 'package:preconnect/pages/friend_schedule_sections/compare_schedules.dart';
import 'package:preconnect/pages/ui_kit.dart';
import 'dart:convert';

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
  final VoidCallback onToggleFavorite;
  final VoidCallback onEditNickname;
  final VoidCallback onDelete;

  @override
  State<FriendDetailPage> createState() => _FriendDetailPageState();
}

class _FriendDetailPageState extends State<FriendDetailPage> {
  Map<String, dynamic>? _comparison;
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadComparison();
  }

  Future<void> _loadComparison() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final jsonString = await BracuAuthManager().getStudentSchedule();
      if (jsonString == null || jsonString.isEmpty) {
        setState(() {
          _isLoading = false;
          _errorMessage = null; // Don't show error, just don't compare
        });
        return;
      }

      final parsed = jsonDecode(jsonString);
      final List<Course> myCourses = (parsed['courses'] as List<dynamic>? ?? [])
          .map((e) => Course.fromJson(e))
          .toList();

      final comparison = CompareSchedulesPage.compareSchedules(
        myCourses,
        widget.friend.courses,
      );

      setState(() {
        _comparison = comparison;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
        _errorMessage = null; // Silently fail, just show friend's schedule
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final textPrimary = BracuPalette.textPrimary(context);
    final textSecondary = BracuPalette.textSecondary(context);
    final nameToShow = widget.displayName?.trim().isNotEmpty == true
        ? widget.displayName!
        : widget.friend.name;

    return Scaffold(
      appBar: AppBar(
        title: Text(nameToShow),
        actions: [
          if (widget.onToggleFavorite != null)
            IconButton(
              tooltip: widget.isFavorite ? 'Remove from favorites' : 'Add to favorites',
              onPressed: widget.onToggleFavorite,
              icon: Icon(
                widget.isFavorite ? Icons.star_rounded : Icons.star_outline_rounded,
                color: widget.isFavorite ? const Color(0xFFFFA726) : null,
              ),
            ),
          if (widget.onEditNickname != null)
            IconButton(
              tooltip: 'Edit nickname',
              onPressed: widget.onEditNickname,
              icon: const Icon(Icons.edit_outlined),
            ),
          IconButton(
            tooltip: 'Remove schedule',
            onPressed: () {
              widget.onDelete();
              Navigator.pop(context);
            },
            icon: const Icon(Icons.delete_outline_rounded),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _loadComparison,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            // Friend Info Card
            BracuCard(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        CircleAvatar(
                          backgroundColor: BracuPalette.primary.withValues(alpha: 0.1),
                          child: Text(
                            nameToShow.isNotEmpty ? nameToShow[0].toUpperCase() : '?',
                            style: TextStyle(
                              color: BracuPalette.primary,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                nameToShow,
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w600,
                                  color: textPrimary,
                                ),
                              ),
                              Text(
                                widget.friend.id.trim().isEmpty
                                    ? 'ID: N/A'
                                    : 'ID: ${widget.friend.id}',
                                style: TextStyle(fontSize: 14, color: textSecondary),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),

            // Comparison Section (if available)
            if (_comparison != null) ...[
              _buildComparisonSection(context, _comparison!),
              const SizedBox(height: 20),
            ],

            // Friend's Schedule
            Text(
              '${nameToShow}\'s Schedule',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: textPrimary,
              ),
            ),
            const SizedBox(height: 12),
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
    // Group course entries by day
    final Map<String, List<Map<String, dynamic>>> grouped = {};
    
    for (final course in widget.friend.courses) {
      for (final schedule in course.schedule) {
        if (!grouped.containsKey(schedule.day)) {
          grouped[schedule.day] = [];
        }
        grouped[schedule.day]!.add({
          'courseCode': course.courseCode,
          'sectionName': course.sectionName,
          'roomNumber': course.roomNumber,
          'faculties': course.faculties,
          'startTime': schedule.startTime,
          'endTime': schedule.endTime,
        });
      }
    }

    // Order days
    final orderedDays = ['Saturday', 'Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday'];
    final sortedDays = orderedDays.where((day) => grouped.containsKey(day)).toList();

    List<Widget> widgets = [];
    for (final day in sortedDays) {
      final entries = grouped[day]!;
      
      widgets.add(
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                day,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: BracuPalette.primary,
                ),
              ),
            ),
            ...entries.map((entry) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: BracuCard(
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: BracuPalette.primary.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        entry['sectionName'] ?? '',
                        style: TextStyle(
                          color: BracuPalette.primary,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
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
                            entry['courseCode'] ?? '',
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${entry['startTime']} - ${entry['endTime']}',
                            style: TextStyle(
                              color: BracuPalette.textSecondary(context),
                              fontSize: 13,
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
                          if (entry['faculties'] != null && entry['faculties'].trim().isNotEmpty) ...[
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
            )),
            const SizedBox(height: 12),
          ],
        ),
      );
    }
    return widgets;
  }

  Widget _buildComparisonSection(BuildContext context, Map<String, dynamic> comparison) {
    final textPrimary = BracuPalette.textPrimary(context);
    final freeSlots = (comparison['freeSlots'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    final commonClasses = (comparison['commonClasses'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    final busySlots = (comparison['busySlots'] as List?)?.cast<Map<String, dynamic>>() ?? [];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Schedule Comparison',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: textPrimary,
          ),
        ),
        const SizedBox(height: 12),
        
        // Free Slots
        if (freeSlots.isNotEmpty) ...[
          Text(
            'Free Together (${freeSlots.length})',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: const Color(0xFF4CAF50),
            ),
          ),
          const SizedBox(height: 8),
          ...freeSlots.take(3).map((slot) => _buildSlotCard(
            context,
            slot,
            const Color(0xFF4CAF50),
            Icons.check_circle_outline,
          )),
          if (freeSlots.length > 3)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                '+ ${freeSlots.length - 3} more free slots',
                style: TextStyle(
                  fontSize: 12,
                  color: BracuPalette.textSecondary(context),
                  fontStyle: FontStyle.italic,
                ),
              ),
            ),
          const SizedBox(height: 16),
        ],

        // Common Classes
        if (commonClasses.isNotEmpty) ...[
          Text(
            'Common Classes (${commonClasses.length})',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: const Color(0xFF2196F3),
            ),
          ),
          const SizedBox(height: 8),
          ...commonClasses.take(3).map((cls) => _buildClassCard(context, cls)),
          if (commonClasses.length > 3)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                '+ ${commonClasses.length - 3} more common classes',
                style: TextStyle(
                  fontSize: 12,
                  color: BracuPalette.textSecondary(context),
                  fontStyle: FontStyle.italic,
                ),
              ),
            ),
          const SizedBox(height: 16),
        ],

        // Busy Slots
        if (busySlots.isNotEmpty) ...[
          Text(
            'Both Busy (${busySlots.length})',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: const Color(0xFFFF9800),
            ),
          ),
          const SizedBox(height: 8),
          ...busySlots.take(2).map((slot) => _buildSlotCard(
            context,
            slot,
            const Color(0xFFFF9800),
            Icons.schedule,
          )),
          if (busySlots.length > 2)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                '+ ${busySlots.length - 2} more busy times',
                style: TextStyle(
                  fontSize: 12,
                  color: BracuPalette.textSecondary(context),
                  fontStyle: FontStyle.italic,
                ),
              ),
            ),
        ],
      ],
    );
  }

  Widget _buildSlotCard(
    BuildContext context,
    Map<String, dynamic> slot,
    Color color,
    IconData icon,
  ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: BracuCard(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Icon(icon, color: color, size: 20),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      slot['day'] ?? '',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: BracuPalette.textPrimary(context),
                        fontSize: 13,
                      ),
                    ),
                    Text(
                      '${slot['startTime']} - ${slot['endTime']}',
                      style: TextStyle(
                        color: BracuPalette.textSecondary(context),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildClassCard(BuildContext context, Map<String, dynamic> cls) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: BracuCard(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Icon(Icons.school, color: const Color(0xFF2196F3), size: 20),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${cls['courseCode']} - ${cls['sectionName']}',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: BracuPalette.textPrimary(context),
                        fontSize: 13,
                      ),
                    ),
                    Text(
                      cls['roomNumber'] ?? 'No room',
                      style: TextStyle(
                        color: BracuPalette.textSecondary(context),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
