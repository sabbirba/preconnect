import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:preconnect/model/friend_schedule.dart';
import 'package:preconnect/tools/app_storage.dart';

class FriendScheduleStore {
  FriendScheduleStore._internal();

  static final FriendScheduleStore _instance = FriendScheduleStore._internal();
  factory FriendScheduleStore() => _instance;

  static const String _encodedSchedulesKey = 'friend_schedules_encoded_v1';
  static const String _metadataKey = 'friend_schedules_metadata_v1';

  Future<FriendScheduleStoreSnapshot> loadSnapshot() async {
    try {
      final prefs = AppStorage.instance;
      final encodedRaw = await prefs.getString(_encodedSchedulesKey);
      final metadataRawPrimary = await prefs.getString(_metadataKey);

      List<String> encodedSchedules = <String>[];
      if (encodedRaw != null && encodedRaw.isNotEmpty) {
        try {
          final parsed = jsonDecode(encodedRaw);
          if (parsed is List) {
            encodedSchedules = parsed.whereType<String>().toList();
          }
        } catch (_) {}
      }

      final metadata = <String, FriendMetadata>{};
      if (metadataRawPrimary != null && metadataRawPrimary.isNotEmpty) {
        try {
          final decoded = jsonDecode(metadataRawPrimary);
          if (decoded is Map) {
            for (final entry in decoded.entries) {
              try {
                metadata['${entry.key}'] = FriendMetadata.fromJson(
                  Map<String, dynamic>.from(entry.value as Map),
                );
              } catch (_) {}
            }
          }
        } catch (_) {}
      }

      return FriendScheduleStoreSnapshot(
        encodedSchedules: encodedSchedules,
        metadata: metadata,
      );
    } catch (_) {
      return const FriendScheduleStoreSnapshot(
        encodedSchedules: <String>[],
        metadata: <String, FriendMetadata>{},
      );
    }
  }

  Future<void> upsertEncodedSchedule(String encodedValue) =>
      upsertEncodedSchedules([encodedValue]);

  Future<void> upsertEncodedSchedules(List<String> encodedValues) async {
    if (encodedValues.isEmpty) return;
    final snapshot = await loadSnapshot();
    final incoming = <String, String>{};
    for (final v in encodedValues) {
      final encoded = v.trim();
      if (encoded.isEmpty) continue;
      final id = _extractFriendId(encoded);
      if (id == null || id.isEmpty) continue;
      incoming[id] = encoded;
    }
    if (incoming.isEmpty) return;
    final next = <String>[
      for (final existing in snapshot.encodedSchedules)
        if (!incoming.containsKey(_extractFriendId(existing))) existing,
      ...incoming.values,
    ];
    await AppStorage.instance.setString(_encodedSchedulesKey, jsonEncode(next));
  }

  Future<void> removeByEncoded(String encodedValue) async {
    final encoded = encodedValue.trim();
    if (encoded.isEmpty) return;
    final snapshot = await loadSnapshot();
    final next = snapshot.encodedSchedules
        .where((value) => value != encoded)
        .toList();
    await AppStorage.instance.setString(_encodedSchedulesKey, jsonEncode(next));
  }

  Future<void> saveAllMetadata(Map<String, FriendMetadata> metadata) async {
    await AppStorage.instance.setString(
      _metadataKey,
      jsonEncode(metadata.map((key, value) => MapEntry(key, value.toJson()))),
    );
  }

  Future<void> clearAll() async {
    await AppStorage.instance.remove(_encodedSchedulesKey);
    await AppStorage.instance.remove(_metadataKey);
  }

  static FriendSchedule? parseSchedulePayload(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return null;

    try {
      final decodedBase64 = base64.decode(trimmed);
      try {
        final decompressed = GZipDecoder().decodeBytes(decodedBase64);
        final jsonStr = utf8.decode(decompressed);
        final parsed = jsonDecode(jsonStr);
        if (parsed is Map<String, dynamic>) {
          return FriendSchedule.fromJson(parsed);
        }
      } catch (_) {
        final jsonStr = utf8.decode(decodedBase64);
        final parsed = jsonDecode(jsonStr);
        if (parsed is Map<String, dynamic>) {
          return FriendSchedule.fromJson(parsed);
        }
      }
    } catch (_) {}

    try {
      final parsed = jsonDecode(trimmed);
      if (parsed is Map<String, dynamic>) {
        return FriendSchedule.fromJson(parsed);
      }
    } catch (_) {}

    return null;
  }

  static List<String>? extractExportSchedules(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return null;

    dynamic parsed;
    try {
      final decodedBase64 = base64.decode(trimmed);
      try {
        final decompressed = GZipDecoder().decodeBytes(decodedBase64);
        parsed = jsonDecode(utf8.decode(decompressed));
      } catch (_) {
        parsed = jsonDecode(utf8.decode(decodedBase64));
      }
    } catch (_) {
      try {
        parsed = jsonDecode(trimmed);
      } catch (_) {}
    }

    if (parsed is Map<String, dynamic> &&
        parsed['type'] == 'friend_schedules_export') {
      final schedules = parsed['schedules'];
      if (schedules is List) {
        return schedules.whereType<String>().toList();
      }
    }
    return null;
  }

  String? _extractFriendId(String base64Data) {
    final schedule = parseSchedulePayload(base64Data);
    final id = schedule?.id.trim() ?? '';
    return id.isEmpty ? null : id;
  }
}

class FriendScheduleStoreSnapshot {
  const FriendScheduleStoreSnapshot({
    required this.encodedSchedules,
    required this.metadata,
  });

  final List<String> encodedSchedules;
  final Map<String, FriendMetadata> metadata;
}
