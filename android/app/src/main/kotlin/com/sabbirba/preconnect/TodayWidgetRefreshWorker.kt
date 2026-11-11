package com.sabbirba.preconnect

import android.content.Context
import androidx.work.CoroutineWorker
import androidx.work.ExistingPeriodicWorkPolicy
import androidx.work.ExistingWorkPolicy
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.PeriodicWorkRequestBuilder
import androidx.work.WorkManager
import androidx.work.WorkerParameters
import io.flutter.FlutterInjector
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.TimeUnit
import kotlin.coroutines.resume
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeoutOrNull

class TodayWidgetRefreshWorker(
    context: Context,
    params: WorkerParameters,
) : CoroutineWorker(context, params) {
    override suspend fun doWork(): Result {
        withTimeoutOrNull(TIMEOUT_MILLIS) { runDartRefresh() }
        return Result.success()
    }

    private suspend fun runDartRefresh() =
        withContext(Dispatchers.Main) {
            val engine = FlutterEngine(applicationContext)
            try {
                suspendCancellableCoroutine { continuation ->
                    MethodChannel(engine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { _, result ->
                        result.success(null)
                        if (continuation.isActive) continuation.resume(Unit)
                    }
                    engine.dartExecutor.executeDartEntrypoint(
                        DartExecutor.DartEntrypoint(
                            FlutterInjector.instance().flutterLoader().findAppBundlePath(),
                            ENTRYPOINT,
                        ),
                    )
                }
            } finally {
                engine.destroy()
            }
        }

    companion object {
        private const val CHANNEL = "preconnect/today_widget"
        private const val ENTRYPOINT = "todayWidgetRefresh"
        private const val PERIODIC_WORK = "today_widget_periodic_refresh"
        private const val ONE_TIME_WORK = "today_widget_refresh"
        private const val INTERVAL_HOURS = 6L
        private const val TIMEOUT_MILLIS = 60_000L

        fun schedule(context: Context) {
            val request =
                PeriodicWorkRequestBuilder<TodayWidgetRefreshWorker>(INTERVAL_HOURS, TimeUnit.HOURS).build()
            WorkManager.getInstance(context)
                .enqueueUniquePeriodicWork(PERIODIC_WORK, ExistingPeriodicWorkPolicy.UPDATE, request)
        }

        fun refreshNow(context: Context) {
            val request = OneTimeWorkRequestBuilder<TodayWidgetRefreshWorker>().build()
            WorkManager.getInstance(context)
                .enqueueUniqueWork(ONE_TIME_WORK, ExistingWorkPolicy.KEEP, request)
        }

        fun cancel(context: Context) {
            WorkManager.getInstance(context).apply {
                cancelUniqueWork(PERIODIC_WORK)
                cancelUniqueWork(ONE_TIME_WORK)
            }
        }
    }
}
