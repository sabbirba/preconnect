import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shimmer/shimmer.dart';

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
    this.maxBytesInPrefs = 2 * 1024 * 1024,
  });

  final String url;
  final BoxFit? fit;
  final AlignmentGeometry alignment;
  final double? width;
  final double? height;
  final FilterQuality filterQuality;
  final Widget? placeholder;
  final Widget? error;
  final int maxBytesInPrefs;

  static void clearMemoryCache() {
    _CachedImageState.clearMemoryCache();
  }

  @override
  State<CachedImage> createState() => _CachedImageState();
}

class _CachedImageState extends State<CachedImage> {
  static final Future<SharedPreferences> _prefs =
      SharedPreferences.getInstance();
  static final Map<String, Uint8List> _memoryCache = {};

  static void clearMemoryCache() {
    _memoryCache.clear();
  }

  Uint8List? _bytes;
  Object? _error;
  bool _loading = false;
  String? _errorLabel;

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
      _errorLabel = null;
      _loading = false;
      _load();
    }
  }

  String _prefKey(String url) {
    final encoded = base64Url.encode(utf8.encode(url));
    return 'img_cache_$encoded';
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
    final isRemoteHttp =
        url.startsWith('http://') || url.startsWith('https://');

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

    final memoryHit = _memoryCache[url];
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
      final prefs = await _prefs;
      final cached = prefs.getString(_prefKey(url));
      if (cached != null && cached.isNotEmpty) {
        final decoded = base64Decode(cached);
        _memoryCache[url] = decoded;
        if (!mounted) return;
        setState(() {
          _bytes = decoded;
          _loading = false;
        });
        return;
      }

      final response = await http.get(
        Uri.parse(url),
        headers: const {
          'User-Agent':
              'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
              '(KHTML, like Gecko) Chrome/125.0 Safari/537.36',
          'Accept': 'image/avif,image/webp,image/apng,image/*,*/*;q=0.8',
        },
      );
      if (response.statusCode >= 200 && response.statusCode < 300) {
        final bytes = response.bodyBytes;
        _memoryCache[url] = bytes;
        if (bytes.length <= widget.maxBytesInPrefs) {
          await prefs.setString(_prefKey(url), base64Encode(bytes));
        }
        if (!mounted) return;
        setState(() {
          _bytes = bytes;
          _loading = false;
        });
        return;
      }

      if (!mounted) return;
      setState(() {
        _error = response.statusCode;
        _errorLabel = 'Image unavailable';
        _loading = false;
      });
      developer.log(
        'CachedImage failed with status ${response.statusCode}',
        name: 'CachedImage',
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _errorLabel = 'Image unavailable';
        _loading = false;
      });
      developer.log('CachedImage fetch failed for $url', name: 'CachedImage', error: e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final url = widget.url.trim();
    final isRemoteHttp =
        url.startsWith('http://') || url.startsWith('https://');
    if (isRemoteHttp && kIsWeb) {
      return Image.network(
        url,
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
        color: isDark
            ? const Color(0xFF20242D)
            : const Color(0xFFF1F5FB),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.broken_image_outlined,
            color: isDark ? Colors.white70 : const Color(0xFF5E6D82),
          ),
          const SizedBox(height: 6),
          Text(
            _errorLabel ?? 'Image unavailable',
            style: TextStyle(
              color: isDark ? Colors.white70 : const Color(0xFF5E6D82),
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
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
