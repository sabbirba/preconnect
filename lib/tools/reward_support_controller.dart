import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class RewardSupportController {
  RewardSupportController._();

  static final RewardSupportController instance = RewardSupportController._();

  static const String _supportCountPrefsKey = 'reward_support_count';

  final ValueNotifier<int> supportCount = ValueNotifier<int>(0);
  bool _loaded = false;

  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    final prefs = await SharedPreferences.getInstance();
    supportCount.value = prefs.getInt(_supportCountPrefsKey) ?? 0;
  }

  int get count => supportCount.value;

  Future<int> recordReward() async {
    await load();
    final next = count + 1;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_supportCountPrefsKey, next);
    supportCount.value = next;
    return next;
  }

  Future<void> clear() async {
    await load();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_supportCountPrefsKey);
    supportCount.value = 0;
  }
}
