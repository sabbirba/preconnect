import 'dart:async';
import 'dart:convert';

import 'package:preconnect/tools/app_storage.dart';
import 'package:preconnect/tools/http/http_utils.dart';

class CdnJsonCache {
  CdnJsonCache._();

  static final Map<String, Object?> _memory = <String, Object?>{};
  static final Map<String, Future<Object?>> _inFlight =
      <String, Future<Object?>>{};

  static T? peek<T extends Object>(String cacheKey) {
    return _memory[cacheKey] as T?;
  }

  static Future<T?> load<T extends Object>({
    required String url,
    required String cacheKey,
    required T? Function(dynamic decoded) decode,
    bool forceRefresh = false,
    Duration timeout = const Duration(seconds: 8),
  }) async {
    if (!forceRefresh && _memory.containsKey(cacheKey)) {
      return _memory[cacheKey] as T?;
    }

    if (!forceRefresh) {
      final cached = await _readCached<T>(cacheKey, decode);
      if (cached != null) {
        _memory[cacheKey] = cached;
        unawaited(
          load<T>(
            url: url,
            cacheKey: cacheKey,
            decode: decode,
            forceRefresh: true,
            timeout: timeout,
          ),
        );
        return cached;
      }
    }

    final existingFetch = _inFlight[cacheKey];
    if (!forceRefresh && existingFetch != null) {
      return (await existingFetch) as T?;
    }

    final fetch = _fetch<T>(
      url: url,
      cacheKey: cacheKey,
      decode: decode,
      timeout: timeout,
    );
    _inFlight[cacheKey] = fetch;
    try {
      return await fetch;
    } finally {
      if (identical(_inFlight[cacheKey], fetch)) {
        _inFlight.remove(cacheKey);
      }
    }
  }

  static Future<T?> _fetch<T extends Object>({
    required String url,
    required String cacheKey,
    required T? Function(dynamic decoded) decode,
    required Duration timeout,
  }) async {
    try {
      final response = await HttpUtils.client
          .get(Uri.parse(url))
          .timeout(timeout);
      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body);
        final value = decode(decoded);
        if (value != null) {
          _memory[cacheKey] = value;
          await AppStorage.instance.setString(cacheKey, response.body);
          return value;
        }
      }
    } catch (_) {}

    final cached = await _readCached<T>(cacheKey, decode);
    if (cached != null) {
      _memory[cacheKey] = cached;
      return cached;
    }
    return null;
  }

  static Future<T?> _readCached<T extends Object>(
    String cacheKey,
    T? Function(dynamic decoded) decode,
  ) async {
    final raw = await AppStorage.instance.getString(cacheKey);
    if (raw == null || raw.trim().isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      return decode(decoded);
    } catch (_) {
      return null;
    }
  }
}
