import 'dart:async';
import 'dart:convert';
import 'package:preconnect/tools/preload_cache.dart';
import 'package:preconnect/api/repository_cache.dart';
import 'package:http/http.dart' as http;

import 'package:preconnect/tools/app_storage.dart';
import 'package:preconnect/tools/http/http_utils.dart';

class CdnJsonCache {
  CdnJsonCache._();

  static final Map<String, Object?> _memory = <String, Object?>{};
  static final Map<String, DateTime> _storedAt = <String, DateTime>{};
  static final Map<String, PreloadCache<Object?>> _fetches =
      <String, PreloadCache<Object?>>{};

  static T? peek<T extends Object>(String cacheKey) {
    return _memory[cacheKey] as T?;
  }

  static Future<T?> load<T extends Object>({
    required String url,
    required String cacheKey,
    required T? Function(dynamic decoded) decode,
    bool forceRefresh = false,
    http.Client? client,
    Duration timeout = const Duration(seconds: 8),
    Duration? maxAge,
  }) async {
    final fresh = maxAge == null || _isFresh(cacheKey, maxAge);
    if (!forceRefresh && fresh && _memory.containsKey(cacheKey)) {
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
            client: client,
            timeout: timeout,
          ),
        );
        return cached;
      }
    }

    final fetched = await _fetches
        .putIfAbsent(cacheKey, PreloadCache<Object?>.new)
        .share(
          () => _fetch<T>(
            url: url,
            cacheKey: cacheKey,
            decode: decode,
            timeout: timeout,
            client: client,
          ),
        );
    return fetched as T?;
  }

  static Future<T?> _fetch<T extends Object>({
    required String url,
    required String cacheKey,
    required T? Function(dynamic decoded) decode,
    required Duration timeout,
    http.Client? client,
  }) async {
    try {
      final response = await (client ?? HttpUtils.client)
          .get(Uri.parse(url))
          .timeout(timeout);
      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body);
        final value = decode(decoded);
        if (value != null) {
          _remember(cacheKey, value);
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

  static void _remember(String cacheKey, Object value) {
    _memory[cacheKey] = value;
    _storedAt[cacheKey] = DateTime.now();
  }

  static bool _isFresh(String cacheKey, Duration maxAge) {
    final storedAt = _storedAt[cacheKey];
    return storedAt != null && DateTime.now().difference(storedAt) < maxAge;
  }

  static Future<T?> _readCached<T extends Object>(
    String cacheKey,
    T? Function(dynamic decoded) decode,
  ) {
    return RepositoryCache.instance.readJson(cacheKey, decode);
  }
}
