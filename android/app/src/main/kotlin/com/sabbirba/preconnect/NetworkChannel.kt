package com.sabbirba.preconnect

import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

internal class NetworkChannel(
    private val messenger: BinaryMessenger,
    private val methodHandler: MethodChannel.MethodCallHandler,
    private val onListen: (EventChannel.EventSink?) -> Unit,
    private val onCancel: () -> Unit,
) {
    fun configure() {
        MethodChannel(messenger, METHOD_CHANNEL).setMethodCallHandler(methodHandler)
        EventChannel(messenger, EVENT_CHANNEL).setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(
                    arguments: Any?,
                    events: EventChannel.EventSink?,
                ) {
                    onListen(events)
                }

                override fun onCancel(arguments: Any?) {
                    onCancel()
                }
            },
        )
    }

    private companion object {
        const val METHOD_CHANNEL = "preconnect/network_assist"
        const val EVENT_CHANNEL = "preconnect/network_assist_events"
    }
}
