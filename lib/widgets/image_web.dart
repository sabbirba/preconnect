import 'package:flutter/material.dart';
import 'package:web/web.dart' as web;

class WebSafeNetworkImage extends StatelessWidget {
  const WebSafeNetworkImage({
    super.key,
    required this.url,
    this.fit,
    this.alignment = Alignment.center,
    this.width,
    this.height,
    this.filterQuality = FilterQuality.low,
  });

  final String url;
  final BoxFit? fit;
  final AlignmentGeometry alignment;
  final double? width;
  final double? height;
  final FilterQuality filterQuality;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      height: height,
      child: HtmlElementView.fromTagName(
        tagName: 'img',
        onElementCreated: (element) {
          final image = element as web.HTMLImageElement;
          image
            ..src = url
            ..loading = 'lazy'
            ..decoding = 'async'
            ..style.width = '100%'
            ..style.height = '100%'
            ..style.objectFit = _cssObjectFit(fit)
            ..style.objectPosition = _cssObjectPosition(alignment);
        },
      ),
    );
  }

  String _cssObjectFit(BoxFit? value) {
    switch (value) {
      case BoxFit.cover:
        return 'cover';
      case BoxFit.fill:
        return 'fill';
      case BoxFit.fitHeight:
        return 'contain';
      case BoxFit.fitWidth:
        return 'contain';
      case BoxFit.none:
        return 'none';
      case BoxFit.scaleDown:
        return 'scale-down';
      case null:
      case BoxFit.contain:
        return 'contain';
    }
  }

  String _cssObjectPosition(AlignmentGeometry value) {
    final alignment = value.resolve(TextDirection.ltr);
    final x = ((alignment.x + 1) / 2 * 100).clamp(0, 100);
    final y = ((alignment.y + 1) / 2 * 100).clamp(0, 100);
    return '$x% $y%';
  }
}
