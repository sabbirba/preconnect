// ignore_for_file: invalid_use_of_protected_member

part of 'package:preconnect/pages/degree_progress.dart';

extension _DegreeProgressPageStateHelpers on _DegreeProgressPageState {
  Future<void> _loadCurrentSemesterCourses() async {
    final currentSessionSemesterId = await resolveCurrentSessionSemesterId();
    if (currentSessionSemesterId == null) return;
    final scheduleService = ScheduleService();
    final scheduleJson = await scheduleService.getStudentScheduleForSemester(
      semesterSessionId: currentSessionSemesterId,
    );
    if (!mounted) return;
    final sections = section.parseSectionsFromScheduleJson(scheduleJson);
    if (_sameSections(_currentSemesterSections, sections)) return;
    setState(() {
      _currentSemesterSections = sections;
    });
  }

  bool _sameSections(List<section.Section> a, List<section.Section> b) {
    if (identical(a, b)) return true;
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      final left = a[i];
      final right = b[i];
      if (left.sectionId != right.sectionId) return false;
      if (left.courseCode != right.courseCode) return false;
      if (left.sectionName != right.sectionName) return false;
      if (left.courseCredit != right.courseCredit) return false;
      if (left.roomNumber != right.roomNumber) return false;
      if (left.semesterSessionId != right.semesterSessionId) return false;
    }
    return true;
  }

  bool _isLikelyRequired(String? courseType) {
    final type = (courseType ?? '').trim().toUpperCase();
    if (type.isEmpty) return false;
    if (type.contains('ELECTIVE')) return false;
    if (type.contains('OPTIONAL')) return false;
    return true;
  }

  String _resolveCurrentCourseTitle(
    section.Section current,
    Map<String, String> titleByCode,
  ) {
    final code = current.courseCode.trim().toUpperCase();
    final fromProgress = (titleByCode[code] ?? '').trim();
    if (fromProgress.isNotEmpty) return fromProgress;
    final fromSchedule = (current.name ?? '').trim();
    return fromSchedule;
  }

  bool _sameSummary(ProgressSummary? a, ProgressSummary? b) {
    if (a == null || b == null) return false;
    return a.programName == b.programName &&
        a.totalCredit == b.totalCredit &&
        a.completedCredit == b.completedCredit &&
        a.completionPercent == b.completionPercent &&
        a.remainingCourses == b.remainingCourses;
  }

  String _formatCredit(double value) {
    if (value % 1 == 0) {
      return value.toStringAsFixed(0);
    }
    return value.toStringAsFixed(1);
  }

  String _resolveProgramTitle(ProgressInfo info) {
    final curriculumName = info.programName.trim();
    if (_fullProgramName.isNotEmpty) return _fullProgramName;
    final summaryName = (_summary?.programName ?? '').trim();
    if (summaryName.isNotEmpty) return summaryName;
    if (curriculumName.isNotEmpty) return curriculumName;
    return 'Program';
  }

  List<_WishlistCourse> _buildWishlistCourses({
    required ProgressInfo info,
    required List<section.Section> currentSections,
  }) {
    final completedCodes = info.completedCourses
        .map((c) => c.code.trim().toUpperCase())
        .where((code) => code.isNotEmpty)
        .toSet();
    final currentCodes = currentSections
        .map((s) => s.courseCode.trim().toUpperCase())
        .where((code) => code.isNotEmpty)
        .toSet();
    final readyCodes = <String>{...completedCodes, ...currentCodes};

    final wishlist = <_WishlistCourse>[];
    for (final course in info.curriculumCourses) {
      final code = course.code.trim().toUpperCase();
      if (code.isEmpty) continue;
      if (completedCodes.contains(code) || currentCodes.contains(code)) {
        continue;
      }

      final prereqMet =
          course.prerequisiteExpression.trim().isEmpty ||
          _isPrerequisiteSatisfied(course.prerequisiteExpression, readyCodes);
      if (!prereqMet) continue;

      wishlist.add(
        _WishlistCourse(
          course: course,
          basis: course.prerequisiteExpression.trim().isEmpty
              ? _WishlistBasis.noPrerequisite
              : _WishlistBasis.prerequisiteSatisfied,
        ),
      );
    }

    wishlist.sort((a, b) {
      final basisCmp = a.basis.index.compareTo(b.basis.index);
      if (basisCmp != 0) return basisCmp;
      if (a.course.isMandatory != b.course.isMandatory) {
        return a.course.isMandatory ? -1 : 1;
      }
      return compareNaturalText(a.course.code, b.course.code);
    });

    return wishlist;
  }

  bool _isPrerequisiteSatisfied(String raw, Set<String> readyCodes) {
    final tokens = _tokenizePrerequisite(raw);
    if (tokens.isEmpty) return true;
    var index = 0;

    late bool Function() parseExpression;
    late bool Function() parseTerm;
    late bool Function() parseFactor;

    parseExpression = () {
      var value = parseTerm();
      while (index < tokens.length && tokens[index] == 'OR') {
        index++;
        value = value || parseTerm();
      }
      return value;
    };

    parseTerm = () {
      var value = parseFactor();
      while (index < tokens.length && tokens[index] == 'AND') {
        index++;
        value = value && parseFactor();
      }
      return value;
    };

    parseFactor = () {
      if (index >= tokens.length) return true;
      final token = tokens[index];
      if (token == '(') {
        index++;
        final value = parseExpression();
        if (index < tokens.length && tokens[index] == ')') {
          index++;
        }
        return value;
      }
      index++;
      return readyCodes.contains(token);
    };

    return parseExpression();
  }

  List<String> _tokenizePrerequisite(String raw) {
    final normalized = raw.trim().toUpperCase();
    if (normalized.isEmpty ||
        normalized == 'N/A' ||
        normalized == 'NONE' ||
        normalized == '-') {
      return const <String>[];
    }

    final pattern = RegExp(
      r'\(|\)|\bAND\b|\bOR\b|\b[A-Z]{2,4}\s*-?\s*\d{3,4}[A-Z]?\b',
    );
    return pattern
        .allMatches(normalized)
        .map((match) => (match.group(0) ?? '').replaceAll(RegExp(r'\s+'), ''))
        .where((token) => token.isNotEmpty)
        .toList();
  }
}

enum _WishlistBasis { prerequisiteSatisfied, noPrerequisite }

class _WishlistCourse {
  const _WishlistCourse({required this.course, required this.basis});

  final CurriculumCourse course;
  final _WishlistBasis basis;
}

class _Metric extends StatelessWidget {
  const _Metric({required this.title, required this.value});

  final String title;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      decoration: BoxDecoration(
        color: BracuPalette.textSecondary(context).withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(
            title,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: BracuPalette.textSecondary(context),
              fontSize: 10,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: BracuPalette.textPrimary(context),
              fontSize: 14,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _OptionWrap extends StatelessWidget {
  const _OptionWrap({required this.title, required this.items});

  final String title;
  final List<String> items;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(
            color: BracuPalette.textSecondary(context),
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: items.map((item) {
            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: BracuPalette.accent.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                item,
                style: const TextStyle(
                  color: BracuPalette.accent,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }
}
