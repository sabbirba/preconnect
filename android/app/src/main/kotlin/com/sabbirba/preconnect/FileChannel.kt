package com.sabbirba.preconnect

import android.app.Activity
import android.content.Intent
import androidx.core.content.FileProvider
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.io.File

class FileChannel(
    private val activity: Activity,
    messenger: BinaryMessenger,
) {
    private val channel = MethodChannel(messenger, "preconnect/file")

    fun configure() {
        channel.setMethodCallHandler { call, result ->
            if (call.method != "open") {
                result.notImplemented()
                return@setMethodCallHandler
            }
            val path = call.argument<String>("path")?.trim().orEmpty()
            val file = File(path)
            if (path.isEmpty() || !file.isFile) {
                result.success(false)
                return@setMethodCallHandler
            }
            try {
                val uri =
                    FileProvider.getUriForFile(
                        activity,
                        "${activity.packageName}.fileprovider",
                        file,
                    )
                val intent =
                    Intent(Intent.ACTION_VIEW).apply {
                        setDataAndType(
                            uri,
                            activity.contentResolver.getType(uri) ?: "application/pdf",
                        )
                        addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                    }
                activity.startActivity(Intent.createChooser(intent, null))
                result.success(true)
            } catch (error: Exception) {
                result.error("OPEN_FILE_FAILED", error.localizedMessage, null)
            }
        }
    }

    fun dispose() {
        channel.setMethodCallHandler(null)
    }
}
