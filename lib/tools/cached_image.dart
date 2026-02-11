import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

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

  @override
  State<CachedImage> createState() => _CachedImageState();
}

class _CachedImageState extends State<CachedImage> {
  static final Future<SharedPreferences> _prefs =
      SharedPreferences.getInstance();
  static final Map<String, Uint8List> _memoryCache = {};

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

      final response = await http.get(Uri.parse(url));
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
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
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
      return widget.error ?? const SizedBox.shrink();
    }
    return widget.placeholder ?? const SizedBox.shrink();
  }
}
