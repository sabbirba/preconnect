package com.sabbirba.preconnect

import android.app.Activity
import android.content.Intent
import android.provider.CalendarContract
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

class CalendarChannel(
    private val activity: Activity,
    messenger: BinaryMessenger,
) {
    private val channel = MethodChannel(messenger, "preconnect/calendar")

    fun configure() {
        channel.setMethodCallHandler { call, result ->
            if (call.method != "add") {
                result.notImplemented()
                return@setMethodCallHandler
            }
            val title = call.argument<String>("title")?.trim().orEmpty()
            val start = call.argument<Number>("start")?.toLong()
            val end = call.argument<Number>("end")?.toLong()
            if (title.isEmpty() || start == null || end == null) {
                result.success(false)
                return@setMethodCallHandler
            }
            val intent =
                Intent(Intent.ACTION_INSERT, CalendarContract.Events.CONTENT_URI).apply {
                    putExtra(CalendarContract.Events.TITLE, title)
                    putExtra(
                        CalendarContract.Events.DESCRIPTION,
                        call.argument<String>("description"),
                    )
                    putExtra(
                        CalendarContract.Events.EVENT_LOCATION,
                        call.argument<String>("location"),
                    )
                    putExtra(CalendarContract.EXTRA_EVENT_BEGIN_TIME, start)
                    putExtra(CalendarContract.EXTRA_EVENT_END_TIME, end)
                    recurrenceRule(call)?.let {
                        putExtra(CalendarContract.Events.RRULE, it)
                    }
                }
            if (intent.resolveActivity(activity.packageManager) == null) {
                result.success(false)
                return@setMethodCallHandler
            }
            activity.startActivity(intent)
            result.success(true)
        }
    }

    fun dispose() {
        channel.setMethodCallHandler(null)
    }

    private fun recurrenceRule(call: io.flutter.plugin.common.MethodCall): String? {
        val frequency = call.argument<Number>("frequency")?.toInt() ?: return null
        val label =
            when (frequency) {
                0 -> "DAILY"
                1 -> "WEEKLY"
                2 -> "MONTHLY"
                3 -> "YEARLY"
                else -> return null
            }
        val interval = call.argument<Number>("interval")?.toInt() ?: 1
        return "FREQ=$label;INTERVAL=$interval"
    }
}
