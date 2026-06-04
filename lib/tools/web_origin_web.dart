import 'package:web/web.dart' as web;

String getWebAppOrigin() {
  return web.window.location.origin.trim();
}
