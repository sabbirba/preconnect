import 'package:flutter/material.dart';
import 'package:preconnect/model/progress_info.dart';
import 'package:preconnect/model/section_info.dart' as section;
import 'package:preconnect/pages/ui_kit.dart';

part 'shared_widgets/cgpa_calculator_models.dart';

class CgpaCalculatorPage extends StatefulWidget {
  const CgpaCalculatorPage({
    super.key,
    required this.info,
    required this.currentSections,
    required this.currentCgpa,
  });

  final ProgressInfo info;
  final List<section.Section> currentSections;
  final String currentCgpa;

  @override
  State<CgpaCalculatorPage> createState() => _CgpaCalculatorPageState();
}

class _CgpaCalculatorPageState extends State<CgpaCalculatorPage> {
  final List<_CurrentCourseDraft> _currentCourses = <_CurrentCourseDraft>[];
  final List<_CompletedCourseDraft> _completedCourses =
      <_CompletedCourseDraft>[];
  final Map<String, String> _titleByCode = <String, String>{};
  final Map<String, bool> _mandatoryByCode = <String, bool>{};

  @override
  void initState() {
    super.initState();
    _buildTitleMap();
    _seedCompletedCourses();
    _seedCurrentCourses();
  }

  @override
  void dispose() {
    for (final draft in _currentCourses) {
      draft.dispose();
    }
    for (final draft in _completedCourses) {
      draft.dispose();
    }
    super.dispose();
  }

  void _buildTitleMap() {
    for (final course in widget.info.curriculumCourses) {
      final code = course.code.trim().toUpperCase();
      final title = course.title.trim();
      if (code.isEmpty || title.isEmpty) continue;
      _titleByCode[code] = title;
      _mandatoryByCode[code] = course.isMandatory;
    }
    for (final course in widget.info.completedCourses) {
      final code = course.code.trim().toUpperCase();
      final title = course.title.trim();
      if (code.isEmpty || title.isEmpty) continue;
      _titleByCode.putIfAbsent(code, () => title);
    }
  }

  void _seedCompletedCourses() {
    final completed = [...widget.info.completedCourses]
      ..sort(
        (a, b) => _semesterRank(
          a.semesterSession,
        ).compareTo(_semesterRank(b.semesterSession)),
      );
    for (final course in completed) {
      _completedCourses.add(
        _CompletedCourseDraft.auto(
          code: course.code,
          title: course.title,
          credit: _formatCredit(course.credit),
          grade: _normalizeImportedGrade(course.grade),
          semester: course.semesterSession,
          isRequired:
              _mandatoryByCode[course.code.trim().toUpperCase()] ?? false,
        ),
      );
    }
  }

  void _seedCurrentCourses() {
    final sorted = [...widget.currentSections]
      ..sort((a, b) => compareNaturalText(a.courseCode, b.courseCode));
    for (final item in sorted) {
      final code = item.courseCode.trim().toUpperCase();
      final title = (_titleByCode[code] ?? (item.name ?? '')).trim();
      _currentCourses.add(
        _CurrentCourseDraft(
          code: code,
          title: title,
          credit: item.courseCredit <= 0 ? '' : '${item.courseCredit}',
          isRequired: _mandatoryByCode[code] ?? true,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final expectedResult = _buildExpectedResult();
    final completedCodes = _completedEffectiveCodes;
    final autoRetakeCodes = _currentCourses
        .where((draft) => completedCodes.contains(draft.codeValue))
        .map((draft) => draft.codeValue)
        .toSet();
    final autoRetakeCurrentCourses =
        _currentCourses
            .where((draft) => autoRetakeCodes.contains(draft.codeValue))
            .toList()
          ..sort((a, b) => compareNaturalText(a.codeValue, b.codeValue));
    final manualRetakeCourses = _selectedRetakeCourses
        .where((draft) => !autoRetakeCodes.contains(draft.codeValue))
        .toList();
    return BracuPageScaffold(
      title: 'Expected CGPA',
      subtitle: 'Grade Calculator',
      icon: Icons.calculate_outlined,
      body: ListView(
        padding: kBracuPageListPadding,
        children: [
          _buildSummaryCard(context, expectedResult),
          if (autoRetakeCurrentCourses.isNotEmpty ||
              manualRetakeCourses.isNotEmpty) ...[
            const SizedBox(height: 14),
            const BracuSectionTitle(title: 'Retake Courses'),
            const SizedBox(height: 10),
            ...autoRetakeCurrentCourses.map((draft) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _buildCurrentRetakeCourseCard(context, draft),
              );
            }),
            ...manualRetakeCourses.map((draft) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _buildRetakeCourseCard(context, draft),
              );
            }),
          ],
          const SizedBox(height: 14),
          const BracuSectionTitle(title: 'Current Courses'),
          const SizedBox(height: 10),
          ..._currentCourses.map((draft) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _buildCurrentCourseCard(context, draft),
            );
          }),
          const SizedBox(height: 18),
          const BracuSectionTitle(title: 'Completed Courses'),
          const SizedBox(height: 10),
          ..._completedCourses.map((draft) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _buildCompletedCourseCard(context, draft),
            );
          }),
        ],
      ),
    );
  }

  List<_CompletedCourseDraft> get _selectedRetakeCourses {
    final list = _completedCourses
        .where((draft) => draft.hasRetakeSelection)
        .toList();
    list.sort((a, b) => compareNaturalText(a.codeValue, b.codeValue));
    return list;
  }

  Set<String> get _completedEffectiveCodes {
    final codes = <String>{};
    for (final draft in _completedCourses) {
      final snapshot = draft.toCompletedSnapshot();
      if (!snapshot.countsToGpa || snapshot.code.isEmpty) continue;
      codes.add(snapshot.code);
    }
    return codes;
  }

  Widget _buildSummaryCard(
    BuildContext context,
    _ExpectedResult expectedResult,
  ) {
    final delta = expectedResult.cgpaDelta;
    final deltaValue = delta.abs().clamp(0.0, 1.0);
    final deltaColor = delta >= 0 ? BracuPalette.accent : BracuPalette.warning;
    final selectedRetakes = _selectedRetakeCourses;
    final stats = <({String title, String value})>[
      (title: 'Current', value: expectedResult.currentCgpaLabel),
      (title: 'Expected', value: expectedResult.expectedCgpaLabel),
      (
        title: 'Delta',
        value:
            '${expectedResult.cgpaDelta >= 0 ? '+' : ''}${expectedResult.cgpaDelta.toStringAsFixed(3)}',
      ),
      (
        title: 'Courses',
        value: '${_currentCourses.length + selectedRetakes.length}',
      ),
      (title: 'Retakes', value: '${selectedRetakes.length}'),
      (title: 'Credits', value: _formatCredit(expectedResult.selectedCredits)),
    ];
    return BracuCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Summary',
            style: TextStyle(
              color: BracuPalette.textPrimary(context),
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 12),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: List.generate(stats.length, (index) {
                final item = stats[index];
                return Padding(
                  padding: EdgeInsets.only(
                    right: index == stats.length - 1 ? 0 : 10,
                  ),
                  child: SizedBox(
                    width: 96,
                    child: _Metric(title: item.title, value: item.value),
                  ),
                );
              }),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: SimpleProgressBar(value: deltaValue, color: deltaColor),
              ),
              const SizedBox(width: 8),
              Text(
                '${delta >= 0 ? '+' : ''}${delta.toStringAsFixed(3)}',
                style: TextStyle(
                  color: deltaColor,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCurrentCourseCard(
    BuildContext context,
    _CurrentCourseDraft draft,
  ) {
    final isRetake = _completedEffectiveCodes.contains(draft.codeValue);
    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: () async {
        final selected = await _pickGrade(
          courseCode: draft.codeValue,
          subtitle: 'Choose expected grade',
          currentGrade: draft.grade,
          resetGrade: 'A',
        );
        if (!mounted || selected == null) return;
        final wasReset = selected == 'A' && draft.grade != 'A';
        setState(() {
          draft.grade = selected;
        });
        _showCalculatorSnackBar(
          wasReset
              ? '${draft.codeValue} reset to A'
              : '${draft.codeValue} grade set to $selected',
        );
      },
      child: BracuCard(
        child: _buildCourseCard(
          context,
          badgeLabel: draft.grade,
          codeLine: draft.codeValue,
          titleLine: draft.titleValue,
          creditLine: draft.creditValue,
          statusLabel: isRetake
              ? 'Retake'
              : (draft.isRequired ? 'Required' : 'Elective'),
          statusColor: isRetake
              ? BracuPalette.info
              : (draft.isRequired ? BracuPalette.warning : BracuPalette.accent),
        ),
      ),
    );
  }

  Widget _buildCurrentRetakeCourseCard(
    BuildContext context,
    _CurrentCourseDraft draft,
  ) {
    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: () async {
        final selected = await _pickGrade(
          courseCode: draft.codeValue,
          subtitle: 'Choose retake grade',
          currentGrade: draft.grade,
          resetGrade: 'A',
        );
        if (!mounted || selected == null) return;
        final wasReset = selected == 'A' && draft.grade != 'A';
        setState(() {
          draft.grade = selected;
        });
        _showCalculatorSnackBar(
          wasReset
              ? '${draft.codeValue} retake reset to A'
              : '${draft.codeValue} retake set to $selected',
        );
      },
      child: BracuCard(
        child: _buildCourseCard(
          context,
          badgeLabel: draft.grade,
          codeLine: draft.codeValue,
          titleLine: draft.titleValue,
          creditLine: draft.creditValue,
          statusLabel: 'Retake',
          statusColor: BracuPalette.info,
        ),
      ),
    );
  }

  Widget _buildRetakeCourseCard(
    BuildContext context,
    _CompletedCourseDraft draft,
  ) {
    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: () async {
        final selected = await _pickGrade(
          courseCode: draft.codeValue,
          subtitle: 'Choose retake grade',
          currentGrade: draft.selectedRetakeGrade ?? draft.completedGrade,
          resetGrade: draft.completedGrade,
        );
        if (!mounted || selected == null) return;
        final wasReset = selected == draft.completedGrade;
        setState(() {
          draft.selectedRetakeGrade = selected == draft.completedGrade
              ? null
              : selected;
        });
        _showCalculatorSnackBar(
          wasReset
              ? '${draft.codeValue} retake reset'
              : '${draft.codeValue} retake set to $selected',
        );
      },
      child: BracuCard(
        child: _buildCourseCard(
          context,
          badgeLabel: draft.selectedRetakeGrade ?? draft.completedGrade,
          codeLine: draft.codeValue,
          titleLine: draft.titleValue,
          creditLine: draft.creditValue,
          statusLabel: 'Retake',
          statusColor: BracuPalette.info,
        ),
      ),
    );
  }

  Widget _buildCompletedCourseCard(
    BuildContext context,
    _CompletedCourseDraft draft,
  ) {
    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: () async {
        final selected = await _pickGrade(
          courseCode: draft.codeValue,
          subtitle: 'Choose retake grade',
          currentGrade: draft.selectedRetakeGrade ?? draft.completedGrade,
          resetGrade: draft.completedGrade,
        );
        if (!mounted || selected == null) return;
        final wasReset = selected == draft.completedGrade;
        setState(() {
          draft.selectedRetakeGrade = selected == draft.completedGrade
              ? null
              : selected;
        });
        _showCalculatorSnackBar(
          wasReset
              ? '${draft.codeValue} retake reset'
              : '${draft.codeValue} retake set to $selected',
        );
      },
      child: BracuCard(
        child: _buildCourseCard(
          context,
          badgeLabel: draft.selectedRetakeGrade ?? draft.completedGrade,
          codeLine: draft.semesterValue.isEmpty
              ? draft.codeValue
              : '${draft.codeValue} • ${formatSemesterTitle(draft.semesterValue)}',
          titleLine: draft.titleValue,
          creditLine: draft.creditValue,
          statusLabel: draft.isRequired ? 'Required' : 'Elective',
          statusColor: draft.isRequired
              ? BracuPalette.warning
              : BracuPalette.accent,
          trailingNote: draft.hasRetakeSelection
              ? 'Retake: ${draft.selectedRetakeGrade}'
              : null,
        ),
      ),
    );
  }

  void _showCalculatorSnackBar(String message) {
    if (!mounted) return;
    showAppSnackBar(context, message);
  }

  Widget _buildCourseCard(
    BuildContext context, {
    required String badgeLabel,
    required String codeLine,
    required String titleLine,
    required String creditLine,
    required String statusLabel,
    required Color statusColor,
    String? trailingNote,
  }) {
    final resolvedCode = codeLine.trim().isEmpty ? '--' : codeLine.trim();
    final resolvedTitle = titleLine.trim().isEmpty
        ? resolvedCode
        : titleLine.trim();
    final resolvedCredit = creditLine.trim().isEmpty ? '--' : creditLine.trim();
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionBadge(
          label: badgeLabel,
          color: BracuPalette.primary,
          size: 40,
          fontSize: 13,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                resolvedCode,
                style: TextStyle(
                  color: BracuPalette.textPrimary(context),
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                resolvedTitle,
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
                '$resolvedCredit credits',
                style: TextStyle(
                  color: BracuPalette.textPrimary(context),
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                statusLabel,
                style: TextStyle(
                  color: statusColor,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (trailingNote != null && trailingNote.trim().isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(
                  trailingNote.trim(),
                  style: TextStyle(
                    color: BracuPalette.textSecondary(context),
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  _ExpectedResult _buildExpectedResult() {
    final baseline = _buildBaseline();
    var selectedCredits = 0.0;
    var selectedQualityPoints = 0.0;
    var totalCredits = baseline.totalCredits;
    var totalQualityPoints = baseline.qualityPoints;
    final manualRetakeByCode = {
      for (final draft in _selectedRetakeCourses) draft.codeValue: draft,
    };
    final autoRetakeByCode = <String, _CourseSnapshot>{};
    for (final draft in _currentCourses) {
      final snapshot = draft.toSnapshot();
      if (!snapshot.countsToGpa || snapshot.code.isEmpty) continue;
      if (!baseline.effectiveByCode.containsKey(snapshot.code)) continue;
      autoRetakeByCode[snapshot.code] = snapshot;
    }
    final retakeCodes = <String>{
      ...manualRetakeByCode.keys,
      ...autoRetakeByCode.keys,
    };

    for (final code in retakeCodes) {
      final completedSnapshot = baseline.effectiveByCode[code];
      if (completedSnapshot == null || !completedSnapshot.countsToGpa) {
        continue;
      }
      final manualDraft = manualRetakeByCode[code];
      final retakeSnapshot =
          autoRetakeByCode[code] ?? manualDraft?.toRetakeSnapshot();
      if (retakeSnapshot == null || !retakeSnapshot.countsToGpa) continue;

      selectedCredits += retakeSnapshot.credit;
      selectedQualityPoints += retakeSnapshot.qualityPoints;
      totalQualityPoints +=
          retakeSnapshot.qualityPoints - completedSnapshot.qualityPoints;
    }

    for (final draft in _currentCourses) {
      final snapshot = draft.toSnapshot();
      if (!snapshot.countsToGpa) continue;
      if (retakeCodes.contains(snapshot.code)) continue;
      selectedCredits += snapshot.credit;
      selectedQualityPoints += snapshot.qualityPoints;
      totalCredits += snapshot.credit;
      totalQualityPoints += snapshot.qualityPoints;
    }

    final currentCgpa = baseline.cgpa;
    final expectedCgpa = totalCredits <= 0
        ? 0.0
        : totalQualityPoints / totalCredits;
    final selectedGpa = selectedCredits <= 0
        ? 0.0
        : selectedQualityPoints / selectedCredits;
    return _ExpectedResult(
      currentCgpa: currentCgpa,
      expectedCgpa: expectedCgpa,
      selectedGpa: selectedGpa,
      cgpaDelta: expectedCgpa - currentCgpa,
      selectedCredits: selectedCredits,
      usedOfficialCgpa: baseline.usedOfficialCgpa,
    );
  }

  _Baseline _buildBaseline() {
    final effectiveByCode = <String, _CourseSnapshot>{};
    for (final draft in _completedCourses) {
      final snapshot = draft.toCompletedSnapshot();
      if (!snapshot.countsToGpa || snapshot.code.isEmpty) continue;
      effectiveByCode[snapshot.code] = snapshot;
    }

    var derivedCredits = 0.0;
    var derivedQualityPoints = 0.0;
    for (final snapshot in effectiveByCode.values) {
      derivedCredits += snapshot.credit;
      derivedQualityPoints += snapshot.qualityPoints;
    }

    final officialCgpa = double.tryParse(widget.currentCgpa.trim());
    final usedOfficialCgpa = officialCgpa != null && derivedCredits > 0;
    final cgpa = usedOfficialCgpa
        ? officialCgpa
        : (derivedCredits <= 0 ? 0.0 : derivedQualityPoints / derivedCredits);
    final qualityPoints = cgpa * derivedCredits;

    return _Baseline(
      cgpa: cgpa,
      totalCredits: derivedCredits,
      qualityPoints: qualityPoints,
      effectiveByCode: effectiveByCode,
      usedOfficialCgpa: usedOfficialCgpa,
    );
  }

  Future<String?> _pickGrade({
    required String courseCode,
    required String subtitle,
    required String currentGrade,
    required String resetGrade,
  }) {
    return showBracuBottomSheet<String>(
      context,
      title: courseCode.isEmpty ? 'Select grade' : courseCode,
      subtitle: subtitle,
      initialChildSize: 0.40,
      actions: [
        IconButton(
          onPressed: () => Navigator.of(context).pop(resetGrade),
          icon: Icon(
            Icons.refresh_rounded,
            color: BracuPalette.textSecondary(context),
          ),
          tooltip: 'Reset',
        ),
      ],
      builder: (sheetContext, textPrimary, textSecondary) {
        return SingleChildScrollView(
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _gradeOptions.map((grade) {
              final selected = currentGrade == grade;
              return ChoiceChip(
                label: Text(grade),
                selected: selected,
                showCheckmark: false,
                labelStyle: TextStyle(
                  color: selected ? BracuPalette.primary : textPrimary,
                  fontWeight: FontWeight.w700,
                ),
                backgroundColor: BracuPalette.card(
                  sheetContext,
                ).withValues(alpha: 0.92),
                selectedColor: BracuPalette.primary.withValues(alpha: 0.14),
                side: BorderSide(
                  color: selected
                      ? BracuPalette.primary
                      : textSecondary.withValues(alpha: 0.24),
                ),
                onSelected: (_) => Navigator.of(sheetContext).pop(grade),
              );
            }).toList(),
          ),
        );
      },
    );
  }

  int _semesterRank(String raw) {
    final cleaned = raw.trim();
    if (cleaned.isEmpty) return -1;
    final numeric = int.tryParse(cleaned);
    if (numeric != null) return numeric;
    final lower = cleaned.toLowerCase();
    final yearMatch = RegExp(r'(19|20)\d{2}').firstMatch(lower);
    final year = yearMatch == null ? 0 : int.tryParse(yearMatch.group(0)!) ?? 0;
    var season = 0;
    if (lower.contains('spring')) {
      season = 1;
    } else if (lower.contains('summer')) {
      season = 2;
    } else if (lower.contains('fall')) {
      season = 3;
    }
    return (year * 10) + season;
  }
}
