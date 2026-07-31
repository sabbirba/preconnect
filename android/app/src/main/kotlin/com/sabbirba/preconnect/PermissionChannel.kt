package com.sabbirba.preconnect

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.os.PowerManager
import android.provider.Settings
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

internal class PermissionChannel(
    private val activity: Activity,
) {
    fun configure(messenger: BinaryMessenger) {
        MethodChannel(messenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "isBatteryOptimizationIgnored" -> result.success(isIgnored())
                "requestIgnoreBatteryOptimization" -> result.success(requestExemption())
                else -> result.notImplemented()
            }
        }
    }

    private fun isIgnored(): Boolean {
        val manager = activity.getSystemService(Context.POWER_SERVICE) as PowerManager
        return manager.isIgnoringBatteryOptimizations(activity.packageName)
    }

    private fun requestExemption(): Boolean =
        try {
            activity.startActivity(
                Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS).apply {
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                },
            )
            true
        } catch (_: Exception) {
            false
        }

    private companion object {
        const val CHANNEL = "preconnect/background_permission"
    }
}
