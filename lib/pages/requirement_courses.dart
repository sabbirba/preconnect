import 'package:flutter/material.dart';
import 'package:preconnect/model/progress_info.dart';
import 'package:preconnect/pages/shared_widgets/course_tile.dart';
import 'package:preconnect/pages/ui_kit.dart';
import 'package:preconnect/tools/string_utils.dart';
import 'package:preconnect/tools/token_storage.dart';

class RequirementCoursesPage extends StatefulWidget {
  const RequirementCoursesPage({
    super.key,
    required this.info,
    required this.headerTitle,
    this.currentSemesterCodes = const <String>{},
  });

  final ProgressInfo info;
  final String headerTitle;
  final Set<String> currentSemesterCodes;

  @override
  State<RequirementCoursesPage> createState() => _RequirementCoursesPageState();
}

class _RequirementCoursesPageState extends State<RequirementCoursesPage> {
  final Set<String> _pinnedCodes = <String>{};

  String get _pinScope {
    final normalized = widget.headerTitle
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^_|_$'), '');
    return normalized.isEmpty ? 'requirement_all' : 'requirement_$normalized';
  }

  @override
  void initState() {
    super.initState();
    _loadPins();
  }

  Future<void> _loadPins() async {
    final pins = await CoursePinStore.load(_pinScope);
    if (!mounted) return;
    setState(() {
      _pinnedCodes
        ..clear()
        ..addAll(pins);
    });
  }

  Future<void> _togglePin(String code) async {
    final key = code.trim().toUpperCase();
    if (key.isEmpty) return;
    final willPin = !_pinnedCodes.contains(key);
    setState(() {
      if (willPin) {
        _pinnedCodes.add(key);
      } else {
        _pinnedCodes.remove(key);
      }
    });
    await CoursePinStore.save(_pinScope, _pinnedCodes);
    if (!mounted) return;
    showAppSnackBar(context, willPin ? '$key pinned to top' : '$key unpinned');
  }

  @override
  Widget build(BuildContext context) {
    final completedMap = <String, CompletedCourse>{
      for (final c in widget.info.completedCourses) c.code.toUpperCase(): c,
    };
    final currentSemesterCodes = widget.currentSemesterCodes
        .map((code) => code.trim().toUpperCase())
        .where((code) => code.isNotEmpty)
        .toSet();
    final courses = [...widget.info.coursesForHeader(widget.headerTitle)]
      ..sort((a, b) {
        final aCode = a.code.trim().toUpperCase();
        final bCode = b.code.trim().toUpperCase();
        final ap = _pinnedCodes.contains(aCode) ? 0 : 1;
        final bp = _pinnedCodes.contains(bCode) ? 0 : 1;
        if (ap != bp) {
          return ap.compareTo(bp);
        }
        final aTop =
            completedMap.containsKey(aCode) ||
                currentSemesterCodes.contains(aCode)
            ? 0
            : 1;
        final bTop =
            completedMap.containsKey(bCode) ||
                currentSemesterCodes.contains(bCode)
            ? 0
            : 1;
        if (aTop != bTop) {
          return aTop.compareTo(bTop);
        }
        return compareNaturalText(a.code, b.code);
      });

    return BracuPageScaffold(
      title: widget.headerTitle,
      subtitle: 'Requirement Courses',
      icon: Icons.menu_book_outlined,
      body: ListView.builder(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
        itemCount: courses.isEmpty ? 1 : courses.length,
        itemBuilder: (context, index) {
          if (courses.isEmpty) {
            return const BracuCard(
              child: BracuEmptyState(
                message: 'No courses found for this section.',
              ),
            );
          }
          final course = courses[index];
          final courseCode = course.code.trim().toUpperCase();
          final completed = completedMap[courseCode];
          final takingNow = currentSemesterCodes.contains(courseCode);
          final done = completed != null;
          final grade = completed?.grade.trim() ?? '';
          final gradeLabel = grade.isEmpty ? null : grade;
          final String? statusLabel;
          final Color? statusColor;
          if (done && gradeLabel == null) {
            statusLabel = 'Completed';
            statusColor = BracuPalette.accent;
          } else if (takingNow) {
            statusLabel = 'This semester';
            statusColor = BracuPalette.primary;
          } else {
            statusLabel = null;
            statusColor = null;
          }
          return CourseTile(
            code: course.code,
            title: course.title,
            credit: course.credit,
            isMandatory: course.isMandatory,
            isPinned: _pinnedCodes.contains(courseCode),
            onTogglePin: () => _togglePin(course.code),
            gradeLabel: gradeLabel,
            statusLabel: statusLabel,
            statusColor: statusColor,
            bottomPadding: 10,
          );
        },
      ),
    );
  }
}
