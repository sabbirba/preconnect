import 'package:flutter/material.dart';
import 'package:preconnect/model/progress_info.dart';
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
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
        children: [
          if (courses.isEmpty)
            const BracuCard(
              child: BracuEmptyState(
                message: 'No courses found for this section.',
              ),
            )
          else
            ...courses.map((course) {
              final courseCode = course.code.trim().toUpperCase();
              final completed = completedMap[courseCode];
              final takingNow = currentSemesterCodes.contains(courseCode);
              final done = completed != null;
              final grade = completed?.grade.trim() ?? '';
              final infoLabel = course.isMandatory ? 'Required' : 'Optional';
              final gradeLabel = grade.isEmpty ? null : grade;
              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: BracuCard(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      if (gradeLabel != null) ...[
                        SectionBadge(
                          label: gradeLabel,
                          color: BracuPalette.primary,
                          size: 40,
                          fontSize: 13,
                        ),
                        const SizedBox(width: 10),
                      ],
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                Flexible(
                                  child: Text.rich(
                                    TextSpan(
                                      children: [
                                        TextSpan(text: course.code),
                                        WidgetSpan(
                                          alignment:
                                              PlaceholderAlignment.middle,
                                          child: Padding(
                                            padding: const EdgeInsets.only(
                                              left: 4,
                                            ),
                                            child: Tooltip(
                                              message:
                                                  _pinnedCodes.contains(
                                                    course.code.toUpperCase(),
                                                  )
                                                  ? 'Unpin'
                                                  : 'Pin to top',
                                              child: InkWell(
                                                borderRadius:
                                                    BorderRadius.circular(999),
                                                onTap: () =>
                                                    _togglePin(course.code),
                                                child: Icon(
                                                  _pinnedCodes.contains(
                                                        course.code
                                                            .toUpperCase(),
                                                      )
                                                      ? Icons.star_rounded
                                                      : Icons
                                                            .star_outline_rounded,
                                                  size: 16,
                                                  color:
                                                      _pinnedCodes.contains(
                                                        course.code
                                                            .toUpperCase(),
                                                      )
                                                      ? BracuPalette.favorite
                                                      : BracuPalette.textSecondary(
                                                          context,
                                                        ),
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    style: TextStyle(
                                      color: BracuPalette.textPrimary(context),
                                      fontSize: 13,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 3),
                            Text(
                              course.title.isEmpty ? '--' : course.title,
                              style: TextStyle(
                                color: BracuPalette.textSecondary(context),
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 10),
                      SizedBox(
                        width: 96,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              '${_formatCredit(course.credit)} credits',
                              style: TextStyle(
                                color: BracuPalette.textPrimary(context),
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 1),
                            Text(
                              infoLabel,
                              style: TextStyle(
                                color: course.isMandatory
                                    ? BracuPalette.warning
                                    : BracuPalette.accent,
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            if (done && gradeLabel == null) ...[
                              const SizedBox(height: 2),
                              Text(
                                'Completed',
                                style: TextStyle(
                                  color: BracuPalette.accent,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ] else if (takingNow) ...[
                              const SizedBox(height: 2),
                              Text(
                                'This semester',
                                style: TextStyle(
                                  color: BracuPalette.primary,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }),
        ],
      ),
    );
  }

  String _formatCredit(double value) {
    if (value % 1 == 0) return value.toStringAsFixed(0);
    return value.toStringAsFixed(1);
  }
}
