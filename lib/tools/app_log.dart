import 'dart:io';
import 'app_paths.dart';

class AppLog {
  AppLog._();

  static File? _file;
  static int _approxSize = -1;
  static Future<void>? _queue;

  static Future<File> getFile() async {
    if (_file != null) return _file!;
    final dir = await AppPaths.documentsDirectory();
    _file = File('${dir.path}/debug_logs.txt');
    return _file!;
  }

  static Future<void> write(String message) {
    final previous = _queue ?? Future<void>.value();
    final next = previous.then((_) => _writeOne(message));
    _queue = next;
    return next;
  }

  static Future<void> _writeOne(String message) async {
    try {
      final file = await getFile();
      if (_approxSize < 0) {
        _approxSize = await file.exists() ? await file.length() : 0;
      }
      if (_approxSize > 10 * 1024 * 1024) {
        await file.writeAsString('');
        _approxSize = 0;
      }
      final timestamp = DateTime.now().toIso8601String();
      final line = '[$timestamp] $message\n';
      await file.writeAsString(line, mode: FileMode.append);
      _approxSize += line.length;
    } catch (_) {}
  }
}
