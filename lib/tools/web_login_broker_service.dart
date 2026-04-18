import 'dart:convert';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:http/http.dart' as http;
import 'package:preconnect/api/api_config.dart';
import 'package:preconnect/tools/web_login_models.dart';

class WebLoginBrokerSession {
  const WebLoginBrokerSession({required this.request, required this.status});

  final WebLoginRequestPayload request;
  final String status;
}

class WebLoginBrokerStatus {
  const WebLoginBrokerStatus({
    required this.status,
    required this.sessionId,
    required this.approved,
    required this.expired,
  });

  final String status;
  final String sessionId;
  final bool approved;
  final bool expired;
}

class WebLoginBrokerService {
  static const Duration _timeout = Duration(seconds: 12);
  final http.Client _client;

  WebLoginBrokerService({http.Client? client})
    : _client = client ?? http.Client();

  String get _origin => kIsWeb ? Uri.base.origin : ApiConfig.webLoginBrokerBase;
  String get _base => kIsWeb ? '$_origin/api' : ApiConfig.webLoginBrokerBase;

  Future<http.Response> _postJson({
    required Uri uri,
    required String body,
  }) async {
    final request = http.Request('POST', uri)
      ..headers.addAll({
        'Content-Type': 'application/json',
        'Cache-Control': 'no-store',
      })
      ..body = body;
    final streamed = await _client.send(request).timeout(_timeout);
    return http.Response.fromStream(streamed);
  }

  Future<WebLoginBrokerSession> createSession() async {
    final response = await _postJson(
      uri: Uri.parse('$_base/web-login/session'),
      body: '{}',
    );
    if (response.statusCode != 200) {
      final message = response.body.trim();
      throw Exception(
        message.isEmpty
            ? 'Unable to create login session (${response.statusCode})'
            : 'Unable to create login session (${response.statusCode}): $message',
      );
    }
    final json = jsonDecode(response.body) as Map<String, dynamic>;
    return WebLoginBrokerSession(
      request: WebLoginRequestPayload(
        version: 1,
        type: 'web_login_request',
        sessionId: '${json['sessionId'] ?? ''}',
        sessionToken: '${json['sessionToken'] ?? ''}',
        studentEmail: '${json['studentEmail'] ?? ''}',
        nonce: '${json['nonce'] ?? ''}',
        expiresAtMillis: (json['expiresAt'] as num?)?.toInt() ?? 0,
      ),
      status: '${json['status'] ?? 'pending'}',
    );
  }

  Future<WebLoginBrokerStatus> getStatus(WebLoginRequestPayload request) async {
    final uri = Uri.parse(
      '$_base/web-login/session/${request.sessionId}'
      '?sessionToken=${Uri.encodeQueryComponent(request.sessionToken)}'
      '&_ts=${DateTime.now().millisecondsSinceEpoch}',
    );
    final response = await _client
        .get(uri, headers: {'Cache-Control': 'no-store'})
        .timeout(_timeout);
    if (response.statusCode != 200) {
      throw Exception('Unable to check login status');
    }
    final json = jsonDecode(response.body) as Map<String, dynamic>;
    return WebLoginBrokerStatus(
      status: '${json['status'] ?? ''}',
      sessionId: '${json['sessionId'] ?? ''}',
      approved: json['approved'] == true,
      expired: json['expired'] == true,
    );
  }

  Future<bool> isActiveWebSession({
    required String webSessionId,
    required String webSessionToken,
  }) async {
    final id = webSessionId.trim();
    final token = webSessionToken.trim();
    if (id.isEmpty || token.isEmpty) return false;
    final uri = Uri.parse(
      '$_base/web-login/active/$id'
      '?sessionToken=${Uri.encodeQueryComponent(token)}'
      '&_ts=${DateTime.now().millisecondsSinceEpoch}',
    );
    final response = await _client
        .get(uri, headers: {'Cache-Control': 'no-store'})
        .timeout(_timeout);
    if (response.statusCode != 200) return false;
    final json = jsonDecode(response.body) as Map<String, dynamic>;
    return json['active'] == true;
  }

  Future<WebLoginApprovePayload> consume(WebLoginRequestPayload request) async {
    final response = await _client
        .post(
          Uri.parse('$_base/web-login/session/${request.sessionId}/consume'),
          headers: {
            'Content-Type': 'application/json',
            'Cache-Control': 'no-store',
          },
          body: jsonEncode({'sessionToken': request.sessionToken}),
        )
        .timeout(_timeout);
    if (response.statusCode != 200) {
      throw Exception('Unable to complete web login');
    }
    return WebLoginApprovePayload.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }

  Future<void> approve({
    required WebLoginRequestPayload request,
    required WebLoginApprovePayload payload,
  }) async {
    final normalizedStudentEmail = payload.studentEmail.trim().toLowerCase();
    final response = await _client
        .post(
          Uri.parse('$_base/web-login/session/${request.sessionId}/approve'),
          headers: {
            'Content-Type': 'application/json',
            'Cache-Control': 'no-store',
          },
          body: jsonEncode({
            'sessionToken': request.sessionToken,
            'studentEmail': normalizedStudentEmail,
            ...payload.toJson(),
          }),
        )
        .timeout(_timeout);
    if (response.statusCode != 200) {
      final body = response.body.trim();
      throw Exception(body.isEmpty ? 'Unable to approve web login' : body);
    }
  }

  Future<List<WebActiveSession>> listActiveSessions({
    required String accessToken,
  }) async {
    final response = await _client
        .post(
          Uri.parse('$_base/web-login/sessions/list'),
          headers: {
            'Content-Type': 'application/json',
            'Cache-Control': 'no-store',
          },
          body: jsonEncode({'accessToken': accessToken}),
        )
        .timeout(_timeout);
    if (response.statusCode == 404) {
      return const <WebActiveSession>[];
    }
    if (response.statusCode != 200) {
      throw Exception('Unable to load active web sessions');
    }
    final json = jsonDecode(response.body) as Map<String, dynamic>;
    final raw = json['sessions'];
    if (raw is! List) return const <WebActiveSession>[];
    return raw
        .whereType<Map<String, dynamic>>()
        .map(WebActiveSession.fromJson)
        .toList();
  }

  Future<void> revokeSession({
    required String accessToken,
    required String webSessionId,
  }) async {
    final response = await _client
        .post(
          Uri.parse('$_base/web-login/sessions/revoke'),
          headers: {
            'Content-Type': 'application/json',
            'Cache-Control': 'no-store',
          },
          body: jsonEncode({
            'accessToken': accessToken,
            'webSessionId': webSessionId,
          }),
        )
        .timeout(_timeout);
    if (response.statusCode == 404) {
      throw Exception(
        'Session logout is not available on current server build',
      );
    }
    if (response.statusCode != 200) {
      throw Exception('Unable to revoke web session');
    }
  }

  Future<void> revokeAllSessions({required String accessToken}) async {
    final response = await _client
        .post(
          Uri.parse('$_base/web-login/sessions/revoke-all'),
          headers: {
            'Content-Type': 'application/json',
            'Cache-Control': 'no-store',
          },
          body: jsonEncode({'accessToken': accessToken}),
        )
        .timeout(_timeout);
    if (response.statusCode == 404) {
      throw Exception(
        'Session logout is not available on current server build',
      );
    }
    if (response.statusCode != 200) {
      throw Exception('Unable to revoke all web sessions');
    }
  }
}
