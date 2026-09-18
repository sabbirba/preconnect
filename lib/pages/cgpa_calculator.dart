import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:gap/gap.dart';
import 'package:preconnect/model/progress_info.dart';
import 'package:preconnect/model/section_info.dart' as section;
import 'package:preconnect/pages/shared_widgets/metric_tile.dart';
import 'package:preconnect/pages/ui_kit.dart';
import 'package:preconnect/tools/app_storage.dart';
import 'package:preconnect/tools/storage_keys.dart';
import 'package:preconnect/tools/string_utils.dart';

part 'shared_widgets/cgpa_models.dart';

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
  final List<_PlannedCourseDraft> _plannedCourses = <_PlannedCourseDraft>[];
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
    _loadFromStorage();
  }

  Future<String> _storageKey() async {
    final studentId = await AppStorage.instance.getString(
      StorageKeys.studentId,
    );
    final trimmed = studentId?.trim();
    if (trimmed != null && trimmed.isNotEmpty) {
      return 'cgpa_calc_data_$trimmed';
    }
    return 'cgpa_calc_data_default';
  }

  Future<void> _saveToStorage() async {
    final currentGrades = <String, String>{};
    for (final draft in _currentCourses) {
      if (draft.codeValue.isNotEmpty && draft.grade != 'A') {
        currentGrades[draft.codeValue] = draft.grade;
      }
    }

    final plannedList = _plannedCourses.map((draft) {
      return {
        'code': draft.codeValue,
        'title': draft.titleValue,
        'credit': draft.creditValue,
        'grade': draft.grade,
      };
    }).toList();

    final retakeGrades = <String, String>{};
    for (final draft in _completedCourses) {
      if (draft.hasRetakeSelection && draft.codeValue.isNotEmpty) {
        retakeGrades[draft.codeValue] = draft.selectedRetakeGrade!;
      }
    }

    final key = await _storageKey();
    if (currentGrades.isEmpty && plannedList.isEmpty && retakeGrades.isEmpty) {
      await AppStorage.instance.setString(key, '');
      return;
    }

    final payload = jsonEncode({
      'currentGrades': currentGrades,
      'plannedCourses': plannedList,
      'retakeGrades': retakeGrades,
    });
    await AppStorage.instance.setString(key, payload);
  }

  Future<void> _loadFromStorage() async {
    try {
      final key = await _storageKey();
      final raw = await AppStorage.instance.getString(key);
      if (raw == null || raw.trim().isEmpty) return;
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return;

      final currentGrades = decoded['currentGrades'];
      if (currentGrades is Map) {
        for (final draft in _currentCourses) {
          final saved = currentGrades[draft.codeValue];
          if (saved is String && _gradeOptions.contains(saved)) {
            draft.grade = saved;
          }
        }
      }

      final plannedList = decoded['plannedCourses'];
      if (plannedList is List) {
        for (final draft in _plannedCourses) {
          draft.dispose();
        }
        _plannedCourses.clear();
        for (final item in plannedList) {
          if (item is Map) {
            final code = (item['code'] ?? '').toString();
            final title = (item['title'] ?? '').toString();
            final credit = (item['credit'] ?? '3').toString();
            final grade = (item['grade'] ?? 'A').toString();
            _plannedCourses.add(
              _PlannedCourseDraft(
                code: code,
                title: title,
                credit: credit,
                grade: _normalizeGrade(grade),
              ),
            );
          }
        }
      }

      final retakeGrades = decoded['retakeGrades'];
      if (retakeGrades is Map) {
        for (final draft in _completedCourses) {
          final saved = retakeGrades[draft.codeValue];
          if (saved is String && _gradeOptions.contains(saved)) {
            draft.selectedRetakeGrade = saved;
          }
        }
      }

      if (mounted) {
        setState(() {});
      }
    } catch (_) {}
  }

  bool get _hasCurrentModifications =>
      _currentCourses.any((draft) => draft.grade != 'A');

  bool get _hasCompletedRetakeModifications =>
      _completedCourses.any((draft) => draft.hasRetakeSelection);

  void _resetCurrentCourses() {
    setState(() {
      for (final draft in _currentCourses) {
        draft.grade = 'A';
      }
    });
    _saveToStorage();
    _showCalculatorSnackBar('Current course grades reset to A');
  }

  void _resetCompletedRetakes() {
    setState(() {
      for (final draft in _completedCourses) {
        draft.selectedRetakeGrade = null;
      }
    });
    _saveToStorage();
    _showCalculatorSnackBar('All retake courses reset');
  }

  @override
  void dispose() {
    for (final draft in _currentCourses) {
      draft.dispose();
    }
    for (final draft in _plannedCourses) {
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
          credit: formatCredit(course.credit),
          grade: _normalizeImportedGrade(course.grade),
          gradePoint: course.gradePoint,
          semester: course.semesterSession,
          isRequired:
              _mandatoryByCode[course.code.trim().toUpperCase()] ?? false,
        ),
      );
    }
  }

  void _seedCurrentCourses() {
    final seen = <String>{};
    final sorted = [...widget.currentSections]
      ..sort((a, b) => compareNaturalText(a.courseCode, b.courseCode));
    for (final item in sorted) {
      final code = item.courseCode.trim().toUpperCase();
      if (code.isEmpty || seen.contains(code)) continue;
      seen.add(code);
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
    for (final item in widget.info.inProgressCourses) {
      final code = item.code.trim().toUpperCase();
      if (code.isEmpty || seen.contains(code)) continue;
      seen.add(code);
      final title = (_titleByCode[code] ?? item.title).trim();
      _currentCourses.add(
        _CurrentCourseDraft(
          code: code,
          title: title,
          credit: item.credit <= 0 ? '' : '${item.credit}',
          isRequired: _mandatoryByCode[code] ?? true,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final expectedResult = _buildExpectedResult();
    return AppPageScaffold(
      title: 'Expected CGPA',
      subtitle: 'Grade Calculator',
      icon: Icons.calculate_outlined,
      body: ListView(
        padding: kPageListPadding,
        children: [
          _buildSummaryCard(context, expectedResult),
          const Gap(16),
          const AppSectionTitle(title: 'Current Courses'),
          const Gap(12),
          ..._currentCourses.map((draft) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _buildCurrentCourseCard(context, draft),
            );
          }),
          if (_hasCurrentModifications)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Center(
                child: OutlinedButton.icon(
                  onPressed: _resetCurrentCourses,
                  icon: const Icon(Icons.refresh_rounded, size: 16),
                  label: const Text('Reset Current Courses'),
                  style: appOutlinedButtonStyle(
                    context,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 9,
                    ),
                    borderRadius: 14,
                  ),
                ),
              ),
            ),
          const Gap(16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const AppSectionTitle(title: 'Planned Courses'),
              TextButton.icon(
                onPressed: _showAddPlannedCourseSheet,
                icon: const Icon(Icons.add_rounded, size: 18),
                label: const Text('Add Course'),
                style: TextButton.styleFrom(
                  foregroundColor: AppPalette.primary,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
            ],
          ),
          const Gap(12),
          if (_plannedCourses.isEmpty)
            InkWell(
              borderRadius: BorderRadius.circular(18),
              onTap: _showAddPlannedCourseSheet,
              child: AppCard(
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.add_circle_outline_rounded,
                          size: 18,
                          color: AppPalette.primary,
                        ),
                        const Gap(8),
                        Text(
                          'Add hypothetical or future course',
                          style: TextStyle(
                            color: AppPalette.primary,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            )
          else
            ..._plannedCourses.map((draft) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _buildPlannedCourseCard(context, draft),
              );
            }),
          const Gap(16),
          const AppSectionTitle(title: 'Completed Courses'),
          const Gap(12),
          ..._completedCourses.map((draft) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _buildCompletedCourseCard(context, draft),
            );
          }),
          if (_hasCompletedRetakeModifications)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Center(
                child: OutlinedButton.icon(
                  onPressed: _resetCompletedRetakes,
                  icon: const Icon(Icons.refresh_rounded, size: 16),
                  label: const Text('Reset Retake Courses'),
                  style: appOutlinedButtonStyle(
                    context,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 9,
                    ),
                    borderRadius: 14,
                  ),
                ),
              ),
            ),
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
    final deltaColor = delta >= 0 ? AppPalette.accent : AppPalette.warning;
    final stats = <({String title, String value})>[
      (title: 'Current', value: expectedResult.currentCgpaLabel),
      (title: 'Expected', value: expectedResult.expectedCgpaLabel),
      (
        title: 'Delta',
        value:
            '${expectedResult.cgpaDelta >= 0 ? '+' : ''}${expectedResult.cgpaDelta.toStringAsFixed(3)}',
      ),
      (title: 'Round Up', value: expectedResult.roundUpCgpaLabel),
      (title: 'Courses', value: '${expectedResult.evaluatedCourseCount}'),
      (title: 'Retakes', value: '${expectedResult.retakeCount}'),
      (title: 'Credits', value: formatCredit(expectedResult.selectedCredits)),
    ];
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Summary',
            style: TextStyle(
              color: AppPalette.textPrimary(context),
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
          ),
          const Gap(12),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: List.generate(stats.length, (index) {
                final item = stats[index];
                return Padding(
                  padding: EdgeInsets.only(
                    right: index == stats.length - 1 ? 0 : 12,
                  ),
                  child: SizedBox(
                    width: 96,
                    child: MetricTile(title: item.title, value: item.value),
                  ),
                );
              }),
            ),
          ),
          const Gap(12),
          Row(
            children: [
              Expanded(
                child: SimpleProgressBar(value: deltaValue, color: deltaColor),
              ),
              const Gap(12),
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
          isRetake: isRetake,
        );
        if (!mounted || selected == null) return;
        final wasReset = selected == 'A' && draft.grade != 'A';
        setState(() {
          draft.grade = selected;
        });
        _saveToStorage();
        _showCalculatorSnackBar(
          wasReset
              ? '${draft.codeValue} reset to A'
              : '${draft.codeValue} grade set to $selected',
        );
      },
      child: AppCard(
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
              ? AppPalette.info
              : (draft.isRequired ? AppPalette.warning : AppPalette.accent),
        ),
      ),
    );
  }

  Widget _buildPlannedCourseCard(
    BuildContext context,
    _PlannedCourseDraft draft,
  ) {
    final isRetake = _completedEffectiveCodes.contains(draft.codeValue);
    return Dismissible(
      key: ValueKey(draft),
      direction: DismissDirection.endToStart,
      onDismissed: (_) {
        setState(() {
          _plannedCourses.remove(draft);
        });
        draft.dispose();
        _saveToStorage();
        _showCalculatorSnackBar('Removed ${draft.codeValue}');
      },
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        decoration: BoxDecoration(
          color: AppPalette.danger.withValues(alpha: 0.16),
          borderRadius: BorderRadius.circular(18),
        ),
        child: const Icon(
          Icons.delete_outline_rounded,
          color: AppPalette.danger,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () async {
          final selected = await _pickGrade(
            courseCode: draft.codeValue,
            subtitle: 'Choose expected grade',
            currentGrade: draft.grade,
            resetGrade: 'A',
            isRetake: isRetake,
          );
          if (!mounted || selected == null) return;
          final wasReset = selected == 'A' && draft.grade != 'A';
          setState(() {
            draft.grade = selected;
          });
          _saveToStorage();
          _showCalculatorSnackBar(
            wasReset
                ? '${draft.codeValue} reset to A'
                : '${draft.codeValue} grade set to $selected',
          );
        },
        child: AppCard(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              SectionBadge(
                label: draft.grade,
                color: AppPalette.primary,
                size: 40,
                fontSize: 13,
              ),
              const Gap(12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      draft.codeValue.isEmpty
                          ? 'Custom Course'
                          : draft.codeValue,
                      style: TextStyle(
                        color: AppPalette.textPrimary(context),
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const Gap(3),
                    Text(
                      draft.titleValue.isEmpty
                          ? 'Planned Course'
                          : draft.titleValue,
                      style: TextStyle(
                        color: AppPalette.textSecondary(context),
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
              const Gap(8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '${draft.creditValue.isEmpty ? "3" : draft.creditValue} credits',
                    style: TextStyle(
                      color: AppPalette.textPrimary(context),
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const Gap(2),
                  Text(
                    isRetake ? 'Retake' : 'Planned',
                    style: TextStyle(
                      color: isRetake ? AppPalette.info : AppPalette.accent,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
              const Gap(4),
              IconButton(
                onPressed: () {
                  setState(() {
                    _plannedCourses.remove(draft);
                  });
                  draft.dispose();
                  _saveToStorage();
                  _showCalculatorSnackBar('Removed ${draft.codeValue}');
                },
                icon: Icon(
                  Icons.delete_outline_rounded,
                  size: 20,
                  color: AppPalette.textSecondary(context),
                ),
                tooltip: 'Remove',
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showAddPlannedCourseSheet() async {
    final codeController = TextEditingController();
    final titleController = TextEditingController();
    var selectedCredit = '3';
    var selectedGrade = 'A';
    final creditOptions = [
      '1',
      '1.5',
      '2',
      '3',
      '4',
      '4.5',
      '6',
      '8',
      '10',
      '12',
      '18',
    ];

    await showAppBottomSheet<void>(
      context,
      title: 'Add Planned Course',
      subtitle: 'Simulate a future or hypothetical course',
      initialChildSize: 0.75,
      builder: (sheetContext, textPrimary, textSecondary) {
        return StatefulBuilder(
          builder: (dialogContext, setDialogState) {
            final dragController = bottomSheetScrollController(sheetContext);
            return ListView(
              controller: dragController,
              physics: const ClampingScrollPhysics(),
              padding: const EdgeInsets.only(bottom: 24),
              children: [
                TextField(
                  controller: codeController,
                  textCapitalization: TextCapitalization.characters,
                  style: TextStyle(color: textPrimary),
                  decoration: InputDecoration(
                    labelText: 'Course Code',
                    hintText: 'e.g. CSE421',
                    labelStyle: TextStyle(color: textSecondary),
                    hintStyle: TextStyle(
                      color: textSecondary.withValues(alpha: 0.6),
                    ),
                    isDense: true,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide(
                        color: textSecondary.withValues(alpha: 0.24),
                      ),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: const BorderSide(color: AppPalette.primary),
                    ),
                  ),
                ),
                const Gap(12),
                TextField(
                  controller: titleController,
                  textCapitalization: TextCapitalization.words,
                  style: TextStyle(color: textPrimary),
                  decoration: InputDecoration(
                    labelText: 'Course Title (Optional)',
                    hintText: 'e.g. Computer Networks',
                    labelStyle: TextStyle(color: textSecondary),
                    hintStyle: TextStyle(
                      color: textSecondary.withValues(alpha: 0.6),
                    ),
                    isDense: true,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide(
                        color: textSecondary.withValues(alpha: 0.24),
                      ),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: const BorderSide(color: AppPalette.primary),
                    ),
                  ),
                ),
                const Gap(16),
                Text(
                  'Credits',
                  style: TextStyle(
                    color: textPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Gap(8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: creditOptions.map((credit) {
                    final isSelected = selectedCredit == credit;
                    return ChoiceChip(
                      label: Text(credit),
                      selected: isSelected,
                      showCheckmark: false,
                      labelStyle: TextStyle(
                        color: isSelected ? AppPalette.primary : textPrimary,
                        fontWeight: FontWeight.w700,
                      ),
                      backgroundColor: AppPalette.card(
                        sheetContext,
                      ).withValues(alpha: 0.92),
                      selectedColor: AppPalette.primary.withValues(alpha: 0.14),
                      side: BorderSide(
                        color: isSelected
                            ? AppPalette.primary
                            : textSecondary.withValues(alpha: 0.24),
                      ),
                      onSelected: (_) {
                        setDialogState(() {
                          selectedCredit = credit;
                        });
                      },
                    );
                  }).toList(),
                ),
                const Gap(16),
                Text(
                  'Expected Grade',
                  style: TextStyle(
                    color: textPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Gap(8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: _gradeOptions.take(13).map((grade) {
                    final isSelected = selectedGrade == grade;
                    return ChoiceChip(
                      label: Text(grade),
                      selected: isSelected,
                      showCheckmark: false,
                      labelStyle: TextStyle(
                        color: isSelected ? AppPalette.primary : textPrimary,
                        fontWeight: FontWeight.w700,
                      ),
                      backgroundColor: AppPalette.card(
                        sheetContext,
                      ).withValues(alpha: 0.92),
                      selectedColor: AppPalette.primary.withValues(alpha: 0.14),
                      side: BorderSide(
                        color: isSelected
                            ? AppPalette.primary
                            : textSecondary.withValues(alpha: 0.24),
                      ),
                      onSelected: (_) {
                        setDialogState(() {
                          selectedGrade = grade;
                        });
                      },
                    );
                  }).toList(),
                ),
                const Gap(24),
                FilledButton(
                  onPressed: () {
                    final rawCode = codeController.text.trim();
                    final code = rawCode.isEmpty
                        ? 'PLANNED ${_plannedCourses.length + 1}'
                        : rawCode.toUpperCase();
                    final title = titleController.text.trim();
                    setState(() {
                      _plannedCourses.add(
                        _PlannedCourseDraft(
                          code: code,
                          title: title,
                          credit: selectedCredit,
                          grade: selectedGrade,
                        ),
                      );
                    });
                    _saveToStorage();
                    Navigator.of(sheetContext).pop();
                    _showCalculatorSnackBar('Added $code to planner');
                  },
                  style: FilledButton.styleFrom(
                    backgroundColor: AppPalette.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: const Text(
                    'Add Course',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                  ),
                ),
                const Gap(16),
                InkWell(
                  borderRadius: BorderRadius.circular(14),
                  onTap: () => openExternalUrl(
                    sheetContext,
                    'https://www.bracu.ac.bd/academics/policies-and-procedures',
                  ),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.transparent,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: textSecondary.withValues(alpha: 0.24),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Official BRAC University Policies & Procedures:',
                          style: TextStyle(
                            color: textPrimary,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const Gap(8),
                        Text(
                          '1. Retake Policy (for courses with an "F" grade):\n"The best of the grades received is counted for the calculation of the CGPA."',
                          style: TextStyle(
                            color: textPrimary,
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                            height: 1.35,
                          ),
                        ),
                        const Gap(8),
                        Text(
                          '2. Repeat Policy (for grade improvement):\n"A student may repeat a course once in order to improve the grade, however, s/he must repeat the course within 2 semesters of the initial enrollment on the course. There will not be any cap on the grade of the repeated course and the latest grade earned would be counted for the CGPA calculation."',
                          style: TextStyle(
                            color: textPrimary,
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                            height: 1.35,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
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
          isRetake: true,
        );
        if (!mounted || selected == null) return;
        final wasReset = selected == draft.completedGrade;
        setState(() {
          draft.selectedRetakeGrade = selected == draft.completedGrade
              ? null
              : selected;
        });
        _saveToStorage();
        _showCalculatorSnackBar(
          wasReset
              ? '${draft.codeValue} retake reset'
              : '${draft.codeValue} retake set to $selected',
        );
      },
      child: AppCard(
        child: _buildCourseCard(
          context,
          badgeLabel: draft.completedGrade,
          codeLine: draft.semesterValue.isEmpty
              ? draft.codeValue
              : '${draft.codeValue} • ${formatSemesterTitle(draft.semesterValue)}',
          titleLine: draft.titleValue,
          creditLine: draft.creditValue,
          statusLabel: draft.isRequired ? 'Required' : 'Elective',
          statusColor: draft.isRequired
              ? AppPalette.warning
              : AppPalette.accent,
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
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        SectionBadge(
          label: badgeLabel,
          color: AppPalette.primary,
          size: 40,
          fontSize: 13,
        ),
        const Gap(12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                resolvedCode,
                style: TextStyle(
                  color: AppPalette.textPrimary(context),
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Gap(3),
              Text(
                resolvedTitle,
                style: TextStyle(
                  color: AppPalette.textSecondary(context),
                  fontSize: 11,
                ),
              ),
            ],
          ),
        ),
        const Gap(12),
        SizedBox(
          width: 96,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '$resolvedCredit credits',
                style: TextStyle(
                  color: AppPalette.textPrimary(context),
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Gap(2),
              Text(
                statusLabel,
                style: TextStyle(
                  color: statusColor,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (trailingNote != null && trailingNote.trim().isNotEmpty) ...[
                const Gap(2),
                Text(
                  trailingNote.trim(),
                  style: TextStyle(
                    color: AppPalette.textSecondary(context),
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
    for (final draft in _plannedCourses) {
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

    for (final draft in _plannedCourses) {
      final snapshot = draft.toSnapshot();
      if (!snapshot.countsToGpa) continue;
      if (retakeCodes.contains(snapshot.code)) continue;
      selectedCredits += snapshot.credit;
      selectedQualityPoints += snapshot.qualityPoints;
      totalCredits += snapshot.credit;
      totalQualityPoints += snapshot.qualityPoints;
    }

    final manualRetakesNotInCurrent = manualRetakeByCode.keys
        .where((k) => !autoRetakeByCode.containsKey(k))
        .length;
    final evaluatedCourseCount =
        _currentCourses.length +
        _plannedCourses.length +
        manualRetakesNotInCurrent;
    final retakeCount = retakeCodes.length;

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
      retakeCount: retakeCount,
      evaluatedCourseCount: evaluatedCourseCount,
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
    bool isRetake = false,
  }) {
    return showAppBottomSheet<String>(
      context,
      title: courseCode.isEmpty ? 'Select grade' : courseCode,
      subtitle: subtitle,
      initialChildSize: 0.64,
      actions: [
        IconButton(
          onPressed: () => Navigator.of(context).pop(resetGrade),
          icon: Icon(
            Icons.refresh_rounded,
            color: AppPalette.textSecondary(context),
          ),
          tooltip: 'Reset',
        ),
      ],
      builder: (sheetContext, textPrimary, textSecondary) {
        final dragController = bottomSheetScrollController(sheetContext);
        return ListView(
          controller: dragController,
          physics: const ClampingScrollPhysics(),
          padding: const EdgeInsets.only(bottom: 24),
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _gradeOptions.map((grade) {
                final selected = currentGrade == grade;
                return ChoiceChip(
                  label: Text(grade),
                  selected: selected,
                  showCheckmark: false,
                  labelStyle: TextStyle(
                    color: selected ? AppPalette.primary : textPrimary,
                    fontWeight: FontWeight.w700,
                  ),
                  backgroundColor: AppPalette.card(
                    sheetContext,
                  ).withValues(alpha: 0.92),
                  selectedColor: AppPalette.primary.withValues(alpha: 0.14),
                  side: BorderSide(
                    color: selected
                        ? AppPalette.primary
                        : textSecondary.withValues(alpha: 0.24),
                  ),
                  onSelected: (_) => Navigator.of(sheetContext).pop(grade),
                );
              }).toList(),
            ),
            const Gap(12),
            _buildGradeGuideLegend(sheetContext, textPrimary, textSecondary),
          ],
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
