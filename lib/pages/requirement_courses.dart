import 'package:material_ui/material_ui.dart';
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

enum _CourseFilter { all, required, optional }

class _RequirementCoursesPageState extends State<RequirementCoursesPage> {
  final Set<String> _pinnedCodes = <String>{};
  _CourseFilter _filter = _CourseFilter.all;

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

  Future<void> _pickFilter(BuildContext anchorContext) async {
    final value = await showAppSelectDropdown<_CourseFilter>(
      anchorContext,
      title: 'Filter Courses',
      options: const [
        AppSelectOption(value: _CourseFilter.all, label: 'All Courses'),
        AppSelectOption(value: _CourseFilter.required, label: 'Required Only'),
        AppSelectOption(value: _CourseFilter.optional, label: 'Optional Only'),
      ],
      selectedValue: _filter,
    );
    if (value == null || !mounted) return;
    setState(() => _filter = value);
  }

  bool _matchesFilter(CurriculumCourse course) {
    return switch (_filter) {
      _CourseFilter.all => true,
      _CourseFilter.required => course.isMandatory,
      _CourseFilter.optional => !course.isMandatory,
    };
  }

  String get _emptyMessage {
    return switch (_filter) {
      _CourseFilter.all => 'No courses found for this section.',
      _CourseFilter.required => 'No required courses found for this section.',
      _CourseFilter.optional => 'No optional courses found for this section.',
    };
  }

  @override
  Widget build(BuildContext context) {
    final completedMap = <String, CompletedCourse>{
      for (final c in widget.info.completedCourses) courseCodeKey(c.code): c,
    };
    final inProgressCodes = widget.info.inProgressCourses
        .map((c) => courseCodeKey(c.code))
        .where((code) => code.isNotEmpty)
        .toSet();
    final currentSemesterCodes = {
      ...widget.currentSemesterCodes
          .map(courseCodeKey)
          .where((code) => code.isNotEmpty),
      ...inProgressCodes,
    };
    final courses = [...widget.info.coursesForHeader(widget.headerTitle)]
      ..retainWhere(_matchesFilter)
      ..sort((a, b) {
        final aCode = a.code.trim().toUpperCase();
        final bCode = b.code.trim().toUpperCase();
        final ap = _pinnedCodes.contains(aCode) ? 0 : 1;
        final bp = _pinnedCodes.contains(bCode) ? 0 : 1;
        if (ap != bp) {
          return ap.compareTo(bp);
        }
        final aKey = courseCodeKey(a.code);
        final bKey = courseCodeKey(b.code);
        final aDone = completedMap[aKey]?.isPassed == true;
        final bDone = completedMap[bKey]?.isPassed == true;
        final aTop = aDone || currentSemesterCodes.contains(aKey) ? 0 : 1;
        final bTop = bDone || currentSemesterCodes.contains(bKey) ? 0 : 1;
        if (aTop != bTop) {
          return aTop.compareTo(bTop);
        }
        return compareNaturalText(a.code, b.code);
      });

    return AppPageScaffold(
      title: widget.headerTitle,
      subtitle: 'Requirement Courses',
      icon: Icons.menu_book_outlined,
      actions: [
        Builder(
          builder: (chipContext) => AppSelectChip(
            icon: Icons.filter_list_rounded,
            selected: _filter != _CourseFilter.all,
            compact: true,
            showArrow: false,
            showBorder: false,
            onTap: () => _pickFilter(chipContext),
          ),
        ),
      ],
      body: ListView.builder(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
        itemCount: courses.isEmpty ? 1 : courses.length,
        itemBuilder: (context, index) {
          if (courses.isEmpty) {
            return AppCard(child: AppEmptyState(message: _emptyMessage));
          }
          final course = courses[index];
          final courseCode = course.code.trim().toUpperCase();
          final courseKey = courseCodeKey(course.code);
          final completed = completedMap[courseKey];
          final takingNow = currentSemesterCodes.contains(courseKey);
          final done = completed != null && completed.isPassed;
          final isFailed = completed != null && !completed.isPassed;
          final grade = completed?.grade.trim() ?? '';
          final gradeLabel = grade.isEmpty ? null : grade;
          final String? statusLabel;
          final Color? statusColor;
          if (takingNow) {
            statusLabel = isFailed ? 'This semester (Retake)' : 'This semester';
            statusColor = AppPalette.primary;
          } else if (done && gradeLabel == null) {
            statusLabel = 'Completed';
            statusColor = AppPalette.accent;
          } else if (isFailed) {
            statusLabel = 'Retake needed';
            statusColor = AppPalette.danger;
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
