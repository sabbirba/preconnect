part of 'package:preconnect/pages/ui_kit.dart';

Future<bool> openPdfUrl(
  BuildContext context,
  String rawUrl, {
  String failureMessage = 'Unable to open PDF link.',
}) async {
  final url = rawUrl.trim();
  if (url.isEmpty) {
    if (context.mounted) showAppSnackBar(context, failureMessage);
    return false;
  }
  if (kIsWeb) {
    return openExternalUrl(context, url, failureMessage: failureMessage);
  }
  try {
    final originalFileName = _resolveOriginalFileName(url);
    final dir = await AppPaths.temporaryDirectory();
    final file = File('${dir.path}/$originalFileName');
    if (await file.exists() && (await file.length()) > 0) {
      final opened = await _openPdfNativelyOrFallback(file.path);
      if (opened) return true;
    }
    final client = ApiClient();
    final response = await client.authenticatedGet(
      url,
      additionalHeaders: const <String, String>{
        'Accept': 'application/pdf, text/plain, */*',
      },
    );
    if (response.statusCode == 200 && response.bodyBytes.isNotEmpty) {
      final headerName = _extractFilenameFromHeaders(response.headers);
      final finalFileName = headerName != null && headerName.isNotEmpty
          ? _sanitizeFileName(headerName)
          : originalFileName;
      final targetFile = File('${dir.path}/$finalFileName');
      await targetFile.parent.create(recursive: true);
      await targetFile.writeAsBytes(response.bodyBytes, flush: true);
      final opened = await _openPdfNativelyOrFallback(targetFile.path);
      return opened;
    }
  } catch (_) {}
  if (!context.mounted) return false;
  return openExternalUrl(context, url, failureMessage: failureMessage);
}

String _resolveOriginalFileName(String url) {
  try {
    final uri = Uri.parse(url);
    final segment = uri.pathSegments.lastWhere(
      (s) => s.trim().isNotEmpty,
      orElse: () => '',
    );
    if (segment.isNotEmpty) {
      final decoded = Uri.decodeComponent(segment);
      return _sanitizeFileName(decoded);
    }
  } catch (_) {}
  return 'document_${url.hashCode.abs()}.pdf';
}

String? _extractFilenameFromHeaders(Map<String, String> headers) {
  final disposition =
      headers['content-disposition'] ?? headers['Content-Disposition'];
  if (disposition == null || disposition.isEmpty) return null;
  final match = RegExp(
    'filename\\*?=(?:UTF-8\'\')?["\']?([^"\';]+)["\']?',
    caseSensitive: false,
  ).firstMatch(disposition);
  if (match != null && match.group(1) != null) {
    return Uri.decodeComponent(match.group(1)!);
  }
  return null;
}

String _sanitizeFileName(String raw) {
  var name = raw.replaceAll(RegExp(r'[\\/:*?"<>|]+'), '_').trim();
  if (!name.toLowerCase().endsWith('.pdf')) {
    name = '$name.pdf';
  }
  return name;
}

Future<bool> openExternalUrl(
  BuildContext context,
  String rawUrl, {
  String failureMessage = 'Unable to open link.',
  LaunchMode mobilePreferredMode = LaunchMode.inAppBrowserView,
  LaunchMode mobileFallbackMode = LaunchMode.externalApplication,
}) async {
  var url = rawUrl.trim();
  url = url.replaceAll(RegExp(r'\s+'), '');
  if (url.startsWith('www.')) {
    url = 'https://$url';
  }
  if (url.isEmpty) {
    if (context.mounted) showAppSnackBar(context, failureMessage);
    return false;
  }
  final uri = Uri.tryParse(url);
  if (uri == null || !uri.hasScheme || !uri.hasAuthority) {
    if (context.mounted) showAppSnackBar(context, failureMessage);
    return false;
  }
  final platform = Theme.of(context).platform;
  final isMobilePlatform =
      !kIsWeb &&
      (platform == TargetPlatform.android || platform == TargetPlatform.iOS);
  final mode = isMobilePlatform
      ? mobilePreferredMode
      : LaunchMode.platformDefault;
  var launched = await launchUrl(uri, mode: mode);
  if (!launched && isMobilePlatform) {
    launched = await launchUrl(uri, mode: mobileFallbackMode);
  }
  if (!launched && context.mounted) {
    showAppSnackBar(context, failureMessage);
  }
  return launched;
}

Future<bool> openMailComposer(
  BuildContext context,
  String email, {
  String failureMessage = 'Unable to open email compose',
}) async {
  final cleaned = email.trim();
  if (cleaned.isEmpty) {
    if (context.mounted) showAppSnackBar(context, failureMessage);
    return false;
  }
  final mailtoUri = Uri(scheme: 'mailto', path: cleaned);
  final openedMail = await launchUrl(
    mailtoUri,
    mode: LaunchMode.platformDefault,
  );
  if (!openedMail && context.mounted) {
    showAppSnackBar(context, failureMessage);
  }
  return openedMail;
}

Future<bool> openPhoneDialer(
  BuildContext context,
  String phone, {
  String failureMessage = 'Unable to open phone dialer',
}) async {
  final cleaned = phone.trim();
  if (cleaned.isEmpty) {
    if (context.mounted) showAppSnackBar(context, failureMessage);
    return false;
  }
  final normalized = cleaned.replaceAll(RegExp(r'[^\d+]'), '');
  if (normalized.isEmpty) {
    if (context.mounted) showAppSnackBar(context, failureMessage);
    return false;
  }
  final telUri = Uri(scheme: 'tel', path: normalized);
  final opened = await launchUrl(telUri, mode: LaunchMode.platformDefault);
  if (!opened && context.mounted) {
    showAppSnackBar(context, failureMessage);
  }
  return opened;
}

Widget buildCenteredOutlinedActionButton({
  required String label,
  required VoidCallback onPressed,
  EdgeInsetsGeometry padding = const EdgeInsets.only(top: 2, bottom: 8),
}) {
  return Padding(
    padding: padding,
    child: Center(
      child: BracuActionButton(onPressed: onPressed, label: label),
    ),
  );
}

Widget buildLoadMoreButton({required VoidCallback onPressed}) {
  return buildCenteredOutlinedActionButton(
    label: 'Load More',
    onPressed: onPressed,
  );
}

Widget buildScrollToTopButton({required ScrollController controller}) {
  return Padding(
    padding: const EdgeInsets.only(top: 16, bottom: 8),
    child: Center(
      child: IconButton(
        icon: const Icon(
          Icons.arrow_upward_rounded,
          color: BracuPalette.primary,
        ),
        onPressed: () {
          controller.animateTo(
            0,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
          );
        },
      ),
    ),
  );
}
