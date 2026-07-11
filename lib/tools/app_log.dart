import 'dart:io';
import 'app_paths.dart';

class AppLog {
  AppLog._();

  static File? _file;

  static Future<File> getFile() async {
    if (_file != null) return _file!;
    final dir = await AppPaths.documentsDirectory();
    _file = File('${dir.path}/preconnect_debug_logs.txt');
    return _file!;
  }

  static Future<void> write(String message) async {
    try {
      final file = await getFile();
      if (await file.exists()) {
        final size = await file.length();
        if (size > 10 * 1024 * 1024) {
          await file.writeAsString('');
        }
      }
      final timestamp = DateTime.now().toIso8601String();
      await file.writeAsString(
        '[$timestamp] $message\n',
        mode: FileMode.append,
      );
    } catch (_) {}
  }
}
