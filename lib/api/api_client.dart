import 'dart:async';
import 'dart:io' show SocketException;
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:retry/retry.dart';
import 'package:clock/clock.dart';
import 'package:preconnect/api/api_config.dart';
import 'package:preconnect/api/auth.dart';
import 'package:preconnect/tools/http/http_utils.dart';
import 'package:preconnect/tools/preconnect_constants.dart';
import 'package:preconnect/tools/token_refresh.dart';
import 'package:preconnect/tools/token_storage.dart';

class ApiClient {
  static final ApiClient _instance = ApiClient._internal();
  factory ApiClient() => _instance;
  ApiClient._internal();

  final TokenStorage _storage = TokenStorage.instance;
  final Map<String, Future<http.Response>> _inFlightRequests =
      <String, Future<http.Response>>{};
  final Map<String, _CachedHttpResponse> _cachedResponses =
      <String, _CachedHttpResponse>{};
  static const Duration _requestTimeout = Duration(seconds: 12);
  static const Duration _connectivityProbeTimeout = Duration(seconds: 2);
  static const Duration _defaultGetCacheTtl = Duration(seconds: 2);
  static const Duration _accessTokenCacheTtl = Duration(seconds: 2);
  static const Duration _connectionCacheTtl = Duration(seconds: 5);

  String? _cachedAccessToken;
  DateTime? _cachedAccessTokenAt;
  bool? _cachedHasConnection;
  DateTime? _cachedHasConnectionAt;

  void clearTransientCaches() {
    _cachedResponses.clear();
    _cachedAccessToken = null;
    _cachedAccessTokenAt = null;
    _cachedHasConnection = null;
    _cachedHasConnectionAt = null;
  }

  void _purgeExpiredResponseCache() {
    _cachedResponses.removeWhere(
      (_, cachedResponse) => cachedResponse.isExpired,
    );
    if (_cachedResponses.length <= 200) return;

    final excess = _cachedResponses.length - 150;
    final keysToRemove = _cachedResponses.keys.take(excess).toList();
    for (final key in keysToRemove) {
      _cachedResponses.remove(key);
    }
  }

  Future<bool> hasConnection({bool forceRefresh = false}) async {
    if (!forceRefresh) {
      final cached = _cachedHasConnection;
      final cachedAt = _cachedHasConnectionAt;
      if (cached != null &&
          cachedAt != null &&
          clock.now().difference(cachedAt) <= _connectionCacheTtl) {
        return cached;
      }
    }

    try {
      final connectivityResult = await Connectivity().checkConnectivity();
      if (connectivityResult.contains(ConnectivityResult.none)) {
        _cachedHasConnection = false;
        _cachedHasConnectionAt = clock.now();
        return false;
      }

      final response = await HttpUtils.client
          .get(
            Uri.parse(ApiConfig.connectApiBase),
            headers: compressionHeaders(),
          )
          .timeout(_connectivityProbeTimeout);
      final connected = response.statusCode < 500;
      _cachedHasConnection = connected;
      _cachedHasConnectionAt = clock.now();
      return connected;
    } catch (_) {
      _cachedHasConnection = false;
      _cachedHasConnectionAt = clock.now();
      return false;
    }
  }

  Future<String?> getAccessToken({int retries = 3}) async {
    final cachedToken = _cachedAccessToken;
    final cachedAt = _cachedAccessTokenAt;
    if (cachedToken != null &&
        cachedToken.isNotEmpty &&
        cachedAt != null &&
        clock.now().difference(cachedAt) <= _accessTokenCacheTtl) {
      return cachedToken;
    }

    for (int i = 0; i < retries; i++) {
      try {
        final token = await _storage.read(
          key: PreConnectStorageKeys.accessToken,
        );
        if (token != null && token.isNotEmpty) {
          _cachedAccessToken = token;
          _cachedAccessTokenAt = clock.now();
          return token;
        }
      } catch (_) {}

      if (i < retries - 1) {
        continue;
      }
    }
    _cachedAccessToken = null;
    _cachedAccessTokenAt = clock.now();
    return null;
  }

  Future<bool> hasAccessToken() async {
    final token = await getAccessToken();
    return token != null && token.trim().isNotEmpty;
  }

  Future<void> _refreshTokensWithRetry() async {
    try {
      final status = await retry(() async {
        final s = await AuthService().refreshTokenStatus();
        if (s == TokenRefreshStatus.retryableFailure) {
          throw const SocketException('Retryable session refresh failure');
        }
        return s;
      }, maxAttempts: 3);
      if (status == TokenRefreshStatus.invalidSession) {
        await AuthService().logout(force: true);
        throw const SessionExpiredException();
      }
    } catch (_) {
      throw const SessionExpiredException();
    }
  }

  Future<http.Response> authenticatedGet(
    String url, {
    Map<String, String> additionalHeaders = const <String, String>{},
    Set<int> acceptedStatusCodes = const <int>{200},
    Duration cacheDuration = _defaultGetCacheTtl,
  }) async {
    final token = await getAccessToken();
    if (token == null || token.isEmpty) {
      unawaited(AuthService().logout(force: true));
      throw const UnauthenticatedException();
    }
    final headers = await _authHeaders(token, method: 'GET', url: url);
    if (additionalHeaders.isNotEmpty) {
      headers.addAll(additionalHeaders);
    }

    final response = await _sendSharedRequest(
      'GET',
      url,
      headers: headers,
      cacheDuration: cacheDuration,
    );
    if (acceptedStatusCodes.contains(response.statusCode)) {
      return response;
    }

    if (response.statusCode == 401) {
      await _refreshTokensWithRetry();

      final newToken = await getAccessToken();
      if (newToken == null || newToken.isEmpty) {
        throw const SessionExpiredException();
      }
      final retryHeaders = await _authHeaders(
        newToken,
        method: 'GET',
        url: url,
      );
      if (additionalHeaders.isNotEmpty) {
        retryHeaders.addAll(additionalHeaders);
      }

      final retryResponse = await _sendSharedRequest(
        'GET',
        url,
        headers: retryHeaders,
        cacheDuration: cacheDuration,
      );
      if (acceptedStatusCodes.contains(retryResponse.statusCode)) {
        return retryResponse;
      }
      if (retryResponse.statusCode == 401) {
        throw const SessionExpiredException();
      }
      if (retryResponse.statusCode >= 500) {
        throw ApiException(retryResponse.statusCode, retryResponse.body);
      }

      throw ApiException(retryResponse.statusCode, retryResponse.body);
    }

    throw ApiException(response.statusCode, response.body);
  }

  Future<http.Response> authenticatedRequest(
    String method,
    String url, {
    String body = '',
    Map<String, String> additionalHeaders = const <String, String>{},
    Set<int> acceptedStatusCodes = const <int>{200},
    Duration cacheDuration = _defaultGetCacheTtl,
  }) async {
    final normalizedMethod = method.trim().toUpperCase();

    if (normalizedMethod == 'GET') {
      return authenticatedGet(
        url,
        additionalHeaders: additionalHeaders,
        acceptedStatusCodes: acceptedStatusCodes,
        cacheDuration: cacheDuration,
      );
    }
    final token = await getAccessToken();
    if (token == null || token.isEmpty) {
      throw const UnauthenticatedException();
    }
    final headers = await _authHeaders(
      token,
      method: normalizedMethod,
      url: url,
      body: body,
    );
    if (additionalHeaders.isNotEmpty) {
      headers.addAll(additionalHeaders);
    }

    final response = await _sendAuthenticatedRequest(
      normalizedMethod,
      url,
      headers: headers,
      body: body,
      cacheDuration: cacheDuration,
    );
    if (acceptedStatusCodes.contains(response.statusCode)) {
      return response;
    }

    if (response.statusCode == 401) {
      await _refreshTokensWithRetry();

      final newToken = await getAccessToken();
      if (newToken == null || newToken.isEmpty) {
        throw const SessionExpiredException();
      }
      final retryHeaders = await _authHeaders(
        newToken,
        method: normalizedMethod,
        url: url,
        body: body,
      );
      if (additionalHeaders.isNotEmpty) {
        retryHeaders.addAll(additionalHeaders);
      }
      final retryResponse = await _sendAuthenticatedRequest(
        normalizedMethod,
        url,
        headers: retryHeaders,
        body: body,
        cacheDuration: cacheDuration,
      );
      if (acceptedStatusCodes.contains(retryResponse.statusCode)) {
        return retryResponse;
      }
      if (retryResponse.statusCode == 401) {
        throw const SessionExpiredException();
      }
      throw ApiException(retryResponse.statusCode, retryResponse.body);
    }

    throw ApiException(response.statusCode, response.body);
  }

  Future<http.Response> publicGet(
    String url, {
    Map<String, String> headers = const <String, String>{},
    Set<int> acceptedStatusCodes = const <int>{200},
    Duration cacheDuration = _defaultGetCacheTtl,
  }) async {
    final uri = Uri.parse(url);
    final mergedHeaders = <String, String>{
      'Accept': 'application/json',
      ...headers,
    };
    mergedHeaders.addAll(compressionHeadersForUri(uri));
    final response = await _sendSharedRequest(
      'GET',
      url,
      headers: mergedHeaders,
      cacheDuration: cacheDuration,
    );
    if (acceptedStatusCodes.contains(response.statusCode)) {
      return response;
    }
    throw ApiException(response.statusCode, response.body);
  }

  Future<http.Response> publicPost(
    String url, {
    String body = '',
    Map<String, String> headers = const <String, String>{},
    Set<int> acceptedStatusCodes = const <int>{200, 201},
  }) async {
    final uri = Uri.parse(url);
    final mergedHeaders = <String, String>{
      'Accept': 'application/json',
      'Content-Type': 'application/json',
      ...headers,
    };
    mergedHeaders.addAll(compressionHeadersForUri(uri));
    final response = await _sendSharedRequest(
      'POST',
      url,
      headers: mergedHeaders,
      body: body,
      cacheDuration: Duration.zero,
    );
    if (acceptedStatusCodes.contains(response.statusCode)) {
      return response;
    }
    throw ApiException(response.statusCode, response.body);
  }

  Future<http.Response> authenticatedGetWithEtag(
    String url, {
    String? etag,
    Map<String, String> additionalHeaders = const <String, String>{},
    Set<int> acceptedStatusCodes = const <int>{200, 304},
    Duration cacheDuration = _defaultGetCacheTtl,
  }) {
    final headers = <String, String>{...additionalHeaders};
    if (etag != null && etag.isNotEmpty) {
      headers['If-None-Match'] = etag;
    }
    return authenticatedGet(
      url,
      additionalHeaders: headers,
      acceptedStatusCodes: acceptedStatusCodes,
      cacheDuration: cacheDuration,
    );
  }

  Future<T?> fetchWithFallback<T>({
    required String url,
    required Future<void> Function(http.Response response) cacheResponse,
    required Future<T?> Function({required bool fromFetch}) readCache,
    required bool fromGet,
    String? etag,
    Future<void> Function(String etag)? cacheEtag,
    Duration cacheDuration = _defaultGetCacheTtl,
  }) async {
    if (!await hasConnection()) {
      return readCache(fromFetch: true);
    }

    try {
      final headers = <String, String>{};
      if (etag != null && etag.isNotEmpty) {
        headers['If-None-Match'] = etag;
      }
      final response = await authenticatedGet(
        url,
        additionalHeaders: headers,
        acceptedStatusCodes: const <int>{200, 304},
        cacheDuration: cacheDuration,
      );
      if (response.statusCode == 304) {
        return readCache(fromFetch: true);
      }
      final newEtag = response.headers['etag'];
      if (newEtag != null && newEtag.isNotEmpty && cacheEtag != null) {
        await cacheEtag(newEtag);
      }
      await cacheResponse(response);
      return readCache(fromFetch: true);
    } on UnauthenticatedException {
      return readCache(fromFetch: true);
    } on SessionExpiredException {
      return readCache(fromFetch: true);
    } on ApiException {
      return readCache(fromFetch: true);
    } catch (_) {
      return readCache(fromFetch: true);
    }
  }

  Future<Map<String, String>> _authHeaders(
    String token, {
    required String method,
    required String url,
    String body = '',
  }) async {
    final headers = <String, String>{
      'Authorization': 'Bearer $token',
      ...ApiConfig.apiHeaders,
    };

    final idToken = await TokenStorage.instance.read(
      key: PreConnectStorageKeys.idToken,
    );
    if (idToken != null && idToken.isNotEmpty) {
      headers['X-ID-Token'] = idToken;
    }

    final uri = Uri.tryParse(url);
    headers.addAll(compressionHeadersForUri(uri));
    if (uri != null && uri.host == 'connect.bracu.ac.bd') {
      headers['Origin'] = ApiConfig.connectOrigin;
    }

    return headers;
  }

  Future<http.Response> _sendAuthenticatedRequest(
    String method,
    String url, {
    required Map<String, String> headers,
    required String body,
    Duration cacheDuration = Duration.zero,
  }) {
    return _sendSharedRequest(
      method,
      url,
      headers: headers,
      body: body,
      cacheDuration: cacheDuration,
    );
  }

  Future<http.Response> _sendSharedRequest(
    String method,
    String url, {
    required Map<String, String> headers,
    String body = '',
    Duration cacheDuration = Duration.zero,
  }) {
    final normalizedMethod = method.trim().toUpperCase();
    if (normalizedMethod != 'GET') {
      return _sendRawRequest(
        normalizedMethod,
        url,
        headers: headers,
        body: body,
      );
    }

    final inFlightKey = _inFlightRequestKey(
      normalizedMethod,
      url,
      headers: headers,
      body: body,
    );
    _purgeExpiredResponseCache();
    final cachedResponse = _cachedResponses[inFlightKey];
    if (cachedResponse != null && !cachedResponse.isExpired) {
      return Future<http.Response>.value(cachedResponse.response);
    }
    final inFlight = _inFlightRequests[inFlightKey];
    if (inFlight != null) return inFlight;

    final request = _sendRawRequest(
      normalizedMethod,
      url,
      headers: headers,
      body: body,
    );
    _inFlightRequests[inFlightKey] = request;
    return request
        .then((response) {
          if (cacheDuration > Duration.zero && response.statusCode == 200) {
            _cachedResponses[inFlightKey] = _CachedHttpResponse(
              response: response,
              expiresAt: clock.now().add(cacheDuration),
            );
          }
          return response;
        })
        .whenComplete(() => _inFlightRequests.remove(inFlightKey));
  }

  Future<http.Response> _sendRawRequest(
    String method,
    String url, {
    required Map<String, String> headers,
    required String body,
  }) {
    final uri = Uri.parse(url);
    switch (method) {
      case 'GET':
        return HttpUtils.client
            .get(uri, headers: headers)
            .timeout(_requestTimeout);
      case 'POST':
        return HttpUtils.client
            .post(uri, headers: headers, body: body)
            .timeout(_requestTimeout);
      case 'PUT':
        return HttpUtils.client
            .put(uri, headers: headers, body: body)
            .timeout(_requestTimeout);
      case 'PATCH':
        return HttpUtils.client
            .patch(uri, headers: headers, body: body)
            .timeout(_requestTimeout);
      case 'DELETE':
        return HttpUtils.client
            .delete(uri, headers: headers, body: body.isEmpty ? null : body)
            .timeout(_requestTimeout);
      default:
        throw ArgumentError.value(method, 'method', 'Unsupported HTTP method');
    }
  }

  String _inFlightRequestKey(
    String method,
    String url, {
    required Map<String, String> headers,
    required String body,
  }) {
    final headerKey =
        headers.entries
            .map((entry) => MapEntry(entry.key.toLowerCase(), entry.value))
            .toList()
          ..sort((a, b) => a.key.compareTo(b.key));
    return <String>[
      method,
      url,
      for (final entry in headerKey) '${entry.key}:${entry.value}',
      body,
    ].join('\n');
  }
}

class _CachedHttpResponse {
  _CachedHttpResponse({required this.response, required this.expiresAt});

  final http.Response response;
  final DateTime expiresAt;

  bool get isExpired => clock.now().isAfter(expiresAt);
}

Map<String, String> compressionHeaders() {
  if (kIsWeb) return const <String, String>{};
  return const <String, String>{'Accept-Encoding': 'gzip'};
}

Map<String, String> compressionHeadersForUri(Uri? uri) {
  return compressionHeaders();
}

sealed class PreConnectException implements Exception {
  const PreConnectException([this.message]);
  final String? message;

  @override
  String toString() => message ?? runtimeType.toString();
}

class OfflineException extends PreConnectException {
  const OfflineException() : super('No network connection');
}

class UnauthenticatedException extends PreConnectException {
  const UnauthenticatedException() : super('Not authenticated');
}

class SessionExpiredException extends PreConnectException {
  const SessionExpiredException() : super('Session expired');
}

class ApiException extends PreConnectException {
  const ApiException(this.statusCode, [super.message]);
  final int statusCode;

  @override
  String toString() =>
      'ApiException($statusCode${message != null ? ': $message' : ''})';
}

class CacheEmptyException extends PreConnectException {
  const CacheEmptyException([super.message]);
}

class MissingDependencyException extends PreConnectException {
  const MissingDependencyException(String field)
    : super('Missing required field: $field');
}

Map<String, String> ifNoneMatchHeader(String? etag) {
  return const <String, String>{};
}

String? extractEtagFromHeaders(Map<String, String> headers) {
  return null;
}

String? extractEtagFromResponse(http.Response response) {
  return null;
}

final _portfolioIdResolutionFailures = <DateTime>[];
const _portfolioIdQuarantinePeriod = Duration(minutes: 5);

Future<String?> resolvePortfolioId({
  required dynamic prefs,
  required Future<void> Function() refreshProfile,
  int maxRetries = 2,
  int currentRetry = 0,
}) async {
  var id = await prefs.getString('id');
  if (id == null || id.isEmpty) {
    final now = clock.now();
    final recentFailures = _portfolioIdResolutionFailures
        .where((t) => now.difference(t) < _portfolioIdQuarantinePeriod)
        .toList();

    if (recentFailures.isNotEmpty) {
      return null;
    }

    if (currentRetry >= maxRetries) {
      _portfolioIdResolutionFailures.add(now);
      return null;
    }
    try {
      await refreshProfile();
    } catch (e) {
      _portfolioIdResolutionFailures.add(now);
      return null;
    }

    id = await prefs.getString('id');
  }
  if (id == null || id.isEmpty) {
    return null;
  }
  return id;
}
