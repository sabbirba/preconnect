package com.sabbirba.preconnect

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.net.Uri
import android.view.View
import android.widget.RemoteViews
import java.util.Calendar
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetProvider
import es.antonborri.home_widget.HomeWidgetScheduler

class TodayWidgetProvider : HomeWidgetProvider() {
    override fun onEnabled(context: Context) {
        super.onEnabled(context)
        TodayWidgetRefreshWorker.schedule(context)
    }

    override fun onDisabled(context: Context) {
        TodayWidgetRefreshWorker.cancel(context)
        HomeWidgetScheduler.cancel(context, javaClass.name)
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
        val now = Calendar.getInstance()
        val nowMinutes = now.get(Calendar.HOUR_OF_DAY) * 60 + now.get(Calendar.MINUTE)
        val highlightedSlots = currentOrNextSlots(widgetData, nowMinutes)
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
                views.setInt(
                    row.container,
                    "setBackgroundResource",
                    if (slot in highlightedSlots) R.drawable.card_bg_highlight else R.drawable.card_bg,
                )
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

            appWidgetManager.updateAppWidget(widgetId, views)
        }

        TodayWidgetRefreshWorker.schedule(context)
        HomeWidgetScheduler.schedule(context, javaClass.name, redrawTimes(widgetData, now))
        if (readInt(widgetData, "today_day") != dayKey(now)) {
            TodayWidgetRefreshWorker.refreshNow(context)
        }
    }

    private fun redrawTimes(
        widgetData: SharedPreferences,
        now: Calendar,
    ): List<Long> {
        val startOfDay =
            (now.clone() as Calendar).apply {
                set(Calendar.HOUR_OF_DAY, 0)
                set(Calendar.MINUTE, 0)
                set(Calendar.SECOND, 0)
                set(Calendar.MILLISECOND, 0)
            }
        val boundaries =
            (1..3).flatMap { slot ->
                listOf(
                    readInt(widgetData, "today_item${slot}_start"),
                    readInt(widgetData, "today_item${slot}_end"),
                )
            }.filter { it >= 0 } + MINUTES_PER_DAY
        return boundaries.map { minutes ->
            (startOfDay.clone() as Calendar).apply { add(Calendar.MINUTE, minutes) }.timeInMillis
        }
    }

    private fun dayKey(now: Calendar): Int =
        now.get(Calendar.YEAR) * 10000 + (now.get(Calendar.MONTH) + 1) * 100 + now.get(Calendar.DAY_OF_MONTH)

    private fun currentOrNextSlots(
        widgetData: SharedPreferences,
        nowMinutes: Int,
    ): Set<Int> {
        val slots =
            (1..3).map { slot ->
                Triple(
                    slot,
                    readInt(widgetData, "today_item${slot}_start"),
                    readInt(widgetData, "today_item${slot}_end"),
                )
            }.filter { (_, start, end) -> start in 0 until end }
        val running = slots.filter { (_, start, end) -> nowMinutes in start until end }
        if (running.isNotEmpty()) return running.map { it.first }.toSet()
        val nextStart = slots.map { it.second }.filter { it > nowMinutes }.minOrNull()
        return slots.filter { it.second == nextStart }.map { it.first }.toSet()
    }

    private fun readInt(
        widgetData: SharedPreferences,
        key: String,
    ): Int =
        when (val value = widgetData.all[key]) {
            is Number -> value.toInt()
            else -> -1
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
        const val MINUTES_PER_DAY = 24 * 60
    }
}
