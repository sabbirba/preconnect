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
    if (await file.exists()) {
      final length = await file.length();
      if (length > 4) {
        final header = await file.openRead(0, 1024).first;
        if (_isPdfHeader(header)) {
          final opened = await _openPdfNativelyOrFallback(file.path);
          if (opened) return true;
        } else {
          await file.delete().catchError((_) => file);
        }
      } else {
        await file.delete().catchError((_) => file);
      }
    }

    final parsedUri = Uri.tryParse(url);
    if (parsedUri != null) {
      http.Response? response;
      try {
        response = await http
            .get(
              parsedUri,
              headers: const <String, String>{
                'Accept': 'application/pdf, text/plain, */*',
              },
            )
            .timeout(const Duration(seconds: 15));
      } catch (_) {}

      if (response == null || response.statusCode != 200) {
        final client = ApiClient();
        try {
          response = await client.authenticatedGet(
            url,
            additionalHeaders: const <String, String>{
              'Accept': 'application/pdf, text/plain, */*',
            },
          );
        } catch (_) {
          try {
            response = await client.publicGet(
              url,
              headers: const <String, String>{
                'Accept': 'application/pdf, text/plain, */*',
              },
            );
          } catch (_) {}
        }
      }

      if (response != null &&
          response.statusCode == 200 &&
          response.bodyBytes.isNotEmpty &&
          _isPdfHeader(response.bodyBytes)) {
        final headerName = _extractFilenameFromHeaders(response.headers);
        final finalFileName = headerName != null && headerName.isNotEmpty
            ? _sanitizeFileName(headerName)
            : originalFileName;
        final targetFile = File('${dir.path}/$finalFileName');
        await targetFile.parent.create(recursive: true);
        await targetFile.writeAsBytes(response.bodyBytes, flush: true);
        final opened = await _openPdfNativelyOrFallback(targetFile.path);
        if (opened) return true;
      }
    }
  } catch (_) {}

  if (!context.mounted) return false;
  return openExternalUrl(
    context,
    url,
    failureMessage: failureMessage,
    mobilePreferredMode: LaunchMode.inAppBrowserView,
  );
}

bool _isPdfHeader(List<int> bytes) {
  if (bytes.length < 4) return false;
  final limit = bytes.length < 1024 ? bytes.length - 3 : 1021;
  for (var i = 0; i < limit; i++) {
    if (bytes[i] == 0x25 &&
        bytes[i + 1] == 0x50 &&
        bytes[i + 2] == 0x44 &&
        bytes[i + 3] == 0x46) {
      return true;
    }
  }
  return false;
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
  var launched = false;
  try {
    launched = await launchUrl(uri, mode: mode);
  } catch (_) {}
  if (!launched && isMobilePlatform) {
    try {
      launched = await launchUrl(uri, mode: mobileFallbackMode);
    } catch (_) {}
  }
  if (!launched &&
      isMobilePlatform &&
      mobileFallbackMode != LaunchMode.platformDefault) {
    try {
      launched = await launchUrl(uri, mode: LaunchMode.platformDefault);
    } catch (_) {}
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
  String? subject,
}) async {
  final cleaned = email.trim();
  if (cleaned.isEmpty) {
    if (context.mounted) showAppSnackBar(context, failureMessage);
    return false;
  }
  final mailtoUri = Uri(
    scheme: 'mailto',
    path: cleaned,
    query: subject == null ? null : 'subject=${Uri.encodeComponent(subject)}',
  );
  var openedMail = false;
  try {
    openedMail = await launchUrl(mailtoUri, mode: LaunchMode.platformDefault);
  } catch (_) {
    openedMail = false;
  }
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
