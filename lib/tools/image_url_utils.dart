String? normalizeImageUrl(
  String raw, {
  String? baseUrl,
}) {
  final value = raw.trim();
  if (value.isEmpty) return null;

  if (value.startsWith('data:')) return null;
  if (value.startsWith('//')) return 'https:$value';
  if (value.startsWith('www.')) return 'https://$value';

  final parsed = Uri.tryParse(value);
  if (parsed != null && (parsed.scheme == 'http' || parsed.scheme == 'https')) {
    return parsed.toString();
  }

  final base = baseUrl?.trim();
  if (base != null && base.isNotEmpty) {
    final baseUri = Uri.tryParse(base);
    if (baseUri != null) {
      try {
        return baseUri.resolve(value).toString();
      } catch (_) {}
    }
  }

  return null;
}
