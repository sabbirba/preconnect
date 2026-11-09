import 'dart:convert';
import 'package:http/http.dart' as http;

class PushDeviceRegistry {
  const PushDeviceRegistry({
    required this.registerUrl,
    required this.unregisterUrl,
    required http.Client client,
    this.timeout = const Duration(seconds: 15),
  }) : _client = client;

  final String registerUrl;
  final String unregisterUrl;
  final http.Client _client;
  final Duration timeout;

  Future<void> post(String url, Map<String, dynamic> payload) async {
    final response = await _client
        .post(
          Uri.parse(url),
          headers: const {'Content-Type': 'application/json'},
          body: jsonEncode(payload),
        )
        .timeout(timeout);
    if (response.statusCode != 200) {
      throw StateError('Push request failed with HTTP ${response.statusCode}');
    }
    final result = jsonDecode(response.body);
    if (result is! Map || result['ok'] != true) {
      throw StateError('Push request was not acknowledged');
    }
  }

  Future<void> register({required String token, required String platform}) {
    return post(registerUrl, {'token': token, 'platform': platform});
  }

  Future<void> unregister(String token) {
    return post(unregisterUrl, {'token': token});
  }
}
