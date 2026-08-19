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

      if (first.statusCode == 204) {
        final validated = await isValidatedViaProbe(
          client: client,
          cookies: cookies,
        );
        if (validated) return true;
      }

      var loginUri = first.uri;
      var loginPageBody = first.body;
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

      await Future<void>.delayed(const Duration(milliseconds: 1500));

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

      final response = await retryOperation(
        () => postOnce(
          client: client,
          uri: apiLoginUri,
          body: encoded,
          cookies: cookies,
          referer: loginUri,
        ),
        isSuccess: (res) => res != null && res.statusCode < 400,
      );

      if (response == null) return false;

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
      case '3000':
        return 'The parameter is empty.';
      case '3014':
        return 'The total number of users has reached the upper limit.';
      case '3019':
      case '10900':
      case '10901':
      case '20100':
      case '20101':
        return 'An internal server exception occurred.';
      case '4000':
        return 'Enter your student ID and password.';
      case '4015':
        return 'The account has been temporarily locked.';
      case '10101':
        return 'The user notice is not checked.';
      case '10102':
        return 'Authentication type is illegal.';
      case '10103':
        return 'User IP address is illegal.';
      case '10104':
        return 'User MAC address is illegal.';
      case '10105':
        return 'Already on the current network.';
      case '10200':
        return 'Device information verification failed.';
      case '10201':
        return 'Authentication failed: device does not exist.';
      case '10202':
        return 'Abnormal license status on portal.';
      case '10203':
        return 'SSID does not exist.';
      case '10216':
        return 'Device IP address does not exist.';
      case '10300':
        return 'Authentication type verification failed.';
      case '10301':
        return 'Authentication is disabled.';
      case '10303':
        return 'Username password authentication is not enabled.';
      case '10400':
        return 'MAC-free authentication failed.';
      case '10403':
        return 'MAC-free authentication expired.';
      case '10500':
        return 'User information verification failed.';
      case '10501':
        return 'User does not exist.';
      case '10503':
        return 'Incorrect Student ID or password.';
      case '10504':
        return 'User account has expired.';
      case '10505':
        return 'The user has been locked. Try again later.';
      case '10508':
        return 'Authentication failed: password incorrect or account disabled.';
      case '10512':
        return 'Change your password upon first login.';
      case '10513':
        return 'Authentication failed because the password has expired.';
      case '10514':
        return 'The user has been locked. Contact the administrator.';
      case '10515':
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
        return 'Authentication failed: terminal authentication device IP does not match.';
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
        return 'Authentication failed: no remaining traffic or online duration.';
      case '10700':
        return 'Authorization failed.';
      case '10706':
        return 'Users have reached access restrictions.';
      case '10711':
        return 'Authentication failed: number of online users has reached the upper limit.';
      case '10712':
        return 'Authentication failed: number of access users exceeded the maximum.';
      case '10713':
        return 'Traffic or online time is exhausted.';
      case '10715':
        return 'Authorization rules deny user access.';
      case '10907':
      case '20400':
      case '20401':
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
      case '20104':
        return 'Authentication request timed out.';
      case '20205':
      case '20405':
        return 'Device has reached the maximum access limit.';
      default:
        return 'Incorrect Student ID or password.';
    }
  }
}
