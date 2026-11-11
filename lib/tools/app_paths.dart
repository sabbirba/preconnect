import 'dart:io';
import 'paths_stub.dart'
    if (dart.library.io) 'package:path_provider/path_provider.dart';

class AppPaths {
  AppPaths._();

  static Future<Directory> supportDirectory() {
    return _persistentDirectory('support');
  }

  static Future<Directory> documentsDirectory() {
    return _persistentDirectory('documents');
  }

  static Future<Directory> temporaryDirectory() {
    return _ensureDirectory(
      Directory('${Directory.systemTemp.path}/PreConnect'),
    );
  }

  static Future<Directory> _persistentDirectory(String bucket) async {
    if (Platform.isAndroid || Platform.isIOS) {
      final root = await getApplicationSupportDirectory();
      return _ensureDirectory(Directory('${root.path}/PreConnect/$bucket'));
    }
    return _ensureDirectory(_desktopDataRoot(bucket));
  }

  static Future<Directory> _ensureDirectory(Directory directory) async {
    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }
    return directory;
  }

  static Directory _desktopDataRoot(String bucket) {
    final home = Platform.environment['HOME'] ?? Directory.systemTemp.path;
    if (Platform.isMacOS) {
      return Directory('$home/Library/Application Support/PreConnect/$bucket');
    }
    return Directory('$home/PreConnect/$bucket');
  }
}
