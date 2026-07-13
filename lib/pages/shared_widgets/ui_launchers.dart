part of 'package:preconnect/pages/ui_kit.dart';

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
