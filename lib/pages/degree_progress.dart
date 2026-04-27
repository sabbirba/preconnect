import 'dart:async';

import 'package:flutter/material.dart';
import 'package:preconnect/api/profile_service.dart';
import 'package:preconnect/api/progress_service.dart';
import 'package:preconnect/api/schedule_service.dart';
import 'package:preconnect/model/progress_info.dart';
import 'package:preconnect/model/section_info.dart' as section;
import 'package:preconnect/pages/all_courses.dart';
import 'package:preconnect/pages/cgpa_calculator.dart';
import 'package:preconnect/pages/requirement_courses.dart';
import 'package:preconnect/pages/shared_widgets/grade_sheet_card.dart';
import 'package:preconnect/pages/shared_widgets/current_session_helper.dart';
import 'package:preconnect/pages/ui_kit.dart';
import 'package:preconnect/tools/refresh_bus.dart';

part 'student_profile_sections/degree_progress_helpers.dart';

class DegreeProgressPage extends StatefulWidget {
  const DegreeProgressPage({super.key});

  static Future<void> preload() async {
    await _DegreeProgressPageState.preloadData();
  }

  @override
  State<DegreeProgressPage> createState() => _DegreeProgressPageState();
}

class _DegreeProgressPageState extends State<DegreeProgressPage>
    with RefreshBusState {
  static const int _coursesChunkSize = 7;
  static ProgressInfo? _cachedInfo;
  static Future<ProgressInfo?>? _preloadFuture;

  late Future<ProgressInfo?> _future;
  ProgressInfo? _latestInfo;
  bool _isRefreshing = false;
  String _cgpa = '--';
  String _fullProgramName = '';
  ProgressSummary? _summary;
  List<section.Section> _currentSemesterSections = const [];
  int _wishlistVisibleCount = _coursesChunkSize;
  int _currentVisibleCount = _coursesChunkSize;
  int _completedVisibleCount = _coursesChunkSize;

  @override
  void initState() {
    super.initState();
    _latestInfo = _cachedInfo;
    _future = _cachedInfo == null
        ? preloadData().then((info) {
            _latestInfo = info;
            if (info != null) {
              unawaited(_refreshFromNetworkSilent());
            }
            return info;
          })
        : Future<ProgressInfo?>.value(_cachedInfo);
    unawaited(_warmAndBind());
    unawaited(_loadCgpa());
    unawaited(_loadSummary());
    unawaited(_loadCurrentSemesterCourses());
    bindRefreshBus(_onRefreshSignal);
  }

  static Future<ProgressInfo?> preloadData({bool forceRefresh = false}) async {
    if (!forceRefresh && _cachedInfo != null) {
      return _cachedInfo!;
    }
    if (!forceRefresh) {
      final inFlight = _preloadFuture;
      if (inFlight != null) {
        return inFlight;
      }
    }

    final future = ProgressService().getProgress();
    _preloadFuture = future;
    try {
      final info = await future;
      if (info != null) {
        _cachedInfo = info;
      }
      return info;
    } finally {
      if (identical(_preloadFuture, future)) {
        _preloadFuture = null;
      }
    }
  }

  Future<void> _warmAndBind() async {
    final info = await preloadData();
    if (!mounted || info == null) return;
    setState(() {
      _latestInfo = info;
      _future = Future<ProgressInfo?>.value(info);
    });
  }

  @override
  void dispose() {
    unbindRefreshBus(_onRefreshSignal);
    super.dispose();
  }

  void _onRefreshSignal() {
    if (!mounted) return;
    final reason = refreshBusReason;
    if (reason == 'degree_progress') return;
    if (reason != 'home_dashboard' &&
        reason != 'student_profile' &&
        reason != 'auth') {
      return;
    }
    unawaited(_refresh(notify: false));
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
        _cachedInfo = freshInfo;
      }
      if (shouldUpdateSummary) {
        _summary = freshSummary;
      }
    });
  }

  Future<void> _refresh({bool notify = true}) async {
    if (_isRefreshing) return;
    if (!await ensureOnline(context, notify: notify)) return;
    if (_wishlistVisibleCount != _coursesChunkSize ||
        _currentVisibleCount != _coursesChunkSize ||
        _completedVisibleCount != _coursesChunkSize) {
      setState(() {
        _wishlistVisibleCount = _coursesChunkSize;
        _currentVisibleCount = _coursesChunkSize;
        _completedVisibleCount = _coursesChunkSize;
      });
    }
    _isRefreshing = true;
    try {
      final freshInfo = await ProgressService().fetchProgress();
      final freshSummary = await ProgressService().getProgressSummary(
        fromFetch: true,
      );
      final currentSessionSemesterId = await resolveCurrentSessionSemesterId();
      final freshScheduleJson = await ScheduleService()
          .fetchStudentScheduleForSemester(
            semesterSessionId: currentSessionSemesterId,
          );
      final freshSections = section.parseSectionsFromScheduleJson(
        freshScheduleJson,
      );
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
            _cachedInfo = freshInfo;
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
        RefreshBus.instance.notify(reason: 'degree_progress');
      }
    } finally {
      _isRefreshing = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return BracuPageScaffold(
      title: 'Degree Progress',
      subtitle: 'Curriculum Based',
      icon: Icons.trending_up_rounded,
      body: FutureBuilder<ProgressInfo?>(
        future: _future,
        builder: (context, snapshot) {
          final info = _latestInfo ?? snapshot.data;
          if (snapshot.hasError && info == null) {
            return buildRefreshErrorState(
              onRefresh: _refresh,
              topSpacing: 180,
              error: snapshot.error,
            );
          }

          if (info == null) {
            return buildRefreshEmptyState(
              onRefresh: _refresh,
              topSpacing: 180,
              message: 'No progress data available.',
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
          final summaryStats = [
            (title: 'Total', value: _formatCredit(summaryTotal)),
            (title: 'Done', value: _formatCredit(summaryCompleted)),
            (title: 'Attempt', value: _formatCredit(attemptedCredit)),
            (title: 'Left', value: _formatCredit(remainingCredit)),
          ];
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
          final wishlistCourses = _buildWishlistCourses(
            info: info,
            currentSections: _currentSemesterSections,
          );
          final wishlistCoursesForDisplay = wishlistCourses
              .take(_wishlistVisibleCount)
              .toList();
          final currentSectionsVisible = currentSectionsForDisplay
              .take(_currentVisibleCount)
              .toList();
          final topCoursesVisible = topCourses
              .take(_completedVisibleCount)
              .toList();

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
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: List.generate(summaryStats.length, (index) {
                          final item = summaryStats[index];
                          return Padding(
                            padding: EdgeInsets.only(
                              right: index == summaryStats.length - 1 ? 0 : 10,
                            ),
                            child: SizedBox(
                              width: 96,
                              child: _Metric(
                                title: item.title,
                                value: item.value,
                              ),
                            ),
                          );
                        }),
                      ),
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
                      BracuActionButton(
                        filled: true,
                        onPressed: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => AllCoursesPage(info: info),
                            ),
                          );
                        },
                        icon: Icons.tune,
                        label: 'Open',
                      ),
                    ],
                  ),
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
                              'CGPA Calculator',
                              style: TextStyle(
                                color: BracuPalette.textPrimary(context),
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Based on your progress',
                              style: TextStyle(
                                color: BracuPalette.textSecondary(context),
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      BracuActionButton(
                        filled: true,
                        onPressed: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => CgpaCalculatorPage(
                                info: info,
                                currentSections: currentSectionsForDisplay,
                                currentCgpa: _cgpa,
                              ),
                            ),
                          );
                        },
                        icon: Icons.calculate_outlined,
                        label: 'Open',
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 14),
              const GradeSheetCard(),
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
              const BracuSectionTitle(title: 'Wishlist for Next Semester'),
              const SizedBox(height: 10),
              if (wishlistCourses.isEmpty)
                BracuCard(
                  child: Text(
                    'No next-semester suggestions available yet.',
                    style: TextStyle(
                      color: BracuPalette.textSecondary(context),
                    ),
                  ),
                )
              else ...[
                ...wishlistCoursesForDisplay.map((course) {
                  final item = course.course;
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
                                  item.code,
                                  style: TextStyle(
                                    color: BracuPalette.textPrimary(context),
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  item.title.isEmpty ? item.code : item.title,
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
                            width: 108,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text(
                                  '${_formatCredit(item.credit)} credits',
                                  style: TextStyle(
                                    color: BracuPalette.textPrimary(context),
                                    fontSize: 14,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  item.isMandatory ? 'Required' : 'Elective',
                                  style: TextStyle(
                                    color: item.isMandatory
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
                if (wishlistCourses.length > wishlistCoursesForDisplay.length)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: ShowMoreButton(
                      onPressed: () {
                        setState(() {
                          _wishlistVisibleCount += _coursesChunkSize;
                        });
                      },
                    ),
                  ),
                const SizedBox(height: 4),
              ],
              if (currentSectionsForDisplay.isNotEmpty) ...[
                const BracuSectionTitle(title: 'Current Semester Courses'),
                const SizedBox(height: 10),
                ...currentSectionsVisible.map((current) {
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
                if (currentSectionsForDisplay.length >
                    currentSectionsVisible.length)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: ShowMoreButton(
                      onPressed: () {
                        setState(() {
                          _currentVisibleCount += _coursesChunkSize;
                        });
                      },
                    ),
                  ),
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
                ...topCoursesVisible.map((course) {
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
              if (topCourses.length > topCoursesVisible.length)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: ShowMoreButton(
                    onPressed: () {
                      setState(() {
                        _completedVisibleCount += _coursesChunkSize;
                      });
                    },
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}
