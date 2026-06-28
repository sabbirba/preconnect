import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'libsync_config.dart';
import 'google_auth_helper.dart';
import 'client_creator.dart';

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

    final responseCookies = _parseResponseCookies(response.headers);
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

  Map<String, String> _parseResponseCookies(Map<String, String> headers) {
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

  Future<bool> _attemptTokenRefresh() async {
    try {
      final cookies = await getStoredCookies();
      final refreshCookie = cookies['refresh'];
      if (refreshCookie != null) {
        final refreshResponse = await _inner.post(
          Uri.parse(LibSyncConfig.tokenRefreshUrl),
          headers: {
            'Cookie': _buildCookieHeaderString(cookies),
            'Content-Type': 'application/json',
          },
        );

        if (refreshResponse.statusCode == 200) {
          final responseCookies = _parseResponseCookies(
            refreshResponse.headers,
          );
          if (responseCookies.isNotEmpty) {
            await saveCookies(responseCookies);
            return true;
          }
        }
      }
    } catch (_) {}

    try {
      final googleRefreshToken = await getGoogleRefreshToken();
      if (googleRefreshToken != null) {
        final googleTokens = await GoogleAuthHelper.refreshAccessToken(
          googleRefreshToken,
        );
        final googleAccessToken = googleTokens['access_token'] as String?;
        if (googleAccessToken != null) {
          final libsyncAuthResponse = await _inner.post(
            Uri.parse(LibSyncConfig.authSocialGoogleUrl),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'access_token': googleAccessToken}),
          );

          if (libsyncAuthResponse.statusCode == 200) {
            final responseCookies = _parseResponseCookies(
              libsyncAuthResponse.headers,
            );
            if (responseCookies.isNotEmpty) {
              await saveCookies(responseCookies);
              final newGoogleRefresh = googleTokens['refresh_token'] as String?;
              if (newGoogleRefresh != null) {
                await storeGoogleRefreshToken(newGoogleRefresh);
              }
              return true;
            }
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
