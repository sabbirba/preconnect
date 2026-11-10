import 'dart:async';
import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:preconnect/tools/app_storage.dart';
import 'package:preconnect/tools/storage_keys.dart';

class Drafts {
  Drafts._();

  static final Drafts instance = Drafts._();
  static const Duration _saveDelay = Duration(milliseconds: 300);

  final ValueNotifier<int> version = ValueNotifier<int>(0);
  Map<String, String>? _drafts;
  Timer? _saveTimer;

  Map<String, String> get _all => _drafts ??= _load();

  Map<String, String> _load() {
    final raw = AppStorage.instance.getStringSync(StorageKeys.drafts);
    if (raw == null || raw.isEmpty) return <String, String>{};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return <String, String>{};
      return <String, String>{
        for (final entry in decoded.entries) '${entry.key}': '${entry.value}',
      };
    } on FormatException {
      return <String, String>{};
    }
  }

  String read(String key) => _all[key] ?? '';

  void write(String key, String value) {
    final drafts = _all;
    final next = value.trim().isEmpty ? null : value;
    if (drafts[key] == next) return;
    if (next == null) {
      drafts.remove(key);
    } else {
      drafts[key] = next;
    }
    _saveTimer?.cancel();
    _saveTimer = Timer(_saveDelay, _save);
  }

  void clear(String key) => write(key, '');

  void bind(TextEditingController controller, String key) {
    final saved = read(key);
    if (saved.isNotEmpty) controller.text = saved;
    controller.addListener(() => write(key, controller.text));
  }

  void reset() {
    _saveTimer?.cancel();
    _drafts = null;
    version.value++;
  }

  void _save() {
    final drafts = _all;
    version.value++;
    unawaited(
      drafts.isEmpty
          ? AppStorage.instance.remove(StorageKeys.drafts)
          : AppStorage.instance.setString(
              StorageKeys.drafts,
              jsonEncode(drafts),
            ),
    );
  }
}
