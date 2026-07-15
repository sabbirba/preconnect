int compareNaturalText(String a, String b) {
  return _compareNatural(a.trim().toLowerCase(), b.trim().toLowerCase());
}

int _compareNatural(String a, String b) {
  int i = 0, j = 0;
  while (i < a.length && j < b.length) {
    final ca = a[i], cb = b[j];
    final da = ca.codeUnitAt(0), db = cb.codeUnitAt(0);
    final aIsDigit = da >= 48 && da <= 57;
    final bIsDigit = db >= 48 && db <= 57;
    if (aIsDigit && bIsDigit) {
      int numA = 0, numB = 0;
      while (i < a.length &&
          a[i].codeUnitAt(0) >= 48 &&
          a[i].codeUnitAt(0) <= 57) {
        numA = numA * 10 + (a[i].codeUnitAt(0) - 48);
        i++;
      }
      while (j < b.length &&
          b[j].codeUnitAt(0) >= 48 &&
          b[j].codeUnitAt(0) <= 57) {
        numB = numB * 10 + (b[j].codeUnitAt(0) - 48);
        j++;
      }
      if (numA != numB) return numA.compareTo(numB);
    } else {
      final cmp = ca.compareTo(cb);
      if (cmp != 0) return cmp;
      i++;
      j++;
    }
  }
  return a.length.compareTo(b.length);
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
