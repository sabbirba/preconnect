import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'libsync_config.dart';
import 'client_creator.dart';

import 'auth_service.dart';

class LibSyncApiClient extends http.BaseClient {
  LibSyncApiClient() : _inner = createLibSyncClient();

  final http.Client _inner;
  static const _secureStorage = FlutterSecureStorage();
  static const String _cookiesStorageKey = 'libsync_cookies';
  static const String _googleRefreshTokenKey = 'libsync_google_refresh_token';

  static final Map<String, String> _etagCache = {};
  static final Map<String, String> _bodyCache = {};
  static final Map<String, Map<String, String>> _headersCache = {};

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    _injectBrowserHeaders(request.headers);
    final cookies = await getStoredCookies();
    if (cookies.isNotEmpty) {
      request.headers['Cookie'] = _buildCookieHeaderString(cookies);
    }

    final response = await _sendWithEtag(request);

    if (response.statusCode == 401) {
      final refreshed = await _attemptTokenRefresh();
      if (refreshed) {
        final newRequest = _cloneRequest(request);
        final newCookies = await getStoredCookies();
        if (newCookies.isNotEmpty) {
          newRequest.headers['Cookie'] = _buildCookieHeaderString(newCookies);
        }
        return _sendWithEtag(newRequest);
      } else {
        LibSyncAuthService.instance.logout();
      }
    }

    return response;
  }

  Future<http.StreamedResponse> _sendWithEtag(http.BaseRequest request) async {
    final isGet = request.method == 'GET';
    final urlKey = request.url.toString();

    if (isGet && _etagCache.containsKey(urlKey)) {
      request.headers['If-None-Match'] = _etagCache[urlKey]!;
    }

    final response = await _inner.send(request);

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
      final etag = response.headers['etag'] ?? response.headers['ETag'];
      if (etag != null) {
        final bytes = await response.stream.toBytes();
        _etagCache[urlKey] = etag;
        _bodyCache[urlKey] = utf8.decode(bytes);
        _headersCache[urlKey] = response.headers;
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

  void _injectBrowserHeaders(Map<String, String> headers) {
    headers['User-Agent'] =
        'Mozilla/5.0 (Linux; Android 15; Pixel 9) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/149.0.0.0 Mobile Safari/537.36';
    headers['Accept'] = '*/*';
    headers['Accept-Language'] = 'en-US,en;q=0.9';
    headers['Referer'] = 'https://libsync.bracu.ac.bd/';
    headers['sec-ch-ua-mobile'] = '?1';
    headers['sec-ch-ua-platform'] = '"Android"';
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
