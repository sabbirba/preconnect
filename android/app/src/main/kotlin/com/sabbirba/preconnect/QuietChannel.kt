package com.sabbirba.preconnect

import android.app.Activity
import android.content.Intent
import android.provider.Settings
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

internal class QuietChannel(
    private val activity: Activity,
) {
    fun configure(messenger: BinaryMessenger) {
        MethodChannel(messenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "setQuietMode" -> setQuietMode(call, result)
                "openQuietModeSettings" -> openSettings(result)
                else -> result.notImplemented()
            }
        }
    }

    private fun setQuietMode(
        call: MethodCall,
        result: MethodChannel.Result,
    ) {
        val windows =
            call.argument<List<*>>("windows").orEmpty().mapNotNull { item ->
                val raw = item as? Map<*, *> ?: return@mapNotNull null
                val startAt =
                    (raw["startAt"] as? Number)?.toLong()
                        ?: raw["startAt"]?.toString()?.toLongOrNull()
                        ?: return@mapNotNull null
                val endAt =
                    (raw["endAt"] as? Number)?.toLong()
                        ?: raw["endAt"]?.toString()?.toLongOrNull()
                        ?: return@mapNotNull null
                QuietModeWindow(
                    startAtMillis = startAt,
                    endAtMillis = endAt,
                    source = raw["source"]?.toString().orEmpty(),
                    label = raw["label"]?.toString().orEmpty(),
                )
            }
        result.success(
            QuietModeAutomation.handleSetQuietMode(
                context = activity,
                enabled = call.argument<Boolean>("enabled") == true,
                source =
                    call
                        .argument<String>("source")
                        ?.trim()
                        .orEmpty()
                        .ifBlank { "sync" },
                windows = windows,
            ),
        )
    }

    private fun openSettings(result: MethodChannel.Result) {
        try {
            activity.startActivity(
                Intent(Settings.ACTION_NOTIFICATION_POLICY_ACCESS_SETTINGS).apply {
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                },
            )
            result.success(true)
        } catch (_: Exception) {
            result.success(false)
        }
    }

    private companion object {
        const val CHANNEL = "preconnect/quiet_mode"
    }
}
