import 'dart:convert';
import 'package:http/http.dart' as http;

class DohResolver {
  static final Map<String, String> _cache = <String, String>{};
  static final Map<String, DateTime> _cachedAt = <String, DateTime>{};
  static const Duration _cacheTtl = Duration(minutes: 5);

  static String? parseIpv4Hint(String data) {
    final match = RegExp(r'ipv4hint=([0-9\.,]+)').firstMatch(data);
    return match?.group(1)?.split(',').first.trim();
  }

  static String? parseTypeA(dynamic data) {
    if (data is String && RegExp(r'^[0-9\.]+$').hasMatch(data.trim())) {
      return data.trim();
    }
    return null;
  }

  static Future<String?> resolve(String domain, {http.Client? client}) async {
    final now = DateTime.now();
    final cached = _cache[domain];
    final cachedTime = _cachedAt[domain];
    if (cached != null &&
        cachedTime != null &&
        now.difference(cachedTime) < _cacheTtl) {
      return cached;
    }

    final isPreconnect = domain.contains('preconnect.app');
    final queryType = isPreconnect ? 'HTTPS' : 'A';

    try {
      final uri = Uri.parse(
        'https://1.1.1.1/dns-query?name=$domain&type=$queryType',
      );
      final httpClient = client ?? http.Client();
      final response = await httpClient
          .get(
            uri,
            headers: const <String, String>{
              'Accept': 'application/dns-json',
              'Host': 'cloudflare-dns.com',
            },
          )
          .timeout(const Duration(seconds: 3));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data is Map<String, dynamic> && data['Answer'] is List) {
          for (final item in data['Answer'] as List) {
            if (item is Map<String, dynamic>) {
              final raw = item['data']?.toString() ?? '';
              final ip = isPreconnect
                  ? parseIpv4Hint(raw)
                  : (item['type'] == 1 ? parseTypeA(raw) : null);
              if (ip != null && ip.isNotEmpty) {
                _cache[domain] = ip;
                _cachedAt[domain] = now;
                return ip;
              }
            }
          }
        }
      }
    } catch (_) {}
    return null;
  }

  static Future<void> warmup({http.Client? client}) async {
    const domains = <String>[
      'api.preconnect.app',
      'preconnect.app',
      'connect.bracu.ac.bd',
      'bracu.ac.bd',
    ];
    await Future.wait(domains.map((domain) => resolve(domain, client: client)));
  }
}
