import 'dart:typed_data';

import 'package:flutter/material.dart';

const String defaultWebPageTitle =
    'PreConnect Web | Fast, Calm Academic Companion App for BRAC University';

String normalizeWebPageTitle(String title) {
  final value = title.trim();
  if (value.isEmpty) return defaultWebPageTitle;
  if (value.startsWith('PreConnect Web |')) return value;
  return 'PreConnect Web | $value';
}

void setWebPageTitle(String title) {}

class WebExtensionLoginPage extends StatelessWidget {
  const WebExtensionLoginPage({super.key});

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

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
  Widget build(BuildContext context) => const SizedBox.shrink();
}

class WebExtensionLoginFlow {
  const WebExtensionLoginFlow();

  Stream<WebExtensionLoginState> get events async* {}

  Future<void> start() async {}

  Future<void> dispose() async {}
}

class WebExtensionLoginState {
  const WebExtensionLoginState.started()
    : type = WebExtensionLoginStateKind.started,
      message = null;
  const WebExtensionLoginState.complete()
    : type = WebExtensionLoginStateKind.complete,
      message = null;
  const WebExtensionLoginState.failed(this.message)
    : type = WebExtensionLoginStateKind.failed;

  final WebExtensionLoginStateKind type;
  final String? message;

  bool get isStarted => type == WebExtensionLoginStateKind.started;
  bool get isComplete => type == WebExtensionLoginStateKind.complete;
  bool get isFailed => type == WebExtensionLoginStateKind.failed;
}

enum WebExtensionLoginStateKind { started, complete, failed }

class WebExtensionSessionFlow {
  const WebExtensionSessionFlow();

  Stream<WebExtensionSessionEvent> get events => const Stream.empty();

  Future<void> dispose() async {}
}

class WebExtensionSessionEvent {
  const WebExtensionSessionEvent.logoutComplete()
    : type = WebExtensionSessionEventKind.logoutComplete;

  final WebExtensionSessionEventKind type;
}

enum WebExtensionSessionEventKind { logoutComplete }

Future<bool> ensureFreshWebExtensionSession({
  bool forceRefresh = false,
}) async {
  final _ = forceRefresh;
  return false;
}

class WebLogoutFlow {
  static Future<void> openConnectLogoutPage() async {}
}

Future<String?> webExtensionStorageGet(String key) async => null;

Future<void> webExtensionStorageSet(String key, String? value) async {}

Future<void> webExtensionStorageRemoveKeys(Iterable<String> keys) async {}

Future<String?> pickQrFromSystemImage() async {
  throw UnsupportedError(
    'QR import from gallery is not available in the Chrome extension yet.',
  );
}

Future<void> openPdfInBrowser({
  required Uint8List bytes,
  required String fileName,
}) async {}
