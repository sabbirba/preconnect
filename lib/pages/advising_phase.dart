import 'dart:async';

import 'package:flutter/material.dart';
import 'package:preconnect/api/schedule.dart';
import 'package:preconnect/model/advising_phase.dart';
import 'package:preconnect/model/section_info.dart';
import 'package:preconnect/pages/section_loader.dart';
import 'package:preconnect/pages/ui_kit.dart';

Future<List<Section>> _loadAdvisingSections(
  AdvisingPhase phase, {
  bool forceRefresh = false,
}) {
  return ScheduleService().fetchStudentCoursesForPhase(
    phase,
    forceRefresh: forceRefresh,
  );
}

class AdvisingPhasePage extends StatefulWidget {
  const AdvisingPhasePage({super.key, required this.phase, this.loadSections});

  final AdvisingPhase phase;
  final SectionLoader<AdvisingPhase>? loadSections;

  @override
  State<AdvisingPhasePage> createState() => _AdvisingPhasePageState();
}

class _AdvisingPhasePageState extends State<AdvisingPhasePage> {
  late final SectionLoadController<AdvisingPhase> _controller;

  @override
  void initState() {
    super.initState();
    _controller = SectionLoadController<AdvisingPhase>(
      key: widget.phase,
      loader: widget.loadSections ?? _loadAdvisingSections,
    );
    unawaited(_controller.load());
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        return BracuPageScaffold(
          title: widget.phase.label,
          subtitle: widget.phase.subtitle,
          icon: widget.phase.icon,
          actions: [
            BracuRefreshButton(
              onPressed: () => _controller.load(forceRefresh: true),
              isLoading: _controller.isLoading,
            ),
          ],
          body: SectionLoadView<AdvisingPhase>(
            controller: _controller,
            errorTitle: 'Could not load ${widget.phase.label} data.',
            label: 'My Courses',
            emptyMessage:
                'No registered courses yet for ${widget.phase.label}.',
          ),
        );
      },
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
