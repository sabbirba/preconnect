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
      final metadataRaw = await prefs.getString(_metadataKey);
      final encodedSchedules = encodedRaw == null || encodedRaw.isEmpty
          ? const <String>[]
          : (jsonDecode(encodedRaw) as List).whereType<String>().toList(
              growable: false,
            );
      final metadata = <String, FriendMetadata>{};
      if (metadataRaw != null && metadataRaw.isNotEmpty) {
        final decoded = jsonDecode(metadataRaw);
        if (decoded is Map) {
          for (final entry in decoded.entries) {
            try {
              metadata['${entry.key}'] = FriendMetadata.fromJson(
                Map<String, dynamic>.from(entry.value as Map),
              );
            } catch (_) {}
          }
        }
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

  Future<void> upsertEncodedSchedule(String encodedValue) async {
    final encoded = encodedValue.trim();
    if (encoded.isEmpty) return;
    final friendId = _extractFriendId(encoded);
    if (friendId == null || friendId.isEmpty) return;
    final snapshot = await loadSnapshot();
    final next = <String>{...snapshot.encodedSchedules, encoded}.toList();
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

  String? _extractFriendId(String base64Data) {
    try {
      final decodedBase64 = base64.decode(base64Data);
      final decodedGzip = GZipDecoder().decodeBytes(decodedBase64);
      final originalJson = utf8.decode(decodedGzip);
      final parsed = jsonDecode(originalJson);
      if (parsed is Map<String, dynamic>) {
        final id = parsed['id']?.toString().trim() ?? '';
        return id.isEmpty ? null : id;
      }
    } catch (_) {}
    return null;
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
