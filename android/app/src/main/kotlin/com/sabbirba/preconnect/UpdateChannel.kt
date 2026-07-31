package com.sabbirba.preconnect

import android.app.Activity
import androidx.activity.result.ActivityResultLauncher
import androidx.activity.result.IntentSenderRequest
import com.google.android.play.core.appupdate.AppUpdateInfo
import com.google.android.play.core.appupdate.AppUpdateManager
import com.google.android.play.core.appupdate.AppUpdateManagerFactory
import com.google.android.play.core.appupdate.AppUpdateOptions
import com.google.android.play.core.install.InstallStateUpdatedListener
import com.google.android.play.core.install.model.AppUpdateType
import com.google.android.play.core.install.model.InstallStatus
import com.google.android.play.core.install.model.UpdateAvailability
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

class UpdateChannel(
    private val activity: Activity,
    messenger: BinaryMessenger,
    private val updateLauncher: ActivityResultLauncher<IntentSenderRequest>,
) : EventChannel.StreamHandler {
    private val manager: AppUpdateManager = AppUpdateManagerFactory.create(activity)
    private val methodChannel = MethodChannel(messenger, METHOD_CHANNEL)
    private val eventChannel = EventChannel(messenger, EVENT_CHANNEL)
    private var eventSink: EventChannel.EventSink? = null
    private var installListener: InstallStateUpdatedListener? = null
    private var pendingResult: MethodChannel.Result? = null

    fun configure() {
        methodChannel.setMethodCallHandler(::handleMethod)
        eventChannel.setStreamHandler(this)
    }

    fun dispose() {
        installListener?.let(manager::unregisterListener)
        installListener = null
        eventSink = null
        methodChannel.setMethodCallHandler(null)
        eventChannel.setStreamHandler(null)
    }

    fun handleActivityResult(resultCode: Int) {
        val value =
            when (resultCode) {
                Activity.RESULT_OK -> RESULT_SUCCESS
                Activity.RESULT_CANCELED -> RESULT_CANCELED
                else -> RESULT_FAILED
            }
        pendingResult?.success(value)
        pendingResult = null
    }

    private fun handleMethod(
        call: MethodCall,
        result: MethodChannel.Result,
    ) {
        when (call.method) {
            "checkForUpdate" -> checkForUpdate(result)
            "startUpdate" -> startUpdate(call, result)
            "completeUpdate" -> completeUpdate(result)
            else -> result.notImplemented()
        }
    }

    private fun checkForUpdate(result: MethodChannel.Result) {
        manager.appUpdateInfo
            .addOnSuccessListener { result.success(serialize(it)) }
            .addOnFailureListener {
                result.error("CHECK_UPDATE_FAILED", it.localizedMessage, null)
            }
    }

    private fun startUpdate(
        call: MethodCall,
        result: MethodChannel.Result,
    ) {
        if (pendingResult != null) {
            result.error("UPDATE_RUNNING", "An update flow is already active", null)
            return
        }
        val updateType =
            if (call.argument<Boolean>("immediate") == true) {
                AppUpdateType.IMMEDIATE
            } else {
                AppUpdateType.FLEXIBLE
            }
        pendingResult = result
        manager.appUpdateInfo
            .addOnSuccessListener { info ->
                val available =
                    info.updateAvailability() == UpdateAvailability.UPDATE_AVAILABLE ||
                        info.updateAvailability() ==
                        UpdateAvailability.DEVELOPER_TRIGGERED_UPDATE_IN_PROGRESS
                if (!available || !info.isUpdateTypeAllowed(updateType)) {
                    pendingResult?.error(
                        "UPDATE_NOT_AVAILABLE",
                        "The selected update flow is unavailable",
                        null,
                    )
                    pendingResult = null
                    return@addOnSuccessListener
                }
                val options = AppUpdateOptions.newBuilder(updateType).build()
                if (!manager.startUpdateFlowForResult(info, updateLauncher, options)) {
                    pendingResult?.error(
                        "UPDATE_START_FAILED",
                        "Unable to start the update flow",
                        null,
                    )
                    pendingResult = null
                }
            }.addOnFailureListener {
                pendingResult?.error("CHECK_UPDATE_FAILED", it.localizedMessage, null)
                pendingResult = null
            }
    }

    private fun completeUpdate(result: MethodChannel.Result) {
        manager
            .completeUpdate()
            .addOnSuccessListener { result.success(null) }
            .addOnFailureListener {
                result.error("COMPLETE_UPDATE_FAILED", it.localizedMessage, null)
            }
    }

    private fun serialize(info: AppUpdateInfo): Map<String, Any?> =
        mapOf(
            "updateAvailability" to info.updateAvailability(),
            "installStatus" to info.installStatus(),
            "isImmediateUpdateAllowed" to info.isUpdateTypeAllowed(AppUpdateType.IMMEDIATE),
            "isFlexibleUpdateAllowed" to info.isUpdateTypeAllowed(AppUpdateType.FLEXIBLE),
        )

    override fun onListen(
        arguments: Any?,
        events: EventChannel.EventSink?,
    ) {
        eventSink = events
        installListener =
            InstallStateUpdatedListener { state ->
                eventSink?.success(mapOf("status" to state.installStatus()))
            }
        manager.registerListener(installListener!!)
    }

    override fun onCancel(arguments: Any?) {
        installListener?.let(manager::unregisterListener)
        installListener = null
        eventSink = null
    }

    private companion object {
        const val METHOD_CHANNEL = "preconnect/app_update"
        const val EVENT_CHANNEL = "preconnect/app_update_events"
        const val RESULT_SUCCESS = 0
        const val RESULT_CANCELED = 1
        const val RESULT_FAILED = 2
    }
}
