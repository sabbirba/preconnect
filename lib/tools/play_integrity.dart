import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:crypto/crypto.dart';
import 'package:preconnect/api/api_config.dart';

class PlayIntegrity {
  PlayIntegrity._();
  static const MethodChannel _channel = MethodChannel(
    'preconnect/play_integrity',
  );

  static bool _prepared = false;
  static DateTime? _preparedAtUtc;
  static const Duration _prepareTtl = Duration(hours: 8);

  static String? _cachedToken;
  static DateTime? _cachedAtUtc;
  static String? _cachedRequestHash;
  static const Duration _cacheTtl = Duration(minutes: 2);

  static Future<void> prepare() async {
    if (!Platform.isAndroid) return;
    final cloudProjectNumber = ApiConfig.playIntegrityCloudProjectNumber;
    if (cloudProjectNumber == null) return;

    final preparedAt = _preparedAtUtc;
    if (_prepared && preparedAt != null) {
      final stillValid =
          DateTime.now().toUtc().difference(preparedAt) < _prepareTtl;
      if (stillValid) return;
    }

    await _channel.invokeMethod('prepare', <String, dynamic>{
      'cloudProjectNumber': cloudProjectNumber,
    });
    _prepared = true;
    _preparedAtUtc = DateTime.now().toUtc();
  }

  static Future<String?> tokenForRequest({
    required String method,
    required String url,
    String body = '',
  }) async {
    if (!Platform.isAndroid) return null;
    if (ApiConfig.playIntegrityCloudProjectNumber == null) return null;

    try {
      await prepare();
    } catch (_) {
      _prepared = false;
      return null;
    }

    final requestHash = _buildRequestHash(method: method, url: url, body: body);
    final now = DateTime.now().toUtc();
    final token = _cachedToken;
    final cachedAtUtc = _cachedAtUtc;
    final cachedRequestHash = _cachedRequestHash;
    if (token != null &&
        cachedAtUtc != null &&
        requestHash == cachedRequestHash &&
        now.difference(cachedAtUtc) < _cacheTtl) {
      return token;
    }

    final dynamic value = await _channel.invokeMethod(
      'requestToken',
      <String, dynamic>{'requestHash': requestHash},
    );
    if (value is! String || value.isEmpty) return null;

    _cachedToken = value;
    _cachedAtUtc = now;
    _cachedRequestHash = requestHash;
    return value;
  }

  static String requestHash({
    required String method,
    required String url,
    String body = '',
  }) {
    return _buildRequestHash(method: method, url: url, body: body);
  }

  static String _buildRequestHash({
    required String method,
    required String url,
    required String body,
  }) {
    final canonical =
        '${method.trim().toUpperCase()}|${url.trim()}|${body.trim()}';
    final digest = sha256.convert(utf8.encode(canonical));
    return base64UrlEncode(digest.bytes).replaceAll('=', '');
  }
}
