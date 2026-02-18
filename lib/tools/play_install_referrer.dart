import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

class PlayInstallReferrer {
  PlayInstallReferrer._();

  static const MethodChannel _channel = MethodChannel(
    'preconnect/play_install_referrer',
  );
  static const String _cacheKey = 'play_install_referrer_payload_v1';
  static const int _maxReferrerLength = 512;

  static Map<String, String>? _cachedHeaders;

  static Future<void> prefetch() async {
    await headers();
  }

  static Future<Map<String, String>> headers() async {
    if (!Platform.isAndroid) return const {};

    final cached = _cachedHeaders;
    if (cached != null) return cached;

    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_cacheKey);
    if (raw != null && raw.isNotEmpty) {
      final parsed = _parseHeadersFromJson(raw);
      if (parsed.isNotEmpty) {
        _cachedHeaders = parsed;
        return parsed;
      }
    }

    try {
      final dynamic data = await _channel.invokeMethod('getInstallReferrer');
      if (data is! Map) return const {};

      final payload = <String, dynamic>{};
      data.forEach((key, value) {
        if (key is String) payload[key] = value;
      });
      final headers = _headersFromPayload(payload);
      if (headers.isEmpty) return const {};

      await prefs.setString(_cacheKey, jsonEncode(payload));
      _cachedHeaders = headers;
      return headers;
    } catch (_) {
      return const {};
    }
  }

  static Map<String, String> _parseHeadersFromJson(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return const {};
      return _headersFromPayload(decoded);
    } catch (_) {
      return const {};
    }
  }

  static Map<String, String> _headersFromPayload(Map<String, dynamic> payload) {
    final headers = <String, String>{};

    final referrer = payload['installReferrer']?.toString();
    if (referrer != null && referrer.isNotEmpty) {
      headers['X-Play-Install-Referrer'] = _sanitize(
        referrer,
        _maxReferrerLength,
      );
    }

    final clickTs = payload['referrerClickTimestampSeconds'];
    if (clickTs != null) {
      headers['X-Play-Referrer-Click-Seconds'] = clickTs.toString();
    }

    final installTs = payload['installBeginTimestampSeconds'];
    if (installTs != null) {
      headers['X-Play-Install-Begin-Seconds'] = installTs.toString();
    }

    final installVersion = payload['installVersion']?.toString();
    if (installVersion != null && installVersion.isNotEmpty) {
      headers['X-Play-Install-Version'] = _sanitize(installVersion, 64);
    }

    final instantParam = payload['googlePlayInstantParam'];
    if (instantParam != null) {
      headers['X-Play-Instant-App'] = instantParam.toString();
    }

    return headers;
  }

  static String _sanitize(String input, int maxLen) {
    final sanitized = input.replaceAll(RegExp(r'[\r\n]'), '').trim();
    if (sanitized.length <= maxLen) return sanitized;
    return sanitized.substring(0, maxLen);
  }
}
