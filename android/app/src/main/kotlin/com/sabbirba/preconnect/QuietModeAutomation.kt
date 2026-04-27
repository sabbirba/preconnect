package com.sabbirba.preconnect

import android.app.AlarmManager
import android.app.AutomaticZenRule
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import android.service.notification.Condition
import org.json.JSONArray
import org.json.JSONObject

private const val QUIET_MODE_PREFS = "preconnect.quiet_mode"
private const val QUIET_MODE_RULE_ID = "quiet_mode_rule_id"
private const val QUIET_MODE_PLAN_KEY = "quiet_mode_schedule_plan_v1"
private const val QUIET_MODE_ALARM_ACTION =
    "com.sabbirba.preconnect.action.QUIET_MODE_ALARM"
private const val QUIET_MODE_ALARM_REQUEST_CODE = 9182

data class QuietModeWindow(
    val startAtMillis: Long,
    val endAtMillis: Long,
    val source: String,
    val label: String,
) {
    fun toJson(): JSONObject {
        return JSONObject()
            .put("startAt", startAtMillis)
            .put("endAt", endAtMillis)
            .put("source", source)
            .put("label", label)
    }

    companion object {
        fun fromJson(json: JSONObject): QuietModeWindow? {
            val startAt = json.optLong("startAt", -1L)
            val endAt = json.optLong("endAt", -1L)
            if (startAt <= 0L || endAt <= 0L) return null
            return QuietModeWindow(
                startAtMillis = startAt,
                endAtMillis = endAt,
                source = json.optString("source", ""),
                label = json.optString("label", ""),
            )
        }
    }
}

object QuietModeAutomation {
    fun syncFromStoredPlan(context: Context): Map<String, Any?> {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) {
            return mapOf(
                "status" to "unsupported",
                "applied" to false,
                "enabled" to false,
                "message" to "Do Not Disturb is not supported on this Android version.",
            )
        }
        val windows = loadPlan(context)
        if (windows.isEmpty()) {
            cancelNextAlarm(context)
            applyQuietModeState(context, false)
            return mapOf(
                "status" to "disabled",
                "applied" to true,
                "enabled" to false,
                "message" to "Quiet Mode disabled.",
            )
        }

        val notificationManager = notificationManager(context) ?: return mapOf(
            "status" to "unavailable",
            "applied" to false,
            "enabled" to false,
            "message" to "Notification manager is unavailable.",
        )

        if (!notificationManager.isNotificationPolicyAccessGranted) {
            return mapOf(
                "status" to "permission_required",
                "applied" to false,
                "enabled" to true,
                "permission" to "notification_policy",
                "message" to "Needs DND access to keep Quiet Mode synced.",
            )
        }

        val activeNow = isActiveNow(windows)
        applyQuietModeState(context, activeNow)
        scheduleNext(context, windows, promptForPermission = false)
        return mapOf(
            "status" to if (activeNow) "enabled" else "scheduled",
            "applied" to true,
            "enabled" to activeNow,
            "message" to if (activeNow) {
                "Quiet Mode synced with your schedules."
            } else {
                "Quiet Mode schedule synced."
            },
        )
    }

    fun handleSetQuietMode(
        context: Context,
        enabled: Boolean,
        source: String,
        windows: List<QuietModeWindow>,
    ): Map<String, Any?> {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) {
            return mapOf(
                "status" to "unsupported",
                "applied" to false,
                "enabled" to false,
                "message" to "Do Not Disturb is not supported on this Android version.",
            )
        }
        val notificationManager = notificationManager(context) ?: return mapOf(
            "status" to "unavailable",
            "applied" to false,
            "enabled" to false,
            "message" to "Notification manager is unavailable.",
        )

        if (!enabled || windows.isEmpty()) {
            clearPlan(context)
            cancelNextAlarm(context)
            applyQuietModeState(context, false)
            return mapOf(
                "status" to if (enabled) "stored" else "disabled",
                "applied" to true,
                "enabled" to false,
                "message" to if (enabled) {
                    "No schedule windows found yet."
                } else {
                    "Quiet Mode disabled."
                },
            )
        }

        savePlan(context, windows)

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M &&
            !notificationManager.isNotificationPolicyAccessGranted
        ) {
            if (source == "user") {
                openQuietModeSettings(context)
            }
            return mapOf(
                "status" to "permission_required",
                "applied" to false,
                "enabled" to true,
                "permission" to "notification_policy",
                "message" to "Needs DND access to sync Quiet Mode.",
            )
        }

        val activeNow = isActiveNow(windows)
        applyQuietModeState(context, activeNow)

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            val alarmManager = alarmManager(context)
            if (alarmManager != null && !alarmManager.canScheduleExactAlarms()) {
                if (source == "user") {
                    openExactAlarmSettings(context)
                }
                return mapOf(
                    "status" to "permission_required",
                    "applied" to activeNow,
                    "enabled" to true,
                    "permission" to "exact_alarms",
                    "message" to "Needs device alarm access to automate Quiet Mode on schedule.",
                )
            }
        }

        scheduleNext(context, windows, promptForPermission = true)
        return mapOf(
            "status" to "scheduled",
            "applied" to true,
            "enabled" to activeNow,
            "message" to if (activeNow) {
                "Quiet Mode enabled for your current schedule."
            } else {
                "Quiet Mode synced with your schedules."
            },
        )
    }

    private fun scheduleNext(
        context: Context,
        windows: List<QuietModeWindow>,
        promptForPermission: Boolean,
    ) {
        val alarmManager = alarmManager(context) ?: return
        val nextTransition = nextTransition(windows, System.currentTimeMillis()) ?: run {
            cancelNextAlarm(context)
            return
        }

        val intent = Intent(context, QuietModeAutomationReceiver::class.java).apply {
            action = QUIET_MODE_ALARM_ACTION
        }
        val pendingIntent = PendingIntent.getBroadcast(
            context,
            QUIET_MODE_ALARM_REQUEST_CODE,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )

        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                alarmManager.setExactAndAllowWhileIdle(
                    AlarmManager.RTC_WAKEUP,
                    nextTransition,
                    pendingIntent,
                )
            } else {
                alarmManager.setExact(
                    AlarmManager.RTC_WAKEUP,
                    nextTransition,
                    pendingIntent,
                )
            }
        } catch (_: SecurityException) {
            if (promptForPermission) {
                openExactAlarmSettings(context)
            }
        }
    }

    private fun nextTransition(
        windows: List<QuietModeWindow>,
        nowMillis: Long,
    ): Long? {
        var next: Long? = null
        for (window in windows) {
            val candidates = listOf(window.startAtMillis, window.endAtMillis)
            for (candidate in candidates) {
                if (candidate <= nowMillis) continue
                if (next == null || candidate < next) {
                    next = candidate
                }
            }
        }
        return next
    }

    private fun isActiveNow(windows: List<QuietModeWindow>): Boolean {
        val now = System.currentTimeMillis()
        return windows.any { now >= it.startAtMillis && now < it.endAtMillis }
    }

    private fun savePlan(context: Context, windows: List<QuietModeWindow>) {
        val prefs = context.getSharedPreferences(QUIET_MODE_PREFS, Context.MODE_PRIVATE)
        val array = JSONArray()
        windows.forEach { array.put(it.toJson()) }
        prefs.edit().putString(QUIET_MODE_PLAN_KEY, array.toString()).apply()
    }

    private fun loadPlan(context: Context): List<QuietModeWindow> {
        val prefs = context.getSharedPreferences(QUIET_MODE_PREFS, Context.MODE_PRIVATE)
        val raw = prefs.getString(QUIET_MODE_PLAN_KEY, null)?.trim().orEmpty()
        if (raw.isEmpty()) return emptyList()
        return try {
            val array = JSONArray(raw)
            buildList {
                for (i in 0 until array.length()) {
                    val entry = array.optJSONObject(i) ?: continue
                    val window = QuietModeWindow.fromJson(entry) ?: continue
                    if (window.endAtMillis > System.currentTimeMillis()) {
                        add(window)
                    }
                }
            }
        } catch (_: Exception) {
            emptyList()
        }
    }

    private fun clearPlan(context: Context) {
        val prefs = context.getSharedPreferences(QUIET_MODE_PREFS, Context.MODE_PRIVATE)
        prefs.edit().remove(QUIET_MODE_PLAN_KEY).apply()
    }

    private fun cancelNextAlarm(context: Context) {
        val alarmManager = alarmManager(context) ?: return
        val intent = Intent(context, QuietModeAutomationReceiver::class.java).apply {
            action = QUIET_MODE_ALARM_ACTION
        }
        val pendingIntent = PendingIntent.getBroadcast(
            context,
            QUIET_MODE_ALARM_REQUEST_CODE,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        alarmManager.cancel(pendingIntent)
    }

    private fun notificationManager(context: Context): NotificationManager? {
        return context.getSystemService(Context.NOTIFICATION_SERVICE) as? NotificationManager
    }

    private fun alarmManager(context: Context): AlarmManager? {
        return context.getSystemService(Context.ALARM_SERVICE) as? AlarmManager
    }

    private fun applyQuietModeState(context: Context, enabled: Boolean) {
        val notificationManager = notificationManager(context) ?: return
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) return

        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) {
            try {
                notificationManager.setInterruptionFilter(
                    if (enabled) {
                        NotificationManager.INTERRUPTION_FILTER_NONE
                    } else {
                        NotificationManager.INTERRUPTION_FILTER_ALL
                    },
                )
            } catch (_: Exception) {}
            return
        }

        val ruleId = ensureQuietModeRule(context, notificationManager) ?: return
        try {
            val condition = Condition(
                quietModeConditionId(context),
                context.getString(R.string.quiet_mode_rule_type),
                if (enabled) Condition.STATE_TRUE else Condition.STATE_FALSE,
            )
            notificationManager.setAutomaticZenRuleState(ruleId, condition)
        } catch (_: Exception) {}
    }

    private fun ensureQuietModeRule(
        context: Context,
        notificationManager: NotificationManager,
    ): String? {
        val prefs = context.getSharedPreferences(QUIET_MODE_PREFS, Context.MODE_PRIVATE)
        val storedRuleId = prefs.getString(QUIET_MODE_RULE_ID, null)
        if (!storedRuleId.isNullOrBlank()) {
            if (notificationManager.getAutomaticZenRule(storedRuleId) != null) {
                return storedRuleId
            }
        }

        return try {
            val rule = AutomaticZenRule(
                context.getString(R.string.quiet_mode_rule_type),
                null,
                ComponentName(context, MainActivity::class.java),
                quietModeConditionId(context),
                null,
                NotificationManager.INTERRUPTION_FILTER_NONE,
                true,
            )
            val ruleId = notificationManager.addAutomaticZenRule(rule)
            if (!ruleId.isNullOrBlank()) {
                prefs.edit().putString(QUIET_MODE_RULE_ID, ruleId).apply()
            }
            ruleId
        } catch (_: Exception) {
            null
        }
    }

    private fun quietModeConditionId(context: Context): Uri {
        return Condition.newId(context)
            .appendPath("quiet_mode_during_schedules")
            .build()
    }

    private fun openQuietModeSettings(context: Context) {
        try {
            val intent = Intent(Settings.ACTION_NOTIFICATION_POLICY_ACCESS_SETTINGS).apply {
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            context.startActivity(intent)
        } catch (_: Exception) {}
    }

    private fun openExactAlarmSettings(context: Context) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S) return
        try {
            val intent = Intent(Settings.ACTION_REQUEST_SCHEDULE_EXACT_ALARM).apply {
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            context.startActivity(intent)
        } catch (_: Exception) {}
    }
}

class QuietModeAutomationReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent?) {
        if (intent?.action != QUIET_MODE_ALARM_ACTION) return
        QuietModeAutomation.syncFromStoredPlan(context)
    }
}

class QuietModeBootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent?) {
        val action = intent?.action ?: return
        if (action != Intent.ACTION_BOOT_COMPLETED &&
            action != Intent.ACTION_MY_PACKAGE_REPLACED
        ) {
            return
        }
        QuietModeAutomation.syncFromStoredPlan(context)
    }
}
