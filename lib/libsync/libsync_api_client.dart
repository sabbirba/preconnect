import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'google_sign_in_helper.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'libsync_config.dart';
import 'client_creator.dart';
import 'google_auth_helper.dart';
import 'package:preconnect/api/preferences_store.dart';

class LibSyncApiClient extends http.BaseClient {
  LibSyncApiClient() : _inner = createLibSyncClient();

  final http.Client _inner;
  static String? _sessionIp;
  static const _secureStorage = FlutterSecureStorage();
  static const String _cookiesStorageKey = 'libsync_cookies';
  static const String _googleRefreshTokenKey = 'libsync_google_refresh_token';
  static const String _profileStorageKey = 'libsync_profile';
  static const String _etagCacheKey = 'libsync_etag_cache';
  static const String _bodyCacheKey = 'libsync_body_cache';
  static const String _headersCacheKey = 'libsync_headers_cache';
  static const String _throttledUntilKey = 'libsync_throttled_until';

  static final Map<String, String> _etagCache = {};
  static final Map<String, String> _bodyCache = {};
  static final Map<String, Map<String, String>> _headersCache = {};

  bool _cacheInitialized = false;

  Future<void> _ensureCacheLoaded() async {
    if (_cacheInitialized) return;
    try {
      final store = AppPreferencesStore();
      final etags = await store.getJsonMap(_etagCacheKey);
      if (etags != null) {
        _etagCache.addAll(etags.map((k, v) => MapEntry(k, v.toString())));
      }
      final bodies = await store.getJsonMap(_bodyCacheKey);
      if (bodies != null) {
        _bodyCache.addAll(bodies.map((k, v) => MapEntry(k, v.toString())));
      }
      final headers = await store.getJsonMap(_headersCacheKey);
      if (headers != null) {
        _headersCache.addAll(
          headers.map((k, v) {
            final val = v as Map<String, dynamic>;
            return MapEntry(
              k,
              val.map((hk, hv) => MapEntry(hk, hv.toString())),
            );
          }),
        );
      }
    } catch (_) {}
    _cacheInitialized = true;
  }

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    await _ensureCacheLoaded();
    final store = AppPreferencesStore();
    final throttledUntilStr = await store.getString(_throttledUntilKey);
    if (throttledUntilStr != null) {
      final throttledUntil = DateTime.tryParse(throttledUntilStr);
      if (throttledUntil != null && DateTime.now().isBefore(throttledUntil)) {
        if (request.method == 'GET') {
          final urlKey = request.url.toString();
          final cachedBody = _bodyCache[urlKey];
          if (cachedBody != null) {
            final bodyBytes = utf8.encode(cachedBody);
            return http.StreamedResponse(
              Stream.value(bodyBytes),
              200,
              contentLength: bodyBytes.length,
              request: request,
              headers: _headersCache[urlKey] ?? {},
            );
          }
        }
        final waitSeconds = throttledUntil.difference(DateTime.now()).inSeconds;
        return http.StreamedResponse(
          Stream.value(
            utf8.encode(
              jsonEncode({
                'detail':
                    'Request was throttled. Expected available in $waitSeconds seconds.',
              }),
            ),
          ),
          429,
          headers: {
            'content-type': 'application/json',
            'retry-after': '$waitSeconds',
          },
          request: request,
        );
      }
    }

    _injectBrowserHeaders(request.headers);
    final cookies = await getStoredCookies();
    if (cookies.isNotEmpty) {
      request.headers['Cookie'] = _buildCookieHeaderString(cookies);
      final csrf = cookies['csrftoken'];
      if (csrf != null) {
        request.headers['X-CSRFToken'] = csrf;
      }
    }

    final response = await _sendWithEtag(request);

    if (response.statusCode == 401 || response.statusCode == 403) {
      final refreshed = await _attemptTokenRefresh();
      if (refreshed) {
        final newRequest = _cloneRequest(request);
        final newCookies = await getStoredCookies();
        if (newCookies.isNotEmpty) {
          newRequest.headers['Cookie'] = _buildCookieHeaderString(newCookies);
          final csrf = newCookies['csrftoken'];
          if (csrf != null) {
            newRequest.headers['X-CSRFToken'] = csrf;
          }
        }
        return _sendWithEtag(newRequest);
      } else {
        final urlKey = request.url.toString();
        final isGet = request.method == 'GET';
        if (isGet && _bodyCache.containsKey(urlKey)) {
          final cachedBody = _bodyCache[urlKey]!;
          final bodyBytes = utf8.encode(cachedBody);
          return http.StreamedResponse(
            Stream.value(bodyBytes),
            200,
            contentLength: bodyBytes.length,
            request: request,
            headers: _headersCache[urlKey] ?? {},
          );
        }
      }
    }

    return response;
  }

  Future<http.StreamedResponse> _sendWithEtag(
    http.BaseRequest request, {
    bool isRetry = false,
  }) async {
    final isGet = request.method == 'GET';
    final urlKey = request.url.toString();
    final isMedia =
        urlKey.contains('/media/') ||
        urlKey.endsWith('.png') ||
        urlKey.endsWith('.jpg') ||
        urlKey.endsWith('.jpeg');

    if (request.method != 'GET') {
      _etagCache.removeWhere((key, _) => key.contains('/api/reservation/'));
      _bodyCache.removeWhere((key, _) => key.contains('/api/reservation/'));
      _headersCache.removeWhere((key, _) => key.contains('/api/reservation/'));
      final store = AppPreferencesStore();
      await store.setJson(_etagCacheKey, _etagCache);
      await store.setJson(_bodyCacheKey, _bodyCache);
      await store.setJson(_headersCacheKey, _headersCache);
    }

    if (isGet && !isMedia && _etagCache.containsKey(urlKey)) {
      request.headers['If-None-Match'] = _etagCache[urlKey]!;
    }

    http.StreamedResponse response;
    try {
      response = await _inner.send(request);
    } catch (e) {
      if (isGet && !isMedia && _bodyCache.containsKey(urlKey)) {
        final cachedBody = _bodyCache[urlKey]!;
        final bodyBytes = utf8.encode(cachedBody);
        return http.StreamedResponse(
          Stream.value(bodyBytes),
          200,
          contentLength: bodyBytes.length,
          request: request,
          headers: _headersCache[urlKey] ?? {},
        );
      }
      rethrow;
    }

    if (isMedia) {
      final responseCookies = parseResponseCookies(response.headers);
      if (responseCookies.isNotEmpty) {
        await saveCookies(responseCookies);
      }
      return response;
    }

    if (response.statusCode == 429 && !isRetry) {
      final spoofedIp = _generateRandomIP();
      final newRequest = _cloneRequest(request);
      newRequest.headers['X-Forwarded-For'] = spoofedIp;
      newRequest.headers['X-Real-IP'] = spoofedIp;
      newRequest.headers['Client-IP'] = spoofedIp;

      final secondResponse = await _sendWithEtag(newRequest, isRetry: true);
      if (secondResponse.statusCode == 200 ||
          secondResponse.statusCode == 304) {
        _sessionIp = spoofedIp;
        return secondResponse;
      } else {
        _sessionIp = null;
        response = secondResponse;
      }
    }

    if (response.statusCode == 429) {
      final retryAfterStr =
          response.headers['retry-after'] ?? response.headers['Retry-After'];
      if (retryAfterStr != null) {
        final seconds = int.tryParse(retryAfterStr);
        if (seconds != null) {
          final until = DateTime.now().add(Duration(seconds: seconds));
          final store = AppPreferencesStore();
          await store.setString(_throttledUntilKey, until.toIso8601String());
        }
      }
    }

    if (isGet && response.statusCode == 304) {
      final cachedBody = _bodyCache[urlKey];
      if (cachedBody != null) {
        final bodyBytes = utf8.encode(cachedBody);
        return http.StreamedResponse(
          Stream.value(bodyBytes),
          200,
          contentLength: bodyBytes.length,
          request: request,
          headers: _headersCache[urlKey] ?? response.headers,
        );
      }
    }

    final responseCookies = parseResponseCookies(response.headers);
    if (responseCookies.isNotEmpty) {
      await saveCookies(responseCookies);
    }

    if (isGet && response.statusCode == 200) {
      final bytes = await response.stream.toBytes();
      final etag = response.headers['etag'] ?? response.headers['ETag'];
      if (etag != null) {
        _etagCache[urlKey] = etag;
      } else {
        _etagCache.remove(urlKey);
      }
      _bodyCache[urlKey] = utf8.decode(bytes);
      _headersCache[urlKey] = response.headers;
      final store = AppPreferencesStore();
      await store.setJson(_etagCacheKey, _etagCache);
      await store.setJson(_bodyCacheKey, _bodyCache);
      await store.setJson(_headersCacheKey, _headersCache);
      return http.StreamedResponse(
        Stream.value(bytes),
        200,
        contentLength: bytes.length,
        request: request,
        headers: response.headers,
        isRedirect: response.isRedirect,
        persistentConnection: response.persistentConnection,
        reasonPhrase: response.reasonPhrase,
      );
    }

    return response;
  }

  Future<void> storeGoogleRefreshToken(String token) async {
    await _secureStorage.write(key: _googleRefreshTokenKey, value: token);
  }

  Future<String?> getGoogleRefreshToken() async {
    return await _secureStorage.read(key: _googleRefreshTokenKey);
  }

  Future<void> clearAuthData() async {
    await _secureStorage.delete(key: _cookiesStorageKey);
    await _secureStorage.delete(key: _googleRefreshTokenKey);
    await _secureStorage.delete(key: _profileStorageKey);
    await clearCache();
    final store = AppPreferencesStore();
    await store.remove(_throttledUntilKey);
  }

  Future<void> clearCache() async {
    final store = AppPreferencesStore();
    await store.remove(_etagCacheKey);
    await store.remove(_bodyCacheKey);
    await store.remove(_headersCacheKey);
    _etagCache.clear();
    _bodyCache.clear();
    _headersCache.clear();
  }

  Future<void> saveCachedProfile(Map<String, dynamic> profile) async {
    await _secureStorage.write(
      key: _profileStorageKey,
      value: jsonEncode(profile),
    );
  }

  Future<Map<String, dynamic>?> getCachedProfile() async {
    try {
      final data = await _secureStorage.read(key: _profileStorageKey);
      if (data == null) return null;
      return jsonDecode(data) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  Future<Map<String, String>> getStoredCookies() async {
    try {
      final data = await _secureStorage.read(key: _cookiesStorageKey);
      if (data == null) return {};
      final Map<String, dynamic> decoded = jsonDecode(data);
      return decoded.map((key, value) => MapEntry(key, value.toString()));
    } catch (_) {
      return {};
    }
  }

  Future<void> saveCookies(Map<String, String> newCookies) async {
    final currentCookies = await getStoredCookies();
    currentCookies.addAll(newCookies);
    await _secureStorage.write(
      key: _cookiesStorageKey,
      value: jsonEncode(currentCookies),
    );
  }

  String _buildCookieHeaderString(Map<String, String> cookies) {
    return cookies.entries.map((e) => '${e.key}=${e.value}').join('; ');
  }

  Map<String, String> parseResponseCookies(Map<String, String> headers) {
    final Map<String, String> cookies = {};
    final setCookieHeader = headers['set-cookie'] ?? headers['Set-Cookie'];
    if (setCookieHeader == null) return cookies;

    final parts = setCookieHeader.split(RegExp(r',(?=[^;]*=)'));
    for (var part in parts) {
      final cookiePart = part.split(';').first.trim();
      final eqIndex = cookiePart.indexOf('=');
      if (eqIndex != -1) {
        final name = cookiePart.substring(0, eqIndex).trim();
        final value = cookiePart.substring(eqIndex + 1).trim();
        if (name.isNotEmpty) {
          cookies[name] = value;
        }
      }
    }
    return cookies;
  }

  String _generateRandomIP() {
    final random = Random();
    final bracuSubnets = ['103.67.66', '103.67.67'];
    final baseSubnet = bracuSubnets[random.nextInt(bracuSubnets.length)];
    final lastOctet = random.nextInt(254) + 1;
    return '$baseSubnet.$lastOctet';
  }

  void _injectBrowserHeaders(Map<String, String> headers) {
    headers['User-Agent'] =
        'Mozilla/5.0 (Linux; Android 15; Pixel 9) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/149.0.0.0 Mobile Safari/537.36';
    headers['Accept'] = '*/*';
    headers['Accept-Language'] = 'en-US,en;q=0.9';
    headers['Referer'] = 'https://libsync.bracu.ac.bd/';
    headers['Origin'] = 'https://libsync.bracu.ac.bd';
    headers['sec-ch-ua-mobile'] = '?1';
    headers['sec-ch-ua-platform'] = '"Android"';

    if (_sessionIp != null) {
      headers['X-Forwarded-For'] = _sessionIp!;
      headers['X-Real-IP'] = _sessionIp!;
      headers['Client-IP'] = _sessionIp!;
    }
  }

  Future<bool> _attemptTokenRefresh() async {
    try {
      final cookies = await getStoredCookies();
      final refreshCookie = cookies['refresh'];
      if (refreshCookie != null) {
        final refreshHeaders = {
          'Cookie': _buildCookieHeaderString(cookies),
          'Content-Type': 'application/json',
        };
        _injectBrowserHeaders(refreshHeaders);
        final refreshResponse = await _inner.post(
          Uri.parse(LibSyncConfig.tokenRefreshUrl),
          headers: refreshHeaders,
          body: jsonEncode({'refresh': refreshCookie}),
        );

        if (refreshResponse.statusCode == 429) {
          final retryAfterStr =
              refreshResponse.headers['retry-after'] ??
              refreshResponse.headers['Retry-After'];
          if (retryAfterStr != null) {
            final seconds = int.tryParse(retryAfterStr);
            if (seconds != null) {
              final until = DateTime.now().add(Duration(seconds: seconds));
              final store = AppPreferencesStore();
              await store.setString(
                _throttledUntilKey,
                until.toIso8601String(),
              );
            }
          }
        }

        if (refreshResponse.statusCode == 200) {
          final responseCookies = parseResponseCookies(refreshResponse.headers);
          final Map<String, String> cookiesToSave = Map.from(responseCookies);
          try {
            final body =
                jsonDecode(refreshResponse.body) as Map<String, dynamic>;
            final accessVal = body['access'] ?? body['access_token'];
            final refreshVal = body['refresh'] ?? body['refresh_token'];
            if (accessVal != null) {
              cookiesToSave['access'] = accessVal.toString();
            }
            if (refreshVal != null) {
              cookiesToSave['refresh'] = refreshVal.toString();
            }
          } catch (_) {}

          if (cookiesToSave.isNotEmpty) {
            await saveCookies(cookiesToSave);
            return true;
          }
        }
      }

      String? googleAccessToken;
      if (!kIsWeb) {
        try {
          final googleSignIn = GoogleSignIn(
            scopes: LibSyncConfig.googleScopes.isEmpty
                ? ['email', 'profile']
                : LibSyncConfig.googleScopes.split(' '),
          );
          final account = await googleSignIn.signInSilently();
          final auth = await account?.authentication;
          googleAccessToken = auth?.accessToken;
        } catch (_) {}
      }

      if (googleAccessToken == null) {
        final googleRefreshToken = await getGoogleRefreshToken();
        if (googleRefreshToken != null) {
          final tokens = await GoogleAuthHelper.refreshAccessToken(
            googleRefreshToken,
          );
          googleAccessToken = tokens['access_token'] as String?;
        }
      }

      if (googleAccessToken != null) {
        final loginHeaders = {'Content-Type': 'application/json'};
        _injectBrowserHeaders(loginHeaders);
        final loginResponse = await _inner.post(
          Uri.parse(LibSyncConfig.authSocialGoogleUrl),
          headers: loginHeaders,
          body: jsonEncode({'access_token': googleAccessToken}),
        );

        if (loginResponse.statusCode == 200) {
          final responseCookies = parseResponseCookies(loginResponse.headers);
          final Map<String, String> cookiesToSave = Map.from(responseCookies);
          try {
            final body = jsonDecode(loginResponse.body) as Map<String, dynamic>;
            final accessVal = body['access'] ?? body['access_token'];
            final refreshVal = body['refresh'] ?? body['refresh_token'];
            if (accessVal != null) {
              cookiesToSave['access'] = accessVal.toString();
            }
            if (refreshVal != null) {
              cookiesToSave['refresh'] = refreshVal.toString();
            }
          } catch (_) {}

          if (cookiesToSave.isNotEmpty) {
            await saveCookies(cookiesToSave);
            return true;
          }
        }
      }
    } catch (_) {}

    return false;
  }

  http.BaseRequest _cloneRequest(http.BaseRequest request) {
    if (request is http.Request) {
      final copy = http.Request(request.method, request.url)
        ..headers.addAll(request.headers)
        ..maxRedirects = request.maxRedirects
        ..followRedirects = request.followRedirects
        ..persistentConnection = request.persistentConnection
        ..bodyBytes = request.bodyBytes;
      return copy;
    }
    throw ArgumentError('Unsupported request type: ${request.runtimeType}');
  }
}
