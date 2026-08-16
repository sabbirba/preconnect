package com.sabbirba.preconnect

import android.app.Activity
import com.google.android.play.core.review.ReviewInfo
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
                            when (reviewInfo.isNoOp()) {
                                true -> {
                                    result.success(false)
                                    return@addOnSuccessListener
                                }

                                null -> {
                                    result.error("REVIEW_UNAVAILABLE", null, null)
                                    return@addOnSuccessListener
                                }

                                false -> Unit
                            }
                            manager
                                .launchReviewFlow(activity, reviewInfo)
                                .addOnCompleteListener { task ->
                                    if (task.isSuccessful) {
                                        result.success(true)
                                    } else {
                                        result.error(
                                            "REVIEW_UNAVAILABLE",
                                            task.exception?.localizedMessage,
                                            null,
                                        )
                                    }
                                }
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

    private fun ReviewInfo.isNoOp(): Boolean? =
        runCatching {
            ReviewInfo::class.java
                .getDeclaredMethod("zzb")
                .apply { isAccessible = true }
                .invoke(this) as Boolean
        }.getOrNull()
}
