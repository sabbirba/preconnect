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

  static Future<void> write(String message) async {
    try {
      final f = await getFile();
      final time = DateTime.now().toIso8601String();
      await f.writeAsString(
        '[$time] $message\n',
        mode: FileMode.append,
        flush: true,
      );
    } catch (_) {}
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
