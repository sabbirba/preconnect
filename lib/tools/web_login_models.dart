import 'dart:convert';

import 'package:archive/archive.dart';

class WebLoginRequestPayload {
  const WebLoginRequestPayload({
    required this.version,
    required this.type,
    required this.sessionId,
    required this.sessionToken,
    required this.studentEmail,
    required this.nonce,
    required this.expiresAtMillis,
  });

  final int version;
  final String type;
  final String sessionId;
  final String sessionToken;
  final String studentEmail;
  final String nonce;
  final int expiresAtMillis;

  bool get isExpired => DateTime.now().millisecondsSinceEpoch > expiresAtMillis;

  Map<String, dynamic> toJson() => {
    'v': version,
    't': type,
    'sid': sessionId,
    'st': sessionToken,
    'se': studentEmail,
    'n': nonce,
    'exp': expiresAtMillis,
  };

  String toQrData() {
    final raw = jsonEncode(toJson());
    final encoded = utf8.encode(raw);
    final gzip = const GZipEncoder().encode(encoded);
    return base64Url.encode(gzip);
  }

  static WebLoginRequestPayload fromQrData(String data) {
    final bytes = base64Url.decode(base64Url.normalize(data.trim()));
    final jsonStr = utf8.decode(const GZipDecoder().decodeBytes(bytes));
    final json = jsonDecode(jsonStr) as Map<String, dynamic>;
    return WebLoginRequestPayload(
      version: (json['v'] as num?)?.toInt() ?? 1,
      type: '${json['t'] ?? json['type'] ?? ''}',
      sessionId: '${json['sid'] ?? json['sessionId'] ?? ''}',
      sessionToken: '${json['st'] ?? json['sessionToken'] ?? ''}',
      studentEmail: '${json['se'] ?? json['studentEmail'] ?? ''}',
      nonce: '${json['n'] ?? json['nonce'] ?? ''}',
      expiresAtMillis:
          (json['exp'] as num?)?.toInt() ??
          (json['expiresAt'] as num?)?.toInt() ??
          0,
    );
  }
}

class WebLoginApprovePayload {
  const WebLoginApprovePayload({
    required this.studentEmail,
    required this.studentId,
    required this.accessToken,
    required this.refreshToken,
    required this.sessionExpiresAtMillis,
    this.webSessionId,
    this.webSessionToken,
  });

  final String studentEmail;
  final String studentId;
  final String accessToken;
  final String refreshToken;
  final int sessionExpiresAtMillis;
  final String? webSessionId;
  final String? webSessionToken;

  Map<String, dynamic> toJson() => {
    'studentEmail': studentEmail,
    'studentId': studentId,
    'accessToken': accessToken,
    'refreshToken': refreshToken,
    'sessionExpiresAt': sessionExpiresAtMillis,
    if ((webSessionId ?? '').trim().isNotEmpty) 'webSessionId': webSessionId,
    if ((webSessionToken ?? '').trim().isNotEmpty)
      'webSessionToken': webSessionToken,
  };

  static WebLoginApprovePayload fromJson(Map<String, dynamic> json) {
    return WebLoginApprovePayload(
      studentEmail: '${json['studentEmail'] ?? ''}',
      studentId: '${json['studentId'] ?? ''}',
      accessToken: '${json['accessToken'] ?? ''}',
      refreshToken: '${json['refreshToken'] ?? ''}',
      sessionExpiresAtMillis: (json['sessionExpiresAt'] as num?)?.toInt() ?? 0,
      webSessionId: '${json['webSessionId'] ?? ''}'.trim().isEmpty
          ? null
          : '${json['webSessionId']}',
      webSessionToken: '${json['webSessionToken'] ?? ''}'.trim().isEmpty
          ? null
          : '${json['webSessionToken']}',
    );
  }
}

class WebActiveSession {
  const WebActiveSession({
    required this.webSessionId,
    required this.studentId,
    required this.studentEmail,
    required this.createdAtMillis,
    required this.lastSeenAtMillis,
    required this.sessionExpiresAtMillis,
    required this.revokedAtMillis,
    required this.revoked,
    required this.userAgent,
  });

  final String webSessionId;
  final String studentId;
  final String studentEmail;
  final int createdAtMillis;
  final int lastSeenAtMillis;
  final int sessionExpiresAtMillis;
  final int revokedAtMillis;
  final bool revoked;
  final String userAgent;

  bool get isExpired =>
      sessionExpiresAtMillis > 0 &&
      sessionExpiresAtMillis <= DateTime.now().millisecondsSinceEpoch;

  static WebActiveSession fromJson(Map<String, dynamic> json) {
    return WebActiveSession(
      webSessionId: '${json['webSessionId'] ?? ''}',
      studentId: '${json['studentId'] ?? ''}',
      studentEmail: '${json['studentEmail'] ?? ''}',
      createdAtMillis: (json['createdAt'] as num?)?.toInt() ?? 0,
      lastSeenAtMillis: (json['lastSeenAt'] as num?)?.toInt() ?? 0,
      sessionExpiresAtMillis: (json['sessionExpiresAt'] as num?)?.toInt() ?? 0,
      revokedAtMillis: (json['revokedAt'] as num?)?.toInt() ?? 0,
      revoked: json['revoked'] == true,
      userAgent: '${json['userAgent'] ?? ''}',
    );
  }
}
