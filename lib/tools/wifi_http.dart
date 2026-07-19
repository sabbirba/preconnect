import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:preconnect/tools/network_assist.dart';
import 'package:preconnect/tools/token_storage.dart';

class CaptiveWifiHttpResult {
  const CaptiveWifiHttpResult({
    required this.statusCode,
    required this.uri,
    required this.body,
    required this.location,
  });

  final int statusCode;
  final Uri uri;
  final String body;
  final Uri? location;
}

class CaptiveWifiHttp {
  CaptiveWifiHttp._();

  static final CaptiveWifiHttp instance = CaptiveWifiHttp._();

  String? lastError;
  String lastResponseLog = '';
  static final Uri defaultProbeUri = Uri.parse(
    'http://connectivitycheck.gstatic.com/generate_204',
  );

  static const String kPreConnectUserAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36';

  static const Duration _connectionTimeout = Duration(seconds: 10);
  final Map<String, Cookie> sessionCookies = {};

  static Uri? resolvePortalUri(AndroidNetworkStatus? status) {
    if (status == null) return defaultProbeUri;
    final captiveWifiUrl = (status.captiveWifiUrl ?? '').trim();
    final parsedUrl = Uri.tryParse(captiveWifiUrl);
    if (parsedUrl != null &&
        parsedUrl.hasScheme &&
        parsedUrl.hasAuthority &&
        (parsedUrl.scheme == 'http' || parsedUrl.scheme == 'https')) {
      return parsedUrl;
    }
    return defaultProbeUri;
  }

  static Future<Uri?> detectCaptivePortal() async {
    if (AndroidNetworkAssist.isSupported) {
      await AndroidNetworkAssist.bindToWifiNetwork();
    }
    try {
      final client = HttpClient()
        ..userAgent = kPreConnectUserAgent
        ..connectionTimeout = const Duration(seconds: 5);
      client.badCertificateCallback = (cert, host, port) => true;
      final request = await client.getUrl(defaultProbeUri);
      request.followRedirects = false;
      final response = await request.close();
      final status = response.statusCode;
      final location =
          response.headers.value('location') ??
          response.headers.value('Location');
      if (status >= 300 && status < 400 && location != null) {
        return Uri.tryParse(location);
      }
      final body = await response.transform(utf8.decoder).join();
      if (status == 200) {
        final metaReg = RegExp(
          r'''<meta\b([^>]*http-equiv\s*=\s*["']refresh["'][^>]*)>''',
          caseSensitive: false,
        );
        final metaMatch = metaReg.firstMatch(body);
        if (metaMatch != null) {
          final attrs = metaMatch.group(1) ?? '';
          final contentReg = RegExp(
            r'''content\s*=\s*["']\s*(?:\d+\s*;\s*)?url\s*=\s*([^"']+)["']''',
            caseSensitive: false,
          );
          final contentMatch = contentReg.firstMatch(attrs);
          if (contentMatch != null) {
            final targetUrl = contentMatch.group(1)?.trim();
            if (targetUrl != null && targetUrl.isNotEmpty) {
              return Uri.tryParse(targetUrl);
            }
          }
        }
      }
    } catch (_) {
    } finally {
      if (AndroidNetworkAssist.isSupported) {
        await AndroidNetworkAssist.unbindFromWifiNetwork();
      }
    }
    return null;
  }

  static Future<bool> checkIfOnCampusNetwork() async {
    if (AndroidNetworkAssist.isSupported) {
      await AndroidNetworkAssist.bindToWifiNetwork();
    }
    try {
      final savedUrlStr = await CaptiveLoginStore.instance.readLastPortalUrl();
      if (savedUrlStr == null || savedUrlStr.isEmpty) {
        final portalUri = await detectCaptivePortal();
        return portalUri != null;
      }

      final savedUri = Uri.tryParse(savedUrlStr);
      if (savedUri == null) return false;

      final client = HttpClient();
      client.connectionTimeout = const Duration(seconds: 3);
      client.badCertificateCallback = (cert, host, port) => true;

      final request = await client.getUrl(
        Uri.parse('http://${savedUri.host}/'),
      );
      final response = await request.close().timeout(
        const Duration(seconds: 3),
      );
      final body = await response.transform(utf8.decoder).join();
      client.close(force: true);

      final isPortal =
          body.contains('portalauth') ||
          body.contains('portalpage') ||
          body.contains(savedUri.host) ||
          response.headers.value('location')?.contains('portal') == true;

      return isPortal;
    } catch (_) {
    } finally {
      if (AndroidNetworkAssist.isSupported) {
        await AndroidNetworkAssist.unbindFromWifiNetwork();
      }
    }
    return false;
  }

  static Map<String, String> parseFormInputs(String html) {
    final inputs = <String, String>{};
    final inputReg = RegExp(
      r'''<input\b[^>]*>''',
      caseSensitive: false,
      multiLine: true,
      dotAll: true,
    );
    final matches = inputReg.allMatches(html);
    for (final match in matches) {
      final attrs = match.group(0) ?? '';
      final nameReg = RegExp(
        r'''\bname\s*=\s*(?:["']([^"']*)["']|([^\s>]+))''',
        caseSensitive: false,
      );
      final nameMatch = nameReg.firstMatch(attrs);
      if (nameMatch == null) continue;
      final name = (nameMatch.group(1) ?? nameMatch.group(2) ?? '').trim();
      if (name.isEmpty) continue;

      final valueReg = RegExp(
        r'''\bvalue\s*=\s*(?:["']([^"']*)["']|([^\s>]+))''',
        caseSensitive: false,
      );
      final valueMatch = valueReg.firstMatch(attrs);
      final value = (valueMatch?.group(1) ?? valueMatch?.group(2) ?? '').trim();

      inputs[name] = value;
    }
    return inputs;
  }

  Future<HttpClient> newClient() async {
    final client = HttpClient()..userAgent = kPreConnectUserAgent;
    client.connectionTimeout = _connectionTimeout;
    client.badCertificateCallback =
        (X509Certificate cert, String host, int port) => true;
    return client;
  }

  Future<bool> isValidatedViaProbe({
    required HttpClient client,
    required Map<String, Cookie> cookies,
    Uri? probeUri,
  }) async {
    final target = probeUri ?? defaultProbeUri;
    for (var i = 0; i < 4; i++) {
      if (i > 0) {
        await Future<void>.delayed(Duration(milliseconds: 500 * i));
      }
      try {
        final result = await getWithRedirects(
          client: client,
          uri: target,
          cookies: cookies,
        );
        if (result.statusCode == 204) {
          return true;
        }
      } catch (_) {}
    }
    return false;
  }

  Future<CaptiveWifiHttpResult> getWithRedirects({
    required HttpClient client,
    required Uri uri,
    required Map<String, Cookie> cookies,
  }) async {
    var current = uri;
    for (var i = 0; i < 8; i++) {
      final request = await client.getUrl(current);
      request.followRedirects = false;
      final cookieHeader = _cookieHeader(cookies);
      if (cookieHeader != null) {
        request.headers.set('Cookie', cookieHeader);
      }
      final response = await request.close();
      _captureCookies(response, cookies);

      final status = response.statusCode;
      final location =
          response.headers.value('location') ??
          response.headers.value('Location');
      final body = await response.transform(utf8.decoder).join();

      if (status >= 300 && status < 400 && location != null) {
        current = Uri.parse(location).isAbsolute
            ? Uri.parse(location)
            : current.resolve(location);
        continue;
      }

      if (status == 200) {
        final metaReg = RegExp(
          r'''<meta\b([^>]*http-equiv\s*=\s*["']refresh["'][^>]*)>''',
          caseSensitive: false,
        );
        final metaMatch = metaReg.firstMatch(body);
        if (metaMatch != null) {
          final attrs = metaMatch.group(1) ?? '';
          final contentReg = RegExp(
            r'''content\s*=\s*["']\s*(?:\d+\s*;\s*)?url\s*=\s*([^"']+)["']''',
            caseSensitive: false,
          );
          final contentMatch = contentReg.firstMatch(attrs);
          if (contentMatch != null) {
            final targetUrl = contentMatch.group(1)?.trim();
            if (targetUrl != null && targetUrl.isNotEmpty) {
              current = Uri.parse(targetUrl).isAbsolute
                  ? Uri.parse(targetUrl)
                  : current.resolve(targetUrl);
              continue;
            }
          }
        }

        final jsReg = RegExp(
          r'''(?:window\.)?location(?:\.href|\.replace)?\s*=\s*["']([^"']+)["']''',
          caseSensitive: false,
        );
        final jsMatch = jsReg.firstMatch(body);
        if (jsMatch != null) {
          final targetUrl = jsMatch.group(1)?.trim();
          if (targetUrl != null && targetUrl.isNotEmpty) {
            current = Uri.parse(targetUrl).isAbsolute
                ? Uri.parse(targetUrl)
                : current.resolve(targetUrl);
            continue;
          }
        }

        final jsAssignReg = RegExp(
          r'''(?:window\.)?location\.assign\s*\(\s*["']([^"']+)["']\s*\)''',
          caseSensitive: false,
        );
        final jsAssignMatch = jsAssignReg.firstMatch(body);
        if (jsAssignMatch != null) {
          final targetUrl = jsAssignMatch.group(1)?.trim();
          if (targetUrl != null && targetUrl.isNotEmpty) {
            current = Uri.parse(targetUrl).isAbsolute
                ? Uri.parse(targetUrl)
                : current.resolve(targetUrl);
            continue;
          }
        }
      }

      return CaptiveWifiHttpResult(
        statusCode: status,
        uri: current,
        body: body,
        location: location == null ? null : Uri.parse(location),
      );
    }
    return CaptiveWifiHttpResult(
      statusCode: 0,
      uri: current,
      body: '',
      location: null,
    );
  }

  Future<CaptiveWifiHttpResult> postOnce({
    required HttpClient client,
    required Uri uri,
    required String body,
    required Map<String, Cookie> cookies,
    Uri? referer,
  }) async {
    final request = await client.postUrl(uri);
    request.followRedirects = false;
    request.headers.set('content-type', 'application/x-www-form-urlencoded');
    request.headers.set('X-Requested-With', 'XMLHttpRequest');

    if (referer != null) {
      request.headers.set('Referer', referer.toString());
      request.headers.set(
        'Origin',
        '${referer.scheme}://${referer.host}:${referer.port}',
      );
    }

    String? xsrfToken;
    for (final cookie in cookies.values) {
      if (cookie.name.toUpperCase() == 'XSRF-TOKEN') {
        xsrfToken = cookie.value;
        break;
      }
    }
    if (xsrfToken != null) {
      request.headers.set('X-XSRF-TOKEN', xsrfToken);
    }

    final cookieHeader = _cookieHeader(cookies);
    if (cookieHeader != null) {
      request.headers.set('Cookie', cookieHeader);
    }
    request.write(body);
    final response = await request.close();
    _captureCookies(response, cookies);
    final location =
        response.headers.value('location') ??
        response.headers.value('Location');
    final text = await response.transform(utf8.decoder).join();

    return CaptiveWifiHttpResult(
      statusCode: response.statusCode,
      uri: uri,
      body: text,
      location: location == null ? null : Uri.parse(location),
    );
  }

  void _captureCookies(HttpClientResponse response, Map<String, Cookie> jar) {
    for (final cookie in response.cookies) {
      jar[cookie.name] = cookie;
    }
  }

  String? _cookieHeader(Map<String, Cookie> cookies) {
    if (cookies.isEmpty) return null;
    return cookies.values.map((c) => '${c.name}=${c.value}').join('; ');
  }

  Future<bool> loginViaCaptiveApi({
    required String studentId,
    required String password,
    required Uri captiveWifiUrl,
    required String ssid,
  }) async {
    lastError = null;
    lastResponseLog = '';
    final client = await newClient();
    final cookies = sessionCookies;
    cookies.clear();

    var targetUrl = captiveWifiUrl;
    if (targetUrl == defaultProbeUri) {
      final savedUrlStr = await CaptiveLoginStore.instance.readLastPortalUrl();
      if (savedUrlStr != null && savedUrlStr.isNotEmpty) {
        final parsed = Uri.tryParse(savedUrlStr);
        if (parsed != null) {
          targetUrl = parsed;
        }
      }
    }

    try {
      final first = await getWithRedirects(
        client: client,
        uri: targetUrl,
        cookies: cookies,
      );

      if (first.statusCode == 204) {
        return true;
      }

      var loginUri = first.uri;
      if (loginUri.path.contains('/portalpage/')) {
        unawaited(
          CaptiveLoginStore.instance.saveLastPortalUrl(loginUri.toString()),
        );
      }
      try {
        final dynamic decoded = jsonDecode(first.body);
        if (decoded is Map) {
          final userPortalUrl =
              decoded['user-portal-url'] ?? decoded['userPortalUrl'];
          if (userPortalUrl is String && userPortalUrl.isNotEmpty) {
            loginUri = Uri.parse(userPortalUrl);

            if (loginUri.path.contains('/portalpage/')) {
              unawaited(
                CaptiveLoginStore.instance.saveLastPortalUrl(
                  loginUri.toString(),
                ),
              );
            }
            final second = await getWithRedirects(
              client: client,
              uri: loginUri,
              cookies: cookies,
            );
            loginUri = second.uri;

            if (loginUri.path.contains('/portalpage/')) {
              unawaited(
                CaptiveLoginStore.instance.saveLastPortalUrl(
                  loginUri.toString(),
                ),
              );
            }
          }
        }
      } catch (_) {
        assert(true);
      }

      String apiBasePath = '/portalauth';
      final initialPath = loginUri.path;
      if (initialPath.contains('/')) {
        apiBasePath = initialPath.substring(0, initialPath.lastIndexOf('/'));
      }

      Uri apiLoginUri;
      final formReg = RegExp(
        r'''<form\b[^>]*\baction\s*=\s*(?:["']([^"']+)["']|([^\s>]+))''',
        caseSensitive: false,
      );
      final match = formReg.firstMatch(first.body);
      final formAction = (match?.group(1) ?? match?.group(2) ?? '').trim();
      if (formAction.isNotEmpty) {
        apiLoginUri = Uri.parse(formAction).isAbsolute
            ? Uri.parse(formAction)
            : loginUri.resolve(formAction);
        final path = apiLoginUri.path;
        if (path.contains('/')) {
          apiBasePath = path.substring(0, path.lastIndexOf('/'));
        }
      } else {
        apiLoginUri = loginUri.replace(
          path: '$apiBasePath/login',
          queryParameters: {},
        );
      }

      final status = await AndroidNetworkAssist.getNetworkStatus();
      var deviceUmac = status?.clientMac;
      if (deviceUmac != null) {
        deviceUmac = deviceUmac
            .replaceAll(':', '')
            .replaceAll('-', '')
            .toLowerCase();
      }

      final params = loginUri.queryParameters;
      final originalParams = captiveWifiUrl.queryParameters;

      String getParam(String key, [String defaultValue = '']) {
        var val = params[key] ?? originalParams[key];
        if (val == null || val.isEmpty) {
          if (key == 'acip') {
            val =
                params['wlanacip'] ??
                originalParams['wlanacip'] ??
                params['ac-ip'] ??
                originalParams['ac-ip'] ??
                params['ac_ip'] ??
                originalParams['ac_ip'];
          } else if (key == 'apmac') {
            val =
                params['wlanapmac'] ??
                originalParams['wlanapmac'] ??
                params['ap-mac'] ??
                originalParams['ap-mac'] ??
                params['ap_mac'] ??
                originalParams['ap_mac'];
          } else if (key == 'uaddress') {
            val =
                params['wlanuserip'] ??
                originalParams['wlanuserip'] ??
                params['user-ip'] ??
                originalParams['user-ip'] ??
                params['user_ip'] ??
                originalParams['user_ip'];
          } else if (key == 'umac') {
            val =
                params['wlanusermac'] ??
                originalParams['wlanusermac'] ??
                params['user-mac'] ??
                originalParams['user-mac'] ??
                params['user_mac'] ??
                originalParams['user_mac'];
          } else if (key == 'accessMac') {
            val =
                params['wlanacmac'] ??
                originalParams['wlanacmac'] ??
                params['ac-mac'] ??
                originalParams['ac-mac'] ??
                params['ac_mac'] ??
                originalParams['ac_mac'];
          }
        }
        return (val != null && val.isNotEmpty) ? val : defaultValue;
      }

      var acip = getParam('acip');
      if (acip.isEmpty && status?.gatewayAddress != null) {
        acip = status!.gatewayAddress!;
      }

      var apmac = getParam('apmac');
      if (apmac.isEmpty && status?.apMac != null) {
        apmac = status!.apMac!;
      }

      if (apmac.isNotEmpty) {
        apmac = apmac.replaceAll(':', '').replaceAll('-', '').toLowerCase();
      }

      if (acip.isEmpty || apmac.isEmpty) {
        lastError =
            'Missing gateway parameters (acip/apmac) in portal redirect URL.';
        return false;
      }

      final formInputs = parseFormInputs(first.body);
      final payload = <String, String>{};
      for (final entry in formInputs.entries) {
        payload[entry.key] = entry.value;
      }

      final userNameKey = payload.keys.firstWhere(
        (k) => k.toLowerCase() == 'username',
        orElse: () => 'userName',
      );
      payload[userNameKey] = studentId;

      final passwordKey = payload.keys.firstWhere(
        (k) => k.toLowerCase() == 'userpass' || k.toLowerCase() == 'password',
        orElse: () => 'userPass',
      );
      payload[passwordKey] = password;

      final resolvedPushPageId = getParam('pushPageId').isNotEmpty
          ? getParam('pushPageId')
          : (payload['pushPageId'] ?? '');

      final resolvedBase64Ssid = getParam('ssid').isNotEmpty
          ? getParam('ssid')
          : (payload['ssid'] ??
                (status?.ssid != null
                    ? base64.encode(utf8.encode(status!.ssid!))
                    : base64.encode(utf8.encode(ssid))));

      var resolvedUaddress = getParam('uaddress');
      if (resolvedUaddress.isEmpty && status?.ipAddress != null) {
        resolvedUaddress = status!.ipAddress!;
      }
      if (resolvedUaddress.isEmpty) {
        resolvedUaddress = payload['uaddress'] ?? '';
      }

      var resolvedUmac = getParam('umac');
      if (resolvedUmac.isEmpty) {
        resolvedUmac = deviceUmac ?? '';
      }
      if (resolvedUmac.isEmpty) {
        resolvedUmac = payload['umac'] ?? '';
      }
      if (resolvedUmac.isNotEmpty) {
        resolvedUmac = resolvedUmac
            .replaceAll(':', '')
            .replaceAll('-', '')
            .toLowerCase();
      }

      payload['pushPageId'] = resolvedPushPageId;
      payload['apmac'] = apmac;
      payload['ssid'] = resolvedBase64Ssid;
      payload['uaddress'] = resolvedUaddress;
      payload['umac'] = resolvedUmac;
      payload['acip'] = acip;

      if (!payload.containsKey('authType')) {
        payload['authType'] = getParam('authType', '1');
      }
      if (!payload.containsKey('agreed')) {
        payload['agreed'] = getParam('agreed', '1');
      }

      for (final key in [
        'esn',
        'armac',
        'accessMac',
        'businessType',
        'registerCode',
        'questions',
        'dynamicValidCode',
        'dynamicRSAToken',
        'validCode',
      ]) {
        if (!payload.containsKey(key)) {
          payload[key] = getParam(key);
        }
      }

      final encoded = Uri(queryParameters: payload).query;

      lastResponseLog =
          '--- CAPTIVE LOGIN DIAGNOSTICS ---\n'
          'Target Login URI: $apiLoginUri\n'
          'Referer URI: $loginUri\n'
          'Request Body (Encoded): $encoded\n'
          'Request Body (Decoded): $payload\n'
          'Initiating POST request...\n';

      await Future<void>.delayed(const Duration(seconds: 3));

      CaptiveWifiHttpResult? response;
      for (var attempt = 0; attempt < 3; attempt++) {
        if (attempt > 0) {
          await Future<void>.delayed(const Duration(seconds: 3));
        }
        try {
          response = await postOnce(
            client: client,
            uri: apiLoginUri,
            body: encoded,
            cookies: cookies,
            referer: loginUri,
          );
          if (response.statusCode < 400) {
            final decoded = jsonDecode(response.body);
            if (decoded is Map && decoded['success'] != false) {
              break;
            }
          }
        } catch (_) {}
      }

      if (response == null || response.statusCode >= 400) {
        lastError = response == null
            ? 'POST login connection failed.'
            : 'POST login failed with HTTP status ${response.statusCode}';

        return false;
      }

      lastResponseLog =
          '--- LOGIN RESPONSE ---\n'
          'Status: ${response.statusCode}\n'
          'Body: ${response.body}\n';

      String? successUrl;
      try {
        final decoded = jsonDecode(response.body);
        if (decoded is Map) {
          if (decoded['success'] == false) {
            final errorCode = decoded['errorcode']?.toString() ?? '';
            lastError = _mapPortalErrorCode(errorCode);

            return false;
          }
          successUrl = (decoded['successUrl'] ?? decoded['successurl'])
              ?.toString();
          if (successUrl != null && successUrl.isNotEmpty) {
            unawaited(CaptiveLoginStore.instance.saveSuccessUrl(successUrl));
          }
        }
      } catch (_) {
        assert(true);
      }

      try {
        final apiSyncUri = loginUri.replace(
          path: '$apiBasePath/syncPortalResult',
          queryParameters: {},
        );

        if (!cookies.containsKey('countdown')) {
          cookies['countdown'] = Cookie('countdown', '0');
        }
        final syncVal = successUrl ?? 'null';

        final syncResponse = await postOnce(
          client: client,
          uri: apiSyncUri,
          body: 'successUrl=${Uri.encodeComponent(syncVal)}',
          cookies: cookies,
          referer: loginUri,
        );

        lastResponseLog +=
            '\n--- SYNC RESPONSE ---\n'
            'Status: ${syncResponse.statusCode}\n'
            'Body: ${syncResponse.body}\n';

        if (syncResponse.statusCode == 200) {
          final syncDecoded = jsonDecode(syncResponse.body);
          if (syncDecoded is Map && syncDecoded['success'] == false) {
            final errorCode = syncDecoded['errorcode']?.toString() ?? '';
            lastError = _mapPortalErrorCode(errorCode);

            return false;
          }
        } else {
          lastError =
              'POST syncPortalResult failed with HTTP status ${syncResponse.statusCode}';

          return false;
        }
      } catch (e) {
        lastError = 'Network error during session sync.';

        return false;
      }

      await Future<void>.delayed(const Duration(seconds: 3));

      final redirectTarget =
          response.location ??
          (successUrl != null ? Uri.tryParse(successUrl) : null);
      if (redirectTarget != null) {
        final redirected = redirectTarget.isAbsolute
            ? redirectTarget
            : apiLoginUri.resolveUri(redirectTarget);

        final successRedirectResult = await getWithRedirects(
          client: client,
          uri: redirected,
          cookies: cookies,
        );
        if (successRedirectResult.uri != redirected) {
          unawaited(
            CaptiveLoginStore.instance.saveSuccessUrl(
              successRedirectResult.uri.toString(),
            ),
          );
        }
      }

      final probeSuccess = await isValidatedViaProbe(
        client: client,
        cookies: cookies,
      );

      if (probeSuccess) {
        unawaited(
          CaptiveLoginStore.instance.saveLastLoginAt(
            DateTime.now().millisecondsSinceEpoch,
          ),
        );
      } else {
        lastError =
            'Gateway authentication POST completed but probe to generate_204 failed (still captive)';
      }
      return probeSuccess;
    } catch (e) {
      lastError = 'Connection error. Make sure you are on $ssid.';

      return false;
    } finally {
      client.close(force: true);
    }
  }

  Future<bool> logoutViaCaptiveApi({
    required Uri captiveWifiUrl,
    required String ssid,
  }) async {
    lastError = null;
    lastResponseLog = '';
    final client = await newClient();
    final cookies = sessionCookies;

    final savedSuccessUrl = await CaptiveLoginStore.instance.readSuccessUrl();
    var targetUrl = savedSuccessUrl != null && savedSuccessUrl.isNotEmpty
        ? Uri.parse(savedSuccessUrl)
        : captiveWifiUrl;
    if (targetUrl == defaultProbeUri) {
      final savedUrlStr = await CaptiveLoginStore.instance.readLastPortalUrl();
      if (savedUrlStr != null && savedUrlStr.isNotEmpty) {
        final parsed = Uri.tryParse(savedUrlStr);
        if (parsed != null) {
          targetUrl = parsed;
        }
      }
    }

    try {
      final first = await getWithRedirects(
        client: client,
        uri: targetUrl,
        cookies: cookies,
      );
      final loginUri = first.uri;

      String? parsedLogoutPath;
      final logoutFormReg = RegExp(
        r'''<form\b[^>]*\baction\s*=\s*(?:["']([^"']*)["']|([^\s>]+))''',
        caseSensitive: false,
      );
      for (final match in logoutFormReg.allMatches(first.body)) {
        final action = (match.group(1) ?? match.group(2) ?? '').trim();
        if (action.toLowerCase().contains('logout')) {
          parsedLogoutPath = action;
          break;
        }
      }

      if (parsedLogoutPath == null) {
        final logoutLinkReg = RegExp(
          r'''<a\b[^>]*\bhref\s*=\s*(?:["']([^"']*)["']|([^\s>]+))''',
          caseSensitive: false,
        );
        for (final match in logoutLinkReg.allMatches(first.body)) {
          final href = (match.group(1) ?? match.group(2) ?? '').trim();
          if (href.toLowerCase().contains('logout')) {
            parsedLogoutPath = href;
            break;
          }
        }
      }

      Uri apiLogoutUri;
      if (parsedLogoutPath != null && parsedLogoutPath.isNotEmpty) {
        apiLogoutUri = Uri.parse(parsedLogoutPath).isAbsolute
            ? Uri.parse(parsedLogoutPath)
            : loginUri.resolve(parsedLogoutPath);
      } else {
        String logoutBasePath = '/portalauth';
        final initialPath = loginUri.path;
        if (initialPath.contains('/')) {
          logoutBasePath = initialPath.substring(
            0,
            initialPath.lastIndexOf('/'),
          );
        }
        apiLogoutUri = loginUri.replace(
          path: '$logoutBasePath/logout',
          queryParameters: {},
        );
      }

      if (!cookies.containsKey('countdown')) {
        cookies['countdown'] = Cookie('countdown', '0');
      }

      final response = await postOnce(
        client: client,
        uri: apiLogoutUri,
        body: '',
        cookies: cookies,
        referer: loginUri,
      );

      lastResponseLog =
          '--- LOGOUT RESPONSE ---\n'
          'Status: ${response.statusCode}\n'
          'Body: ${response.body}\n';

      if (response.statusCode >= 400) {
        lastError =
            'POST logout failed with HTTP status ${response.statusCode}';

        return false;
      }

      try {
        final decoded = jsonDecode(response.body);
        if (decoded is Map && decoded['success'] == false) {
          final errorCode = decoded['errorcode']?.toString() ?? '';
          lastError = _mapPortalErrorCode(errorCode);

          return false;
        }
      } catch (_) {
        assert(true);
      }

      sessionCookies.clear();

      return true;
    } catch (e) {
      lastError = 'Connection error. Make sure you are on $ssid.';

      return false;
    } finally {
      client.close(force: true);
    }
  }

  Future<CaptiveWifiHttpResult> getOnce({
    required HttpClient client,
    required Uri uri,
    required Map<String, Cookie> cookies,
    Uri? referer,
  }) async {
    final request = await client.getUrl(uri);
    request.followRedirects = false;
    if (referer != null) {
      request.headers.set('Referer', referer.toString());
    }
    final cookieHeader = _cookieHeader(cookies);
    if (cookieHeader != null) {
      request.headers.set('Cookie', cookieHeader);
    }
    final response = await request.close();
    _captureCookies(response, cookies);
    final location =
        response.headers.value('location') ??
        response.headers.value('Location');
    final text = await response.transform(utf8.decoder).join();

    return CaptiveWifiHttpResult(
      statusCode: response.statusCode,
      uri: uri,
      body: text,
      location: location == null ? null : Uri.parse(location),
    );
  }

  String _mapPortalErrorCode(String errorCode) {
    switch (errorCode) {
      case '10503':
        return 'Incorrect Student ID or password.';
      case '10505':
      case '10514':
        return 'Account is locked. Please try again later.';
      case '10513':
        return 'Your password has expired.';
      case '10515':
        return 'Access denied: you do not comply with the access rules.';
      case '10516':
        return 'exceeded the limit';
      case '10517':
        return 'Access not configured for this account.';
      case '10518':
        return 'MAC address does not match.';
      case '10519':
        return 'IP address does not match.';
      case '10520':
        return 'Device IP does not match.';
      case '10528':
        return 'MAC account has expired.';
      case '10605':
        return 'No remaining traffic or time quota.';
      case '10706':
        return 'Access restriction reached.';
      case '10711':
      case '10712':
        return 'Online user limit reached.';
      case '10713':
        return 'Traffic or time quota exhausted.';
      case '20102':
        return 'The system is busy. Please try again later.';
      case '20104':
        return 'Authentication request timed out.';
      case '3001':
        return 'Invalid input. Please check your credentials.';
      default:
        return 'Incorrect Student ID or password.';
    }
  }
}
