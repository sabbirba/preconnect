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
  static final Uri defaultProbeUri = Uri.parse(
    'http://connectivitycheck.gstatic.com/generate_204',
  );

  static const String kPreConnectUserAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36';

  static const Duration _connectionTimeout = Duration(seconds: 10);
  final Map<String, Cookie> sessionCookies = {};

  static Uri? resolvePortalUri(AndroidNetworkStatus status) {
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

  Future<HttpClient> newClient() async {
    final client = HttpClient()..userAgent = kPreConnectUserAgent;
    client.connectionTimeout = _connectionTimeout;
    client.badCertificateCallback =
        (X509Certificate cert, String host, int port) => true;
    return client;
  }

  Future<void> requestSessionExtension(Uri uri) async {
    final client = await newClient();
    try {
      final request = await client.getUrl(uri);
      final response = await request.close();
      await response.drain<void>();
      if (response.statusCode < 200 || response.statusCode >= 400) {
        throw HttpException('HTTP ${response.statusCode}', uri: uri);
      }
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
    try {
      final result = await getWithRedirects(
        client: client,
        uri: target,
        cookies: cookies,
      );
      return result.statusCode == 204;
    } catch (_) {
      return false;
    }
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
  }) async {
    lastError = null;
    final client = await newClient();
    final cookies = sessionCookies;
    cookies.clear();

    try {
      var first = await getWithRedirects(
        client: client,
        uri: captiveWifiUrl,
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
      } catch (_) {}

      final apiLoginUri = loginUri.replace(
        path: '/portalauth/login',
        queryParameters: {},
      );

      final payload = <String, String>{
        'esn': '',
        'armac': '',
        'accessMac': '',
        'businessType': '',
        'acip': '',
        'agreed': '1',
        'registerCode': '',
        'questions': '',
        'dynamicValidCode': '',
        'dynamicRSAToken': '',
        'validCode': '',
        'apmac': 'c0f6ece2af00',
        'umac': '4655d0db28e7',
        'uaddress': '10.100.166.70',
        'pushPageId': '295b3998-ae5e-4e30-9706-bbb5394afc6e',
        'authType': '1',
        'lang': 'en_US',
        ...loginUri.queryParameters,
        'userName': studentId,
        'userPass': password,
      };

      final encoded = Uri(queryParameters: payload).query;
      final response = await postOnce(
        client: client,
        uri: apiLoginUri,
        body: encoded,
        cookies: cookies,
        referer: loginUri,
      );

      if (response.statusCode >= 400) {
        lastError = 'POST login failed with HTTP status ${response.statusCode}';
        return false;
      }

      if (response.location != null) {
        final redirected = response.location!.isAbsolute
            ? response.location!
            : apiLoginUri.resolveUri(response.location!);
        await getWithRedirects(
          client: client,
          uri: redirected,
          cookies: cookies,
        );
      }

      final probeSuccess = await isValidatedViaProbe(
        client: client,
        cookies: cookies,
      );
      if (!probeSuccess) {
        lastError =
            'Gateway authentication POST completed but probe to generate_204 failed (still captive)';
      }
      return probeSuccess;
    } catch (e) {
      lastError = 'Exception: $e';
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

  Future<bool> logoutViaCaptiveApi({required Uri captiveWifiUrl}) async {
    lastError = null;
    final client = await newClient();
    try {
      final candidates = <Map<String, String>>[
        {'path': '/portalauth/logout', 'method': 'POST'},
        {'path': '/portalauth/logout', 'method': 'GET'},
        {'path': '/portalauth/portal/logout', 'method': 'POST'},
        {'path': '/portalauth/portal/logout', 'method': 'GET'},
        {'path': '/portalpage/portal/logout', 'method': 'POST'},
        {'path': '/portalpage/portal/logout', 'method': 'GET'},
        {'path': '/portalpage/logout', 'method': 'POST'},
        {'path': '/portalpage/logout', 'method': 'GET'},
        {'path': captiveWifiUrl.resolve('logout').path, 'method': 'POST'},
        {'path': captiveWifiUrl.resolve('logout').path, 'method': 'GET'},
        {'path': captiveWifiUrl.resolve('logout.html').path, 'method': 'POST'},
        {'path': captiveWifiUrl.resolve('logout.html').path, 'method': 'GET'},
        {'path': captiveWifiUrl.resolve('../logout').path, 'method': 'POST'},
        {'path': captiveWifiUrl.resolve('../logout').path, 'method': 'GET'},
        {'path': captiveWifiUrl.resolve('../../logout').path, 'method': 'POST'},
        {'path': captiveWifiUrl.resolve('../../logout').path, 'method': 'GET'},
      ];

      for (final candidate in candidates) {
        final path = candidate['path']!;
        final method = candidate['method']!;

        Uri logoutUri;
        if (method == 'GET') {
          logoutUri = captiveWifiUrl.replace(path: path);
        } else {
          logoutUri = captiveWifiUrl.replace(path: path, queryParameters: {});
        }

        try {
          if (method == 'POST') {
            final payload = <String, String>{
              'apmac': 'c0f6ece2af00',
              'umac': '4655d0db28e7',
              'uaddress': '10.100.166.70',
              'pushPageId': '295b3998-ae5e-4e30-9706-bbb5394afc6e',
              'authType': '1',
              'lang': 'en_US',
              ...captiveWifiUrl.queryParameters,
            };
            final encoded = Uri(queryParameters: payload).query;
            await postOnce(
              client: client,
              uri: logoutUri,
              body: encoded,
              cookies: sessionCookies,
              referer: captiveWifiUrl,
            );
          } else {
            await getOnce(
              client: client,
              uri: logoutUri,
              cookies: sessionCookies,
              referer: captiveWifiUrl,
            );
          }

          final probeSuccess = await isValidatedViaProbe(
            client: client,
            cookies: sessionCookies,
          );
          if (!probeSuccess) {
            return true;
          }
        } catch (_) {}
      }

      lastError =
          'Tried all candidate logout endpoints, but probe still succeeded (still logged in).';
      return false;
    } catch (e) {
      lastError = 'Logout exception: $e';
      return false;
    } finally {
      client.close(force: true);
    }
  }
}
