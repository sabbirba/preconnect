package com.sabbirba.preconnect

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.net.Uri
import android.view.View
import android.widget.RemoteViews
import java.util.Calendar
import org.json.JSONArray
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
        val now = Calendar.getInstance()
        val today = todayEntry(widgetData, dayKey(now))
        val items = today?.items.orEmpty()
        val nowMinutes = now.get(Calendar.HOUR_OF_DAY) * 60 + now.get(Calendar.MINUTE)
        val highlighted = currentOrNext(items, nowMinutes)
        val openAppIntent =
            HomeWidgetLaunchIntent.getActivity(
                context,
                MainActivity::class.java,
                Uri.parse("preconnect://today"),
            )
        for (widgetId in appWidgetIds) {
            val views = RemoteViews(context.packageName, R.layout.today_widget)
            views.setTextViewText(R.id.today_title, today?.title.orEmpty())
            views.setTextViewText(R.id.today_date, today?.date.orEmpty())
            views.setOnClickPendingIntent(R.id.today_header, openAppIntent)
            rows.forEachIndexed { index, row ->
                val item = items.getOrNull(index)
                if (item == null) {
                    views.setViewVisibility(row.container, View.GONE)
                    return@forEachIndexed
                }
                views.setViewVisibility(row.container, View.VISIBLE)
                views.setOnClickPendingIntent(row.container, openAppIntent)
                views.setInt(
                    row.container,
                    "setBackgroundResource",
                    if (item in highlighted) R.drawable.card_bg_highlight else R.drawable.card_bg,
                )
                views.setTextViewText(row.badge, item.badge)
                views.setTextViewText(row.title, item.title)
                views.setTextViewText(row.subtitle, item.subtitle)
                views.setViewVisibility(
                    row.trailingContainer,
                    if (item.trailing.isEmpty()) View.GONE else View.VISIBLE,
                )
                views.setTextViewText(row.trailing, item.trailing)
                views.setTextViewText(row.trailingSub, item.trailingSub)
            }
            appWidgetManager.updateAppWidget(widgetId, views)
        }

        TodayWidgetRefreshWorker.schedule(context)
        HomeWidgetScheduler.schedule(context, javaClass.name, redrawTimes(items, now))
        if (today == null) TodayWidgetRefreshWorker.refreshNow(context)
    }

    private fun todayEntry(
        widgetData: SharedPreferences,
        today: Int,
    ): Day? {
        val days = runCatching { JSONArray(widgetData.getString("today_days", null) ?: "[]") }.getOrNull() ?: return null
        return (0 until days.length())
            .mapNotNull { days.optJSONObject(it) }
            .firstOrNull { it.optInt("day") == today }
            ?.let { day ->
                val items = day.optJSONArray("items") ?: JSONArray()
                Day(
                    title = day.optString("title"),
                    date = day.optString("date"),
                    items =
                        (0 until items.length()).mapNotNull { items.optJSONObject(it) }.map {
                            Item(
                                badge = it.optString("badge"),
                                title = it.optString("title"),
                                subtitle = it.optString("subtitle"),
                                trailing = it.optString("trailing"),
                                trailingSub = it.optString("trailingSub"),
                                start = it.optInt("start", -1),
                                end = it.optInt("end", -1),
                            )
                        },
                )
            }
    }

    private fun redrawTimes(
        items: List<Item>,
        now: Calendar,
    ): List<Long> {
        val startOfDay =
            (now.clone() as Calendar).apply {
                set(Calendar.HOUR_OF_DAY, 0)
                set(Calendar.MINUTE, 0)
                set(Calendar.SECOND, 0)
                set(Calendar.MILLISECOND, 0)
            }
        val boundaries = items.flatMap { listOf(it.start, it.end) }.filter { it >= 0 } + MINUTES_PER_DAY
        return boundaries.map { minutes ->
            (startOfDay.clone() as Calendar).apply { add(Calendar.MINUTE, minutes) }.timeInMillis
        }
    }

    private fun dayKey(now: Calendar): Int =
        now.get(Calendar.YEAR) * 10000 + (now.get(Calendar.MONTH) + 1) * 100 + now.get(Calendar.DAY_OF_MONTH)

    private fun currentOrNext(
        items: List<Item>,
        nowMinutes: Int,
    ): Set<Item> {
        val timed = items.filter { it.start in 0 until it.end }
        val running = timed.filter { nowMinutes in it.start until it.end }
        if (running.isNotEmpty()) return running.toSet()
        val nextStart = timed.map { it.start }.filter { it > nowMinutes }.minOrNull()
        return timed.filter { it.start == nextStart }.toSet()
    }

    private data class Day(
        val title: String,
        val date: String,
        val items: List<Item>,
    )

    private data class Item(
        val badge: String,
        val title: String,
        val subtitle: String,
        val trailing: String,
        val trailingSub: String,
        val start: Int,
        val end: Int,
    )

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
        val rows =
            listOf(
                Row(R.id.row1, R.id.row1_badge, R.id.row1_title, R.id.row1_subtitle, R.id.row1_trailing_container, R.id.row1_trailing, R.id.row1_trailing_sub),
                Row(R.id.row2, R.id.row2_badge, R.id.row2_title, R.id.row2_subtitle, R.id.row2_trailing_container, R.id.row2_trailing, R.id.row2_trailing_sub),
                Row(R.id.row3, R.id.row3_badge, R.id.row3_title, R.id.row3_subtitle, R.id.row3_trailing_container, R.id.row3_trailing, R.id.row3_trailing_sub),
            )
    }
}
