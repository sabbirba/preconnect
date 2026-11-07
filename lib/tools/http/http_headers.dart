final RegExp _httpEtagPattern = RegExp(r'^(?:W/)?"[\x21\x23-\x7E\x80-\xFF]*"$');

bool isValidHttpEtag(String? value) {
  if (value == null || value.length > 1024) return false;
  return _httpEtagPattern.hasMatch(value);
}
