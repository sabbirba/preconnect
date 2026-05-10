import 'package:flutter/foundation.dart' show TargetPlatform, defaultTargetPlatform, kIsWeb;
import 'package:url_launcher/url_launcher.dart';

Future<bool> openExternalUri(
  String rawUrl, {
  LaunchMode mobilePreferredMode = LaunchMode.inAppBrowserView,
  LaunchMode mobileFallbackMode = LaunchMode.externalApplication,
}) async {
  var url = rawUrl.trim().replaceAll(RegExp(r'\s+'), '');
  if (url.startsWith('www.')) {
    url = 'https://$url';
  }
  if (url.isEmpty) return false;

  final uri = Uri.tryParse(url);
  if (uri == null || !uri.hasScheme || !uri.hasAuthority) {
    return false;
  }

  final isMobilePlatform = !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);
  final mode = isMobilePlatform ? mobilePreferredMode : LaunchMode.platformDefault;
  var launched = await launchUrl(uri, mode: mode);
  if (!launched && isMobilePlatform) {
    launched = await launchUrl(uri, mode: mobileFallbackMode);
  }
  return launched;
}

Future<bool> openUriWithFallback(
  Uri uri, {
  LaunchMode mobilePreferredMode = LaunchMode.inAppBrowserView,
  LaunchMode mobileFallbackMode = LaunchMode.externalApplication,
}) async {
  final isMobilePlatform = !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);
  final mode = isMobilePlatform ? mobilePreferredMode : LaunchMode.platformDefault;
  var launched = await launchUrl(uri, mode: mode);
  if (!launched && isMobilePlatform) {
    launched = await launchUrl(uri, mode: mobileFallbackMode);
  }
  return launched;
}
