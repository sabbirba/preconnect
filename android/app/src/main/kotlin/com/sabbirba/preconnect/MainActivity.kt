package com.sabbirba.preconnect

import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import android.net.NetworkRequest
import android.net.wifi.WifiInfo
import android.net.wifi.WifiManager
import android.net.wifi.WifiNetworkSuggestion
import android.os.Build
import android.os.Bundle
import android.os.Looper
import com.android.installreferrer.api.InstallReferrerClient
import com.android.installreferrer.api.InstallReferrerStateListener
import com.google.android.play.core.integrity.IntegrityManagerFactory
import com.google.android.play.core.integrity.StandardIntegrityManager
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterFragmentActivity() {
    private val shortcutExtraKey = "flutter_shortcut"
    private val shortcutPrefsKey = "flutter.pending_shortcut_action"
    private var standardTokenProvider: StandardIntegrityManager.StandardIntegrityTokenProvider? = null
    private val integrityManager by lazy { IntegrityManagerFactory.createStandard(applicationContext) }

    private val connectivityManager by lazy {
        getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
    }
    private val wifiManager by lazy {
        applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager
    }

    private var networkCallback: ConnectivityManager.NetworkCallback? = null
    private var networkEventSink: EventChannel.EventSink? = null
    private val networkPrefs by lazy {
        getSharedPreferences("preconnect.network_assist", Context.MODE_PRIVATE)
    }
    private lateinit var adsBridge: AdsBridge

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        cacheShortcutAction(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        cacheShortcutAction(intent)
    }

    override fun onDestroy() {
        unregisterNetworkCallback()
        super.onDestroy()
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
        adsBridge = AdsBridge(this)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, AdsBridge.channelName)
            .setMethodCallHandler { call, result ->
                adsBridge.handle(call, result)
            }
        configureIntegrityChannel(flutterEngine)
        configureInstallReferrerChannel(flutterEngine)
        configureBuildInfoChannel(flutterEngine)
        configureNetworkAssistChannels(flutterEngine)
    }

    private fun configureBuildInfoChannel(flutterEngine: FlutterEngine) {
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "preconnect/build_info")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "getBuildInfo" -> result.success(currentBuildInfo())
                    else -> result.notImplemented()
                }
            }
    }

    @Suppress("DEPRECATION")
    private fun currentBuildInfo(): Map<String, String> {
        val packageInfo = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            packageManager.getPackageInfo(
                packageName,
                PackageManager.PackageInfoFlags.of(0),
            )
        } else {
            packageManager.getPackageInfo(packageName, 0)
        }
        val buildNumber = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            packageInfo.longVersionCode.toString()
        } else {
            packageInfo.versionCode.toString()
        }
        return mapOf(
            "version" to (packageInfo.versionName ?: ""),
            "buildNumber" to buildNumber,
        )
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
        call: MethodCall,
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
        call: MethodCall,
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
            deliverOnMainThread {
                result.success(payload)
            }
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

    private fun configureNetworkAssistChannels(flutterEngine: FlutterEngine) {
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "preconnect/network_assist")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "getNetworkStatus" -> result.success(currentNetworkStatus())
                    "addWifiSuggestion" -> addWifiSuggestion(call, result)
                    "removeAllWifiSuggestions" -> removeAllWifiSuggestions(result)
                    "getAndClearPostConnectionEvent" -> result.success(getAndClearPostConnectionEvent())
                    else -> result.notImplemented()
                }
            }

        EventChannel(flutterEngine.dartExecutor.binaryMessenger, "preconnect/network_assist_events")
            .setStreamHandler(
                object : EventChannel.StreamHandler {
                    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                        networkEventSink = events
                        registerNetworkCallback()
                        emitNetworkStatus()
                    }

                    override fun onCancel(arguments: Any?) {
                        networkEventSink = null
                        unregisterNetworkCallback()
                    }
                },
            )
    }

    private fun addWifiSuggestion(call: MethodCall, result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) {
            result.success(mapOf("status" to "unsupported"))
            return
        }

        val ssid = call.argument<String>("ssid")?.trim().orEmpty()
        val password = call.argument<String>("password")?.trim().orEmpty()
        val securityType = call.argument<String>("securityType")?.trim()?.lowercase().orEmpty()
        if (ssid.isEmpty()) {
            result.success(mapOf("status" to "invalid-ssid"))
            return
        }

        try {
            clearExistingSuggestionsForRefresh()
            val builder = WifiNetworkSuggestion.Builder().setSsid(ssid)
            when (securityType) {
                "owe", "enhanced_open", "enhanced-open" -> {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                        builder.setIsEnhancedOpen(true)
                    }
                }
                "wpa2" -> {
                    if (password.isNotEmpty()) {
                        builder.setWpa2Passphrase(password)
                    }
                }
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                builder.setIsAppInteractionRequired(true)
            }
            val suggestion = builder.build()
            val statusCode = wifiManager.addNetworkSuggestions(listOf(suggestion))
            val status = when (statusCode) {
                WifiManager.STATUS_NETWORK_SUGGESTIONS_SUCCESS -> "success"
                WifiManager.STATUS_NETWORK_SUGGESTIONS_ERROR_ADD_DUPLICATE -> "duplicate"
                WifiManager.STATUS_NETWORK_SUGGESTIONS_ERROR_ADD_EXCEEDS_MAX_PER_APP -> "exceeds-max"
                WifiManager.STATUS_NETWORK_SUGGESTIONS_ERROR_APP_DISALLOWED -> "app-disallowed"
                WifiManager.STATUS_NETWORK_SUGGESTIONS_ERROR_INTERNAL -> "internal-error"
                WifiManager.STATUS_NETWORK_SUGGESTIONS_ERROR_REMOVE_INVALID -> "remove-invalid"
                WifiManager.STATUS_NETWORK_SUGGESTIONS_ERROR_ADD_NOT_ALLOWED -> "add-not-allowed"
                WifiManager.STATUS_NETWORK_SUGGESTIONS_ERROR_ADD_INVALID -> "add-invalid"
                WifiManager.STATUS_NETWORK_SUGGESTIONS_ERROR_RESTRICTED_BY_ADMIN -> "restricted-by-admin"
                else -> "error-$statusCode"
            }
            result.success(mapOf("status" to status, "statusCode" to statusCode))
        } catch (security: SecurityException) {
            result.success(
                mapOf(
                    "status" to "permission-required",
                    "reason" to (security.message ?: "SecurityException"),
                ),
            )
        } catch (e: Exception) {
            result.success(mapOf("status" to "error", "reason" to (e.message ?: "Unknown error")))
        }
    }

    private fun clearExistingSuggestionsForRefresh() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) return
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                wifiManager.removeNetworkSuggestions(
                    emptyList(),
                    WifiManager.ACTION_REMOVE_SUGGESTION_LINGER,
                )
            } else {
                wifiManager.removeNetworkSuggestions(emptyList())
            }
        } catch (_: Exception) {
        }
    }

    private fun removeAllWifiSuggestions(result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) {
            result.success(mapOf("status" to "unsupported"))
            return
        }
        try {
            val statusCode = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                wifiManager.removeNetworkSuggestions(
                    emptyList(),
                    WifiManager.ACTION_REMOVE_SUGGESTION_DISCONNECT,
                )
            } else {
                wifiManager.removeNetworkSuggestions(emptyList())
            }
            val status = when (statusCode) {
                WifiManager.STATUS_NETWORK_SUGGESTIONS_SUCCESS -> "success"
                WifiManager.STATUS_NETWORK_SUGGESTIONS_ERROR_APP_DISALLOWED -> "app-disallowed"
                WifiManager.STATUS_NETWORK_SUGGESTIONS_ERROR_INTERNAL -> "internal-error"
                WifiManager.STATUS_NETWORK_SUGGESTIONS_ERROR_REMOVE_INVALID -> "remove-invalid"
                WifiManager.STATUS_NETWORK_SUGGESTIONS_ERROR_RESTRICTED_BY_ADMIN -> "restricted-by-admin"
                else -> "error-$statusCode"
            }
            result.success(mapOf("status" to status, "statusCode" to statusCode))
        } catch (security: SecurityException) {
            result.success(
                mapOf(
                    "status" to "permission-required",
                    "reason" to (security.message ?: "SecurityException"),
                ),
            )
        } catch (e: Exception) {
            result.success(mapOf("status" to "error", "reason" to (e.message ?: "Unknown error")))
        }
    }

    private fun getAndClearPostConnectionEvent(): Map<String, Any> {
        val pending = networkPrefs.getBoolean("wifi_post_connection_pending", false)
        if (!pending) {
            return mapOf("pending" to false)
        }
        val payload = mutableMapOf<String, Any>(
            "pending" to true,
            "at" to networkPrefs.getLong("wifi_post_connection_at", 0L),
        )
        val ssid = networkPrefs.getString("wifi_post_connection_ssid", null)
        if (!ssid.isNullOrBlank()) {
            payload["ssid"] = ssid
        }
        networkPrefs
            .edit()
            .putBoolean("wifi_post_connection_pending", false)
            .remove("wifi_post_connection_ssid")
            .apply()
        return payload
    }

    private fun registerNetworkCallback() {
        if (networkCallback != null) return
        val callback = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            object : ConnectivityManager.NetworkCallback(
                ConnectivityManager.NetworkCallback.FLAG_INCLUDE_LOCATION_INFO,
            ) {
                override fun onAvailable(network: Network) {
                    emitNetworkStatus(network = network)
                }

                override fun onLost(network: Network) {
                    emitNetworkStatus()
                }

                override fun onCapabilitiesChanged(
                    network: Network,
                    networkCapabilities: NetworkCapabilities,
                ) {
                    emitNetworkStatus(network = network, capabilities = networkCapabilities)
                }
            }
        } else {
            object : ConnectivityManager.NetworkCallback() {
                override fun onAvailable(network: Network) {
                    emitNetworkStatus(network = network)
                }

                override fun onLost(network: Network) {
                    emitNetworkStatus()
                }

                override fun onCapabilitiesChanged(
                    network: Network,
                    networkCapabilities: NetworkCapabilities,
                ) {
                    emitNetworkStatus(network = network, capabilities = networkCapabilities)
                }
            }
        }
        val request = NetworkRequest.Builder()
            .addCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)
            .build()
        try {
            connectivityManager.registerNetworkCallback(request, callback)
            networkCallback = callback
        } catch (_: Exception) {
            networkCallback = null
        }
    }

    private fun unregisterNetworkCallback() {
        val callback = networkCallback ?: return
        try {
            connectivityManager.unregisterNetworkCallback(callback)
        } catch (_: Exception) {
        } finally {
            networkCallback = null
        }
    }

    private fun emitNetworkStatus(
        network: Network? = null,
        capabilities: NetworkCapabilities? = null,
    ) {
        val payload = currentNetworkStatus(
            networkOverride = network,
            capabilitiesOverride = capabilities,
        )
        deliverOnMainThread {
            networkEventSink?.success(payload)
        }
    }

    private fun deliverOnMainThread(action: () -> Unit) {
        if (Looper.myLooper() == Looper.getMainLooper()) {
            action()
        } else {
            runOnUiThread(action)
        }
    }

    private fun currentNetworkStatus(
        networkOverride: Network? = null,
        capabilitiesOverride: NetworkCapabilities? = null,
    ): Map<String, Any> {
        val network = networkOverride ?: connectivityManager.activeNetwork
        if (network == null) {
            return mapOf(
                "connected" to false,
                "validated" to false,
                "captive" to false,
                "transport" to "none",
                "androidApi" to Build.VERSION.SDK_INT,
            )
        }

        val caps = capabilitiesOverride ?: connectivityManager.getNetworkCapabilities(network)
        val transport = when {
            caps?.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) == true -> "wifi"
            caps?.hasTransport(NetworkCapabilities.TRANSPORT_CELLULAR) == true -> "cellular"
            caps?.hasTransport(NetworkCapabilities.TRANSPORT_ETHERNET) == true -> "ethernet"
            caps?.hasTransport(NetworkCapabilities.TRANSPORT_VPN) == true -> "vpn"
            else -> "other"
        }

        val payload = mutableMapOf<String, Any>(
            "connected" to true,
            "validated" to (caps?.hasCapability(NetworkCapabilities.NET_CAPABILITY_VALIDATED) == true),
            "captive" to (caps?.hasCapability(NetworkCapabilities.NET_CAPABILITY_CAPTIVE_PORTAL) == true),
            "transport" to transport,
            "androidApi" to Build.VERSION.SDK_INT,
        )
        if (transport == "wifi") {
            val ssid = currentWifiSsid()
            if (!ssid.isNullOrBlank()) {
                payload["ssid"] = ssid
            }
        }
        val captiveWifiData = currentCaptiveWifiData(caps)
        if (captiveWifiData.isNotEmpty()) {
            payload.putAll(captiveWifiData)
        }
        return payload
    }

    private fun currentCaptiveWifiData(caps: NetworkCapabilities?): Map<String, Any> {
        if (caps == null) return emptyMap()
        return try {
            val getCaptivePortalData = NetworkCapabilities::class.java.methods.firstOrNull { method ->
                method.name == "getCaptivePortalData" && method.parameterTypes.isEmpty()
            } ?: return emptyMap()
            val captiveWifiData = getCaptivePortalData.invoke(caps) ?: return emptyMap()

            val payload = mutableMapOf<String, Any>()

            val getUserPortalUrl = captiveWifiData.javaClass.methods.firstOrNull { method ->
                method.name == "getUserPortalUrl" && method.parameterTypes.isEmpty()
            }
            val rawUrl = getUserPortalUrl
                ?.invoke(captiveWifiData)
                ?.toString()
                ?.trim()
                .orEmpty()
            if (rawUrl.isNotEmpty()) {
                payload["captiveWifiUrl"] = rawUrl
            }

            val isSessionExtendable = captiveWifiData.javaClass.methods.firstOrNull { method ->
                method.name == "isSessionExtendable" && method.parameterTypes.isEmpty()
            }?.invoke(captiveWifiData) as? Boolean
            if (isSessionExtendable != null) {
                payload["canExtendSession"] = isSessionExtendable
            }

            val expiryMillis = (captiveWifiData.javaClass.methods.firstOrNull { method ->
                method.name == "getExpiryTimeMillis" && method.parameterTypes.isEmpty()
            }?.invoke(captiveWifiData) as? Long) ?: -1L
            if (expiryMillis > 0L) {
                payload["sessionExpiryTimeMillis"] = expiryMillis
            }

            payload
        } catch (_: Exception) {
            emptyMap()
        }
    }

    private fun currentWifiSsid(): String? {
        return try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                val network = connectivityManager.activeNetwork ?: return null
                val caps = connectivityManager.getNetworkCapabilities(network) ?: return null
                val wifiInfo = caps.transportInfo as? WifiInfo
                normalizeSsid(wifiInfo?.ssid?.trim().orEmpty())
            } else {
                @Suppress("DEPRECATION")
                val raw = wifiManager.connectionInfo?.ssid?.trim().orEmpty()
                normalizeSsid(raw)
            }
        } catch (_: Exception) {
            null
        }
    }

    private fun normalizeSsid(raw: String): String? {
        if (raw.isBlank()) return null
        if (raw == WifiManager.UNKNOWN_SSID) return null
        return if (raw.length >= 2 && raw.startsWith('"') && raw.endsWith('"')) {
            raw.substring(1, raw.length - 1)
        } else {
            raw
        }.trim().ifEmpty { null }
    }
}
