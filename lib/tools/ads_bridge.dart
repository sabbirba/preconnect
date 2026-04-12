import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:preconnect/tools/token_storage.dart';

class AdsBridge {
  AdsBridge._();

  static const MethodChannel _channel = MethodChannel('preconnect/ads');
  static bool get isSupportedPlatform =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  static Future<void> initialize({
    List<String> testDeviceIds = const [],
    bool nonPersonalizedAds = false,
  }) async {
    if (!isSupportedPlatform) {
      return;
    }
    await _channel.invokeMethod<void>('initialize', <String, dynamic>{
      'testDeviceIds': testDeviceIds,
      'nonPersonalizedAds': nonPersonalizedAds,
    });
  }

  static Future<AdsRewardResult> showRewarded({
    String? adUnitId,
    bool nonPersonalizedAds = false,
  }) async {
    if (!isSupportedPlatform || !AdsPreferences.instance.isVisible) {
      return const AdsRewardResult(
        shown: false,
        rewardEarned: false,
        amount: 0,
        type: '',
      );
    }
    final args = <String, dynamic>{'nonPersonalizedAds': nonPersonalizedAds};
    if (adUnitId != null && adUnitId.isNotEmpty) {
      args['adUnitId'] = adUnitId;
    }
    final response = await _channel.invokeMapMethod<String, dynamic>(
      'showRewarded',
      args,
    );
    return AdsRewardResult(
      shown: response?['shown'] == true,
      rewardEarned: response?['rewardEarned'] == true,
      amount: (response?['amount'] as num?)?.toInt() ?? 0,
      type: '${response?['type'] ?? ''}',
    );
  }
}

class AdsRewardResult {
  const AdsRewardResult({
    required this.shown,
    required this.rewardEarned,
    required this.amount,
    required this.type,
  });

  final bool shown;
  final bool rewardEarned;
  final int amount;
  final String type;
}
