import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shimmer/shimmer.dart';
import 'package:preconnect/tools/image_url_utils.dart';

class CachedImage extends StatefulWidget {
  const CachedImage({
    super.key,
    required this.url,
    this.fit,
    this.alignment = Alignment.center,
    this.width,
    this.height,
    this.filterQuality = FilterQuality.low,
    this.placeholder,
    this.error,
  });

  final String url;
  final BoxFit? fit;
  final AlignmentGeometry alignment;
  final double? width;
  final double? height;
  final FilterQuality filterQuality;
  final Widget? placeholder;
  final Widget? error;

  static void clearMemoryCache() {
    _CachedImageState.clearMemoryCache();
  }

  @override
  State<CachedImage> createState() => _CachedImageState();
}

class _CachedImageState extends State<CachedImage> {
  static const String _legacyPrefPrefix = 'img_cache_';
  static const Duration _diskCacheTtl = Duration(days: 90);
  static const int _maxDiskCacheFiles = 350;
  static final Future<SharedPreferences> _prefs =
      SharedPreferences.getInstance();
  static final Future<Directory?> _cacheDirFuture = _resolveCacheDir();
  static final Map<String, Uint8List> _memoryCache = {};

  static void clearMemoryCache() {
    _memoryCache.clear();
  }

  Uint8List? _bytes;
  Object? _error;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(CachedImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url) {
      _bytes = null;
      _error = null;
      _loading = false;
      _load();
    }
  }

  String _prefKey(String url) {
    final encoded = base64Url.encode(utf8.encode(url));
    return '$_legacyPrefPrefix$encoded';
  }

  static Future<Directory?> _resolveCacheDir() async {
    if (kIsWeb) return null;
    try {
      final root = await getTemporaryDirectory();
      final dir = Directory('${root.path}/preconnect_image_cache');
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
      return dir;
    } catch (_) {
      return null;
    }
  }

  String _cacheFileName(String key) {
    return sha1.convert(utf8.encode(key)).toString();
  }

  Future<File?> _cacheFileFor(String key) async {
    final dir = await _cacheDirFuture;
    if (dir == null) return null;
    return File('${dir.path}/${_cacheFileName(key)}.img');
  }

  Future<Uint8List?> _readDiskCache(String key) async {
    final file = await _cacheFileFor(key);
    if (file == null || !await file.exists()) return null;
    try {
      final stat = await file.stat();
      final age = DateTime.now().difference(stat.modified);
      if (age > _diskCacheTtl) {
        await file.delete();
        return null;
      }
      return await file.readAsBytes();
    } catch (_) {
      return null;
    }
  }

  Future<void> _writeDiskCache(String key, Uint8List bytes) async {
    final file = await _cacheFileFor(key);
    if (file == null) return;
    try {
      await file.writeAsBytes(bytes, flush: false);
    } catch (_) {}
  }

  Future<void> _cleanupDiskCacheIfNeeded() async {
    final dir = await _cacheDirFuture;
    if (dir == null) return;
    try {
      final files = await dir
          .list()
          .where((entity) => entity is File)
          .cast<File>()
          .toList();
      if (files.length <= _maxDiskCacheFiles) return;
      files.sort((a, b) {
        final aTs = a.statSync().modified.millisecondsSinceEpoch;
        final bTs = b.statSync().modified.millisecondsSinceEpoch;
        return aTs.compareTo(bTs);
      });
      final extra = files.length - _maxDiskCacheFiles;
      for (var i = 0; i < extra; i++) {
        try {
          await files[i].delete();
        } catch (_) {}
      }
    } catch (_) {}
  }

  Future<Uint8List?> _loadLegacyPrefsImage(String cacheKey) async {
    try {
      final prefs = await _prefs;
      final prefKey = _prefKey(cacheKey);
      final cached = prefs.getString(prefKey);
      if (cached == null || cached.isEmpty) return null;
      final decoded = base64Decode(cached);
      await prefs.remove(prefKey);
      await _writeDiskCache(cacheKey, decoded);
      return decoded;
    } catch (_) {
      return null;
    }
  }

  Future<Uint8List> _fetchWithRetry(Uri uri, {int maxAttempts = 3}) async {
    Object? lastError;
    for (var attempt = 1; attempt <= maxAttempts; attempt++) {
      try {
        final response = await http.get(
          uri,
          headers: const {
            'User-Agent':
                'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
                '(KHTML, like Gecko) Chrome/125.0 Safari/537.36',
            'Accept': 'image/avif,image/webp,image/apng,image/*,*/*;q=0.8',
          },
        );
        if (response.statusCode >= 200 && response.statusCode < 300) {
          return response.bodyBytes;
        }
        if (response.statusCode < 500 && response.statusCode != 429) {
          throw http.ClientException(
            'Unexpected status ${response.statusCode}',
            uri,
          );
        }
        lastError = response.statusCode;
      } catch (e) {
        lastError = e;
      }
      if (attempt < maxAttempts) {
        await Future<void>.delayed(Duration(milliseconds: 350 * attempt));
      }
    }
    if (lastError != null) {
      throw lastError;
    }
    throw StateError('Image fetch failed without an error');
  }

  Uint8List? _tryDecodeInline(String value) {
    final raw = value.trim();
    if (raw.isEmpty) return null;
    if (raw.startsWith('data:image/')) {
      final i = raw.indexOf(',');
      if (i <= 0 || i >= raw.length - 1) return null;
      final payload = raw.substring(i + 1);
      return base64Decode(payload);
    }
    if (raw.startsWith('http://') || raw.startsWith('https://')) return null;
    try {
      return base64Decode(base64.normalize(raw));
    } catch (_) {
      return null;
    }
  }

  Future<void> _load() async {
    if (_loading) return;
    final url = widget.url.trim();
    if (url.isEmpty) return;
    final normalizedRemoteUrl = normalizeImageUrl(url);
    final isRemoteHttp = normalizedRemoteUrl != null;

    if (kIsWeb && isRemoteHttp) {
      if (!mounted) return;
      setState(() {
        _loading = false;
      });
      return;
    }

    final inlineBytes = _tryDecodeInline(url);
    if (inlineBytes != null && inlineBytes.isNotEmpty) {
      setState(() {
        _bytes = inlineBytes;
        _loading = false;
      });
      return;
    }

    final cacheKey = normalizedRemoteUrl ?? url;
    final memoryHit = _memoryCache[cacheKey];
    if (memoryHit != null) {
      setState(() {
        _bytes = memoryHit;
      });
      return;
    }

    setState(() {
      _loading = true;
    });

    try {
      final diskHit = await _readDiskCache(cacheKey);
      if (diskHit != null && diskHit.isNotEmpty) {
        _memoryCache[cacheKey] = diskHit;
        if (!mounted) return;
        setState(() {
          _bytes = diskHit;
          _loading = false;
        });
        return;
      }

      final migrated = await _loadLegacyPrefsImage(cacheKey);
      if (migrated != null && migrated.isNotEmpty) {
        _memoryCache[cacheKey] = migrated;
        if (!mounted) return;
        setState(() {
          _bytes = migrated;
          _loading = false;
        });
        return;
      }

      final bytes = await _fetchWithRetry(
        Uri.parse(normalizedRemoteUrl ?? url),
      );
      _memoryCache[cacheKey] = bytes;
      await _writeDiskCache(cacheKey, bytes);
      unawaited(_cleanupDiskCacheIfNeeded());
      if (!mounted) return;
      setState(() {
        _bytes = bytes;
        _loading = false;
      });
      return;
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _loading = false;
      });
      developer.log(
        'CachedImage fetch failed for $url after retries',
        name: 'CachedImage',
        error: e,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final url = widget.url.trim();
    final normalizedRemoteUrl = normalizeImageUrl(url);
    final remoteUrl = normalizedRemoteUrl;
    final isRemoteHttp = remoteUrl != null;
    if (remoteUrl != null && kIsWeb) {
      return Image.network(
        remoteUrl,
        fit: widget.fit,
        alignment: widget.alignment,
        width: widget.width,
        height: widget.height,
        filterQuality: widget.filterQuality,
        headers: const {
          'User-Agent':
              'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
              '(KHTML, like Gecko) Chrome/125.0 Safari/537.36',
          'Accept': 'image/avif,image/webp,image/apng,image/*,*/*;q=0.8',
        },
        loadingBuilder: (context, child, progress) {
          if (progress == null) return child;
          return widget.placeholder ??
              _CachedImageShimmer(width: widget.width, height: widget.height);
        },
        errorBuilder: (_, _, _) => widget.error ?? _defaultErrorWidget(),
      );
    }
    if (_bytes != null) {
      return Image.memory(
        _bytes!,
        fit: widget.fit,
        alignment: widget.alignment,
        width: widget.width,
        height: widget.height,
        filterQuality: widget.filterQuality,
      );
    }
    if (_error != null) {
      if (isRemoteHttp) {
        return Image.network(
          remoteUrl,
          fit: widget.fit,
          alignment: widget.alignment,
          width: widget.width,
          height: widget.height,
          filterQuality: widget.filterQuality,
          headers: const {
            'User-Agent':
                'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
                '(KHTML, like Gecko) Chrome/125.0 Safari/537.36',
            'Accept': 'image/avif,image/webp,image/apng,image/*,*/*;q=0.8',
          },
          loadingBuilder: (context, child, progress) {
            if (progress == null) return child;
            return widget.placeholder ??
                _CachedImageShimmer(width: widget.width, height: widget.height);
          },
          errorBuilder: (_, _, _) => widget.error ?? _defaultErrorWidget(),
        );
      }
      return widget.error ?? _defaultErrorWidget();
    }
    return widget.placeholder ??
        _CachedImageShimmer(width: widget.width, height: widget.height);
  }

  Widget _defaultErrorWidget() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      width: widget.width,
      height: widget.height,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF20242D) : const Color(0xFFF1F5FB),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.broken_image_outlined,
            color: isDark ? Colors.white70 : const Color(0xFF5E6D82),
          ),
        ],
      ),
    );
  }
}

class _CachedImageShimmer extends StatelessWidget {
  const _CachedImageShimmer({this.width, this.height});

  final double? width;
  final double? height;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Shimmer.fromColors(
      baseColor: isDark ? const Color(0xFF1C1C1C) : const Color(0xFFE7EDF5),
      highlightColor: isDark
          ? const Color(0xFF343434)
          : const Color(0xFFF8FBFF),
      period: const Duration(milliseconds: 1300),
      child: Container(
        width: width ?? double.infinity,
        height: height ?? 120,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(8),
        ),
      ),
    );
  }
}
