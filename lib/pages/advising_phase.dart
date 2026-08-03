import 'dart:async';

import 'package:flutter/material.dart';
import 'package:preconnect/api/schedule.dart';
import 'package:preconnect/model/advising_phase.dart';
import 'package:preconnect/model/section_info.dart';
import 'package:preconnect/pages/ui_kit.dart';

class AdvisingPhasePage extends StatefulWidget {
  const AdvisingPhasePage({super.key, required this.phase});

  final AdvisingPhase phase;

  @override
  State<AdvisingPhasePage> createState() => _AdvisingPhasePageState();
}

class _AdvisingPhasePageState extends State<AdvisingPhasePage> {
  bool _isLoading = true;
  String? _errorMessage;
  List<Section> _courses = const [];

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      final courses = await ScheduleService().fetchStudentCoursesForPhase(
        widget.phase,
      );
      if (!mounted) return;
      setState(() {
        _courses = courses;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = e.toString();
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasData = _courses.isNotEmpty;

    return BracuPageScaffold(
      title: widget.phase.label,
      subtitle: widget.phase.subtitle,
      icon: widget.phase.icon,
      actions: [BracuRefreshButton(onPressed: _load, isLoading: _isLoading)],
      body: _isLoading && !hasData
          ? const Center(child: BracuLoading())
          : (_errorMessage != null && !hasData)
          ? SectionsErrorState(
              title: 'Could not load ${widget.phase.label} data.',
              message: _errorMessage ?? '',
              onRetry: _load,
            )
          : BracuRefreshList(
              onRefresh: _load,
              children: [
                SectionListCard(
                  label: 'My Courses',
                  sections: _courses,
                  emptyMessage:
                      'No registered courses yet for ${widget.phase.label}.',
                ),
              ],
            ),
    );
  }
}

extension AdvisingPhaseUiExt on AdvisingPhase {
  IconData get icon => switch (this) {
    AdvisingPhase.phaseOne => Icons.filter_1_rounded,
    AdvisingPhase.phaseTwo => Icons.filter_2_rounded,
    AdvisingPhase.selfRegistration => Icons.how_to_reg_outlined,
  };

  Color get color => switch (this) {
    AdvisingPhase.phaseOne => const Color(0xFF1E6BE3),
    AdvisingPhase.phaseTwo => const Color(0xFF7C56FF),
    AdvisingPhase.selfRegistration => const Color(0xFF22B573),
  };
}
