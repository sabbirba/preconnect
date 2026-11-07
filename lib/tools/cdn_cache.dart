import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:preconnect/tools/preload_cache.dart';
import 'package:preconnect/api/repository_cache.dart';
import 'package:http/http.dart' as http;

import 'package:preconnect/tools/app_storage.dart';
import 'package:preconnect/tools/http/http_utils.dart';

class CdnJsonCache {
  CdnJsonCache._();

  static final Map<String, Object?> _memory = <String, Object?>{};
  static final Map<String, PreloadCache<Object?>> _fetches =
      <String, PreloadCache<Object?>>{};
  static final Map<String, Future<Object?> Function()> _sources =
      <String, Future<Object?> Function()>{};
  static final ValueNotifier<int> revision = ValueNotifier<int>(0);

  static Future<void> refreshAll() async {
    await Future.wait(_sources.values.map((refresh) => refresh()));
  }

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
  }) async {
    Future<T?> fetch() async =>
        await _fetches
                .putIfAbsent(cacheKey, PreloadCache<Object?>.new)
                .share(() => _fetch<T>(url, cacheKey, decode, timeout, client))
            as T?;
    _sources[cacheKey] = fetch;
    if (forceRefresh) return fetch();
    if (_memory.containsKey(cacheKey)) return _memory[cacheKey] as T?;
    final cached = await _readCached<T>(cacheKey, decode);
    if (cached == null) return fetch();
    _remember(cacheKey, cached);
    unawaited(fetch());
    return cached;
  }

  static void _remember(String cacheKey, Object value, {bool changed = false}) {
    final isNew = !_memory.containsKey(cacheKey);
    _memory[cacheKey] = value;
    if (isNew || changed) revision.value++;
  }

  static Future<T?> _fetch<T extends Object>(
    String url,
    String cacheKey,
    T? Function(dynamic decoded) decode,
    Duration timeout,
    http.Client? client,
  ) async {
    try {
      final response = await (client ?? HttpUtils.client)
          .get(Uri.parse(url))
          .timeout(timeout);
      final value = response.statusCode == 200
          ? decode(jsonDecode(response.body))
          : null;
      if (value != null) {
        final storage = AppStorage.instance;
        final changed = await storage.getString(cacheKey) != response.body;
        if (changed) await storage.setString(cacheKey, response.body);
        _remember(cacheKey, value, changed: changed);
        return value;
      }
    } catch (_) {}
    final cached = await _readCached<T>(cacheKey, decode);
    if (cached != null) _remember(cacheKey, cached);
    return cached;
  }

  static Future<T?> _readCached<T extends Object>(
    String cacheKey,
    T? Function(dynamic decoded) decode,
  ) {
    return RepositoryCache.instance.readJson(cacheKey, decode);
  }
}
