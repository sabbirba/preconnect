import 'package:flutter/material.dart';

enum AdvisingPhase {
  phaseOne,
  phaseTwo,
  selfRegistration;

  String get queryValue => switch (this) {
    AdvisingPhase.phaseOne => 'PHASE_ONE',
    AdvisingPhase.phaseTwo => 'PHASE_TWO',
    AdvisingPhase.selfRegistration => 'SELF_REGISTRATION',
  };

  String get pathSegment => switch (this) {
    AdvisingPhase.phaseOne => 'phase-one',
    AdvisingPhase.phaseTwo => 'phase-two',
    AdvisingPhase.selfRegistration => 'self-registration',
  };

  String get label => switch (this) {
    AdvisingPhase.phaseOne => 'Phase 1',
    AdvisingPhase.phaseTwo => 'Phase 2',
    AdvisingPhase.selfRegistration => 'Self',
  };

  String get subtitle => switch (this) {
    AdvisingPhase.phaseOne => 'Advising',
    AdvisingPhase.phaseTwo => 'Advising',
    AdvisingPhase.selfRegistration => 'Registration',
  };

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
