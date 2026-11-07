const Set<String> _knownNotificationCategories = <String>{
  'announcement',
  'announcements',
  'news',
  'notice',
  'notices',
  'advising',
  'academics',
  'academic',
  'exam',
  'exams',
  'course',
  'courses',
  'grade',
  'grades',
  'payment',
  'library',
  'connect',
  'transport',
  'bus',
  'general',
};

String stripNotificationCategory(
  String raw, {
  Iterable<String?> categories = const <String?>[],
}) {
  var text = raw.trim();
  if (text.isEmpty) return '';
  final candidates = <String>{
    for (final category in categories)
      if (category != null && category.trim().isNotEmpty)
        category.trim().toLowerCase(),
    ..._knownNotificationCategories,
  };
  for (final category in candidates) {
    if (text.toLowerCase() == category) return '';
    final pattern = RegExp(
      r'^\s*(\[|\()?\s*' +
          RegExp.escape(category) +
          r'\s*(\]|\))?\s*[:\-–|•]?\s*',
      caseSensitive: false,
    );
    text = text.replaceFirst(pattern, '').trim();
  }
  return text;
}
