String? normalizeMediaUrl(String raw) {
  final value = raw.trim();
  if (value.isEmpty) return null;

  if (value.startsWith('data:')) return null;

  final uri = Uri.tryParse(value);
  if (uri == null) return null;

  if (uri.scheme != 'http' && uri.scheme != 'https') return null;

  final cleaned = Uri(
    scheme: uri.scheme,
    userInfo: uri.userInfo,
    host: uri.host,
    port: uri.port,
    path: uri.path.replaceAll(RegExp(r'[/\\]+$'), ''),
    query: uri.query,
    fragment: uri.fragment,
  ).toString();

  return cleaned.isEmpty ? null : cleaned;
}

String? normalizeImageUrl(String raw, {String? baseUrl}) {
  final value = raw.trim();
  if (value.isEmpty) return null;

  if (value.startsWith('data:')) return null;
  if (value.startsWith('//')) return 'https:$value';
  if (value.startsWith('www.')) return 'https://$value';

  final parsed = Uri.tryParse(value);
  if (parsed != null && (parsed.scheme == 'http' || parsed.scheme == 'https')) {
    return normalizeMediaUrl(parsed.toString());
  }

  final base = (baseUrl != null && baseUrl.trim().isNotEmpty)
      ? baseUrl.trim()
      : 'https://connect.bracu.ac.bd';
  final baseUri = Uri.tryParse(base);
  if (baseUri != null) {
    try {
      final resolved = baseUri.resolve(value).toString();
      return normalizeMediaUrl(resolved);
    } catch (_) {}
  }

  return null;
}
