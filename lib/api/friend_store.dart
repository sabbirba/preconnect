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

  Future<void> importPayload(String raw) async {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) {
      throw const FormatException('Schedule code is empty');
    }

    final exported = extractExportSchedules(trimmed);
    final encodedValues = exported ?? <String>[trimmed];
    if (encodedValues.isEmpty) {
      throw const FormatException('Schedule code contains no schedules');
    }

    final incoming = <String, String>{};
    for (final value in encodedValues) {
      final encoded = value.trim();
      final schedule = parseSchedulePayload(encoded);
      final id = schedule?.id.trim() ?? '';
      if (encoded.isEmpty || id.isEmpty) {
        throw const FormatException('Invalid friend schedule code');
      }
      incoming[id] = encoded;
    }

    final snapshot = await loadSnapshot();
    final next = <String>[
      for (final existing in snapshot.encodedSchedules)
        if (!incoming.containsKey(_extractFriendId(existing))) existing,
      ...incoming.values,
    ];
    await AppStorage.instance.setString(_encodedSchedulesKey, jsonEncode(next));
    final saved = await loadSnapshot();
    final savedById = <String, String>{
      for (final value in saved.encodedSchedules)
        if (_extractFriendId(value) case final String id) id: value,
    };
    for (final entry in incoming.entries) {
      if (savedById[entry.key] != entry.value) {
        throw StateError('Friend schedule could not be saved');
      }
    }
  }

  Future<void> removeByEncoded(String encodedValue) async {
    final encoded = encodedValue.trim();
    if (encoded.isEmpty) return;
    final snapshot = await loadSnapshot();
    final next = snapshot.encodedSchedules
        .where((value) => value != encoded)
        .toList();
    await AppStorage.instance.setString(_encodedSchedulesKey, jsonEncode(next));
    final saved = await loadSnapshot();
    if (saved.encodedSchedules.contains(encoded)) {
      throw StateError('Friend schedule could not be removed');
    }
  }

  Future<void> saveAllMetadata(Map<String, FriendMetadata> metadata) async {
    await AppStorage.instance.setString(
      _metadataKey,
      jsonEncode(metadata.map((key, value) => MapEntry(key, value.toJson()))),
    );
    final saved = (await loadSnapshot()).metadata;
    if (saved.length != metadata.length) {
      throw StateError('Friend metadata could not be saved');
    }
    for (final entry in metadata.entries) {
      final value = saved[entry.key];
      if (value == null ||
          value.friendId != entry.value.friendId ||
          value.nickname != entry.value.nickname ||
          value.isFavorite != entry.value.isFavorite) {
        throw StateError('Friend metadata could not be saved');
      }
    }
  }

  Future<void> clearAll() async {
    await AppStorage.instance.remove(_encodedSchedulesKey);
    await AppStorage.instance.remove(_metadataKey);
  }

  static FriendSchedule? parseSchedulePayload(String raw) {
    final parsed = _decodeCompressedJson(raw);
    if (parsed is! Map<String, dynamic> ||
        parsed.length != 5 ||
        parsed['name'] is! String ||
        parsed['id'] is! String ||
        (parsed['photoFilePath'] != null &&
            parsed['photoFilePath'] is! String) ||
        parsed['courses'] is! List ||
        (parsed['semester'] != null && parsed['semester'] is! String)) {
      return null;
    }
    const expectedKeys = <String>{
      'name',
      'id',
      'photoFilePath',
      'courses',
      'semester',
    };
    if (!parsed.keys.toSet().containsAll(expectedKeys)) return null;
    try {
      return FriendSchedule.fromJson(parsed);
    } catch (_) {
      return null;
    }
  }

  static List<String>? extractExportSchedules(String raw) {
    final parsed = _decodeCompressedJson(raw);
    if (parsed case {
      'type': 'friend_schedules_export',
      'version': 1,
      'schedules': final List<dynamic> schedules,
    } when parsed.length == 3) {
      if (schedules.any((value) => value is! String || value.trim().isEmpty)) {
        return null;
      }
      return schedules.cast<String>();
    }
    return null;
  }

  static dynamic _decodeCompressedJson(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return null;

    try {
      final decoded = base64.decode(trimmed);
      return jsonDecode(utf8.decode(GZipDecoder().decodeBytes(decoded)));
    } catch (_) {
      return null;
    }
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
