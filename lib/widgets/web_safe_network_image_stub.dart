import 'package:flutter/material.dart';

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
    return Image.network(
      url,
      fit: fit,
      alignment: alignment,
      width: width,
      height: height,
      filterQuality: filterQuality,
    );
  }
}
