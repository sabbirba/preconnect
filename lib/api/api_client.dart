import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:preconnect/api/api_config.dart';
import 'package:preconnect/api/auth_service.dart';
import 'package:preconnect/tools/play_install_referrer.dart';
import 'package:preconnect/tools/preconnect_constants.dart';
import 'package:preconnect/tools/token_refresh_flow.dart';
import 'package:preconnect/tools/token_storage.dart';

class ApiClient {
  static final ApiClient _instance = ApiClient._internal();
  factory ApiClient() => _instance;
  ApiClient._internal();

  final TokenStorage _storage = TokenStorage.instance;
  static const Duration _requestTimeout = Duration(seconds: 12);
  static const Duration _connectivityProbeTimeout = Duration(seconds: 3);

  Future<bool> hasConnection({bool forceRefresh = false}) async {
    try {
      final response = await http
          .get(
            Uri.parse(ApiConfig.connectApiBase),
            headers: compressionHeaders(),
          )
          .timeout(_connectivityProbeTimeout);
      return response.statusCode < 500;
    } catch (_) {
      return false;
    }
  }

  Future<String?> getAccessToken({int retries = 3}) async {
    for (int i = 0; i < retries; i++) {
      try {
        final token = await _storage.read(
          key: PreconnectStorageKeys.accessToken,
        );
        if (token != null && token.isNotEmpty) {
          return token;
        }
      } catch (_) {}

      if (i < retries - 1) {
        continue;
      }
    }
    return null;
  }

  Future<bool> hasAccessToken() async {
    final token = await getAccessToken();
    return token != null && token.trim().isNotEmpty;
  }

  Future<http.Response> authenticatedGet(
    String url, {
    Map<String, String> additionalHeaders = const <String, String>{},
    Set<int> acceptedStatusCodes = const <int>{200},
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

    final response = await http
        .get(Uri.parse(url), headers: headers)
        .timeout(_requestTimeout);
    if (acceptedStatusCodes.contains(response.statusCode)) {
      return response;
    }

    if (response.statusCode == 401) {
      TokenRefreshStatus refreshStatus = TokenRefreshStatus.retryableFailure;
      for (int retryAttempt = 0; retryAttempt < 3; retryAttempt++) {
        try {
          refreshStatus = await AuthService().refreshTokenStatus();

          if (refreshStatus == TokenRefreshStatus.refreshed) {
            break;
          }

          if (refreshStatus == TokenRefreshStatus.invalidSession) {
            await AuthService().logout(force: true);
            throw const SessionExpiredException();
          }
        } catch (_) {}
      }

      if (refreshStatus != TokenRefreshStatus.refreshed) {
        throw const SessionExpiredException();
      }

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

      final retryResponse = await http
          .get(Uri.parse(url), headers: retryHeaders)
          .timeout(_requestTimeout);
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
  }) async {
    final normalizedMethod = method.trim().toUpperCase();

    if (normalizedMethod == 'GET') {
      return authenticatedGet(
        url,
        additionalHeaders: additionalHeaders,
        acceptedStatusCodes: acceptedStatusCodes,
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
    );
    if (acceptedStatusCodes.contains(response.statusCode)) {
      return response;
    }

    if (response.statusCode == 401) {
      TokenRefreshStatus refreshStatus = TokenRefreshStatus.retryableFailure;
      for (int retryAttempt = 0; retryAttempt < 3; retryAttempt++) {
        refreshStatus = await AuthService().refreshTokenStatus();

        if (refreshStatus == TokenRefreshStatus.refreshed) {
          break;
        }

        if (refreshStatus == TokenRefreshStatus.invalidSession) {
          await AuthService().logout(force: true);
          throw const SessionExpiredException();
        }
      }

      if (refreshStatus != TokenRefreshStatus.refreshed) {
        throw const SessionExpiredException();
      }

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
  }) async {
    final uri = Uri.parse(url);
    final mergedHeaders = <String, String>{
      'Accept': 'application/json',
      ...headers,
    };
    mergedHeaders.addAll(compressionHeadersForUri(uri));
    final response = await http
        .get(uri, headers: mergedHeaders)
        .timeout(_requestTimeout);
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
  }) {
    final headers = <String, String>{...additionalHeaders};
    final normalized = (etag ?? '').trim();
    if (normalized.isNotEmpty) {
      headers['If-None-Match'] = normalized;
    }
    return authenticatedGet(
      url,
      additionalHeaders: headers,
      acceptedStatusCodes: acceptedStatusCodes,
    );
  }

  Future<T?> fetchWithFallback<T>({
    required String url,
    required Future<void> Function(http.Response response) cacheResponse,
    required Future<T?> Function({required bool fromFetch}) readCache,
    required bool fromGet,
  }) async {
    if (!await hasConnection()) {
      return fromGet ? null : readCache(fromFetch: true);
    }

    try {
      final response = await authenticatedGet(url);
      await cacheResponse(response);
      return readCache(fromFetch: true);
    } on UnauthenticatedException {
      return fromGet ? null : readCache(fromFetch: true);
    } on SessionExpiredException {
      return fromGet ? null : readCache(fromFetch: true);
    } on ApiException {
      return fromGet ? null : readCache(fromFetch: true);
    } catch (_) {
      return fromGet ? null : readCache(fromFetch: true);
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

    final uri = Uri.tryParse(url);
    headers.addAll(compressionHeadersForUri(uri));
    if (uri != null && uri.host == 'connect.bracu.ac.bd') {
      headers['Origin'] = ApiConfig.connectOrigin;
    }

    try {
      final integrityToken = await PlayIntegrity.tokenForRequest(
        method: method,
        url: url,
        body: body,
      );
      if (integrityToken != null && integrityToken.isNotEmpty) {
        headers['X-Play-Integrity-Token'] = integrityToken;
        headers['X-Play-Integrity-Request-Hash'] = PlayIntegrity.requestHash(
          method: method,
          url: url,
          body: body,
        );
      }
    } catch (_) {}

    try {
      final installReferrerHeaders = await PlayInstallReferrer.headers();
      headers.addAll(installReferrerHeaders);
    } catch (_) {}

    return headers;
  }

  Future<http.Response> _sendAuthenticatedRequest(
    String method,
    String url, {
    required Map<String, String> headers,
    required String body,
  }) {
    final uri = Uri.parse(url);
    switch (method) {
      case 'POST':
        return http
            .post(uri, headers: headers, body: body)
            .timeout(_requestTimeout);
      case 'PUT':
        return http
            .put(uri, headers: headers, body: body)
            .timeout(_requestTimeout);
      case 'PATCH':
        return http
            .patch(uri, headers: headers, body: body)
            .timeout(_requestTimeout);
      case 'DELETE':
        return http
            .delete(uri, headers: headers, body: body.isEmpty ? null : body)
            .timeout(_requestTimeout);
      default:
        throw ArgumentError.value(method, 'method', 'Unsupported HTTP method');
    }
  }
}

Map<String, String> compressionHeaders() {
  if (kIsWeb) return const <String, String>{};
  return const <String, String>{'Accept-Encoding': 'gzip, deflate'};
}

Map<String, String> compressionHeadersForUri(Uri? uri) {
  if (uri != null && uri.host == 'cdn.preconnect.app') {
    return const <String, String>{};
  }
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
  final value = (etag ?? '').trim();
  if (value.isEmpty) return const <String, String>{};
  return <String, String>{'If-None-Match': value};
}

String? extractEtagFromHeaders(Map<String, String> headers) {
  for (final entry in headers.entries) {
    if (entry.key.toLowerCase() == 'etag') {
      final value = entry.value.trim();
      if (value.isNotEmpty) return value;
    }
  }
  return null;
}

String? extractEtagFromResponse(http.Response response) {
  return extractEtagFromHeaders(response.headers);
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
    final now = DateTime.now();
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

class PlayIntegrity {
  PlayIntegrity._();
  static const MethodChannel _channel = MethodChannel(
    'preconnect/play_integrity',
  );

  static bool _prepared = false;
  static DateTime? _preparedAtUtc;
  static const Duration _prepareTtl = Duration(hours: 8);

  static String? _cachedToken;
  static DateTime? _cachedAtUtc;
  static String? _cachedRequestHash;
  static const Duration _cacheTtl = Duration(minutes: 2);

  static Future<void> prepare() async {
    if (!Platform.isAndroid) return;

    final preparedAt = _preparedAtUtc;
    if (_prepared && preparedAt != null) {
      final stillValid =
          DateTime.now().toUtc().difference(preparedAt) < _prepareTtl;
      if (stillValid) return;
    }

    await _channel.invokeMethod('prepare', <String, dynamic>{
      'cloudProjectNumber': ApiConfig.playIntegrityCloudProjectNumber,
    });
    _prepared = true;
    _preparedAtUtc = DateTime.now().toUtc();
  }

  static Future<String?> tokenForRequest({
    required String method,
    required String url,
    String body = '',
  }) async {
    if (!Platform.isAndroid) return null;

    try {
      await prepare();
    } catch (_) {
      _prepared = false;
      return null;
    }

    final requestHash = _buildRequestHash(method: method, url: url, body: body);
    final now = DateTime.now().toUtc();
    final token = _cachedToken;
    final cachedAtUtc = _cachedAtUtc;
    final cachedRequestHash = _cachedRequestHash;
    if (token != null &&
        cachedAtUtc != null &&
        requestHash == cachedRequestHash &&
        now.difference(cachedAtUtc) < _cacheTtl) {
      return token;
    }

    final dynamic value = await _channel.invokeMethod(
      'requestToken',
      <String, dynamic>{'requestHash': requestHash},
    );
    if (value is! String || value.isEmpty) return null;

    _cachedToken = value;
    _cachedAtUtc = now;
    _cachedRequestHash = requestHash;
    return value;
  }

  static String requestHash({
    required String method,
    required String url,
    String body = '',
  }) {
    return _buildRequestHash(method: method, url: url, body: body);
  }

  static String _buildRequestHash({
    required String method,
    required String url,
    required String body,
  }) {
    final canonical =
        '${method.trim().toUpperCase()}|${url.trim()}|${body.trim()}';
    final digest = sha256.convert(utf8.encode(canonical));
    return base64UrlEncode(digest.bytes).replaceAll('=', '');
  }
}
