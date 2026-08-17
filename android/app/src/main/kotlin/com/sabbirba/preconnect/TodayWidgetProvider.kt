package com.sabbirba.preconnect

import android.app.AlarmManager
import android.app.PendingIntent
import android.app.WallpaperManager
import android.appwidget.AppWidgetManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.content.res.Configuration
import android.content.res.ColorStateList
import android.net.Uri
import android.os.Build
import android.os.SystemClock
import android.view.View
import android.widget.RemoteViews
import androidx.core.graphics.ColorUtils
import es.antonborri.home_widget.HomeWidgetBackgroundIntent
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetProvider

class TodayWidgetProvider : HomeWidgetProvider() {
    override fun onEnabled(context: Context) {
        super.onEnabled(context)
        scheduleRefresh(context)
    }

    override fun onDisabled(context: Context) {
        val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        alarmManager.cancel(refreshIntent(context))
        super.onDisabled(context)
    }

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences,
    ) {
        val title = widgetData.getString("today_title", null).orEmpty()
        val date = widgetData.getString("today_date", null).orEmpty()
        for (widgetId in appWidgetIds) {
            val views = RemoteViews(context.packageName, R.layout.today_widget)
            views.setTextViewText(R.id.today_title, title)
            views.setTextViewText(R.id.today_date, date)
            val openAppIntent =
                HomeWidgetLaunchIntent.getActivity(
                    context,
                    MainActivity::class.java,
                    Uri.parse("preconnect://today"),
                )
            views.setOnClickPendingIntent(R.id.today_header, openAppIntent)

            val rows =
                listOf(
                    Row(R.id.row1, R.id.row1_badge, R.id.row1_title, R.id.row1_subtitle, R.id.row1_trailing_container, R.id.row1_trailing, R.id.row1_trailing_sub),
                    Row(R.id.row2, R.id.row2_badge, R.id.row2_title, R.id.row2_subtitle, R.id.row2_trailing_container, R.id.row2_trailing, R.id.row2_trailing_sub),
                    Row(R.id.row3, R.id.row3_badge, R.id.row3_title, R.id.row3_subtitle, R.id.row3_trailing_container, R.id.row3_trailing, R.id.row3_trailing_sub),
                )

            rows.forEachIndexed { index, row ->
                val slot = index + 1
                val itemTitle = widgetData.getString("today_item${slot}_title", null).orEmpty()

                if (itemTitle.isEmpty()) {
                    views.setViewVisibility(row.container, View.GONE)
                    return@forEachIndexed
                }

                views.setViewVisibility(row.container, View.VISIBLE)
                views.setOnClickPendingIntent(row.container, openAppIntent)
                views.setTextViewText(row.title, itemTitle)
                views.setTextViewText(
                    row.subtitle,
                    widgetData.getString("today_item${slot}_subtitle", null).orEmpty(),
                )

                val badge = widgetData.getString("today_item${slot}_badge", null).orEmpty()
                views.setTextViewText(row.badge, badge)

                val trailing = widgetData.getString("today_item${slot}_trailing", null).orEmpty()
                if (trailing.isEmpty()) {
                    views.setViewVisibility(row.trailingContainer, View.GONE)
                } else {
                    views.setViewVisibility(row.trailingContainer, View.VISIBLE)
                    views.setTextViewText(row.trailing, trailing)
                    views.setTextViewText(
                        row.trailingSub,
                        widgetData.getString("today_item${slot}_trailing_sub", null).orEmpty(),
                    )
                }
            }

            wallpaperTintColor(context)?.let { tint ->
                val tintList = ColorStateList.valueOf(tint)
                rows.forEach { row -> views.setColorStateList(row.container, "setBackgroundTintList", tintList) }
            }

            appWidgetManager.updateAppWidget(widgetId, views)
        }

        scheduleRefresh(context)
        maybeRefreshFromCache(context, widgetData)
    }

    private fun scheduleRefresh(context: Context) {
        val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        alarmManager.setInexactRepeating(
            AlarmManager.ELAPSED_REALTIME,
            SystemClock.elapsedRealtime() + REFRESH_INTERVAL_MILLIS,
            REFRESH_INTERVAL_MILLIS,
            refreshIntent(context),
        )
    }

    private fun refreshIntent(context: Context): PendingIntent {
        val appWidgetManager = AppWidgetManager.getInstance(context)
        val widgetIds =
            appWidgetManager.getAppWidgetIds(ComponentName(context, TodayWidgetProvider::class.java))
        val intent =
            Intent(context, TodayWidgetProvider::class.java).apply {
                action = AppWidgetManager.ACTION_APPWIDGET_UPDATE
                putExtra(AppWidgetManager.EXTRA_APPWIDGET_IDS, widgetIds)
            }
        return PendingIntent.getBroadcast(
            context,
            0,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }

    private fun wallpaperTintColor(context: Context): Int? {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S) return null
        val colors =
            WallpaperManager.getInstance(context).getWallpaperColors(WallpaperManager.FLAG_SYSTEM)
                ?: return null
        val isNight =
            (context.resources.configuration.uiMode and Configuration.UI_MODE_NIGHT_MASK) ==
                Configuration.UI_MODE_NIGHT_YES

        val hsl = FloatArray(3)
        ColorUtils.colorToHSL(colors.primaryColor.toArgb(), hsl)
        hsl[1] = if (isNight) 0.28f else 0.35f
        hsl[2] = if (isNight) 0.20f else 0.93f
        return ColorUtils.HSLToColor(hsl)
    }

    private fun maybeRefreshFromCache(
        context: Context,
        widgetData: SharedPreferences,
    ) {
        val now = System.currentTimeMillis()
        val lastRequest = widgetData.getLong("today_last_refresh_request", 0)
        if (now - lastRequest < REFRESH_INTERVAL_MILLIS) return
        widgetData.edit().putLong("today_last_refresh_request", now).apply()
        try {
            HomeWidgetBackgroundIntent.getBroadcast(context, Uri.parse("todaywidget://refresh")).send()
        } catch (_: PendingIntent.CanceledException) {}
    }

    private data class Row(
        val container: Int,
        val badge: Int,
        val title: Int,
        val subtitle: Int,
        val trailingContainer: Int,
        val trailing: Int,
        val trailingSub: Int,
    )

    private companion object {
        const val REFRESH_INTERVAL_MILLIS = 300_000L
    }
}
