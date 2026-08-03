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
}
