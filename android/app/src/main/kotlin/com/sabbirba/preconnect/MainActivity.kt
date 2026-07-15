package com.sabbirba.preconnect

import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.pdf.PdfRenderer
import android.net.CaptivePortal
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import android.net.NetworkRequest
import android.net.Uri
import android.net.wifi.WifiInfo
import android.net.wifi.WifiManager
import android.net.wifi.WifiNetworkSuggestion
import android.os.Build
import android.os.Bundle
import android.os.PowerManager
import android.os.CancellationSignal
import android.os.Looper
import android.os.ParcelFileDescriptor
import android.provider.AlarmClock
import android.provider.Settings
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import android.print.PageRange
import android.print.PrintAttributes
import android.print.PrintDocumentAdapter
import android.print.PrintDocumentInfo
import android.print.PrintManager
import android.graphics.pdf.PdfDocument
import java.io.File
import java.io.FileOutputStream
import java.util.ArrayList

class MainActivity : FlutterFragmentActivity() {
    private val shortcutExtraKey = "flutter_shortcut"
    private val shortcutPrefsKey = "flutter.pending_shortcut_action"

    private var captivePortalUrl: String? = null
    private var intentNetwork: Network? = null
    private var captivePortal: CaptivePortal? = null

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

    private val REQUEST_CODE_LOCATION_SETTINGS = 1092
    private var locationSettingsResult: MethodChannel.Result? = null
    private val mainHandler = android.os.Handler(Looper.getMainLooper())

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == REQUEST_CODE_LOCATION_SETTINGS) {
            val success = resultCode == RESULT_OK
            locationSettingsResult?.success(success)
            locationSettingsResult = null
        }
    }

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
        ignoreNetwork()
        super.onDestroy()
    }

    private fun cacheShortcutAction(intent: Intent?) {
        if (intent == null) return
        val shortcutAction = intent.getStringExtra(shortcutExtraKey)
        val launchAction = intent.action

        val portalUrl = intent.getStringExtra(ConnectivityManager.EXTRA_CAPTIVE_PORTAL_URL)
        if (!portalUrl.isNullOrBlank()) {
            captivePortalUrl = portalUrl
        }
        val network = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            intent.getParcelableExtra(ConnectivityManager.EXTRA_NETWORK, Network::class.java)
        } else {
            @Suppress("DEPRECATION")
            intent.getParcelableExtra(ConnectivityManager.EXTRA_NETWORK) as? Network
        }
        if (network != null) {
            intentNetwork = network
        }
        val portal = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            intent.getParcelableExtra(ConnectivityManager.EXTRA_CAPTIVE_PORTAL, CaptivePortal::class.java)
        } else {
            @Suppress("DEPRECATION")
            intent.getParcelableExtra(ConnectivityManager.EXTRA_CAPTIVE_PORTAL) as? CaptivePortal
        }
        if (portal != null) {
            captivePortal = portal
        }

        val action = when {
            !shortcutAction.isNullOrBlank() -> shortcutAction
            !launchAction.isNullOrBlank() && launchAction.startsWith("quick.") -> launchAction
            !launchAction.isNullOrBlank() && (launchAction == ConnectivityManager.ACTION_CAPTIVE_PORTAL_SIGN_IN || launchAction == "android.net.conn.CAPTIVE_PORTAL") -> "captive_wifi"
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
        configureAndroidAlarmChannel(flutterEngine)
        configureNetworkAssistChannels(flutterEngine)
        configureQuietModeChannel(flutterEngine)
        configureNativePrintChannel(flutterEngine)
        configureBackgroundPermissionChannel(flutterEngine)
    }

    private fun configureAndroidAlarmChannel(flutterEngine: FlutterEngine) {
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "preconnect/android_alarm")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "setAlarm" -> {
                        val hour = (call.argument<Number>("hour")?.toInt()) ?: run {
                            result.success(false)
                            return@setMethodCallHandler
                        }
                        val minute = (call.argument<Number>("minute")?.toInt()) ?: run {
                            result.success(false)
                            return@setMethodCallHandler
                        }
                        val message = call.argument<String>("message") ?: ""
                        val days = call.argument<List<Int>>("days") ?: emptyList()
                        val alarmIntent = Intent(AlarmClock.ACTION_SET_ALARM).apply {
                            putExtra(AlarmClock.EXTRA_HOUR, hour)
                            putExtra(AlarmClock.EXTRA_MINUTES, minute)
                            putExtra(AlarmClock.EXTRA_MESSAGE, message)
                            putExtra(AlarmClock.EXTRA_SKIP_UI, false)
                            if (days.isNotEmpty()) {
                                putIntegerArrayListExtra(AlarmClock.EXTRA_DAYS, ArrayList(days))
                            }
                            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        }
                        try {
                            startActivity(alarmIntent)
                            result.success(true)
                        } catch (_: ActivityNotFoundException) {
                            result.success(false)
                        } catch (_: Exception) {
                            result.success(false)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun configureNetworkAssistChannels(flutterEngine: FlutterEngine) {
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "preconnect/network_assist")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "getNetworkStatus" -> getNetworkStatusWithLocationInfo(result)
                    "isLocationServiceEnabled" -> {
                        val lm = getSystemService(Context.LOCATION_SERVICE) as android.location.LocationManager
                        val enabled = try {
                            lm.isProviderEnabled(android.location.LocationManager.GPS_PROVIDER) ||
                                    lm.isProviderEnabled(android.location.LocationManager.NETWORK_PROVIDER)
                        } catch (e: Exception) {
                            false
                        }
                        result.success(enabled)
                    }
                    "openLocationSettings" -> {
                        try {
                            locationSettingsResult = result
                            val locationRequest = com.google.android.gms.location.LocationRequest.Builder(
                                com.google.android.gms.location.Priority.PRIORITY_HIGH_ACCURACY, 5000
                            ).build()
                            val builder = com.google.android.gms.location.LocationSettingsRequest.Builder()
                                .addLocationRequest(locationRequest)
                            val client = com.google.android.gms.location.LocationServices.getSettingsClient(this)
                            val task = client.checkLocationSettings(builder.build())
                            task.addOnCompleteListener { t ->
                                try {
                                    t.getResult(com.google.android.gms.common.api.ApiException::class.java)
                                    result.success(true)
                                    locationSettingsResult = null
                                } catch (exception: com.google.android.gms.common.api.ApiException) {
                                    when (exception.statusCode) {
                                        com.google.android.gms.location.LocationSettingsStatusCodes.RESOLUTION_REQUIRED -> {
                                            try {
                                                val resolvable = exception as com.google.android.gms.common.api.ResolvableApiException
                                                resolvable.startResolutionForResult(this, REQUEST_CODE_LOCATION_SETTINGS)
                                            } catch (e: Exception) {
                                                result.success(false)
                                                locationSettingsResult = null
                                            }
                                        }
                                        else -> {
                                            val intent = Intent(Settings.ACTION_LOCATION_SOURCE_SETTINGS)
                                            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                                            startActivity(intent)
                                            result.success(true)
                                            locationSettingsResult = null
                                        }
                                    }
                                }
                            }
                        } catch (e: Exception) {
                            try {
                                val intent = Intent(Settings.ACTION_LOCATION_SOURCE_SETTINGS)
                                intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                                startActivity(intent)
                                result.success(true)
                            } catch (e2: Exception) {
                                result.success(false)
                            }
                        }
                    }
                    "openWifiSettings" -> {
                        try {
                            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                                val intent = Intent(Settings.Panel.ACTION_WIFI)
                                intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                                startActivity(intent)
                                result.success(true)
                            } else {
                                val intent = Intent(Settings.ACTION_WIFI_SETTINGS)
                                intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                                startActivity(intent)
                                result.success(true)
                            }
                        } catch (e: Exception) {
                            try {
                                val intent = Intent(Settings.ACTION_WIFI_SETTINGS)
                                intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                                startActivity(intent)
                                result.success(true)
                            } catch (e2: Exception) {
                                result.success(false)
                            }
                        }
                    }
                    "getWifiScanResults" -> {
                        val hasLocation = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                            checkSelfPermission(android.Manifest.permission.ACCESS_FINE_LOCATION) == PackageManager.PERMISSION_GRANTED
                        } else {
                            true
                        }
                        val hasNearby = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                            checkSelfPermission("android.permission.NEARBY_WIFI_DEVICES") == PackageManager.PERMISSION_GRANTED
                        } else {
                            true
                        }
                        if (hasLocation || hasNearby) {
                            try {
                                @Suppress("DEPRECATION")
                                wifiManager.startScan()
                            } catch (_: Exception) {}
                            val list = try {
                                wifiManager.scanResults.mapNotNull { it.SSID }.filter { it.isNotBlank() }.distinct()
                            } catch (e: Exception) {
                                emptyList<String>()
                            }
                            result.success(list)
                        } else {
                            result.success(emptyList<String>())
                        }
                    }
                    "addWifiSuggestion" -> addWifiSuggestion(call, result)
                    "removeAllWifiSuggestions" -> removeAllWifiSuggestions(result)
                    "getAndClearPostConnectionEvent" -> result.success(getAndClearPostConnectionEvent())
                    "bindToWifiNetwork" -> result.success(bindToWifiNetwork())
                    "unbindFromWifiNetwork" -> {
                        unbindFromWifiNetwork()
                        result.success(true)
                    }
                    "reportCaptivePortalDismissed" -> {
                        reportCaptivePortalDismissed()
                        result.success(true)
                    }
                    "ignoreNetwork" -> {
                        ignoreNetwork()
                        result.success(true)
                    }
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

    private fun configureNativePrintChannel(flutterEngine: FlutterEngine) {
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "preconnect/native_print")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "printPdf" -> printPdf(call, result)
                    else -> result.notImplemented()
                }
            }
    }

    private fun configureQuietModeChannel(flutterEngine: FlutterEngine) {
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "preconnect/quiet_mode")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "setQuietMode" -> setQuietMode(call, result)
                    "openQuietModeSettings" -> openQuietModeSettings(result)
                    else -> result.notImplemented()
                }
            }
    }

    private fun setQuietMode(call: MethodCall, result: MethodChannel.Result) {
        val enabled = call.argument<Boolean>("enabled") == true
        val source = call.argument<String>("source")?.trim().orEmpty().ifBlank { "sync" }
        val windows = parseQuietModeWindows(call.argument<List<*>>("windows"))
        result.success(
            QuietModeAutomation.handleSetQuietMode(
                context = this,
                enabled = enabled,
                source = source,
                windows = windows,
            ),
        )
    }

    private fun parseQuietModeWindows(rawWindows: List<*>?): List<QuietModeWindow> {
        if (rawWindows.isNullOrEmpty()) return emptyList()
        return rawWindows.mapNotNull { item ->
            val rawMap = item as? Map<*, *> ?: return@mapNotNull null
            val startAt = (rawMap["startAt"] as? Number)?.toLong()
                ?: (rawMap["startAt"] as? String)?.toLongOrNull()
                ?: return@mapNotNull null
            val endAt = (rawMap["endAt"] as? Number)?.toLong()
                ?: (rawMap["endAt"] as? String)?.toLongOrNull()
                ?: return@mapNotNull null
            QuietModeWindow(
                startAtMillis = startAt,
                endAtMillis = endAt,
                source = rawMap["source"]?.toString().orEmpty(),
                label = rawMap["label"]?.toString().orEmpty(),
            )
        }
    }

    private fun openQuietModeSettings(result: MethodChannel.Result) {
        try {
            val intent = Intent(Settings.ACTION_NOTIFICATION_POLICY_ACCESS_SETTINGS).apply {
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            startActivity(intent)
            result.success(true)
        } catch (e: Exception) {
            result.success(false)
        }
    }


    private fun printPdf(call: MethodCall, result: MethodChannel.Result) {
        val filePath = call.argument<String>("filePath")?.trim().orEmpty()
        val jobName = call.argument<String>("jobName")?.trim().orEmpty().ifBlank {
            "PreConnect PDF"
        }
        if (filePath.isBlank()) {
            result.error("INVALID_PATH", "Missing file path", null)
            return
        }

        val source = File(filePath)
        if (!source.exists() || !source.isFile) {
            result.error("FILE_NOT_FOUND", "Selected PDF file was not found", null)
            return
        }

        val printManager = getSystemService(Context.PRINT_SERVICE) as? PrintManager
        if (printManager == null) {
            result.error("PRINT_UNAVAILABLE", "Print service unavailable", null)
            return
        }

        try {
            val adapter = PdfPrintDocumentAdapter(this, source, jobName)
            printManager.print(jobName, adapter, null)
            result.success(true)
        } catch (e: Exception) {
            result.error("PRINT_ERROR", e.message ?: "Failed to open print dialog", null)
        }
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
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                builder.setIsAppInteractionRequired(true)
                builder.setIsUserInteractionRequired(true)
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

    private fun getNetworkStatusWithLocationInfo(result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S && hasSsidPermission()) {
            val network = getWifiNetwork() ?: connectivityManager.activeNetwork
            if (network != null) {
                val oneShotCallback = object : ConnectivityManager.NetworkCallback(
                    ConnectivityManager.NetworkCallback.FLAG_INCLUDE_LOCATION_INFO
                ) {
                    private var done = false
                    override fun onCapabilitiesChanged(
                        net: Network,
                        networkCapabilities: NetworkCapabilities,
                    ) {
                        if (done) return
                        done = true
                        try {
                            connectivityManager.unregisterNetworkCallback(this)
                        } catch (_: Exception) {}
                        val payload = currentNetworkStatus(
                            networkOverride = net,
                            capabilitiesOverride = networkCapabilities,
                        ).toMutableMap()
                        if (!payload.containsKey("ssid") || payload["ssid"] == null) {
                            val wifiInfo = networkCapabilities.transportInfo as? WifiInfo
                            val ssid = normalizeSsid(wifiInfo?.ssid?.trim().orEmpty())
                            if (ssid != null) payload["ssid"] = ssid
                        }
                        mainHandler.post { result.success(payload) }
                    }
                    override fun onUnavailable() {
                        if (done) return
                        done = true
                        try { connectivityManager.unregisterNetworkCallback(this) } catch (_: Exception) {}
                        mainHandler.post { result.success(currentNetworkStatus()) }
                    }
                }
                try {
                    val request = NetworkRequest.Builder()
                        .addTransportType(NetworkCapabilities.TRANSPORT_WIFI)
                        .build()
                    connectivityManager.registerNetworkCallback(request, oneShotCallback)
                    return
                } catch (_: Exception) {}
            }
        }
        result.success(currentNetworkStatus())
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
            .addTransportType(NetworkCapabilities.TRANSPORT_WIFI)
            .addTransportType(NetworkCapabilities.TRANSPORT_CELLULAR)
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

    private fun bindToWifiNetwork(): Boolean {
        return try {
            val wifiNetwork = getWifiNetwork()
            if (wifiNetwork != null) {
                connectivityManager.bindProcessToNetwork(wifiNetwork)
                true
            } else {
                false
            }
        } catch (_: Exception) {
            false
        }
    }

    private fun unbindFromWifiNetwork() {
        try {
            connectivityManager.bindProcessToNetwork(null)
        } catch (_: Exception) {}
    }

    private fun reportCaptivePortalDismissed() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            captivePortal?.reportCaptivePortalDismissed()
            captivePortal = null
        }
    }

    private fun ignoreNetwork() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            captivePortal?.ignoreNetwork()
            captivePortal = null
        }
    }

    private fun getWifiNetwork(): Network? {
        return try {
            intentNetwork ?: connectivityManager.allNetworks.firstOrNull { net ->
                val caps = connectivityManager.getNetworkCapabilities(net)
                caps?.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) == true
            }
        } catch (_: Exception) {
            null
        }
    }

    private fun currentNetworkStatus(
        networkOverride: Network? = null,
        capabilitiesOverride: NetworkCapabilities? = null,
    ): Map<String, Any> {
        val network = networkOverride ?: getWifiNetwork() ?: connectivityManager.activeNetwork
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
            val gatewayAddress = currentGatewayAddress(network)
            if (!gatewayAddress.isNullOrBlank()) {
                payload["gatewayAddress"] = gatewayAddress
            }
            val ipAddress = getLocalIpAddress(network)
            if (!ipAddress.isNullOrBlank()) {
                payload["ipAddress"] = ipAddress
            }
            val wifiInfo = getWifiInfo(network, caps)
            val apMac = formatMacAddress(wifiInfo?.bssid)
            if (!apMac.isNullOrBlank()) {
                payload["apMac"] = apMac
            }
            val clientMac = getClientMacAddress()
            if (!clientMac.isNullOrBlank()) {
                payload["clientMac"] = clientMac
            }
        }
        val captiveWifiData = currentCaptiveWifiData(caps)
        if (captiveWifiData.isNotEmpty()) {
            payload.putAll(captiveWifiData)
        }
        if (transport == "wifi" && !payload.containsKey("captiveWifiUrl") && !captivePortalUrl.isNullOrBlank()) {
            payload["captiveWifiUrl"] = captivePortalUrl!!
        }
        return payload
    }

    private fun currentGatewayAddress(network: Network): String? {
        return try {
            val linkProperties = connectivityManager.getLinkProperties(network) ?: return null
            val route = linkProperties.routes.firstOrNull { it.isDefaultRoute }
            route?.gateway?.hostAddress
        } catch (_: Exception) {
            null
        }
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

    private fun hasSsidPermission(): Boolean {
        return checkSelfPermission(android.Manifest.permission.ACCESS_FINE_LOCATION) ==
            PackageManager.PERMISSION_GRANTED
    }

    private fun currentWifiSsid(): String? {
        if (!hasSsidPermission()) return null
        return try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                val network = connectivityManager.activeNetwork ?: return null
                val caps = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                    connectivityManager.getNetworkCapabilities(network)
                } else {
                    connectivityManager.getNetworkCapabilities(network)
                } ?: return null
                val wifiInfo = caps.transportInfo as? WifiInfo
                val fromCaps = normalizeSsid(wifiInfo?.ssid?.trim().orEmpty())
                if (fromCaps != null) return fromCaps
                @Suppress("DEPRECATION")
                val legacyInfo = wifiManager.connectionInfo
                normalizeSsid(legacyInfo?.ssid?.trim().orEmpty())
            } else {
                @Suppress("DEPRECATION")
                val info = wifiManager.connectionInfo
                normalizeSsid(info?.ssid?.trim().orEmpty())
            }
        } catch (_: Exception) {
            null
        }
    }

    private fun normalizeSsid(raw: String): String? {
        if (raw.isBlank()) return null
        if (raw == WifiManager.UNKNOWN_SSID) return null
        if (raw == "<unknown ssid>") return null
        return if (raw.length >= 2 && raw.startsWith('"') && raw.endsWith('"')) {
            raw.substring(1, raw.length - 1)
        } else {
            raw
        }.trim().ifEmpty { null }
    }

    private fun getLocalIpAddress(network: Network): String? {
        return try {
            val linkProperties = connectivityManager.getLinkProperties(network) ?: return null
            val linkAddresses = linkProperties.linkAddresses
            val ipv4Address = linkAddresses.firstOrNull {
                it.address is java.net.Inet4Address && !it.address.isLoopbackAddress
            }
            ipv4Address?.address?.hostAddress ?: linkAddresses.firstOrNull {
                !it.address.isLoopbackAddress
            }?.address?.hostAddress
        } catch (_: Exception) {
            null
        }
    }

    private fun getWifiInfo(network: Network, caps: NetworkCapabilities?): WifiInfo? {
        return try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                (caps ?: connectivityManager.getNetworkCapabilities(network))?.transportInfo as? WifiInfo
            } else {
                @Suppress("DEPRECATION")
                wifiManager.connectionInfo
            }
        } catch (_: Exception) {
            null
        }
    }

    private fun formatMacAddress(mac: String?): String? {
        if (mac == null || mac.isBlank()) return null
        if (mac.equals("02:00:00:00:00:00", ignoreCase = true)) return null
        val clean = mac.replace(":", "").replace("-", "").lowercase()
        return if (clean.length == 12) clean else null
    }

    private fun getClientMacAddress(): String? {
        return try {
            val interfaces = java.util.Collections.list(java.net.NetworkInterface.getNetworkInterfaces())
            var macBytes: ByteArray? = null
            val wlan = interfaces.firstOrNull { it.name.equals("wlan0", ignoreCase = true) }
            if (wlan != null) {
                macBytes = wlan.hardwareAddress
            }
            if (macBytes == null || macBytes.isEmpty()) {
                for (iface in interfaces) {
                    if (iface.name.contains("wlan", ignoreCase = true) ||
                        iface.name.contains("eth", ignoreCase = true)) {
                        val hw = iface.hardwareAddress
                        if (hw != null && hw.isNotEmpty()) {
                            macBytes = hw
                            break
                        }
                    }
                }
            }
            if (macBytes != null && macBytes.isNotEmpty()) {
                val sb = StringBuilder()
                for (b in macBytes) {
                    sb.append(String.format("%02x", b))
                }
                sb.toString()
            } else {
                null
            }
        } catch (_: Exception) {
            null
        }
    }

    private fun configureBackgroundPermissionChannel(flutterEngine: FlutterEngine) {
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "preconnect/background_permission")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "isBatteryOptimizationIgnored" -> {
                        val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
                        val ignored = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                            pm.isIgnoringBatteryOptimizations(packageName)
                        } else {
                            true
                        }
                        result.success(ignored)
                    }
                    "requestIgnoreBatteryOptimization" -> {
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                            try {
                                val intent = Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS).apply {
                                    data = Uri.parse("package:$packageName")
                                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                                }
                                startActivity(intent)
                                result.success(true)
                            } catch (e: Exception) {
                                try {
                                    val intent = Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS).apply {
                                        addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                                    }
                                    startActivity(intent)
                                    result.success(true)
                                } catch (e2: Exception) {
                                    result.success(false)
                                }
                            }
                        } else {
                            result.success(true)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }
}

private class PdfPrintDocumentAdapter(
    private val context: Context,
    private val sourceFile: File,
    private val jobName: String,
) : PrintDocumentAdapter() {
    private var parcelFileDescriptor: ParcelFileDescriptor? = null
    private var renderer: PdfRenderer? = null
    private var attributes: PrintAttributes? = null

    override fun onLayout(
        oldAttributes: PrintAttributes?,
        newAttributes: PrintAttributes?,
        cancellationSignal: CancellationSignal,
        callback: LayoutResultCallback,
        extras: Bundle?,
    ) {
        if (cancellationSignal.isCanceled) {
            callback.onLayoutCancelled()
            return
        }

        try {
            closeRenderer()
            attributes = newAttributes
            parcelFileDescriptor = ParcelFileDescriptor.open(
                sourceFile,
                ParcelFileDescriptor.MODE_READ_ONLY,
            )
            renderer = PdfRenderer(parcelFileDescriptor!!)
            if (cancellationSignal.isCanceled) {
                callback.onLayoutCancelled()
                return
            }
            val pageCount = renderer?.pageCount ?: 0
            val info = PrintDocumentInfo.Builder(jobName)
                .setContentType(PrintDocumentInfo.CONTENT_TYPE_DOCUMENT)
                .setPageCount(pageCount)
                .build()
            callback.onLayoutFinished(info, true)
        } catch (e: Exception) {
            callback.onLayoutFailed(e.message)
        }
    }

    override fun onWrite(
        pages: Array<out PageRange>,
        destination: ParcelFileDescriptor,
        cancellationSignal: CancellationSignal,
        callback: WriteResultCallback,
    ) {
        val renderer = renderer
        if (renderer == null) {
            callback.onWriteFailed("PDF renderer unavailable")
            return
        }

        val selectedPages = expandPageRanges(pages, renderer.pageCount)
        val pdfDocument = PdfDocument()
        val mediaSize = attributes?.mediaSize
        val pageWidth = mediaSize?.let {
            (it.widthMils / 1000f * 72f).toInt().coerceAtLeast(1)
        } ?: 612
        val pageHeight = mediaSize?.let {
            (it.heightMils / 1000f * 72f).toInt().coerceAtLeast(1)
        } ?: 792

        try {
            for ((index, pageIndex) in selectedPages.withIndex()) {
                if (cancellationSignal.isCanceled) {
                    callback.onWriteCancelled()
                    pdfDocument.close()
                    return
                }

                val sourcePage = renderer.openPage(pageIndex)
                try {
                    val bitmap = Bitmap.createBitmap(
                        sourcePage.width,
                        sourcePage.height,
                        Bitmap.Config.ARGB_8888,
                    )
                    try {
                        sourcePage.render(
                            bitmap,
                            null,
                            null,
                            PdfRenderer.Page.RENDER_MODE_FOR_PRINT,
                        )

                        val pageInfo = PdfDocument.PageInfo.Builder(
                            pageWidth,
                            pageHeight,
                            index + 1,
                        ).create()
                        val pdfPage = pdfDocument.startPage(pageInfo)
                        try {
                            pdfPage.canvas.drawBitmap(
                                bitmap,
                                null,
                                pageInfo.contentRect,
                                null,
                            )
                        } finally {
                            pdfDocument.finishPage(pdfPage)
                        }
                    } finally {
                        bitmap.recycle()
                    }
                } finally {
                    sourcePage.close()
                }
            }

            FileOutputStream(destination.fileDescriptor).use { output ->
                pdfDocument.writeTo(output)
            }
            callback.onWriteFinished(arrayOf(PageRange.ALL_PAGES))
        } catch (e: Exception) {
            callback.onWriteFailed(e.message)
        } finally {
            pdfDocument.close()
        }
    }

    override fun onFinish() {
        closeRenderer()
        super.onFinish()
    }

    private fun closeRenderer() {
        renderer?.close()
        renderer = null
        parcelFileDescriptor?.close()
        parcelFileDescriptor = null
    }

    private fun expandPageRanges(
        ranges: Array<out PageRange>,
        pageCount: Int,
    ): List<Int> {
        if (pageCount <= 0) return emptyList()
        if (ranges.isEmpty()) return (0 until pageCount).toList()
        val pages = linkedSetOf<Int>()
        for (range in ranges) {
            val start = range.start.coerceAtLeast(0)
            val end = range.end.coerceAtMost(pageCount - 1)
            if (end < start) continue
            for (page in start..end) {
                pages.add(page)
            }
        }
        return if (pages.isEmpty()) (0 until pageCount).toList() else pages.toList()
    }
}
