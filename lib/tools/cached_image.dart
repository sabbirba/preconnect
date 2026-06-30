import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:preconnect/tools/token_storage.dart';
import 'package:preconnect/tools/preconnect_constants.dart';
import 'package:preconnect/tools/url_utils.dart';

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

  static void clearMemoryCache() {}

  @override
  State<CachedImage> createState() => _CachedImageState();
}

class _CachedImageState extends State<CachedImage> {
  Map<String, String>? _headers;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadHeaders();
  }

  @override
  void didUpdateWidget(CachedImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url) {
      _loadHeaders();
    }
  }

  Future<void> _loadHeaders() async {
    final normalized = normalizeImageUrl(widget.url);
    if (normalized == null) {
      if (mounted) {
        setState(() {
          _headers = null;
          _loading = false;
        });
      }
      return;
    }
    final uri = Uri.parse(normalized);
    final headers = <String, String>{
      'Accept': 'image/avif,image/webp,image/apng,image/*,*/*;q=0.8',
      'User-Agent':
          'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
          '(KHTML, like Gecko) Chrome/125.0 Safari/537.36',
    };
    if (uri.host == 'connect.bracu.ac.bd') {
      final token = await TokenStorage.instance.read(
        key: PreConnectStorageKeys.accessToken,
      );
      if (token != null && token.isNotEmpty) {
        headers['Authorization'] = 'Bearer $token';
      }
      final idToken = await TokenStorage.instance.read(
        key: PreConnectStorageKeys.idToken,
      );
      if (idToken != null && idToken.isNotEmpty) {
        headers['X-ID-Token'] = idToken;
      }
    }
    if (mounted) {
      setState(() {
        _headers = headers;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final rawUrl = widget.url.trim();
    if (rawUrl.isEmpty) {
      return widget.error ?? const SizedBox.shrink();
    }

    final dpr = MediaQuery.of(context).devicePixelRatio;
    final cacheWidth = widget.width != null && widget.width! > 0
        ? (widget.width! * dpr).round()
        : null;
    final cacheHeight = widget.height != null && widget.height! > 0
        ? (widget.height! * dpr).round()
        : null;

    if (rawUrl.startsWith('data:image/')) {
      try {
        final commaIdx = rawUrl.indexOf(',');
        if (commaIdx != -1) {
          final data = rawUrl.substring(commaIdx + 1);
          final bytes = base64Decode(data);
          return Image.memory(
            bytes,
            width: widget.width,
            height: widget.height,
            fit: widget.fit,
            alignment: widget.alignment,
            filterQuality: widget.filterQuality,
            cacheWidth: cacheWidth,
            cacheHeight: cacheHeight,
          );
        }
      } catch (_) {}
      return widget.error ?? const SizedBox.shrink();
    }

    final normalized = normalizeImageUrl(widget.url);
    if (normalized == null) {
      return widget.error ?? const SizedBox.shrink();
    }

    if (_loading) {
      return widget.placeholder ?? const SizedBox.shrink();
    }

    return CachedNetworkImage(
      imageUrl: normalized,
      httpHeaders: _headers,
      width: widget.width,
      height: widget.height,
      fit: widget.fit,
      alignment: widget.alignment as Alignment,
      filterQuality: widget.filterQuality,
      memCacheWidth: cacheWidth,
      memCacheHeight: cacheHeight,
      placeholder: (context, url) =>
          widget.placeholder ?? const SizedBox.shrink(),
      errorWidget: (context, url, error) =>
          widget.error ?? const SizedBox.shrink(),
    );
  }
}
