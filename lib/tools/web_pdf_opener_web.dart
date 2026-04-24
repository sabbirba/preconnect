// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use
import 'dart:async';
import 'dart:html' as html;
import 'dart:typed_data';

Future<void> openPdfInBrowser({
  required Uint8List bytes,
  required String fileName,
}) async {
  final blob = html.Blob(<dynamic>[bytes], 'application/pdf');
  final objectUrl = html.Url.createObjectUrlFromBlob(blob);
  try {
    html.window.open(objectUrl, '_blank');
  } catch (_) {
    html.window.location.assign(objectUrl);
    return;
  }
  Timer(const Duration(seconds: 15), () => html.Url.revokeObjectUrl(objectUrl));
}
