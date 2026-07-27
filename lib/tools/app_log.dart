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

  static Future<void> write(String message) async {}
}
