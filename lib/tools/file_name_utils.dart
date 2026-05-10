String sanitizeFileName(String input, {String fallback = 'file'}) {
  final value = input.trim().isEmpty ? fallback : input.trim();
  final safe = value
      .replaceAll(RegExp(r'[\\/:*?"<>|]+'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim()
      .replaceAll(' ', '_');
  return safe.isEmpty ? fallback.replaceAll(' ', '_') : safe;
}
