import 'package:flutter/material.dart';
import 'package:preconnect/model/advising_phase.dart';
import 'package:preconnect/pages/advising_helper.dart';

class AdvisingPhasePage extends StatelessWidget {
  const AdvisingPhasePage({super.key, required this.phase});

  final AdvisingPhase phase;

  @override
  Widget build(BuildContext context) {
    return AdvisingHelperPage(initialPhase: phase);
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
