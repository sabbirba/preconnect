import 'package:flutter/foundation.dart';
import 'package:preconnect/tools/app_storage.dart';

class RewardSupportController {
  RewardSupportController._();

  static final RewardSupportController instance = RewardSupportController._();

  static const String _supportCountPrefsKey = 'reward_support_count';

  final ValueNotifier<int> supportCount = ValueNotifier<int>(0);
  bool _loaded = false;

  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    supportCount.value =
        await AppStorage.instance.getInt(_supportCountPrefsKey) ?? 0;
  }

  int get count => supportCount.value;

  Future<int> recordReward() async {
    await load();
    final next = count + 1;
    await AppStorage.instance.setInt(_supportCountPrefsKey, next);
    supportCount.value = next;
    return next;
  }

  Future<void> clear() async {
    await load();
    await AppStorage.instance.remove(_supportCountPrefsKey);
    supportCount.value = 0;
  }
}
