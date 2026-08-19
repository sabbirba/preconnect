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
  String? lastRequestUrl;
  static final Uri defaultProbeUri = Uri.parse(
    'http://connectivitycheck.gstatic.com/generate_204',
  );

  static const String kPreConnectUserAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36';

  static const Duration kRetryDelay = Duration(milliseconds: 1500);
  static const int kRetryAttempts = 3;

  static Future<T?> retryOperation<T>(
    Future<T?> Function() action, {
    int attempts = kRetryAttempts,
    Duration delay = kRetryDelay,
    bool Function(T? result)? isSuccess,
  }) async {
    T? result;
    for (var i = 0; i < attempts; i++) {
      if (i > 0) {
        await Future<void>.delayed(delay);
      }
      try {
        result = await action();
        if (isSuccess != null ? isSuccess(result) : result != null) {
          return result;
        }
      } catch (_) {
        if (i == attempts - 1) rethrow;
      }
    }
    return result;
  }

  static const Duration _connectionTimeout = Duration(seconds: 10);
  final Map<String, Cookie> sessionCookies = {};
  String? lastErrorCode;
  bool isLastFatal = false;

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

  static const List<String> kProbeUrls = [
    'http://connectivitycheck.gstatic.com/generate_204',
    'http://www.google.com/generate_204',
    'http://gstatic.com/generate_204',
  ];

  static Future<Uri?> detectCaptivePortal() async {
    if (AndroidNetworkAssist.isSupported) {
      await AndroidNetworkAssist.bindToWifiNetwork();
    }
    try {
      final client = HttpClient()
        ..userAgent = kPreConnectUserAgent
        ..connectionTimeout = const Duration(seconds: 4);
      client.badCertificateCallback = (cert, host, port) => true;

      for (final probeStr in kProbeUrls) {
        try {
          final probeUri = Uri.parse(probeStr);
          final request = await client.getUrl(probeUri);
          request.followRedirects = false;
          final response = await request.close().timeout(
            const Duration(seconds: 4),
          );
          final status = response.statusCode;
          final location =
              response.headers.value('location') ??
              response.headers.value('Location');
          if (status >= 300 && status < 400 && location != null) {
            final parsed = Uri.tryParse(location);
            if (parsed != null) {
              return parsed.isAbsolute ? parsed : probeUri.resolve(location);
            }
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
                  final parsed = Uri.tryParse(targetUrl);
                  if (parsed != null) {
                    return parsed.isAbsolute
                        ? parsed
                        : probeUri.resolve(targetUrl);
                  }
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
                final parsed = Uri.tryParse(targetUrl);
                if (parsed != null) {
                  return parsed.isAbsolute
                      ? parsed
                      : probeUri.resolve(targetUrl);
                }
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
                final parsed = Uri.tryParse(targetUrl);
                if (parsed != null) {
                  return parsed.isAbsolute
                      ? parsed
                      : probeUri.resolve(targetUrl);
                }
              }
            }

            if (body.contains('/portalpage/') ||
                body.contains('portalauth') ||
                body.contains('wlanuserip')) {
              return Uri.parse('http://${probeUri.host}/portalpage/index.html');
            }
          }
        } catch (_) {}
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

    final jsVarReg = RegExp(
      r'''\b(?:var|let|const|window\.)\s*([a-zA-Z0-9_]+)\s*=\s*["']([^"']*)["']''',
      caseSensitive: false,
    );
    for (final match in jsVarReg.allMatches(html)) {
      final key = (match.group(1) ?? '').trim();
      final val = (match.group(2) ?? '').trim();
      if (key.isNotEmpty && !inputs.containsKey(key)) {
        inputs[key] = val;
      }
    }

    final jsObjReg = RegExp(
      r'''["']?([a-zA-Z0-9_]+)["']?\s*:\s*["']([^"']*)["']''',
    );
    for (final match in jsObjReg.allMatches(html)) {
      final key = (match.group(1) ?? '').trim();
      final val = (match.group(2) ?? '').trim();
      if (key.isNotEmpty && !inputs.containsKey(key)) {
        inputs[key] = val;
      }
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

  static Future<bool> checkInternetAccess({Uri? probeUri}) async {
    final client = HttpClient()..userAgent = kPreConnectUserAgent;
    client.connectionTimeout = const Duration(seconds: 4);
    client.badCertificateCallback = (cert, host, port) => true;
    try {
      final request = await client.getUrl(probeUri ?? defaultProbeUri);
      request.followRedirects = false;
      final response = await request.close();
      return response.statusCode == 204;
    } catch (_) {
      return false;
    } finally {
      client.close(force: true);
    }
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
    request.headers.set('User-Agent', kPreConnectUserAgent);
    request.headers.set(
      'Accept',
      'application/json, text/javascript, */*; q=0.01',
    );
    request.headers.set('Accept-Language', 'en-US,en;q=0.9');
    request.headers.set(
      'Content-Type',
      'application/x-www-form-urlencoded; charset=UTF-8',
    );
    request.headers.set('X-Requested-With', 'XMLHttpRequest');

    if (referer != null) {
      request.headers.set('Referer', referer.toString());
      final portStr =
          (referer.hasPort && referer.port != 80 && referer.port != 443)
          ? ':${referer.port}'
          : '';
      request.headers.set(
        'Origin',
        '${referer.scheme}://${referer.host}$portStr',
      );
    }

    String? xsrfToken;
    for (final cookie in cookies.values) {
      if (cookie.name.toUpperCase() == 'XSRF-TOKEN') {
        xsrfToken = cookie.value;
        break;
      }
    }
    request.headers.set('X-XSRF-TOKEN', xsrfToken ?? 'null');

    if (!cookies.containsKey('countdown')) {
      cookies['countdown'] = Cookie('countdown', '0');
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
  }) async {
    lastError = null;
    lastErrorCode = null;
    isLastFatal = false;
    lastResponseLog = '';
    if (AndroidNetworkAssist.isSupported) {
      await AndroidNetworkAssist.bindToWifiNetwork();
    }
    final client = await newClient();
    final cookies = sessionCookies;
    cookies.clear();

    var targetUrl = captiveWifiUrl;
    if (targetUrl == defaultProbeUri) {
      final detected = await detectCaptivePortal();
      if (detected != null) {
        targetUrl = detected;
      } else {
        final savedUrlStr = await CaptiveLoginStore.instance
            .readLastPortalUrl();
        if (savedUrlStr != null && savedUrlStr.isNotEmpty) {
          final parsed = Uri.tryParse(savedUrlStr);
          if (parsed != null) {
            targetUrl = parsed;
          }
        }
      }
    }

    try {
      final first = await getWithRedirects(
        client: client,
        uri: targetUrl,
        cookies: cookies,
      );

      var loginUri = first.uri;
      var loginPageBody = first.body;

      if (first.statusCode == 204 ||
          loginUri.path.contains('authSuccess') ||
          loginPageBody.contains('authSuccess.html')) {
        final validated = await isValidatedViaProbe(
          client: client,
          cookies: cookies,
        );
        if (validated || loginUri.path.contains('authSuccess')) {
          return true;
        }
      }
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
            loginPageBody = second.body;

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

      final apiLoginUri = loginUri.replace(
        path: '/portalauth/login',
        queryParameters: {},
      );

      final status = await AndroidNetworkAssist.getNetworkStatus();
      var deviceUmac = status?.clientMac;
      if (deviceUmac != null) {
        deviceUmac = deviceUmac
            .replaceAll(':', '')
            .replaceAll('-', '')
            .toLowerCase();
      }

      final params = loginUri.queryParameters;

      String getParam(String key, [String defaultValue = '']) {
        var val = params[key];
        if (val == null || val.isEmpty) {
          if (key == 'acip') {
            val = params['wlanacip'] ?? params['ac-ip'] ?? params['ac_ip'];
          } else if (key == 'apmac') {
            val = params['wlanapmac'] ?? params['ap-mac'] ?? params['ap_mac'];
          } else if (key == 'uaddress') {
            val =
                params['wlanuserip'] ?? params['user-ip'] ?? params['user_ip'];
          } else if (key == 'umac') {
            val =
                params['wlanusermac'] ??
                params['user-mac'] ??
                params['user_mac'];
          } else if (key == 'accessMac') {
            val = params['wlanacmac'] ?? params['ac-mac'] ?? params['ac_mac'];
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

      final formInputs = parseFormInputs(loginPageBody);
      final resolvedPushPageId = getParam('pushPageId').isNotEmpty
          ? getParam('pushPageId')
          : (formInputs['pushPageId'] ?? '');

      final resolvedBase64Ssid = getParam('ssid').isNotEmpty
          ? getParam('ssid')
          : (formInputs['ssid'] ??
                base64.encode(
                  utf8.encode(CaptiveLoginStore.defaultCampusSsid),
                ));

      var resolvedUaddress = getParam('uaddress');
      if (resolvedUaddress.isEmpty && status?.ipAddress != null) {
        resolvedUaddress = status!.ipAddress!;
      }
      if (resolvedUaddress.isEmpty) {
        resolvedUaddress = formInputs['uaddress'] ?? '';
      }

      var resolvedUmac = getParam('umac');
      if (resolvedUmac.isEmpty) {
        resolvedUmac = deviceUmac ?? '';
      }
      if (resolvedUmac.isEmpty) {
        resolvedUmac = formInputs['umac'] ?? '';
      }
      if (resolvedUmac.isNotEmpty) {
        resolvedUmac = resolvedUmac
            .replaceAll(':', '')
            .replaceAll('-', '')
            .toLowerCase();
      }

      final payload = <String, String>{
        'pushPageId': resolvedPushPageId,
        'userPass': password,
        'esn': getParam('esn'),
        'apmac': apmac,
        'armac': getParam('armac'),
        'authType': getParam('authType', '1'),
        'ssid': resolvedBase64Ssid,
        'uaddress': resolvedUaddress,
        'umac': resolvedUmac,
        'accessMac': getParam('accessMac'),
        'businessType': getParam('businessType'),
        'acip': acip,
        'agreed': getParam('agreed', '1'),
        'registerCode': getParam('registerCode'),
        'questions': getParam('questions'),
        'dynamicValidCode': getParam('dynamicValidCode'),
        'dynamicRSAToken': getParam('dynamicRSAToken'),
        'validCode': getParam('validCode'),
        'userName': studentId,
      };

      final encoded = Uri(queryParameters: payload).query;
      lastRequestUrl = _buildDisplayUrl(apiLoginUri, payload);

      final response = await postOnce(
        client: client,
        uri: apiLoginUri,
        body: encoded,
        cookies: cookies,
        referer: loginUri,
      );

      lastResponseLog =
          '--- LOGIN RESPONSE ---\n'
          'Status: ${response.statusCode}\n'
          'Body: ${response.body}\n';

      if (response.statusCode >= 400) {
        lastError = 'POST login failed with HTTP status ${response.statusCode}';

        return false;
      }

      String? successUrl;
      try {
        final decoded = jsonDecode(response.body);
        if (decoded is Map) {
          if (decoded['success'] == false) {
            final errorCode = decoded['errorcode']?.toString() ?? '';
            if (errorCode == '10105') {
              return true;
            }
            final probeOk = await isValidatedViaProbe(
              client: client,
              cookies: cookies,
            );
            if (probeOk) return true;

            lastErrorCode = errorCode;
            isLastFatal = isFatalErrorCode(errorCode);
            lastError = _mapPortalErrorCode(errorCode);

            return false;
          }
          final token = decoded['token']?.toString();
          if (token != null && token.isNotEmpty) {
            cookies['XSRF-TOKEN'] = Cookie('XSRF-TOKEN', token);
            unawaited(CaptiveLoginStore.instance.saveSessionToken(token));
          }
          final psessionid = decoded['psessionid']?.toString();
          if (psessionid != null && psessionid.isNotEmpty) {
            cookies['PSESSIONID'] = Cookie('PSESSIONID', psessionid);
            unawaited(CaptiveLoginStore.instance.savePSessionId(psessionid));
          }
          successUrl = (decoded['successUrl'] ?? decoded['successurl'])
              ?.toString();
          if (successUrl != null && successUrl.isNotEmpty) {
            unawaited(CaptiveLoginStore.instance.saveSuccessUrl(successUrl));
          } else {
            final authSuccessUri = loginUri.replace(
              path: loginUri.path.replaceAll('/auth.html', '/authSuccess.html'),
              queryParameters: {
                ...loginUri.queryParameters,
                'chanFir': 'n',
                'userInfo': studentId,
                'remainTime': '',
                'remainFlow': '',
                'validPeriod': '',
                'isEscape': '',
              },
            );
            unawaited(
              CaptiveLoginStore.instance.saveSuccessUrl(
                authSuccessUri.toString(),
              ),
            );
          }
        }
      } catch (_) {
        assert(true);
      }

      try {
        final apiSyncUri = loginUri.replace(
          path: '/portalauth/syncPortalResult',
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
          if (syncDecoded is Map) {
            if (syncDecoded['success'] == false) {
              final errorCode = syncDecoded['errorcode']?.toString() ?? '';
              if (errorCode == '10105') {
                return true;
              }
              final probeOk = await isValidatedViaProbe(
                client: client,
                cookies: cookies,
              );
              if (probeOk) return true;

              lastErrorCode = errorCode;
              isLastFatal = isFatalErrorCode(errorCode);
              lastError = _mapPortalErrorCode(errorCode);

              return false;
            }
            final data = syncDecoded['data'];
            if (data is Map) {
              final validPeriod = data['validPeriod']?.toString();
              if (validPeriod != null) {
                unawaited(
                  CaptiveLoginStore.instance.saveValidPeriod(validPeriod),
                );
              }
              final remainTime = data['remainTime']?.toString();
              if (remainTime != null) {
                unawaited(
                  CaptiveLoginStore.instance.saveRemainTime(remainTime),
                );
              }
            }
          }
        } else {
          final probeOk = await isValidatedViaProbe(
            client: client,
            cookies: cookies,
          );
          if (probeOk) return true;
          lastError =
              'POST syncPortalResult failed with HTTP status ${syncResponse.statusCode}';

          return false;
        }
      } catch (e) {
        final probeOk = await isValidatedViaProbe(
          client: client,
          cookies: cookies,
        );
        if (probeOk) return true;
        lastError = 'Network error during session sync.';

        return false;
      }

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

      if (probeSuccess || response.statusCode == 200) {
        unawaited(
          CaptiveLoginStore.instance.saveLastLoginAt(
            DateTime.now().millisecondsSinceEpoch,
          ),
        );
        if (AndroidNetworkAssist.isSupported) {
          unawaited(AndroidNetworkAssist.reportCaptivePortalDismissed());
        }
        return true;
      }
      lastError =
          'Gateway authentication POST completed but probe to generate_204 failed (still captive)';
      return false;
    } catch (e) {
      lastError =
          'Connection error. Make sure you are on ${CaptiveLoginStore.defaultCampusSsid}.';

      return false;
    } finally {
      client.close(force: true);
      if (AndroidNetworkAssist.isSupported) {
        await AndroidNetworkAssist.unbindFromWifiNetwork();
      }
    }
  }

  Future<bool> sendKeepAliveHeartbeat({Uri? captiveWifiUrl}) async {
    try {
      final savedToken = await CaptiveLoginStore.instance.readSessionToken();
      final savedPSessionId = await CaptiveLoginStore.instance.readPSessionId();
      if (savedToken == null || savedToken.isEmpty) return false;
      final client = await newClient();
      final cookies = sessionCookies;
      cookies['XSRF-TOKEN'] = Cookie('XSRF-TOKEN', savedToken);
      if (savedPSessionId != null && savedPSessionId.isNotEmpty) {
        cookies['PSESSIONID'] = Cookie('PSESSIONID', savedPSessionId);
      }
      if (!cookies.containsKey('countdown')) {
        cookies['countdown'] = Cookie('countdown', '0');
      }
      final savedSuccessUrl = await CaptiveLoginStore.instance.readSuccessUrl();
      var targetUrl = savedSuccessUrl != null && savedSuccessUrl.isNotEmpty
          ? Uri.parse(savedSuccessUrl)
          : (captiveWifiUrl ?? defaultProbeUri);
      if (targetUrl == defaultProbeUri) {
        final savedUrlStr = await CaptiveLoginStore.instance
            .readLastPortalUrl();
        if (savedUrlStr != null && savedUrlStr.isNotEmpty) {
          final parsed = Uri.tryParse(savedUrlStr);
          if (parsed != null) {
            targetUrl = parsed;
          }
        }
      }
      final apiSyncUri = targetUrl.replace(
        path: '/portalauth/syncPortalResult',
        queryParameters: {},
      );
      final syncResponse = await postOnce(
        client: client,
        uri: apiSyncUri,
        body: 'successUrl=null',
        cookies: cookies,
        referer: targetUrl,
      );
      client.close(force: true);
      if (syncResponse.statusCode == 200) {
        final syncDecoded = jsonDecode(syncResponse.body);
        if (syncDecoded is Map && syncDecoded['success'] == true) {
          final data = syncDecoded['data'];
          if (data is Map) {
            final validPeriod = data['validPeriod']?.toString();
            if (validPeriod != null) {
              unawaited(
                CaptiveLoginStore.instance.saveValidPeriod(validPeriod),
              );
            }
            final remainTime = data['remainTime']?.toString();
            if (remainTime != null) {
              unawaited(CaptiveLoginStore.instance.saveRemainTime(remainTime));
            }
          }
          return true;
        }
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  Future<bool> logoutViaCaptiveApi({required Uri captiveWifiUrl}) async {
    lastError = null;
    lastResponseLog = '';
    if (AndroidNetworkAssist.isSupported) {
      await AndroidNetworkAssist.bindToWifiNetwork();
    }
    final client = await newClient();
    final cookies = sessionCookies;

    final savedToken = await CaptiveLoginStore.instance.readSessionToken();
    if (savedToken != null && savedToken.isNotEmpty) {
      cookies['XSRF-TOKEN'] = Cookie('XSRF-TOKEN', savedToken);
    }
    final savedPSessionId = await CaptiveLoginStore.instance.readPSessionId();
    if (savedPSessionId != null && savedPSessionId.isNotEmpty) {
      cookies['PSESSIONID'] = Cookie('PSESSIONID', savedPSessionId);
    }
    if (!cookies.containsKey('countdown')) {
      cookies['countdown'] = Cookie('countdown', '0');
    }

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
    if (targetUrl == defaultProbeUri) {
      final status = AndroidNetworkAssist.isSupported
          ? await AndroidNetworkAssist.getNetworkStatus()
          : null;
      final host = status?.gatewayAddress ?? 'wifi2.bracu.ac.bd';
      final port = host.contains('bracu.ac.bd') ? 19008 : 8080;
      final scheme = port == 19008 ? 'https' : 'http';
      targetUrl = Uri(
        scheme: scheme,
        host: host,
        port: port,
        path: '/portalauth/logout',
      );
    }

    try {
      final loginUri = targetUrl;
      final apiLogoutUri = loginUri.replace(
        path: '/portalauth/logout',
        queryParameters: {},
      );

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
      await CaptiveLoginStore.instance.saveSuccessUrl('');
      await CaptiveLoginStore.instance.saveSessionToken('');
      await CaptiveLoginStore.instance.savePSessionId('');
      await CaptiveLoginStore.instance.saveValidPeriod('');
      await CaptiveLoginStore.instance.saveRemainTime('');
      await CaptiveLoginStore.instance.saveLastLoginAt(0);

      return true;
    } catch (e) {
      lastError =
          'Connection error. Make sure you are on ${CaptiveLoginStore.defaultCampusSsid}.';

      return false;
    } finally {
      client.close(force: true);
      if (AndroidNetworkAssist.isSupported) {
        await AndroidNetworkAssist.unbindFromWifiNetwork();
      }
    }
  }

  String _buildDisplayUrl(Uri baseUri, Map<String, String> payload) {
    final masked = Map<String, String>.from(payload);
    if (masked.containsKey('userPass')) {
      masked['userPass'] = '••••••••';
    }
    final query = Uri(queryParameters: masked).query;
    return '$baseUri?$query';
  }

  String _mapPortalErrorCode(String errorCode) {
    switch (errorCode) {
      case '0':
        return 'Success';
      case '1006':
        return 'Deregistration failed because the session has timed out.';
      case '1009':
        return 'Access error.';
      case '1110':
        return 'Failed to get password policy.';
      case '1113':
        return 'The password will expire.';
      case '2001':
      case '3001':
      case '10100':
        return 'Invalid parameter.';
      case '2002':
        return 'Invalid password length.';
      case '2003':
        return 'Password cannot start or end with a space.';
      case '2004':
        return 'Passwords do not match.';
      case '2005':
        return 'Password must contain digits.';
      case '2006':
        return 'Password does not contain special characters.';
      case '2007':
        return 'Password cannot match the username.';
      case '2008':
        return 'Identical characters in password exceed limit.';
      case '2009':
        return 'Password must contain uppercase letters.';
      case '2010':
        return 'Password must contain lowercase letters.';
      case '2011':
      case '2012':
        return 'Password repetition does not meet requirements.';
      case '2013':
        return 'Password can only contain digits, letters, and special characters.';
      case '3000':
        return 'The parameter is empty.';
      case '3002':
      case '3011':
      case '3012':
        return 'User group does not exist or is not configured.';
      case '3003':
      case '3020':
      case '3021':
        return 'Username or mobile number is already registered.';
      case '3004':
      case '13027':
        return 'Invalid email format.';
      case '3006':
        return 'Invalid phone number format.';
      case '3008':
        return 'Username contains invalid special characters.';
      case '3009':
        return 'Username field is too long.';
      case '3010':
      case '4002':
      case '0308000076':
        return 'Invalid verification code.';
      case '3014':
        return 'The total number of users has reached the upper limit.';
      case '3016':
        return 'Registration is not allowed at this time.';
      case '3017':
      case '4013':
      case '10201':
        return 'The authentication device does not exist.';
      case '3018':
        return 'Registration failed.';
      case '3019':
      case '10900':
      case '10901':
      case '20100':
      case '20101':
        return 'An internal server exception occurred.';
      case '3024':
        return 'Registration frequency exceeded limit. Try again later.';
      case '3025':
        return 'Invalid registration information.';
      case '4000':
        return 'Enter your Student ID and password.';
      case '4001':
        return 'Enter the verification code.';
      case '4003':
        return 'Password cannot be reset for this account.';
      case '4008':
        return 'Enter the dynamic verification code.';
      case '4009':
      case '4017':
        return 'Incorrect or expired verification code.';
      case '4010':
      case '4011':
      case '4012':
        return 'Passwords do not match.';
      case '4014':
        return 'Failed to reset password.';
      case '4015':
      case '10505':
      case '10514':
      case '0308000095':
        return 'The user account has been locked. Try again later.';
      case '4018':
        return 'Password cannot match recent historical passwords.';
      case '4019':
        return 'Invalid username.';
      case '4020':
        return 'Account does not exist or function not supported.';
      case '4022':
        return 'RSA dynamic password is incorrect.';
      case '10101':
        return 'User notice must be accepted.';
      case '10102':
        return 'Authentication type is illegal.';
      case '10103':
        return 'User IP address is illegal.';
      case '10104':
        return 'User MAC address is illegal.';
      case '10105':
        return 'Already on the current network.';
      case '10106':
      case '10107':
      case '10541':
        return 'Network switchover failed.';
      case '10200':
        return 'Device information verification failed.';
      case '10202':
      case '10206':
        return 'Abnormal license status on portal.';
      case '10203':
        return 'SSID does not exist.';
      case '10216':
        return 'Device IP address does not exist.';
      case '10217':
        return 'Portal 2.0 shared key does not exist.';
      case '10300':
        return 'Authentication type verification failed.';
      case '10301':
        return 'Authentication is disabled.';
      case '10302':
      case '10303':
        return 'Username password authentication is not enabled.';
      case '10400':
        return 'MAC-free authentication failed.';
      case '10401':
      case '10402':
      case '10403':
        return 'MAC-free authentication expired or not found.';
      case '10500':
        return 'User information verification failed.';
      case '10501':
        return 'User does not exist.';
      case '10502':
        return 'Directory server connection abnormal.';
      case '10503':
        return 'Incorrect Student ID or password.';
      case '10504':
      case '0308000094':
        return 'User account has expired.';
      case '10506':
        return 'Invalid passcode.';
      case '10508':
      case '0308000096':
        return 'Authentication failed: account disabled or incorrect password.';
      case '10509':
      case '10510':
      case '10511':
        return 'Self-registered account pending approval or rejected.';
      case '10512':
        return 'Change your password upon first login.';
      case '10513':
        return 'Authentication failed: password has expired.';
      case '10515':
      case '10715':
        return 'Authentication failed: access denied by network rules.';
      case '10516':
        return 'Authentication failed: maximum terminal limit exceeded.';
      case '10517':
        return 'Authentication failed: account is not configured with access parameters.';
      case '10518':
        return 'Authentication failed: terminal MAC does not match.';
      case '10519':
        return 'Authentication failed: terminal IP does not match.';
      case '10520':
        return 'Authentication failed: terminal device IP does not match.';
      case '10528':
        return 'Authentication failed: MAC account has expired.';
      case '10540':
        return 'Account is not allowed to log in during this time.';
      case '10542':
        return 'Authentication is too frequent. Please try again later.';
      case '10543':
        return 'Failed to verify subscriber information.';
      case '10545':
        return 'The portal page does not exist.';
      case '10605':
      case '10713':
        return 'Authentication failed: no remaining traffic or online duration.';
      case '10700':
        return 'Authorization failed.';
      case '10705':
        return 'Online rejection, cover users failed.';
      case '10706':
        return 'Users have reached access restrictions.';
      case '10711':
        return 'Authentication failed: maximum online users reached.';
      case '10712':
        return 'Authentication failed: maximum access users exceeded.';
      case '10716':
        return 'No available license. Contact administrator.';
      case '10907':
      case '20400':
      case '20401':
      case '20402':
      case '20404':
        return 'RADIUS server authentication failed.';
      case '10909':
        return 'The user is not online.';
      case '20000':
      case '20001':
      case '20207':
        return 'Device response is invalid.';
      case '20002':
      case '20208':
      case '20406':
        return 'Device response timed out.';
      case '20102':
      case '20203':
      case '20403':
        return 'The system is busy. Please try again later.';
      case '20103':
        return 'Authentication packet failed to send.';
      case '20104':
        return 'Authentication request timed out.';
      case '20200':
      case '20202':
      case '20204':
        return 'Device response to challenge packet failed.';
      case '20201':
        return 'Device refuses to respond to challenge packet.';
      case '20205':
      case '20405':
        return 'Device has reached the maximum access limit.';
      case '20206':
        return 'Device prohibits user access.';
      case '0308000002':
        return 'Invalid input parameter.';
      default:
        return 'Incorrect Student ID or password.';
    }
  }

  static bool isFatalErrorCode(String errorCode) {
    switch (errorCode) {
      case '10503':
      case '10501':
      case '10508':
      case '4000':
      case '10504':
      case '10505':
      case '10512':
      case '10513':
      case '10514':
      case '10515':
      case '10516':
      case '10517':
      case '10518':
      case '10519':
      case '10520':
      case '10528':
      case '10540':
      case '10605':
      case '10700':
      case '10705':
      case '10706':
      case '10711':
      case '10712':
      case '10713':
      case '10715':
      case '10716':
      case '10201':
      case '10202':
      case '10203':
      case '10300':
      case '10301':
      case '10303':
      case '2001':
      case '2002':
      case '2003':
      case '2004':
      case '2005':
      case '2006':
      case '2007':
      case '2008':
      case '2009':
      case '2010':
      case '2011':
      case '2012':
      case '2013':
      case '3000':
      case '3001':
      case '3002':
      case '3003':
      case '3004':
      case '3006':
      case '3008':
      case '3009':
      case '3010':
      case '3011':
      case '3012':
      case '3014':
      case '3016':
      case '3017':
      case '3018':
      case '3020':
      case '3021':
      case '3023':
      case '3025':
      case '3034':
      case '3038':
      case '4001':
      case '4002':
      case '4003':
      case '4008':
      case '4009':
      case '4010':
      case '4011':
      case '4012':
      case '4013':
      case '4014':
      case '4015':
      case '4017':
      case '4018':
      case '4019':
      case '4020':
      case '4022':
      case '10100':
      case '10101':
      case '10102':
      case '10103':
      case '10104':
      case '10106':
      case '10107':
      case '10200':
      case '10206':
      case '10216':
      case '10217':
      case '10302':
      case '10304':
      case '10305':
      case '10306':
      case '10307':
      case '10308':
      case '10309':
      case '10310':
      case '10311':
      case '10312':
      case '10313':
      case '10314':
      case '10315':
      case '10316':
      case '10318':
      case '10319':
      case '10320':
      case '10321':
      case '10322':
      case '10323':
      case '10400':
      case '10401':
      case '10402':
      case '10403':
      case '10404':
      case '10405':
      case '10406':
      case '10407':
      case '10408':
      case '10409':
      case '10410':
      case '10414':
      case '10416':
      case '10417':
      case '10418':
      case '10419':
      case '10420':
      case '10421':
      case '10422':
      case '10500':
      case '10502':
      case '10506':
      case '10509':
      case '10510':
      case '10511':
      case '10526':
      case '10527':
      case '10529':
      case '10530':
      case '10531':
      case '10539':
      case '10541':
      case '10543':
      case '10545':
      case '10550':
      case '10551':
      case '10552':
      case '10553':
      case '10554':
      case '10555':
      case '10556':
      case '15555':
      case '10708':
      case '10709':
      case '10710':
      case '10800':
      case '10801':
      case '10802':
      case '10803':
      case '10804':
      case '10805':
      case '10806':
      case '10807':
      case '10809':
      case '10811':
      case '10812':
      case '10813':
      case '10814':
      case '10815':
      case '10816':
      case '10817':
      case '10818':
      case '10819':
      case '10820':
      case '10821':
      case '10903':
      case '10904':
      case '10905':
      case '10906':
      case '10907':
      case '10908':
      case '13027':
      case '13028':
      case '9':
      case '10':
      case '20205':
      case '20206':
      case '20405':
      case '20407':
      case '20408':
      case '0308000002':
      case '0308000094':
      case '0308000095':
      case '0308000096':
      case '0308000012':
      case '0308000076':
      case '0308000014':
      case '030802003':
        return true;
      default:
        return false;
    }
  }
}
