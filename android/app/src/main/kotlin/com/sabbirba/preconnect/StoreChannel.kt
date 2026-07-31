package com.sabbirba.preconnect

import android.app.Activity
import com.google.android.play.core.review.ReviewManagerFactory
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

class StoreChannel(
    private val activity: Activity,
    messenger: BinaryMessenger,
) {
    private val manager = ReviewManagerFactory.create(activity)
    private val channel = MethodChannel(messenger, "preconnect/store")

    fun configure() {
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "isReviewAvailable" -> {
                    result.success(true)
                }

                "requestReview" -> {
                    manager
                        .requestReviewFlow()
                        .addOnSuccessListener { reviewInfo ->
                            manager
                                .launchReviewFlow(activity, reviewInfo)
                                .addOnCompleteListener { result.success(null) }
                        }.addOnFailureListener {
                            result.error("REVIEW_UNAVAILABLE", it.localizedMessage, null)
                        }
                }

                else -> {
                    result.notImplemented()
                }
            }
        }
    }

    fun dispose() {
        channel.setMethodCallHandler(null)
    }
}
