import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:preconnect/tools/image_url_utils.dart';
import 'package:preconnect/tools/persistent_image_cache.dart';

class CachedImage extends StatelessWidget {
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
    PaintingBinding.instance.imageCache.clear();
    PaintingBinding.instance.imageCache.clearLiveImages();
  }

  @override
  Widget build(BuildContext context) {
    final value = url.trim();
    final remoteUrl = normalizeImageUrl(value);
    if (remoteUrl != null) {
      return _buildRemoteImage(context, remoteUrl);
    }

    final inlineBytes = _tryDecodeInline(value);
    if (inlineBytes != null && inlineBytes.isNotEmpty) {
      return Image.memory(
        inlineBytes,
        fit: fit,
        alignment: alignment,
        width: width,
        height: height,
        filterQuality: filterQuality,
      );
    }

    if (value.isEmpty) {
      return _placeholder();
    }
    return _errorWidget(context);
  }

  Widget _buildRemoteImage(BuildContext context, String remoteUrl) {
    final cache = PersistentImageCache.instance;
    return FutureBuilder<Object?>(
      future: cache.fetchFileForUrl(remoteUrl),
      builder: (context, snapshot) {
        final file = snapshot.data;
        if (file is File && file.existsSync()) {
          return Image.file(
            file,
            fit: fit,
            alignment: alignment,
            width: width,
            height: height,
            filterQuality: filterQuality,
            errorBuilder: (context, _, _) => _errorWidget(context),
          );
        }
        if (snapshot.connectionState == ConnectionState.waiting) {
          return _placeholder();
        }
        return Image.network(
          remoteUrl,
          fit: fit,
          alignment: alignment,
          width: width,
          height: height,
          filterQuality: filterQuality,
          frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
            if (wasSynchronouslyLoaded || frame != null) return child;
            return _placeholder();
          },
          errorBuilder: (context, _, _) => _errorWidget(context),
        );
      },
    );
  }

  Uint8List? _tryDecodeInline(String value) {
    if (value.isEmpty) return null;
    if (value.startsWith('data:image/')) {
      final separator = value.indexOf(',');
      if (separator <= 0 || separator >= value.length - 1) return null;
      return base64Decode(value.substring(separator + 1));
    }
    if (value.startsWith('http://') || value.startsWith('https://')) {
      return null;
    }
    try {
      return base64Decode(base64.normalize(value));
    } catch (_) {
      return null;
    }
  }

  Widget _placeholder() {
    if (placeholder != null) return placeholder!;
    return Container(
      width: width ?? double.infinity,
      height: height ?? 120,
      decoration: BoxDecoration(
        color: const Color(0xFFF1F5FB),
        borderRadius: BorderRadius.circular(8),
      ),
    );
  }

  Widget _errorWidget(BuildContext context) {
    if (error != null) return error!;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      width: width,
      height: height,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF20242D) : const Color(0xFFF1F5FB),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Icon(
        Icons.broken_image_outlined,
        color: isDark ? Colors.white70 : const Color(0xFF5E6D82),
      ),
    );
  }
}
