class PrintFinishing {
  const PrintFinishing(this.staple, this.punch);

  final String staple;
  final String punch;

  static const List<PrintFinishing> _cycle = [
    PrintFinishing('Off', 'Off'),
    PrintFinishing('Left Corner', 'Off'),
    PrintFinishing('Right Corner', 'Off'),
    PrintFinishing('Off', '2 Holes'),
    PrintFinishing('Off', '3 Holes'),
  ];

  static PrintFinishing after(String staple, String punch) {
    final index = _cycle.indexWhere(
      (item) => item.staple == staple && item.punch == punch,
    );
    return index < 0 ? _cycle.first : _cycle[(index + 1) % _cycle.length];
  }

  static String label(String staple, String punch) {
    final stapleLabel = switch (staple) {
      'Left Corner' => 'Staple Left',
      'Right Corner' => 'Staple Right',
      _ => null,
    };
    final punchLabel = punch == 'Off' ? null : 'Punch $punch';
    if (stapleLabel != null && punchLabel != null) {
      return '$stapleLabel + $punchLabel';
    }
    return stapleLabel ?? punchLabel ?? 'Finishing Off';
  }
}

class PrintSeparation {
  const PrintSeparation(this.offset, this.slip);

  final bool offset;
  final bool slip;

  static const List<PrintSeparation> _cycle = [
    PrintSeparation(false, false),
    PrintSeparation(true, false),
    PrintSeparation(false, true),
    PrintSeparation(true, true),
  ];

  static PrintSeparation after(bool offset, bool slip) {
    final index = _cycle.indexWhere(
      (item) => item.offset == offset && item.slip == slip,
    );
    return _cycle[(index + 1) % _cycle.length];
  }

  static String label(bool offset, bool slip) {
    if (offset && slip) return 'Offset + Slip';
    if (offset) return 'Offset';
    if (slip) return 'Slip Sheet';
    return 'Separate Off';
  }
}
