import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:preconnect/api/profile_service.dart';
import 'package:preconnect/api/progress_service.dart';
import 'package:preconnect/api/schedule_service.dart';
import 'package:preconnect/model/progress_info.dart';
import 'package:preconnect/model/section_info.dart' as section;
import 'package:preconnect/pages/all_courses.dart';
import 'package:preconnect/pages/requirement_courses.dart';
import 'package:preconnect/pages/shared_widgets/progress_bar.dart';
import 'package:preconnect/pages/shared_widgets/section_badge.dart';
import 'package:preconnect/pages/ui_kit.dart';
import 'package:preconnect/tools/refresh_bus.dart';
import 'package:preconnect/tools/refresh_guard.dart';

class ProgramProgressPage extends StatefulWidget {
  const ProgramProgressPage({super.key});

  @override
  State<ProgramProgressPage> createState() => _ProgramProgressPageState();
}

class _ProgramProgressPageState extends State<ProgramProgressPage> {
  late Future<ProgressInfo?> _future;
  ProgressInfo? _latestInfo;
  bool _isRefreshing = false;
  String _cgpa = '--';
  String _fullProgramName = '';
  ProgressSummary? _summary;
  List<section.Section> _currentSemesterSections = const [];

  @override
  void initState() {
    super.initState();
    _future = _load().then((info) {
      _latestInfo = info;
      // If cached data exists, refresh silently in the background.
      if (info != null) {
        unawaited(_refreshFromNetworkSilent());
      }
      return info;
    });
    unawaited(_loadCgpa());
    unawaited(_loadSummary());
    unawaited(_loadCurrentSemesterCourses());
    RefreshBus.instance.addListener(_onRefreshSignal);
  }

  @override
  void dispose() {
    RefreshBus.instance.removeListener(_onRefreshSignal);
    super.dispose();
  }

  void _onRefreshSignal() {
    if (!mounted) return;
    final reason = RefreshBus.instance.reason;
    if (reason == 'program_progress') return;
    if (reason != 'home_dashboard' &&
        reason != 'student_profile' &&
        reason != 'auth') {
      return;
    }
    unawaited(_refresh(notify: false));
  }

  Future<ProgressInfo?> _load() {
    return ProgressService().getProgress();
  }

  Future<void> _loadCgpa() async {
    final profile = await ProfileService().getProfile();
    if (!mounted) return;
    final value = (profile?['cgpa'] ?? '').trim();
    final profileProgram = (profile?['program'] ?? '').trim();
    final profileProgramAlt = (profile?['programOrCourse'] ?? '').trim();
    final resolvedProgram = profileProgram.isNotEmpty
        ? profileProgram
        : profileProgramAlt;
    final nextCgpa = value.isEmpty ? '--' : value;
    if (_cgpa == nextCgpa && _fullProgramName == resolvedProgram) return;
    setState(() {
      _cgpa = nextCgpa;
      _fullProgramName = resolvedProgram;
    });
  }

  Future<void> _loadSummary() async {
    final summary = await ProgressService().getProgressSummary();
    if (!mounted || summary == null || _sameSummary(_summary, summary)) return;
    setState(() {
      _summary = summary;
    });
  }

  Future<void> _refreshFromNetworkSilent() async {
    final freshInfo = await ProgressService().fetchProgress();
    if (!mounted) return;
    final freshSummary = await ProgressService().getProgressSummary(
      fromFetch: true,
    );
    final shouldUpdateInfo = freshInfo != null;
    final shouldUpdateSummary =
        freshSummary != null && !_sameSummary(_summary, freshSummary);
    if (!shouldUpdateInfo && !shouldUpdateSummary) return;
    setState(() {
      if (shouldUpdateInfo) {
        _latestInfo = freshInfo;
      }
      if (shouldUpdateSummary) {
        _summary = freshSummary;
      }
    });
  }

  Future<void> _refresh({bool notify = true}) async {
    if (_isRefreshing) return;
    if (!await ensureOnline(context, notify: notify)) return;
    _isRefreshing = true;
    try {
      final freshInfo = await ProgressService().fetchProgress();
      final freshSummary = await ProgressService().getProgressSummary(
        fromFetch: true,
      );
      final freshScheduleJson = await ScheduleService().fetchStudentSchedule();
      final freshSections = _parseCurrentSemesterSections(freshScheduleJson);
      unawaited(_loadCgpa());
      if (!mounted) return;
      final shouldUpdateInfo = freshInfo != null;
      final shouldUpdateSummary =
          freshSummary != null && !_sameSummary(_summary, freshSummary);
      final shouldUpdateSections = !_sameSections(
        _currentSemesterSections,
        freshSections,
      );
      if (shouldUpdateInfo || shouldUpdateSummary || shouldUpdateSections) {
        setState(() {
          if (shouldUpdateInfo) {
            _latestInfo = freshInfo;
          }
          if (shouldUpdateSummary) {
            _summary = freshSummary;
          }
          if (shouldUpdateSections) {
            _currentSemesterSections = freshSections;
          }
        });
      }
      if (notify) {
        RefreshBus.instance.notify(reason: 'program_progress');
      }
    } finally {
      _isRefreshing = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return BracuPageScaffold(
      title: 'Progression',
      subtitle: 'Curriculum Based',
      icon: Icons.insights_outlined,
      body: FutureBuilder<ProgressInfo?>(
        future: _future,
        builder: (context, snapshot) {
          final info = _latestInfo ?? snapshot.data;
          if (snapshot.connectionState == ConnectionState.waiting &&
              info == null) {
            return BracuRefreshPlaceholder(
              onRefresh: _refresh,
              topSpacing: 180,
              child: const BracuLoading(),
            );
          }

          if (snapshot.hasError && info == null) {
            return BracuRefreshPlaceholder(
              onRefresh: _refresh,
              topSpacing: 180,
              child: BracuEmptyState(message: 'Error: ${snapshot.error}'),
            );
          }

          if (info == null) {
            return BracuRefreshPlaceholder(
              onRefresh: _refresh,
              topSpacing: 180,
              child: const BracuEmptyState(
                message: 'No progress data available.',
              ),
            );
          }

          final completedCredit = info.completedCredit;
          final totalCredit = info.totalCredit;
          final completion = totalCredit <= 0
              ? 0.0
              : (completedCredit / totalCredit).clamp(0.0, 1.0);
          final summary = _summary;
          final summaryTotal = summary?.totalCredit ?? totalCredit;
          final summaryCompleted = summary?.completedCredit ?? completedCredit;
          final summaryPercent =
              summary?.completionPercent ?? (completion * 100);
          final remainingCredit = (summaryTotal - summaryCompleted)
              .clamp(0, double.infinity)
              .toDouble();
          final mandatoryByCode = <String, bool>{};
          final courseTitleByCode = <String, String>{};
          for (final c in info.curriculumCourses) {
            final code = c.code.toUpperCase();
            mandatoryByCode[code] = c.isMandatory;
            final title = c.title.trim();
            if (title.isNotEmpty) {
              courseTitleByCode[code] = title;
            }
          }
          for (final c in info.completedCourses) {
            final code = c.code.toUpperCase();
            if (courseTitleByCode.containsKey(code)) continue;
            final title = c.title.trim();
            if (title.isNotEmpty) {
              courseTitleByCode[code] = title;
            }
          }
          final currentSectionsForDisplay = _currentSemesterSections.where((
            current,
          ) {
            final resolvedTitle = _resolveCurrentCourseTitle(
              current,
              courseTitleByCode,
            ).trim();
            final hasNoRealName =
                resolvedTitle.isEmpty ||
                resolvedTitle.toUpperCase() ==
                    current.courseCode.trim().toUpperCase();
            return !(current.courseCredit <= 0 && hasNoRealName);
          }).toList();
          final attemptedCredit = currentSectionsForDisplay.fold<double>(
            0,
            (sum, section) => sum + section.courseCredit,
          );
          final topCourses = [...info.completedCourses]
            ..sort((a, b) => compareNaturalText(a.code, b.code));
          final completedCodes = info.completedCourses
              .map((c) => c.code.trim().toUpperCase())
              .toSet();
          final currentSemesterCodes = _currentSemesterSections
              .map((s) => s.courseCode.trim().toUpperCase())
              .where((code) => code.isNotEmpty)
              .toSet();
          final requiredByCode = <String, CurriculumCourse>{};
          for (final course in info.curriculumCourses) {
            final code = course.code.trim().toUpperCase();
            if (!course.isMandatory) continue;
            if (completedCodes.contains(code)) continue;
            if (currentSemesterCodes.contains(code)) continue;
            requiredByCode.putIfAbsent(code, () => course);
          }
          final requiredCourses = requiredByCode.values.toList()
            ..sort((a, b) => compareNaturalText(a.code, b.code));

          return BracuRefreshList(
            onRefresh: _refresh,
            padding: kBracuPageListPadding,
            children: [
              BracuCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _resolveProgramTitle(info),
                      style: TextStyle(
                        color: BracuPalette.textPrimary(context),
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: _Metric(
                            title: 'Total',
                            value: _formatCredit(summaryTotal),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: _Metric(
                            title: 'Done',
                            value: _formatCredit(summaryCompleted),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: _Metric(
                            title: 'Attempted',
                            value: _formatCredit(attemptedCredit),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: _Metric(title: 'CGPA', value: _cgpa),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: _Metric(
                            title: 'Remaining',
                            value: _formatCredit(remainingCredit),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: SimpleProgressBar(
                            value: completion,
                            color: BracuPalette.primary,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '${summaryPercent.toStringAsFixed(1)}%',
                          style: TextStyle(
                            color: BracuPalette.textSecondary(context),
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              BracuCard(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'All Courses',
                              style: TextStyle(
                                color: BracuPalette.textPrimary(context),
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            if (info.academicDegree.isNotEmpty) ...[
                              const SizedBox(height: 2),
                              Text(
                                info.academicDegree,
                                style: TextStyle(
                                  color: BracuPalette.textSecondary(context),
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      ElevatedButton.icon(
                        onPressed: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => AllCoursesPage(info: info),
                            ),
                          );
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: BracuPalette.primary,
                          foregroundColor: Colors.white,
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        icon: const Icon(Icons.tune, size: 16),
                        label: const Text('Open'),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 14),
              if (info.headerProgress.isNotEmpty) ...[
                const BracuSectionTitle(title: 'Requirement Progress'),
                const SizedBox(height: 10),
                ...info.headerProgress.map((item) {
                  final requiredCredit = item.requiredCredit;
                  final earnedCredit = item.earnedCredit;
                  final remainingForHeader = (requiredCredit - earnedCredit)
                      .clamp(0, double.infinity)
                      .toDouble();
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(18),
                      onTap: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => RequirementCoursesPage(
                              info: info,
                              headerTitle: item.title,
                              currentSemesterCodes: _currentSemesterSections
                                  .map(
                                    (section) =>
                                        section.courseCode.trim().toUpperCase(),
                                  )
                                  .where((code) => code.isNotEmpty)
                                  .toSet(),
                            ),
                          ),
                        );
                      },
                      child: BracuCard(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        item.title,
                                        style: TextStyle(
                                          color: BracuPalette.textPrimary(
                                            context,
                                          ),
                                          fontSize: 14,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        'Required ${_formatCredit(requiredCredit)} Credits • Remaining ${_formatCredit(remainingForHeader)} Credits',
                                        style: TextStyle(
                                          color: BracuPalette.textSecondary(
                                            context,
                                          ),
                                          fontSize: 10,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    Text(
                                      '${_formatCredit(earnedCredit)} credits',
                                      style: TextStyle(
                                        color: BracuPalette.textPrimary(
                                          context,
                                        ),
                                        fontSize: 14,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                Expanded(
                                  child: SimpleProgressBar(
                                    value: item.percent,
                                    color: BracuPalette.accent,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  '${(item.percent * 100).toStringAsFixed(1)}%',
                                  style: TextStyle(
                                    color: BracuPalette.textSecondary(context),
                                    fontSize: 10,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                }),
                const SizedBox(height: 4),
              ],
              if (info.majorOptions.isNotEmpty || info.minorOptions.isNotEmpty)
                BracuCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Major / Minor Options',
                        style: TextStyle(
                          color: BracuPalette.textPrimary(context),
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      if (info.majorOptions.isNotEmpty) ...[
                        const SizedBox(height: 10),
                        _OptionWrap(title: 'Majors', items: info.majorOptions),
                      ],
                      if (info.minorOptions.isNotEmpty) ...[
                        const SizedBox(height: 10),
                        _OptionWrap(title: 'Minors', items: info.minorOptions),
                      ],
                    ],
                  ),
                ),
              if (info.majorOptions.isNotEmpty || info.minorOptions.isNotEmpty)
                const SizedBox(height: 14),
              if (currentSectionsForDisplay.isNotEmpty) ...[
                const BracuSectionTitle(title: 'Current Semester Courses'),
                const SizedBox(height: 10),
                ...currentSectionsForDisplay.map((current) {
                  final isRequired =
                      mandatoryByCode[current.courseCode.toUpperCase()] ??
                      _isLikelyRequired(current.courseType);
                  final rawSubtitle = _resolveCurrentCourseTitle(
                    current,
                    courseTitleByCode,
                  );
                  final showSubtitle =
                      rawSubtitle.isNotEmpty &&
                      rawSubtitle.toUpperCase() !=
                          current.courseCode.trim().toUpperCase();
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: BracuCard(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SectionBadge(
                            label: formatSectionBadge(current.sectionName),
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
                                  '${current.courseCode} • ${formatSemesterFromSessionIdInt(current.semesterSessionId)}',
                                  style: TextStyle(
                                    color: BracuPalette.textPrimary(context),
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                if (showSubtitle) ...[
                                  const SizedBox(height: 3),
                                  Text(
                                    rawSubtitle,
                                    style: TextStyle(
                                      color: BracuPalette.textSecondary(
                                        context,
                                      ),
                                      fontSize: 11,
                                    ),
                                  ),
                                ],
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
                                  '${current.courseCredit} credits',
                                  style: TextStyle(
                                    color: BracuPalette.textPrimary(context),
                                    fontSize: 14,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  isRequired ? 'Required' : 'Elective',
                                  style: TextStyle(
                                    color: isRequired
                                        ? BracuPalette.warning
                                        : BracuPalette.accent,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }),
                const SizedBox(height: 4),
              ],
              const BracuSectionTitle(title: 'Completed Courses'),
              const SizedBox(height: 10),
              if (topCourses.isEmpty)
                BracuCard(
                  child: Text(
                    'No completed courses found.',
                    style: TextStyle(
                      color: BracuPalette.textSecondary(context),
                    ),
                  ),
                )
              else
                ...topCourses.map((course) {
                  final semester = formatSemesterTitle(course.semesterSession);
                  final titleLine = semester.isEmpty
                      ? course.code
                      : '${course.code} • $semester';
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: BracuCard(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SectionBadge(
                            label: course.grade.isEmpty ? '--' : course.grade,
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
                                  titleLine,
                                  style: TextStyle(
                                    color: BracuPalette.textPrimary(context),
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  course.title.isEmpty
                                      ? course.code
                                      : course.title,
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
                                const SizedBox(height: 2),
                                Text(
                                  (mandatoryByCode[course.code.toUpperCase()] ??
                                          false)
                                      ? 'Required'
                                      : 'Elective',
                                  style: TextStyle(
                                    color:
                                        (mandatoryByCode[course.code
                                                .toUpperCase()] ??
                                            false)
                                        ? BracuPalette.warning
                                        : BracuPalette.accent,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }),
              const SizedBox(height: 6),
              const BracuSectionTitle(title: 'Required Courses'),
              const SizedBox(height: 10),
              if (requiredCourses.isEmpty)
                BracuCard(
                  child: Text(
                    'No required courses remaining.',
                    style: TextStyle(
                      color: BracuPalette.textSecondary(context),
                    ),
                  ),
                )
              else
                ...requiredCourses.map((course) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: BracuCard(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const SectionBadge(
                            label: '?',
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
                                  course.code,
                                  style: TextStyle(
                                    color: BracuPalette.textPrimary(context),
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  course.title.isEmpty
                                      ? course.code
                                      : course.title,
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
                                const SizedBox(height: 2),
                                const Text(
                                  'Required',
                                  style: TextStyle(
                                    color: BracuPalette.warning,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }),
            ],
          );
        },
      ),
    );
  }

  Future<void> _loadCurrentSemesterCourses() async {
    final scheduleJson = await ScheduleService().getStudentSchedule();
    if (!mounted) return;
    final sections = _parseCurrentSemesterSections(scheduleJson);
    if (_sameSections(_currentSemesterSections, sections)) return;
    setState(() {
      _currentSemesterSections = sections;
    });
  }

  List<section.Section> _parseCurrentSemesterSections(String? scheduleJson) {
    if (scheduleJson == null || scheduleJson.trim().isEmpty) {
      return const <section.Section>[];
    }
    try {
      final decoded = jsonDecode(scheduleJson);
      if (decoded is! List<dynamic>) return const <section.Section>[];
      final sections = <section.Section>[];
      final seen = <String>{};
      for (final raw in decoded.whereType<Map<String, dynamic>>()) {
        final item = section.Section.fromJson(raw);
        // Deduplicate true repeats while keeping distinct lecture/lab sections.
        final key =
            '${item.sectionId}|${item.courseCode}|${item.sectionName}|${item.roomNumber}';
        if (!seen.add(key)) continue;
        sections.add(item);
      }
      sections.sort((a, b) {
        final codeCmp = compareNaturalText(a.courseCode, b.courseCode);
        if (codeCmp != 0) return codeCmp;
        return compareNaturalText(a.sectionName, b.sectionName);
      });
      return sections;
    } catch (_) {
      return const <section.Section>[];
    }
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
}

class _Metric extends StatelessWidget {
  const _Metric({required this.title, required this.value});

  final String title;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
      decoration: BoxDecoration(
        color: BracuPalette.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(
            title,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: BracuPalette.textSecondary(context),
              fontSize: 8,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            value,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: BracuPalette.textPrimary(context),
              fontSize: 18,
              fontWeight: FontWeight.w700,
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
