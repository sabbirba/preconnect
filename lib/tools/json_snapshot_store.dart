import 'dart:convert';

import 'package:preconnect/tools/app_storage.dart';

class JsonSnapshotStore {
  JsonSnapshotStore._();

  static Future<T?> read<T>({
    required String key,
    required T? Function(Map<String, dynamic> value) decode,
  }) async {
    try {
      final raw = await AppStorage.instance.getString(key);
      if (raw == null || raw.trim().isEmpty) return null;
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return null;
      return decode(decoded);
    } catch (_) {
      return null;
    }
  }

  static Future<void> write({
    required String key,
    required Map<String, dynamic> value,
  }) async {
    try {
      await AppStorage.instance.setString(key, jsonEncode(value));
    } catch (_) {}
  }
}
