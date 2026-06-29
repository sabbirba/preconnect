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

class ExamSorting {
  static int typeRank(String type) {
    final normalized = type.trim().toLowerCase();
    if (normalized == 'midterm' || normalized == 'mid') return 0;
    if (normalized == 'final') return 1;
    return 2;
  }

  static int compareExamEntries({
    required String typeA,
    required String typeB,
    required DateTime? dateTimeA,
    required DateTime? dateTimeB,
    required String courseCodeA,
    required String courseCodeB,
    required String sectionNameA,
    required String sectionNameB,
  }) {
    final typeCmp = typeRank(typeA).compareTo(typeRank(typeB));
    if (typeCmp != 0) return typeCmp;

    final dateTimeCmp = _compareNullableDateTimesByDateThenTime(
      dateTimeA,
      dateTimeB,
    );
    if (dateTimeCmp != 0) return dateTimeCmp;

    final courseCmp = compareNaturalText(courseCodeA, courseCodeB);
    if (courseCmp != 0) return courseCmp;
    return compareNaturalText(sectionNameA, sectionNameB);
  }

  static int _compareNullableDateTimesByDateThenTime(DateTime? a, DateTime? b) {
    if (a == null && b == null) return 0;
    if (a == null) return 1;
    if (b == null) return -1;

    final dateCmp = DateTime(
      a.year,
      a.month,
      a.day,
    ).compareTo(DateTime(b.year, b.month, b.day));
    if (dateCmp != 0) return dateCmp;
    return a.compareTo(b);
  }
}
