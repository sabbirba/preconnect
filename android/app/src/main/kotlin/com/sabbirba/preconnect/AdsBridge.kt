package com.sabbirba.preconnect

import android.app.Activity
import android.os.Bundle
import com.google.android.gms.ads.AdRequest
import com.google.android.gms.ads.FullScreenContentCallback
import com.google.android.gms.ads.LoadAdError
import com.google.android.gms.ads.MobileAds
import com.google.android.gms.ads.RequestConfiguration
import com.google.android.gms.ads.rewarded.RewardItem
import com.google.android.gms.ads.rewarded.RewardedAd
import com.google.android.gms.ads.rewarded.RewardedAdLoadCallback
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

class AdsBridge(
    private val activity: Activity,
) {
    companion object {
        const val channelName = "preconnect/ads"
    }

    fun handle(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "initialize" -> initialize(call, result)
            "showRewarded" -> showRewarded(call, result)
            else -> result.notImplemented()
        }
    }

    private fun initialize(call: MethodCall, result: MethodChannel.Result) {
        val testDeviceIds = call.argument<List<*>>("testDeviceIds")
            ?.filterIsInstance<String>()
            .orEmpty()

        val configBuilder = RequestConfiguration.Builder()
        if (testDeviceIds.isNotEmpty()) {
            configBuilder.setTestDeviceIds(testDeviceIds)
        }
        MobileAds.setRequestConfiguration(configBuilder.build())
        MobileAds.initialize(activity) {}
        result.success(null)
    }

    private fun showRewarded(call: MethodCall, result: MethodChannel.Result) {
        val adUnitId = call.argument<String>("adUnitId")
            ?.takeIf { it.isNotBlank() }
            ?: BuildConfig.REWARDED_AD_UNIT_ID
        val nonPersonalizedAds = call.argument<Boolean>("nonPersonalizedAds") ?: true

        RewardedAd.load(
            activity,
            adUnitId,
            buildAdRequest(nonPersonalizedAds),
            object : RewardedAdLoadCallback() {
                override fun onAdFailedToLoad(error: LoadAdError) {
                    result.error("ADS_REWARDED_LOAD", error.message, null)
                }

                override fun onAdLoaded(ad: RewardedAd) {
                    var rewardItem: RewardItem? = null
                    ad.fullScreenContentCallback = object : FullScreenContentCallback() {
                        override fun onAdDismissedFullScreenContent() {
                            result.success(
                                mapOf(
                                    "shown" to true,
                                    "rewardEarned" to (rewardItem != null),
                                    "amount" to (rewardItem?.amount ?: 0),
                                    "type" to (rewardItem?.type ?: ""),
                                ),
                            )
                        }

                        override fun onAdFailedToShowFullScreenContent(adError: com.google.android.gms.ads.AdError) {
                            result.error("ADS_REWARDED_SHOW", adError.message, null)
                        }
                    }
                    ad.show(activity) { reward ->
                        rewardItem = reward
                    }
                }
            },
        )
    }

    internal fun buildAdRequest(nonPersonalizedAds: Boolean): AdRequest {
        val builder = AdRequest.Builder()
        if (nonPersonalizedAds) {
            val extras = Bundle()
            extras.putString("npa", "1")
            builder.addNetworkExtrasBundle(com.google.ads.mediation.admob.AdMobAdapter::class.java, extras)
        }
        return builder.build()
    }
}
