---
name: wifi-tile
description: Work on the Student-WiFi Android quick settings tile and its background login or logout flow.
---

# Wi-Fi Tile

- Native side: `WifiTileController.kt` and `PreConnectWifiTileService.kt` in `android/app/src/main/kotlin/com/sabbirba/preconnect`. The tile logs in when offline, disconnects when connected, and opens the app when credentials are missing or the network is not Student-WiFi.
- Dart side: `lib/tools/wifi_tile.dart` handles the `studentwifi://login|logout` background call and publishes the result through `home_widget`.
- Only trust portal URLs that pass `WifiTile.isTrustedPortal` (`bracu.ac.bd` hosts or private IPv4). Keep `HomeWidgetBackgroundReceiver` non-exported.
- Wi-Fi credentials stay in `FlutterSecureStorage` through `CaptiveLoginStore`.
- Test on an Android device on Student-WiFi; the iOS simulator cannot exercise the tile.
