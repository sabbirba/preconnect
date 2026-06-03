import 'package:web/web.dart' as web;

String getWebAppOrigin() {
  final origin = web.window.location.origin.trim();
  if (origin.isNotEmpty && origin != 'null') {
    return origin;
  }
  return 'https://web.preconnect.app';
}

