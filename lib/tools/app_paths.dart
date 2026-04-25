import 'dart:io';

class AppPaths {
  AppPaths._();

  static Future<Directory> supportDirectory() {
    return _ensureDirectory(_platformDataRoot('support'));
  }

  static Future<Directory> documentsDirectory() {
    return _ensureDirectory(_platformDataRoot('documents'));
  }

  static Future<Directory> temporaryDirectory() {
    return _ensureDirectory(
      Directory('${Directory.systemTemp.path}/PreConnect'),
    );
  }

  static Future<Directory> _ensureDirectory(Directory directory) async {
    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }
    return directory;
  }

  static Directory _platformDataRoot(String bucket) {
    final home = _homeDirectoryPath();
    if (Platform.isMacOS) {
      final base = Directory('$home/Library/Application Support/PreConnect');
      return Directory('${base.path}/$bucket');
    }
    if (Platform.isWindows) {
      final appData = Platform.environment['APPDATA'];
      final root = (appData == null || appData.isEmpty)
          ? Directory('$home/AppData/Roaming/PreConnect')
          : Directory('$appData/PreConnect');
      return Directory('${root.path}/$bucket');
    }
    if (Platform.isLinux) {
      final xdg = Platform.environment['XDG_DATA_HOME'];
      final root = (xdg == null || xdg.isEmpty)
          ? Directory('$home/.local/share/PreConnect')
          : Directory('$xdg/PreConnect');
      return Directory('${root.path}/$bucket');
    }
    return Directory('$home/PreConnect/$bucket');
  }

  static String _homeDirectoryPath() {
    final candidates = <String?>[
      Platform.environment['HOME'],
      Platform.environment['USERPROFILE'],
      Platform.environment['LOCALAPPDATA'],
    ];
    for (final candidate in candidates) {
      final value = candidate?.trim() ?? '';
      if (value.isNotEmpty) return value;
    }
    return Directory.systemTemp.path;
  }
}
