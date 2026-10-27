package com.sabbirba.preconnect

import android.content.ComponentName
import android.content.Context
import android.content.SharedPreferences
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import android.net.Uri
import android.net.wifi.WifiInfo
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.service.quicksettings.Tile
import android.service.quicksettings.TileService
import android.util.Log
import java.lang.ref.WeakReference
import es.antonborri.home_widget.HomeWidgetBackgroundIntent

internal object WifiTileController {
    enum class Tap { BUSY, OPEN_APP, STARTED }

    private enum class Phase { IDLE, LOGGING_IN, LOGGING_OUT }

    private const val PREFS = "HomeWidgetPreferences"
    private const val READY_KEY = "wifi_tile_ready"
    private const val RESULT_KEY = "wifi_tile_result"
    private const val CAMPUS_SSID = "Student-WiFi"
    private const val WORK_TIMEOUT_MS = 85_000L
    private const val OUTCOME_MS = 20_000L
    private const val LABEL = "Student-WiFi"

    private val handler = Handler(Looper.getMainLooper())
    private var phase = Phase.IDLE
    private var listener: SharedPreferences.OnSharedPreferenceChangeListener? = null
    private var timeout: Runnable? = null
    private var outcome: String? = null
    private var outcomeUntil = 0L
    private var active: WeakReference<TileService>? = null

    fun attach(service: TileService?) {
        active = service?.let { WeakReference(it) }
    }

    fun render(
        context: Context,
        tile: Tile?,
    ) {
        tile ?: return
        val (state, subtitle) = describe(context)
        tile.state = state
        tile.label = LABEL
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            tile.subtitle = subtitle
        }
        tile.updateTile()
    }

    fun onTap(context: Context): Tap {
        if (phase != Phase.IDLE) return Tap.BUSY
        val cm = connectivity(context) ?: return Tap.OPEN_APP
        val wifi = wifiNetwork(cm) ?: return Tap.OPEN_APP
        val caps = cm.getNetworkCapabilities(wifi) ?: return Tap.OPEN_APP
        val ssid = ssidOf(caps)
        if (ssid != null && !ssid.equals(CAMPUS_SSID, ignoreCase = true)) return Tap.OPEN_APP

        val online = isOnline(caps)
        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        if (!online && !prefs.getBoolean(READY_KEY, false)) return Tap.OPEN_APP

        start(context, cm, wifi, prefs, if (online) Phase.LOGGING_OUT else Phase.LOGGING_IN)
        return Tap.STARTED
    }

    fun autoLogin(context: Context): Boolean {
        if (phase != Phase.IDLE) return false
        val cm = connectivity(context) ?: return false
        val wifi = wifiNetwork(cm) ?: return false
        val caps = cm.getNetworkCapabilities(wifi) ?: return false
        val ssid = ssidOf(caps)
        if (ssid != null && !ssid.equals(CAMPUS_SSID, ignoreCase = true)) return false
        if (isOnline(caps)) return false
        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        if (!prefs.getBoolean(READY_KEY, false)) return false
        start(context, cm, wifi, prefs, Phase.LOGGING_IN)
        return true
    }

    private fun start(
        context: Context,
        cm: ConnectivityManager,
        wifi: Network,
        prefs: SharedPreferences,
        next: Phase,
    ) {
        phase = next
        outcome = null
        val app = context.applicationContext
        try {
            cm.bindProcessToNetwork(wifi)
        } catch (error: Exception) {
            Log.w("PreConnect", "Unable to bind the Wi-Fi tile network", error)
        }

        val changed =
            SharedPreferences.OnSharedPreferenceChangeListener { _, key ->
                if (key == RESULT_KEY) {
                    val raw = prefs.getString(RESULT_KEY, null)
                    handler.post { finish(app, raw?.substringBefore('|') ?: "failed") }
                }
            }
        listener = changed
        prefs.registerOnSharedPreferenceChangeListener(changed)
        timeout = Runnable { finish(app, "failed") }.also { handler.postDelayed(it, WORK_TIMEOUT_MS) }

        val action = if (next == Phase.LOGGING_IN) "login" else "logout"
        val uri =
            Uri.Builder()
                .scheme("studentwifi")
                .authority(action)
                .apply {
                    portalUrl(cm, wifi)?.let { appendQueryParameter("portal", it) }
                    gatewayOf(cm, wifi)?.let { appendQueryParameter("gateway", it) }
                }.build()
        HomeWidgetBackgroundIntent.getBroadcast(app, uri).send()
        requestRefresh(app)
    }

    private fun finish(
        context: Context,
        result: String,
    ) {
        if (phase == Phase.IDLE) return
        val cm = connectivity(context)
        val loggedIn = phase == Phase.LOGGING_IN
        timeout?.let { handler.removeCallbacks(it) }
        timeout = null
        listener?.let {
            context
                .getSharedPreferences(PREFS, Context.MODE_PRIVATE)
                .unregisterOnSharedPreferenceChangeListener(it)
        }
        listener = null
        val wifi = cm?.let { wifiNetwork(it) }
        try {
            cm?.bindProcessToNetwork(null)
            if (wifi != null && (result == "login_ok" || result == "logout_ok")) {
                cm?.reportNetworkConnectivity(wifi, loggedIn)
            }
        } catch (error: Exception) {
            Log.w("PreConnect", "Unable to release the Wi-Fi tile network", error)
        }
        phase = Phase.IDLE
        outcome = result
        outcomeUntil = System.currentTimeMillis() + OUTCOME_MS
        requestRefresh(context)
        handler.postDelayed({ requestRefresh(context) }, OUTCOME_MS + 500)
    }

    private fun requestRefresh(context: Context) {
        val service = active?.get()
        if (service != null) {
            render(context, service.qsTile)
            return
        }
        try {
            TileService.requestListeningState(
                context,
                ComponentName(context, PreConnectWifiTileService::class.java),
            )
        } catch (error: Exception) {
            Log.w("PreConnect", "Unable to refresh the Wi-Fi tile", error)
        }
    }

    private fun describe(context: Context): Pair<Int, String> {
        when (phase) {
            Phase.LOGGING_IN -> return Tile.STATE_UNAVAILABLE to "Logging in…"
            Phase.LOGGING_OUT -> return Tile.STATE_UNAVAILABLE to "Disconnecting…"
            Phase.IDLE -> Unit
        }
        val recent = System.currentTimeMillis() < outcomeUntil
        when {
            recent && outcome == "login_ok" -> return Tile.STATE_ACTIVE to "Connected"
            recent && outcome == "logout_ok" -> return Tile.STATE_INACTIVE to "Disconnected"
            recent && outcome == "needs_app" -> return Tile.STATE_INACTIVE to "Open PreConnect"
            recent && outcome == "failed" -> return Tile.STATE_INACTIVE to "Failed, tap to retry"
        }
        val cm = connectivity(context) ?: return Tile.STATE_INACTIVE to "No Wi-Fi"
        val wifi = wifiNetwork(cm) ?: return Tile.STATE_INACTIVE to "No Wi-Fi"
        val caps = cm.getNetworkCapabilities(wifi) ?: return Tile.STATE_INACTIVE to "No Wi-Fi"
        val ssid = ssidOf(caps)
        if (ssid != null && !ssid.equals(CAMPUS_SSID, ignoreCase = true)) {
            return Tile.STATE_INACTIVE to "Not Student-WiFi"
        }
        return if (isOnline(caps)) {
            Tile.STATE_ACTIVE to "Connected"
        } else {
            Tile.STATE_INACTIVE to "Tap to log in"
        }
    }

    private fun isOnline(caps: NetworkCapabilities): Boolean =
        caps.hasCapability(NetworkCapabilities.NET_CAPABILITY_VALIDATED) &&
            !caps.hasCapability(NetworkCapabilities.NET_CAPABILITY_CAPTIVE_PORTAL)

    private fun connectivity(context: Context): ConnectivityManager? =
        context.getSystemService(Context.CONNECTIVITY_SERVICE) as? ConnectivityManager

    @Suppress("DEPRECATION")
    private fun wifiNetwork(cm: ConnectivityManager): Network? =
        try {
            cm.allNetworks.firstOrNull {
                cm.getNetworkCapabilities(it)?.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) == true
            }
        } catch (_: Exception) {
            null
        }

    private fun ssidOf(caps: NetworkCapabilities): String? {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) return null
        val raw = (caps.transportInfo as? WifiInfo)?.ssid?.trim()?.trim('"').orEmpty()
        if (raw.isEmpty() || raw == "<unknown ssid>") return null
        return raw
    }

    private fun gatewayOf(
        cm: ConnectivityManager,
        network: Network,
    ): String? =
        try {
            cm.getLinkProperties(network)?.routes?.firstOrNull { it.isDefaultRoute }?.gateway?.hostAddress
        } catch (_: Exception) {
            null
        }

    private fun portalUrl(
        cm: ConnectivityManager,
        network: Network,
    ): String? =
        try {
            val data =
                cm.getLinkProperties(network)?.let { props ->
                    props.javaClass.methods
                        .firstOrNull { it.name == "getCaptivePortalData" && it.parameterTypes.isEmpty() }
                        ?.invoke(props)
                }
            data
                ?.javaClass
                ?.methods
                ?.firstOrNull { it.name == "getUserPortalUrl" && it.parameterTypes.isEmpty() }
                ?.invoke(data)
                ?.toString()
                ?.trim()
                ?.ifEmpty { null }
        } catch (_: Exception) {
            null
        }
}
