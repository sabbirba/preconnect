package com.sabbirba.preconnect

import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.Intent
import android.provider.AlarmClock
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.util.ArrayList

internal class AlarmChannel(
    private val activity: Activity,
) {
    fun configure(messenger: BinaryMessenger) {
        MethodChannel(messenger, CHANNEL).setMethodCallHandler { call, result ->
            if (call.method != "setAlarm") {
                result.notImplemented()
                return@setMethodCallHandler
            }
            val hour = call.argument<Number>("hour")?.toInt()
            val minute = call.argument<Number>("minute")?.toInt()
            if (hour == null || minute == null) {
                result.success(false)
                return@setMethodCallHandler
            }
            val days = call.argument<List<Int>>("days").orEmpty()
            val intent =
                Intent(AlarmClock.ACTION_SET_ALARM).apply {
                    putExtra(AlarmClock.EXTRA_HOUR, hour)
                    putExtra(AlarmClock.EXTRA_MINUTES, minute)
                    putExtra(AlarmClock.EXTRA_MESSAGE, call.argument<String>("message").orEmpty())
                    putExtra(AlarmClock.EXTRA_SKIP_UI, false)
                    if (days.isNotEmpty()) {
                        putIntegerArrayListExtra(AlarmClock.EXTRA_DAYS, ArrayList(days))
                    }
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                }
            try {
                activity.startActivity(intent)
                result.success(true)
            } catch (_: ActivityNotFoundException) {
                result.success(false)
            } catch (_: Exception) {
                result.success(false)
            }
        }
    }

    private companion object {
        const val CHANNEL = "preconnect/android_alarm"
    }
}
