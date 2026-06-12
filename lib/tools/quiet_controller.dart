import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;
import 'package:flutter/services.dart' show MethodChannel;
import 'package:preconnect/tools/app_storage.dart';
import 'package:preconnect/tools/schedule_planner.dart';

class QuietModeResult {
  const QuietModeResult({
    required this.status,
    this.applied = false,
    this.message,
    this.permission,
  });

  final String status;
  final bool applied;
  final String? message;
  final String? permission;
}

class QuietModeController {
  QuietModeController._();

  static final QuietModeController instance = QuietModeController._();

  static const String _prefsKey = 'quiet_mode_during_class';
  static const MethodChannel _channel = MethodChannel('preconnect/quiet_mode');

  bool _loaded = false;
  bool _enabled = false;

  bool get isEnabled => _enabled;

  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    _enabled = await AppStorage.instance.getBool(_prefsKey) ?? false;
  }

  Future<QuietModeResult> refresh() async {
    await load();
    return _syncWithPlatform(_enabled, source: 'sync');
  }

  Future<QuietModeResult> setEnabled(
    bool value, {
    bool promptForPermission = false,
  }) async {
    await load();
    _enabled = value;
    await AppStorage.instance.setBool(_prefsKey, value);

    if (kIsWeb) {
      return QuietModeResult(
        status: 'stored',
        applied: false,
        message: 'Saved for next time',
      );
    }

    if (defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS) {
      return _syncWithPlatform(
        value,
        source: promptForPermission ? 'user' : 'sync',
      );
    }

    return QuietModeResult(
      status: 'stored',
      applied: false,
      message: 'Saved for next time',
    );
  }

  Future<QuietModeResult> requestSetup() async {
    await load();
    if (!_enabled) {
      return QuietModeResult(
        status: 'disabled',
        applied: false,
        message: 'Turn on Quiet Mode first.',
      );
    }

    return _syncWithPlatform(_enabled, source: 'user');
  }

  Future<QuietModeResult> _syncWithPlatform(
    bool enabled, {
    required String source,
  }) async {
    if (kIsWeb) {
      return QuietModeResult(
        status: 'stored',
        applied: false,
        message: 'Saved for next time',
      );
    }

    if (defaultTargetPlatform != TargetPlatform.android &&
        defaultTargetPlatform != TargetPlatform.iOS) {
      return QuietModeResult(
        status: 'stored',
        applied: false,
        message: 'Saved for next time',
      );
    }

    try {
      final plan = enabled
          ? await QuietModeSchedulePlanner().buildPlan()
          : const QuietModeSchedulePlan(
              windows: <QuietModeScheduleWindow>[],
              activeNow: false,
            );
      final response =
          await _channel.invokeMapMethod<String, dynamic>(
            'setQuietMode',
            <String, Object?>{
              'enabled': enabled,
              'source': source,
              'windows': plan.toJsonList(),
            },
          ) ??
          const <String, dynamic>{};

      final status = (response['status'] as String?)?.trim().isNotEmpty == true
          ? response['status'] as String
          : 'stored';
      final applied = response['applied'] == true;
      final message = response['message'] as String?;
      final permission = response['permission'] as String?;
      _enabled = enabled;
      await AppStorage.instance.setBool(_prefsKey, enabled);
      return QuietModeResult(
        status: status,
        applied: applied,
        message: message,
        permission: permission,
      );
    } catch (_) {
      _enabled = enabled;
      await AppStorage.instance.setBool(_prefsKey, enabled);
      return QuietModeResult(
        status: 'stored',
        applied: false,
        message: 'Saved for next time',
      );
    }
  }
}
