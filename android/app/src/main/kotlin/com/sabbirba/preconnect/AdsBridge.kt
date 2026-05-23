package com.sabbirba.preconnect

import android.app.Activity
import android.content.Context
import android.os.Bundle
import android.view.Gravity
import android.view.View
import android.widget.FrameLayout
import com.google.android.gms.ads.AdRequest
import com.google.android.gms.ads.AdSize
import com.google.android.gms.ads.AdView
import com.google.android.gms.ads.FullScreenContentCallback
import com.google.android.gms.ads.LoadAdError
import com.google.android.gms.ads.MobileAds
import com.google.android.gms.ads.RequestConfiguration
import com.google.android.gms.ads.interstitial.InterstitialAd
import com.google.android.gms.ads.interstitial.InterstitialAdLoadCallback
import com.google.android.gms.ads.rewarded.RewardItem
import com.google.android.gms.ads.rewarded.RewardedAd
import com.google.android.gms.ads.rewarded.RewardedAdLoadCallback
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.StandardMessageCodec
import io.flutter.plugin.platform.PlatformView
import io.flutter.plugin.platform.PlatformViewFactory

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
            "showInterstitial" -> showInterstitial(call, result)
            else -> result.notImplemented()
        }
    }

    private fun initialize(call: MethodCall, result: MethodChannel.Result) {
        if (BuildConfig.DEBUG) {
            result.success(null)
            return
        }
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
        if (BuildConfig.DEBUG) {
            result.success(
                mapOf(
                    "shown" to false,
                    "rewardEarned" to false,
                    "amount" to 0,
                    "type" to "",
                ),
            )
            return
        }
        val adUnitId = call.argument<String>("adUnitId")
            ?.takeIf { it.isNotBlank() }
            ?: BuildConfig.REWARDED_AD_UNIT_ID

        RewardedAd.load(
            activity,
            adUnitId,
            buildAdRequest(),
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

    private fun showInterstitial(call: MethodCall, result: MethodChannel.Result) {
        if (BuildConfig.DEBUG) {
            result.success(false)
            return
        }
        val adUnitId = call.argument<String>("adUnitId")
            ?.takeIf { it.isNotBlank() }
            ?: BuildConfig.INTERSTITIAL_AD_UNIT_ID

        if (adUnitId.isBlank()) {
            result.success(false)
            return
        }

        InterstitialAd.load(
            activity,
            adUnitId,
            buildAdRequest(),
            object : InterstitialAdLoadCallback() {
                override fun onAdFailedToLoad(error: LoadAdError) {
                    result.error("ADS_INTERSTITIAL_LOAD", error.message, null)
                }

                override fun onAdLoaded(ad: InterstitialAd) {
                    ad.fullScreenContentCallback = object : FullScreenContentCallback() {
                        override fun onAdDismissedFullScreenContent() {
                            result.success(true)
                        }

                        override fun onAdFailedToShowFullScreenContent(adError: com.google.android.gms.ads.AdError) {
                            result.error("ADS_INTERSTITIAL_SHOW", adError.message, null)
                        }
                    }
                    ad.show(activity)
                }
            },
        )
    }

    internal fun buildAdRequest(): AdRequest {
        return AdRequest.Builder().build()
    }
}

class BannerAdViewFactory(
    private val context: Context,
) : PlatformViewFactory(StandardMessageCodec.INSTANCE) {
    override fun create(context: Context, viewId: Int, args: Any?): PlatformView {
        return BannerAdPlatformView(this.context, args)
    }
}

private class BannerAdPlatformView(
    context: Context,
    args: Any?,
) : PlatformView {
    private val container = FrameLayout(context)
    private val adView = AdView(context)

    init {
        if (!BuildConfig.DEBUG) {
            val bannerWidthDp = resolveBannerWidthDp(context, args)
            val adUnitId = BuildConfig.BANNER_AD_UNIT_ID
            if (adUnitId.isNotBlank()) {
                adView.adUnitId = adUnitId
                adView.setAdSize(
                    AdSize.getCurrentOrientationAnchoredAdaptiveBannerAdSize(context, bannerWidthDp),
                )
                container.addView(
                    adView,
                    FrameLayout.LayoutParams(
                        FrameLayout.LayoutParams.MATCH_PARENT,
                        FrameLayout.LayoutParams.WRAP_CONTENT,
                        Gravity.CENTER_HORIZONTAL,
                    ),
                )
                adView.loadAd(AdRequest.Builder().build())
            }
        }
    }

    override fun getView(): View = container

    override fun dispose() {
        adView.destroy()
    }

    private fun resolveBannerWidthDp(context: Context, args: Any?): Int {
        val displayMetrics = context.resources.displayMetrics
        val requestedWidthDp = (args as? Map<*, *>)?.get("width")
            ?.toString()
            ?.toFloatOrNull()
        val screenWidthDp = (displayMetrics.widthPixels / displayMetrics.density)
        return (requestedWidthDp ?: screenWidthDp)
            .takeIf { it > 0f }
            ?.toInt()
            ?.coerceAtLeast(320)
            ?: 320
    }
}
