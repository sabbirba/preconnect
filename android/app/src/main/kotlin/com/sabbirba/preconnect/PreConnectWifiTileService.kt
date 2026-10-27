package com.sabbirba.preconnect

import android.app.PendingIntent
import android.content.Intent
import android.os.Build
import android.service.quicksettings.TileService
import androidx.annotation.RequiresApi

@RequiresApi(Build.VERSION_CODES.N)
class PreConnectWifiTileService : TileService() {
    override fun onStartListening() {
        super.onStartListening()
        WifiTileController.attach(this)
        WifiTileController.render(applicationContext, qsTile)
    }

    override fun onStopListening() {
        WifiTileController.attach(null)
        super.onStopListening()
    }

    override fun onClick() {
        super.onClick()
        if (isLocked) {
            unlockAndRun { handleTap() }
        } else {
            handleTap()
        }
    }

    private fun handleTap() {
        if (WifiTileController.onTap(applicationContext) == WifiTileController.Tap.OPEN_APP) {
            openApp()
        }
        WifiTileController.render(applicationContext, qsTile)
    }

    private fun openApp() {
        val intent =
            Intent(this, MainActivity::class.java).apply {
                action = "captive_wifi"
                putExtra("flutter_shortcut", "captive_wifi")
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP
            }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            val pendingIntent =
                PendingIntent.getActivity(
                    this,
                    0,
                    intent,
                    PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
                )
            startActivityAndCollapse(pendingIntent)
        } else {
            @Suppress("DEPRECATION")
            startActivityAndCollapse(intent)
        }
    }
}
