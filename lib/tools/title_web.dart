import 'package:preconnect/tools/platform_stub.dart';
import 'package:web/web.dart' as web;

void setWebPageTitle(String title) {
  web.document.title = normalizeWebPageTitle(title);
}
