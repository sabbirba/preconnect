package com.sabbirba.preconnect

import com.android.installreferrer.api.InstallReferrerClient
import com.android.installreferrer.api.InstallReferrerStateListener
import android.content.Intent
import android.os.Bundle
import com.google.android.play.core.integrity.IntegrityManagerFactory
import com.google.android.play.core.integrity.StandardIntegrityManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val shortcutExtraKey = "flutter_shortcut"
    private val shortcutPrefsKey = "flutter.pending_shortcut_action"
    private var standardTokenProvider: StandardIntegrityManager.StandardIntegrityTokenProvider? = null
    private val integrityManager by lazy { IntegrityManagerFactory.createStandard(applicationContext) }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        cacheShortcutAction(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        cacheShortcutAction(intent)
    }

    private fun cacheShortcutAction(intent: Intent?) {
        if (intent == null) return
        val shortcutAction = intent.getStringExtra(shortcutExtraKey)
        val launchAction = intent.action
        val action = when {
            !shortcutAction.isNullOrBlank() -> shortcutAction
            !launchAction.isNullOrBlank() && launchAction.startsWith("quick.") -> launchAction
            else -> null
        }
        if (action.isNullOrBlank()) return
        getSharedPreferences("FlutterSharedPreferences", MODE_PRIVATE)
            .edit()
            .putString(shortcutPrefsKey, action)
            .apply()
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        configureIntegrityChannel(flutterEngine)
        configureInstallReferrerChannel(flutterEngine)
    }

    private fun configureIntegrityChannel(flutterEngine: FlutterEngine) {
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "preconnect/play_integrity")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "prepare" -> prepareIntegrityProvider(call, result)
                    "requestToken" -> requestIntegrityToken(call, result)
                    else -> result.notImplemented()
                }
            }
    }

    private fun prepareIntegrityProvider(
        call: io.flutter.plugin.common.MethodCall,
        result: MethodChannel.Result,
    ) {
        val cloudProjectNumber = when (val raw = call.argument<Any>("cloudProjectNumber")) {
            is Int -> raw.toLong()
            is Long -> raw
            is Number -> raw.toLong()
            else -> null
        }
        if (cloudProjectNumber == null || cloudProjectNumber <= 0L) {
            result.error("INVALID_PROJECT", "Missing cloud project number", null)
            return
        }

        val prepareRequest = StandardIntegrityManager.PrepareIntegrityTokenRequest.builder()
            .setCloudProjectNumber(cloudProjectNumber)
            .build()

        integrityManager.prepareIntegrityToken(prepareRequest)
            .addOnSuccessListener { provider ->
                standardTokenProvider = provider
                result.success(true)
            }
            .addOnFailureListener { exception ->
                result.error(
                    "INTEGRITY_PREPARE_ERROR",
                    exception.message ?: "Failed to prepare integrity provider",
                    null,
                )
            }
    }

    private fun requestIntegrityToken(
        call: io.flutter.plugin.common.MethodCall,
        result: MethodChannel.Result,
    ) {
        val requestHash = call.argument<String>("requestHash")
        if (requestHash.isNullOrBlank()) {
            result.error("INVALID_REQUEST_HASH", "Missing request hash", null)
            return
        }

        val provider = standardTokenProvider
        if (provider == null) {
            result.error("INTEGRITY_NOT_PREPARED", "Integrity provider is not prepared", null)
            return
        }

        val request = StandardIntegrityManager.StandardIntegrityTokenRequest.builder()
            .setRequestHash(requestHash)
            .build()

        provider.request(request)
            .addOnSuccessListener { token ->
                result.success(token.token())
            }
            .addOnFailureListener { exception ->
                standardTokenProvider = null
                result.error(
                    "INTEGRITY_ERROR",
                    exception.message ?: "Failed to request integrity token",
                    null,
                )
            }
    }

    private fun configureInstallReferrerChannel(flutterEngine: FlutterEngine) {
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "preconnect/play_install_referrer")
            .setMethodCallHandler { call, result ->
                if (call.method == "getInstallReferrer") {
                    getInstallReferrer(result)
                } else {
                    result.notImplemented()
                }
            }
    }

    private fun getInstallReferrer(result: MethodChannel.Result) {
        val client = InstallReferrerClient.newBuilder(applicationContext).build()
        var completed = false
        fun complete(payload: Map<String, Any>) {
            if (completed) return
            completed = true
            result.success(payload)
        }

        client.startConnection(
            object : InstallReferrerStateListener {
                override fun onInstallReferrerSetupFinished(responseCode: Int) {
                    try {
                        if (responseCode != InstallReferrerClient.InstallReferrerResponse.OK) {
                            complete(emptyMap<String, Any>())
                            return
                        }

                        val details = client.installReferrer
                        val payload = mutableMapOf<String, Any>(
                            "installReferrer" to details.installReferrer,
                            "referrerClickTimestampSeconds" to details.referrerClickTimestampSeconds,
                            "installBeginTimestampSeconds" to details.installBeginTimestampSeconds,
                            "googlePlayInstantParam" to details.googlePlayInstantParam,
                        )
                        val installVersion = details.installVersion
                        if (!installVersion.isNullOrBlank()) {
                            payload["installVersion"] = installVersion
                        }
                        complete(payload)
                    } catch (_: Exception) {
                        complete(emptyMap<String, Any>())
                    } finally {
                        client.endConnection()
                    }
                }

                override fun onInstallReferrerServiceDisconnected() {
                    complete(emptyMap<String, Any>())
                    client.endConnection()
                }
            },
        )
    }
}
