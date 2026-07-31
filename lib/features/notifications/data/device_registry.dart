import 'dart:convert';

typedef PushRequest =
    Future<void> Function(
      String method,
      String url, {
      String body,
      Map<String, String> additionalHeaders,
    });

class PushDeviceRegistry {
  const PushDeviceRegistry({
    required this.registerUrl,
    required this.unregisterUrl,
    required PushRequest send,
  }) : _send = send;

  final String registerUrl;
  final String unregisterUrl;
  final PushRequest _send;

  Future<void> register({required String token, required String platform}) {
    return _send(
      'POST',
      registerUrl,
      body: jsonEncode(<String, dynamic>{'token': token, 'platform': platform}),
      additionalHeaders: const {'Content-Type': 'application/json'},
    );
  }

  Future<void> unregister(String token) {
    return _send(
      'POST',
      unregisterUrl,
      body: jsonEncode(<String, dynamic>{'token': token}),
      additionalHeaders: const {'Content-Type': 'application/json'},
    );
  }
}
