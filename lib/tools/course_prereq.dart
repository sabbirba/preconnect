import 'package:preconnect/model/progress_info.dart' show courseCodeKey;

bool prerequisiteSatisfied(String raw, Set<String> readyCodes) {
  final tokens = prerequisiteTokens(raw);
  if (tokens.isEmpty) return true;
  var index = 0;

  late bool Function() parseExpression;
  late bool Function() parseTerm;
  late bool Function() parseFactor;

  parseExpression = () {
    var value = parseTerm();
    while (index < tokens.length && tokens[index] == 'OR') {
      index++;
      value = parseTerm() || value;
    }
    return value;
  };

  parseTerm = () {
    var value = parseFactor();
    while (index < tokens.length && tokens[index] == 'AND') {
      index++;
      value = parseFactor() && value;
    }
    return value;
  };

  parseFactor = () {
    if (index >= tokens.length) return true;
    final token = tokens[index];
    if (token == '(') {
      index++;
      final value = parseExpression();
      if (index < tokens.length && tokens[index] == ')') {
        index++;
      }
      return value;
    }
    index++;
    return readyCodes.contains(courseCodeKey(token));
  };

  return parseExpression();
}

List<String> prerequisiteTokens(String raw) {
  final normalized = raw.trim().toUpperCase();
  if (normalized.isEmpty ||
      normalized == 'N/A' ||
      normalized == 'NONE' ||
      normalized == '-') {
    return const <String>[];
  }

  final pattern = RegExp(
    r'\(|\)|\bAND\b|\bOR\b|\b[A-Z]{2,4}\s*-?\s*\d{3,4}[A-Z]?\b',
  );
  return pattern
      .allMatches(normalized)
      .map((match) => (match.group(0) ?? '').replaceAll(RegExp(r'\s+'), ''))
      .where((token) => token.isNotEmpty)
      .toList();
}
