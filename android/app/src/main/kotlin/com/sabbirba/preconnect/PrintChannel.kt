package com.sabbirba.preconnect

import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

internal class PrintChannel(
    private val printPdf: (MethodCall, MethodChannel.Result) -> Unit,
) {
    fun configure(messenger: BinaryMessenger) {
        MethodChannel(messenger, CHANNEL).setMethodCallHandler { call, result ->
            if (call.method == "printPdf") {
                printPdf(call, result)
            } else {
                result.notImplemented()
            }
        }
    }

    private companion object {
        const val CHANNEL = "preconnect/native_print"
    }
}
