import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:preconnect/api/api_client.dart';
import 'package:preconnect/api/api_config.dart';
import 'package:preconnect/api/repository_cache.dart';
import 'package:preconnect/tools/app_log.dart';

class FacultyPhotos extends ValueNotifier<Map<String, String>> {
  FacultyPhotos._() : super(const <String, String>{});

  static final FacultyPhotos instance = FacultyPhotos._();
  static const String indexUrl = '${ApiConfig.realtimeApiBase}/faculty/photos';
  static const String _cacheKey = 'faculty_photos_v1';

  Future<void>? _loading;

  Future<void> load() => _loading ??= _load();

  Future<void> _load() async {
    final cached = await RepositoryCache.instance.readString(_cacheKey);
    if (cached != null && cached.isNotEmpty) {
      value = parseFacultyPhotos(cached, ApiConfig.realtimeApiBase);
    }
    try {
      final response = await ApiClient().publicGet(
        indexUrl,
        cacheDuration: const Duration(hours: 6),
      );
      value = parseFacultyPhotos(response.body, ApiConfig.realtimeApiBase);
      await RepositoryCache.instance.writeString(_cacheKey, response.body);
    } catch (error) {
      _loading = null;
      unawaited(AppLog.write('Faculty photos unavailable: $error'));
    }
  }

  String? photoFor(String? initial) {
    final key = initial?.trim().toUpperCase() ?? '';
    if (key.isEmpty) return null;
    return value[key];
  }
}

Map<String, String> parseFacultyPhotos(String raw, String base) {
  final decoded = jsonDecode(raw);
  if (decoded is! Map) return const <String, String>{};
  return <String, String>{
    for (final entry in decoded.entries)
      if (entry.value case final String path when path.startsWith('/'))
        '${entry.key}'.trim().toUpperCase(): '$base$path',
  };
}
