int compareNaturalText(String a, String b) {
  final tokenPattern = RegExp(r'\d+|\D+');
  final aTokens = tokenPattern
      .allMatches(a.trim().toLowerCase())
      .map((m) => m.group(0) ?? '')
      .toList();
  final bTokens = tokenPattern
      .allMatches(b.trim().toLowerCase())
      .map((m) => m.group(0) ?? '')
      .toList();

  final minLen = aTokens.length < bTokens.length
      ? aTokens.length
      : bTokens.length;
  for (var i = 0; i < minLen; i++) {
    final at = aTokens[i];
    final bt = bTokens[i];
    final aNum = int.tryParse(at);
    final bNum = int.tryParse(bt);
    if (aNum != null && bNum != null) {
      final cmp = aNum.compareTo(bNum);
      if (cmp != 0) return cmp;
      continue;
    }
    final cmp = at.compareTo(bt);
    if (cmp != 0) return cmp;
  }
  return aTokens.length.compareTo(bTokens.length);
}
