import 'dart:io';
import 'app_paths.dart';

class AppLog {
  AppLog._();

  static File? _file;

  static Future<File> getFile() async {
    if (_file != null) return _file!;
    final dir = await AppPaths.documentsDirectory();
    _file = File('${dir.path}/debug_logs.txt');
    return _file!;
  }

  static const int maxBytes = 1024 * 1024;
  static const int maxMessageLength = 500;

  static Future<void> write(String message) async {
    try {
      final f = await getFile();
      if (await f.exists()) await trim(f);
      final time = DateTime.now().toIso8601String();
      await f.writeAsString(
        '[$time] ${shorten(message)}\n',
        mode: FileMode.append,
        flush: true,
      );
    } catch (_) {}
  }

  static String shorten(String message) => message.length <= maxMessageLength
      ? message
      : '${message.substring(0, maxMessageLength)}…';

  static Future<void> trim(File file) async {
    final length = await file.length();
    if (length <= maxBytes) return;
    final tail = await file
        .openRead(length - maxBytes ~/ 2)
        .fold<List<int>>(<int>[], (kept, chunk) => kept..addAll(chunk));
    await file.writeAsBytes(tail, flush: true);
  }

  static Future<String> read() async {
    try {
      final f = await getFile();
      if (await f.exists()) {
        return await f.readAsString();
      }
    } catch (_) {}
    return '';
  }
}
