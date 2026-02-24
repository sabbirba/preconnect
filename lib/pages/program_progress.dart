import 'dart:async';

import 'package:flutter/material.dart';
import 'package:preconnect/api/profile_service.dart';
import 'package:preconnect/api/progress_service.dart';
import 'package:preconnect/model/progress_info.dart';
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
  String _cgpa = '--';
  String _fullProgramName = '';
  ProgressSummary? _summary;

  @override
  void initState() {
    super.initState();
    _future = _load();
    unawaited(_loadCgpa());
    unawaited(_loadSummary());
    unawaited(_refreshFromNetworkSilent());
    RefreshBus.instance.addListener(_onRefreshSignal);
  }

  @override
  void dispose() {
    RefreshBus.instance.removeListener(_onRefreshSignal);
    super.dispose();
  }

  void _onRefreshSignal() {
    if (!mounted) return;
    if (RefreshBus.instance.reason == 'program_progress') return;
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
    setState(() {
      _cgpa = value.isEmpty ? '--' : value;
      _fullProgramName = resolvedProgram;
    });
  }

  Future<void> _loadSummary() async {
    final summary = await ProgressService().getProgressSummary();
    if (!mounted || summary == null) return;
    setState(() {
      _summary = summary;
    });
  }

  Future<void> _refreshFromNetworkSilent() async {
    await ProgressService().fetchProgress();
    if (!mounted) return;
    final freshSummary = await ProgressService().getProgressSummary(
      fromFetch: true,
    );
    setState(() {
      _future = ProgressService().getProgress(fromFetch: true);
      if (freshSummary != null) {
        _summary = freshSummary;
      }
    });
  }

  Future<void> _refresh({bool notify = true}) async {
    if (!await ensureOnline(context, notify: notify)) return;
    setState(() {
      _future = ProgressService().fetchProgress();
    });
    unawaited(_loadCgpa());
    unawaited(_loadSummary());
    await _future;
    if (notify) {
      RefreshBus.instance.notify(reason: 'program_progress');
    }
  }

  @override
  Widget build(BuildContext context) {
    return BracuPageScaffold(
      title: 'Progression',
      subtitle: 'Curriculum & Courses',
      icon: Icons.insights_outlined,
      body: FutureBuilder<ProgressInfo?>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return RefreshIndicator(
              onRefresh: _refresh,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
                children: const [SizedBox(height: 180), BracuLoading()],
              ),
            );
          }

          final info = snapshot.data;
          if (snapshot.hasError) {
            return RefreshIndicator(
              onRefresh: _refresh,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
                children: [
                  const SizedBox(height: 180),
                  BracuEmptyState(message: 'Error: ${snapshot.error}'),
                ],
              ),
            );
          }

          if (info == null) {
            return RefreshIndicator(
              onRefresh: _refresh,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
                children: const [
                  SizedBox(height: 180),
                  BracuEmptyState(message: 'No progress data available.'),
                ],
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
          for (final c in info.curriculumCourses) {
            mandatoryByCode[c.code.toUpperCase()] = c.isMandatory;
          }
          final topCourses = [...info.completedCourses]
            ..sort((a, b) => compareNaturalText(a.code, b.code));

          return RefreshIndicator(
            onRefresh: _refresh,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
              children: [
                BracuCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _resolveProgramTitle(info),
                        style: TextStyle(
                          color: BracuPalette.textPrimary(context),
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 12),
                      LayoutBuilder(
                        builder: (context, constraints) {
                          const spacing = 6.0;
                          final itemWidth =
                              (constraints.maxWidth - (spacing * 3)) / 4;
                          return Wrap(
                            spacing: spacing,
                            runSpacing: spacing,
                            children: [
                              _Metric(
                                title: 'Total',
                                value: _formatCredit(summaryTotal),
                                width: itemWidth,
                              ),
                              _Metric(
                                title: 'Done',
                                value: _formatCredit(summaryCompleted),
                                width: itemWidth,
                              ),
                              _Metric(
                                title: 'CGPA',
                                value: _cgpa,
                                width: itemWidth,
                              ),
                              _Metric(
                                title: 'Remaining',
                                value: _formatCredit(remainingCredit),
                                width: itemWidth,
                              ),
                            ],
                          );
                        },
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
                                        _formatCredit(earnedCredit),
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
                                      color: BracuPalette.textSecondary(
                                        context,
                                      ),
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
                if (info.majorOptions.isNotEmpty ||
                    info.minorOptions.isNotEmpty)
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
                          _OptionWrap(
                            title: 'Majors',
                            items: info.majorOptions,
                          ),
                        ],
                        if (info.minorOptions.isNotEmpty) ...[
                          const SizedBox(height: 10),
                          _OptionWrap(
                            title: 'Minors',
                            items: info.minorOptions,
                          ),
                        ],
                      ],
                    ),
                  ),
                if (info.majorOptions.isNotEmpty ||
                    info.minorOptions.isNotEmpty)
                  const SizedBox(height: 14),
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
                    final semester = formatSemesterTitle(
                      course.semesterSession,
                    );
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
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
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
                                      color: BracuPalette.textSecondary(
                                        context,
                                      ),
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
                                    _formatCredit(course.credit),
                                    style: TextStyle(
                                      color: BracuPalette.textPrimary(context),
                                      fontSize: 14,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    (mandatoryByCode[course.code
                                                .toUpperCase()] ??
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
              ],
            ),
          );
        },
      ),
    );
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
  const _Metric({required this.title, required this.value, this.width});

  final String title;
  final String value;
  final double? width;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
      decoration: BoxDecoration(
        color: BracuPalette.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              color: BracuPalette.textSecondary(context),
              fontSize: 10,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            value,
            style: TextStyle(
              color: BracuPalette.textPrimary(context),
              fontSize: 13,
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
