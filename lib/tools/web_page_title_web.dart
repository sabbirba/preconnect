// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use
import 'dart:html' as html;
import 'package:preconnect/tools/web_page_title_stub.dart';

void setWebPageTitle(String title) {
  html.document.title = normalizeWebPageTitle(title);
}
