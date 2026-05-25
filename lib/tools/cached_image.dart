import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:http/http.dart';
import 'package:http/http.dart' as http;
import 'package:preconnect/api/api_client.dart';
import 'package:preconnect/tools/app_storage.dart';
import 'package:preconnect/tools/app_paths.dart';
import 'package:preconnect/tools/http/http_service.dart';
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
  static final Map<String, Uint8List> _memoryCache = <String, Uint8List>{};
  static final Map<String, Future<Uint8List>> _inFlightFetches =
      <String, Future<Uint8List>>{};
  static const String _manifestKey = 'cached_image_manifest_v1';
  static const String _webCachePrefix = 'cached_image_web_v1';
  static Map<String, String>? _manifest;
  static bool _cleanupScheduled = false;

  Uint8List? _bytes;
  Object? _error;
  bool _loading = false;

  static void clearMemoryCache() {
    _memoryCache.clear();
  }

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

  Future<Uint8List> _fetchWithRetry(Uri uri, {int maxAttempts = 3}) async {
    Object? lastError;
    for (var attempt = 1; attempt <= maxAttempts; attempt++) {
      try {
        final headers = <String, String>{
          'Accept': 'image/avif,image/webp,image/apng,image/*,*/*;q=0.8',
        };
        headers.addAll(compressionHeadersForUri(uri));
        final response =
            uri.toString().contains(
              "api.github.com",
            ) // avoid rhttp if fetching from GitHub
            ? await HttpService.client.get(uri, headers: headers)
            : await http.get(uri, headers: headers);

        if (response.statusCode >= 200 && response.statusCode < 300) {
          return response.bodyBytes;
        }
        if (response.statusCode < 500 && response.statusCode != 429) {
          throw ClientException(
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

  String _cacheKey(String value) {
    return sha256.convert(utf8.encode(value)).toString();
  }

  Future<Directory> _cacheDirectory() async {
    if (kIsWeb) {
      throw UnsupportedError('Web cache does not use the file system.');
    }
    final base = await AppPaths.supportDirectory();
    final dir = Directory('${base.path}/cached_images');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  Future<File> _cacheFileFor(String value) async {
    if (kIsWeb) {
      throw UnsupportedError('Web cache does not use the file system.');
    }
    final dir = await _cacheDirectory();
    return File('${dir.path}/${_cacheKey(value)}.img');
  }

  String _webCacheKey(String value) => '$_webCachePrefix|${_cacheKey(value)}';

  Future<Map<String, String>> _readManifest() async {
    final current = _manifest;
    if (current != null) return current;
    try {
      final raw = await AppStorage.instance.getString(_manifestKey);
      if (raw == null || raw.isEmpty) {
        _manifest = <String, String>{};
        return _manifest!;
      }
      final decoded = jsonDecode(raw);
      if (decoded is! Map) {
        _manifest = <String, String>{};
        return _manifest!;
      }
      _manifest = decoded.map((key, value) => MapEntry('$key', '$value'));
      _scheduleCleanup();
      return _manifest!;
    } catch (_) {
      _manifest = <String, String>{};
      return _manifest!;
    }
  }

  Future<void> _writeManifest(Map<String, String> manifest) async {
    _manifest = manifest;
    try {
      await AppStorage.instance.setString(_manifestKey, jsonEncode(manifest));
    } catch (_) {}
  }

  void _scheduleCleanup() {
    if (_cleanupScheduled) return;
    _cleanupScheduled = true;
    unawaited(_cleanupManifest());
  }

  Future<void> _cleanupManifest() async {
    try {
      if (kIsWeb) return;
      final manifest = await _readManifest();
      if (manifest.isEmpty) return;
      var changed = false;
      for (final entry in manifest.entries.toList(growable: false)) {
        final filePath = entry.value;
        if (filePath.isEmpty) {
          manifest.remove(entry.key);
          changed = true;
          continue;
        }
        final file = File(filePath);
        if (!await file.exists()) {
          manifest.remove(entry.key);
          changed = true;
        }
      }
      if (changed) {
        await _writeManifest(manifest);
      }
    } catch (_) {
    } finally {
      _cleanupScheduled = false;
    }
  }

  Future<Uint8List?> _readCachedBytes(String value) async {
    final normalized = value.trim();
    if (normalized.isEmpty) return null;
    final inMemory = _memoryCache[normalized];
    if (inMemory != null && inMemory.isNotEmpty) {
      return inMemory;
    }
    if (kIsWeb) {
      try {
        final manifest = await _readManifest();
        final mappedKey = manifest[normalized];
        if (mappedKey != null && mappedKey.isNotEmpty) {
          final raw = await AppStorage.instance.getString(mappedKey);
          if (raw != null && raw.isNotEmpty) {
            final bytes = base64Decode(raw);
            if (bytes.isNotEmpty) {
              _memoryCache[normalized] = bytes;
              return bytes;
            }
          }
        }
      } catch (_) {}
      return null;
    }
    try {
      final manifest = await _readManifest();
      final mappedPath = manifest[normalized];
      if (mappedPath != null && mappedPath.isNotEmpty) {
        final mappedFile = File(mappedPath);
        if (await mappedFile.exists()) {
          final bytes = await mappedFile.readAsBytes();
          if (bytes.isNotEmpty) {
            _memoryCache[normalized] = bytes;
            return bytes;
          }
        }
      }
      final file = await _cacheFileFor(normalized);
      if (!await file.exists()) return null;
      final bytes = await file.readAsBytes();
      if (bytes.isEmpty) return null;
      _memoryCache[normalized] = bytes;
      return bytes;
    } catch (_) {
      return null;
    }
  }

  Future<void> _writeCachedBytes(String value, Uint8List bytes) async {
    final normalized = value.trim();
    if (normalized.isEmpty || bytes.isEmpty) return;
    _memoryCache[normalized] = bytes;
    if (kIsWeb) {
      try {
        final cacheKey = _webCacheKey(normalized);
        await AppStorage.instance.setString(cacheKey, base64Encode(bytes));
        final manifest = await _readManifest();
        manifest[normalized] = cacheKey;
        await _writeManifest(manifest);
      } catch (_) {}
      return;
    }
    try {
      final file = await _cacheFileFor(normalized);
      await file.writeAsBytes(bytes, flush: true);
      final manifest = await _readManifest();
      manifest[normalized] = file.path;
      await _writeManifest(manifest);
    } catch (_) {}
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

    final inlineBytes = _tryDecodeInline(url);
    if (inlineBytes != null && inlineBytes.isNotEmpty) {
      setState(() {
        _bytes = inlineBytes;
        _loading = false;
      });
      return;
    }

    final cachedBytes = await _readCachedBytes(normalizedRemoteUrl ?? url);
    if (cachedBytes != null && cachedBytes.isNotEmpty) {
      if (!mounted) return;
      setState(() {
        _bytes = cachedBytes;
        _loading = false;
      });
      return;
    }

    setState(() {
      _loading = true;
    });

    try {
      final cacheKey = normalizedRemoteUrl ?? url;
      final bytes = await _inFlightFetches.putIfAbsent(cacheKey, () async {
        final fetched = await _fetchWithRetry(Uri.parse(cacheKey));
        await _writeCachedBytes(cacheKey, fetched);
        return fetched;
      });
      if (!mounted) return;
      setState(() {
        _bytes = bytes;
        _loading = false;
      });
      _inFlightFetches.remove(cacheKey);
      return;
    } catch (e) {
      _inFlightFetches.remove(normalizedRemoteUrl ?? url);
      if (!mounted) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final url = widget.url.trim();
    final normalizedRemoteUrl = normalizeImageUrl(url);
    final remoteUrl = normalizedRemoteUrl;
    final isRemoteHttp = remoteUrl != null;
    if (remoteUrl != null) {
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
        return widget.error ?? _defaultErrorWidget();
      }
      return widget.placeholder ??
          _CachedImageShimmer(width: widget.width, height: widget.height);
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
        return widget.error ?? _defaultErrorWidget();
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
    return Container(
      width: width ?? double.infinity,
      height: height ?? 120,
      decoration: BoxDecoration(
        color: const Color(0xFFF1F5FB),
        borderRadius: BorderRadius.circular(8),
      ),
    );
  }
}
