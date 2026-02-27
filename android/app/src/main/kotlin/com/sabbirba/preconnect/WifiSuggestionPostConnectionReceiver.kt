package com.sabbirba.preconnect

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.net.wifi.WifiManager
import android.os.Build

class WifiSuggestionPostConnectionReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent?) {
        if (intent?.action != WifiManager.ACTION_WIFI_NETWORK_SUGGESTION_POST_CONNECTION) {
            return
        }

        val prefs = context.getSharedPreferences("preconnect.network_assist", Context.MODE_PRIVATE)
        val editor = prefs.edit()
        editor.putBoolean("wifi_post_connection_pending", true)
        editor.putLong("wifi_post_connection_at", System.currentTimeMillis())

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            val suggestion = intent.getParcelableExtra(
                WifiManager.EXTRA_NETWORK_SUGGESTION,
                android.net.wifi.WifiNetworkSuggestion::class.java,
            )
            val ssid = suggestion?.ssid?.trim()
            if (!ssid.isNullOrEmpty()) {
                editor.putString("wifi_post_connection_ssid", ssid)
            }
        } else if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            @Suppress("DEPRECATION")
            val suggestion =
                intent.getParcelableExtra<android.net.wifi.WifiNetworkSuggestion>(
                    WifiManager.EXTRA_NETWORK_SUGGESTION,
                )
            val ssid = suggestion?.ssid?.trim()
            if (!ssid.isNullOrEmpty()) {
                editor.putString("wifi_post_connection_ssid", ssid)
            }
        }

        editor.apply()
    }
}
