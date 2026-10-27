import 'dart:async';
import 'dart:io';

import 'package:home_widget/home_widget.dart';
import 'package:preconnect/tools/app_log.dart';
import 'package:preconnect/tools/app_storage.dart';
import 'package:preconnect/tools/network_assist.dart';
import 'package:preconnect/tools/storage_keys.dart';
import 'package:preconnect/tools/token_storage.dart';
import 'package:preconnect/tools/wifi_http.dart';

abstract final class WifiTile {
  static const String scheme = 'studentwifi';
  static const String resultKey = 'wifi_tile_result';
  static const Duration _loginTimeout = Duration(seconds: 25);
  static const int _loginAttempts = 3;

  static bool handles(Uri? uri) => uri != null && uri.scheme == scheme;

  static bool isTrustedPortal(Uri? uri) {
    if (uri == null || (uri.scheme != 'http' && uri.scheme != 'https')) {
      return false;
    }
    final host = uri.host.toLowerCase();
    if (host == 'bracu.ac.bd' || host.endsWith('.bracu.ac.bd')) return true;
    final address = InternetAddress.tryParse(host);
    if (address == null || address.type != InternetAddressType.IPv4) {
      return false;
    }
    final bytes = address.rawAddress;
    return bytes[0] == 10 ||
        (bytes[0] == 172 && bytes[1] >= 16 && bytes[1] <= 31) ||
        (bytes[0] == 192 && bytes[1] == 168);
  }

  static Future<void> run(Uri uri) async {
    var outcome = 'failed';
    try {
      await AppStorage.initialize();
      final status = AndroidNetworkStatus(
        connected: true,
        validated: false,
        captive: uri.host == 'login',
        transport: 'wifi',
        androidApi: 0,
        ssid: null,
        captiveWifiUrl: _trustedPortalParam(uri.queryParameters['portal']),
        gatewayAddress: uri.queryParameters['gateway'],
        canExtendSession: null,
        sessionExpiryTimeMillis: null,
      );
      outcome = uri.host == 'logout'
          ? await _logout(status)
          : await _login(status);
    } catch (error, stackTrace) {
      unawaited(AppLog.write('Wi-Fi tile failed: $error\n$stackTrace'));
    }
    await _publish(outcome);
  }

  static String? _trustedPortalParam(String? raw) {
    final parsed = raw == null ? null : Uri.tryParse(raw);
    return isTrustedPortal(parsed) ? raw : null;
  }

  static Future<String> _login(AndroidNetworkStatus status) async {
    final password = (await CaptiveLoginStore.instance.read())?.password ?? '';
    final studentId =
        (await AppStorage.instance.getString(StorageKeys.studentId) ?? '')
            .trim();
    if (password.isEmpty || studentId.isEmpty) return 'needs_app';

    var portal = CaptiveWifiHttp.resolvePortalUri(status);
    if (portal == null || portal == CaptiveWifiHttp.defaultProbeUri) {
      portal = await CaptiveWifiHttp.detectCaptivePortal() ?? portal;
    }
    if (portal == null || !isTrustedPortal(portal)) return 'failed';

    for (var attempt = 0; attempt < _loginAttempts; attempt++) {
      final ok = await CaptiveWifiHttp.instance
          .loginViaCaptiveApi(
            studentId: studentId,
            password: password,
            captiveWifiUrl: portal,
          )
          .timeout(_loginTimeout, onTimeout: () => false);
      if (ok) return 'login_ok';
      if (CaptiveWifiHttp.instance.isLastFatal) break;
      await Future<void>.delayed(const Duration(seconds: 1));
    }
    return 'failed';
  }

  static Future<String> _logout(AndroidNetworkStatus status) async {
    final portal = CaptiveWifiHttp.resolvePortalUri(status);
    if (portal == null) return 'failed';
    final ok = await CaptiveWifiHttp.instance.logoutViaCaptiveApi(
      captiveWifiUrl: portal,
    );
    return ok ? 'logout_ok' : 'failed';
  }

  static Future<void> _publish(String outcome) async {
    try {
      await HomeWidget.saveWidgetData<String>(
        resultKey,
        '$outcome|${DateTime.now().millisecondsSinceEpoch}',
      );
    } catch (error) {
      unawaited(AppLog.write('Wi-Fi tile result failed: $error'));
    }
  }
}
