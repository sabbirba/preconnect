package com.sabbirba.preconnect

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.graphics.Color
import android.net.Uri
import android.view.View
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetBackgroundIntent
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetProvider
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

class TodayWidgetProvider : HomeWidgetProvider() {
    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences,
    ) {
        val title = widgetData.getString("today_title", null).orEmpty()
        val date = widgetData.getString("today_date", null).orEmpty()
        val isSyncing = widgetData.getString("today_syncing", null) == "1"

        for (widgetId in appWidgetIds) {
            val views = RemoteViews(context.packageName, R.layout.today_widget)
            views.setTextViewText(R.id.today_title, title)
            views.setTextViewText(R.id.today_date, date)
            views.setOnClickPendingIntent(
                R.id.today_sync,
                HomeWidgetBackgroundIntent.getBroadcast(context, Uri.parse("todaywidget://sync")),
            )
            views.setViewVisibility(R.id.today_sync_icon, if (isSyncing) View.GONE else View.VISIBLE)
            views.setViewVisibility(R.id.today_sync_progress, if (isSyncing) View.VISIBLE else View.GONE)
            val openAppIntent =
                HomeWidgetLaunchIntent.getActivity(
                    context,
                    MainActivity::class.java,
                    Uri.parse("preconnect://today"),
                )

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
                val badgeColor = widgetData.getString("today_item${slot}_badge_color", null)
                if (badgeColor != null) {
                    try {
                        views.setTextColor(row.badge, Color.parseColor(badgeColor))
                    } catch (_: IllegalArgumentException) {}
                }

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

            appWidgetManager.updateAppWidget(widgetId, views)
        }

        maybeRefreshFromCache(context, widgetData, isSyncing)
    }

    private fun maybeRefreshFromCache(
        context: Context,
        widgetData: SharedPreferences,
        isSyncing: Boolean,
    ) {
        if (isSyncing) return
        val todayKey = SimpleDateFormat("yyyy-MM-dd", Locale.US).format(Date())
        val cachedKey = widgetData.getString("today_date_key", null)
        if (cachedKey == todayKey) return
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
}
