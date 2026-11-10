import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:preconnect/tools/image_cache.dart';
import 'package:preconnect/tools/token_storage.dart';
import 'package:preconnect/tools/url_utils.dart';

class CachedImage extends StatefulWidget {
  const CachedImage({
    super.key,
    required this.url,
    this.cacheKey,
    this.fit,
    this.alignment = Alignment.center,
    this.width,
    this.height,
    this.filterQuality = FilterQuality.low,
    this.placeholder,
    this.error,
  });

  final String url;
  final String? cacheKey;
  final BoxFit? fit;
  final AlignmentGeometry alignment;
  final double? width;
  final double? height;
  final FilterQuality filterQuality;
  final Widget? placeholder;
  final Widget? error;

  static void precache(BuildContext context, String url) {
    final normalized = normalizeImageUrl(url);
    if (normalized == null || normalized.isEmpty) return;
    try {
      precacheImage(
        CachedNetworkImageProvider(
          normalized,
          cacheManager: AppImageCache.instance,
          headers: imageRequestHeaders,
        ),
        context,
      );
    } catch (_) {}
  }

  static void clearMemoryCache() {
    _CachedImageState._fileMemoryCache.clear();
    ProfileImageCache.instance.invalidate();
  }

  @override
  State<CachedImage> createState() => _CachedImageState();
}

class _CachedImageState extends State<CachedImage> {
  static final Map<String, File> _fileMemoryCache = <String, File>{};
  Map<String, String>? _headers;
  File? _localFile;
  bool _loading = true;
  int _loadVersion = 0;

  @override
  void initState() {
    super.initState();
    _loadHeaders();
  }

  @override
  void didUpdateWidget(CachedImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url || oldWidget.cacheKey != widget.cacheKey) {
      _loadHeaders();
    }
  }

  String? get _storeKey {
    final key = widget.cacheKey;
    if (key != null && key.isNotEmpty) return normalizeImageUrl(key);
    return normalizeImageUrl(widget.url);
  }

  Future<void> _loadHeaders() async {
    final version = ++_loadVersion;
    final normalized = normalizeImageUrl(widget.url);
    if (normalized == null) {
      if (mounted) {
        setState(() {
          _headers = null;
          _localFile = null;
          _loading = false;
        });
      }
      return;
    }
    final key = _storeKey ?? normalized;
    setState(() {
      _headers = null;
      _localFile =
          _fileMemoryCache[key] ??
          ProfileImageCache.instance.getFromMemory(normalized);
      _loading = _localFile == null;
    });
    final uri = Uri.parse(normalized);
    try {
      final localFile = uri.host == 'connect.bracu.ac.bd'
          ? await ProfileImageCache.instance.getProfileImage(normalized)
          : (await AppImageCache.instance.getFileFromCache(key))?.file;
      if (localFile != null &&
          await localFile.exists() &&
          await looksLikeImageFile(localFile)) {
        _fileMemoryCache[key] = localFile;
        if (mounted && version == _loadVersion) {
          setState(() {
            _localFile = localFile;
            _loading = false;
          });
          return;
        }
      }
    } catch (_) {}
    final headers = await imageHeadersFor(uri);
    if (mounted && version == _loadVersion) {
      setState(() {
        _headers = headers;
        _localFile = null;
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

    final dpr = MediaQuery.devicePixelRatioOf(context);
    final maxDim = (widget.width != null && widget.height != null)
        ? (widget.width! > widget.height! ? widget.width! : widget.height!)
        : (widget.width ?? widget.height);
    final cacheWidth = maxDim != null && maxDim > 0
        ? (maxDim * dpr).round()
        : (400 * dpr).round();

    if (_localFile != null) {
      return Image.file(
        _localFile!,
        width: widget.width,
        height: widget.height,
        fit: widget.fit,
        alignment: widget.alignment,
        filterQuality: widget.filterQuality,
        cacheWidth: cacheWidth,
        errorBuilder: (context, error, stackTrace) =>
            widget.error ?? const SizedBox.shrink(),
      );
    }

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
      cacheKey: _storeKey,
      cacheManager: AppImageCache.instance,
      httpHeaders: _headers,
      width: widget.width,
      height: widget.height,
      fit: widget.fit,
      alignment: widget.alignment.resolve(Directionality.of(context)),
      filterQuality: widget.filterQuality,
      memCacheWidth: cacheWidth,
      placeholder: (context, url) =>
          widget.placeholder ?? const SizedBox.shrink(),
      errorWidget: (context, url, error) =>
          widget.error ?? const SizedBox.shrink(),
    );
  }
}
