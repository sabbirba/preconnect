import 'package:flutter/material.dart';
import 'package:preconnect/tools/cached_image.dart';

const String bracuLogoUrl =
    'https://www.bracu.ac.bd/sites/default/files/resources/media/bracu_logo_12-0-2022.png';

class BracuLogo extends StatelessWidget {
  const BracuLogo({super.key, required this.width, required this.height});

  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    return CachedImage(
      url: bracuLogoUrl,
      width: width,
      height: height,
      fit: BoxFit.contain,
      error: const SizedBox.shrink(),
      placeholder: const SizedBox.shrink(),
    );
  }
}
