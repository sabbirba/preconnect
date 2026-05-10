import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:preconnect/tools/app_paths.dart';
import 'package:preconnect/tools/cache_registry.dart';
import 'package:preconnect/api/app_preferences_store.dart';

class PersistentImageCache {
  PersistentImageCache._();

  static final PersistentImageCache instance = PersistentImageCache._();
  final Map<String, Future<File?>> _inFlight = <String, Future<File?>>{};
  static const int _maxCachedFiles = 200;
  static const int _maxBytes = 50 * 1024 * 1024;

  Future<File?> fetchFileForUrl(String url) async {
    final value = url.trim();
    if (value.isEmpty) return null;
    final cached = _inFlight[value];
    if (cached != null) return cached;

    final future = _fetchFileForUrlInternal(value);
    _inFlight[value] = future;
    try {
      return await future;
    } finally {
      if (identical(_inFlight[value], future)) {
        _inFlight.remove(value);
      }
    }
  }

  Future<File?> _fetchFileForUrlInternal(String value) async {
    final dir = await AppPaths.supportDirectory();
    final file = File('${dir.path}/${_cacheNameForUrl(value)}');

    if (await file.exists() && await file.length() > 0) {
      await _touchIndex(value, file.path);
      return file;
    }

    try {
      final response = await http.get(Uri.parse(value));
      if (response.statusCode == 200 && response.bodyBytes.isNotEmpty) {
        await file.writeAsBytes(response.bodyBytes, flush: true);
        await _touchIndex(value, file.path);
        await _pruneIfNeeded(dir);
        return file;
      }
    } catch (_) {}

    return null;
  }

  String _cacheNameForUrl(String url) {
    final digest = sha256.convert(utf8.encode(url)).toString();
    return 'img_$digest.bin';
  }

  Future<void> _touchIndex(String url, String path) async {
    try {
      await AppPreferencesStore().setJson(
        '${CacheRegistry.profileImageUrl}_manifest',
        <String, dynamic>{
          'url': url,
          'path': path,
          'at': DateTime.now().millisecondsSinceEpoch,
        },
      );
    } catch (_) {}
  }

  Future<void> _pruneIfNeeded(Directory dir) async {
    try {
      final files = <File>[];
      await for (final entity in dir.list(followLinks: false)) {
        if (entity is File &&
            entity.path.contains('img_') &&
            entity.path.endsWith('.bin')) {
          files.add(entity);
        }
      }
      if (files.length <= _maxCachedFiles) return;

      files.sort((a, b) => a.path.compareTo(b.path));
      var total = 0;
      for (final file in files) {
        try {
          total += await file.length();
        } catch (_) {}
      }
      while (files.length > _maxCachedFiles || total > _maxBytes) {
        final file = files.removeAt(0);
        try {
          total -= await file.length();
          await file.delete();
        } catch (_) {}
      }
    } catch (_) {}
  }
}
