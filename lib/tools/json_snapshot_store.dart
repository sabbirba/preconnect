import 'dart:convert';

import 'package:preconnect/model/section_info.dart';
import 'package:preconnect/tools/app_storage.dart';
import 'package:preconnect/tools/storage_keys.dart';

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

  static Future<List<Section>?> readSections() async {
    return read<List<Section>>(
      key: StorageKeys.alarmsSnapshot,
      decode: (decoded) {
        final sectionsRaw = decoded['sections'];
        if (sectionsRaw is! List) return null;
        return sectionsRaw
            .whereType<Map>()
            .map((entry) => Section.fromJson(entry.cast<String, dynamic>()))
            .toList(growable: false);
      },
    );
  }

  static Future<void> updateSections(List<Section> sections, {bool? isRamadan}) async {
    try {
      final existing = await read<Map<String, dynamic>>(
        key: StorageKeys.alarmsSnapshot,
        decode: (decoded) => decoded,
      );
      final next = existing ?? <String, dynamic>{};
      next['sections'] = sections.map((s) => s.toJson()).toList();
      if (isRamadan != null) {
        next['isRamadan'] = isRamadan;
      }
      await write(
        key: StorageKeys.alarmsSnapshot,
        value: next,
      );
    } catch (_) {}
  }
}
