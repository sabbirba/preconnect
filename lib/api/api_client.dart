import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:http/http.dart' as http;
import 'package:preconnect/api/api_config.dart';
import 'package:preconnect/api/api_exceptions.dart';
import 'package:preconnect/api/auth_service.dart';
import 'package:preconnect/tools/play_install_referrer.dart';
import 'package:preconnect/tools/play_integrity.dart';
import 'package:preconnect/tools/token_storage.dart';
import 'package:preconnect/tools/web_login_broker_service.dart';
import 'package:preconnect/tools/web_login_session_store.dart';

class ApiClient {
  static final ApiClient _instance = ApiClient._internal();
  factory ApiClient() => _instance;
  ApiClient._internal();

  final TokenStorage _storage = TokenStorage.instance;
  final WebLoginBrokerService _webLoginBroker = WebLoginBrokerService();
  static const Duration _requestTimeout = Duration(seconds: 12);
  static const Duration _connectivityCacheTtl = Duration(seconds: 10);
  static const Duration _webSessionCheckTtl = Duration(seconds: 12);
  DateTime? _lastConnectivityCheckedAt;
  bool? _lastConnectivityResult;
  DateTime? _lastWebSessionCheckedAt;
  bool _lastWebSessionIsActive = true;

  Future<bool> hasConnection({bool forceRefresh = false}) async {
    final now = DateTime.now();
    if (!forceRefresh &&
        _lastConnectivityCheckedAt != null &&
        _lastConnectivityResult != null &&
        now.difference(_lastConnectivityCheckedAt!) <= _connectivityCacheTtl) {
      return _lastConnectivityResult!;
    }
    try {
      final result = await Connectivity().checkConnectivity();
      final online = !result.contains(ConnectivityResult.none);
      _lastConnectivityCheckedAt = now;
      _lastConnectivityResult = online;
      return online;
    } catch (_) {
      _lastConnectivityCheckedAt = now;
      _lastConnectivityResult = false;
      return _lastConnectivityResult!;
    }
  }

  Future<String?> getAccessToken() async {
    return _storage.read(key: 'access_token');
  }

  Future<http.Response> authenticatedGet(
    String url, {
    Map<String, String> additionalHeaders = const <String, String>{},
    Set<int> acceptedStatusCodes = const <int>{200},
  }) async {
    if (!await _ensureWebSessionActive()) {
      await AuthService().logout();
      throw const SessionExpiredException();
    }

    final token = await getAccessToken();
    if (token == null || token.isEmpty) {
      throw const UnauthenticatedException();
    }

    final headers = await _authHeaders(token, method: 'GET', url: url);
    if (additionalHeaders.isNotEmpty) {
      headers.addAll(additionalHeaders);
    }

    final response = await http
        .get(Uri.parse(url), headers: headers)
        .timeout(_requestTimeout);

    if (acceptedStatusCodes.contains(response.statusCode)) return response;

    if (response.statusCode == 401) {
      final refreshStatus = await AuthService().refreshTokenStatus();
      if (refreshStatus == TokenRefreshStatus.invalidSession) {
        await AuthService().logout();
        throw const SessionExpiredException();
      }
      if (refreshStatus == TokenRefreshStatus.retryableFailure) {
        throw ApiException(
          401,
          'Token refresh failed due to transient connectivity issues',
        );
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
        await AuthService().logout();
        throw const SessionExpiredException();
      }

      throw ApiException(retryResponse.statusCode, retryResponse.body);
    }

    throw ApiException(response.statusCode, response.body);
  }

  Future<bool> _ensureWebSessionActive() async {
    if (!kIsWeb) return true;
    final loginMode = await WebLoginSessionStore.getLoginMode();
    if (loginMode == 'vm') return true;
    final now = DateTime.now();
    if (_lastWebSessionCheckedAt != null &&
        now.difference(_lastWebSessionCheckedAt!) <= _webSessionCheckTtl) {
      return _lastWebSessionIsActive;
    }
    final sessionId = await WebLoginSessionStore.getWebSessionId();
    final sessionToken = await WebLoginSessionStore.getWebSessionToken();
    if ((sessionId ?? '').isEmpty || (sessionToken ?? '').isEmpty) {
      return false;
    }
    try {
      final isActive = await _webLoginBroker.isActiveWebSession(
        webSessionId: sessionId!,
        webSessionToken: sessionToken!,
      );
      _lastWebSessionCheckedAt = now;
      _lastWebSessionIsActive = isActive;
      return isActive;
    } catch (_) {
      _lastWebSessionCheckedAt = now;
      return _lastWebSessionIsActive;
    }
  }

  Future<http.Response> publicGet(
    String url, {
    Map<String, String> headers = const <String, String>{},
    Set<int> acceptedStatusCodes = const <int>{200},
  }) async {
    final mergedHeaders = <String, String>{
      'Accept': 'application/json',
      ...headers,
    };
    final response = await http
        .get(Uri.parse(url), headers: mergedHeaders)
        .timeout(_requestTimeout);
    if (acceptedStatusCodes.contains(response.statusCode)) return response;
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
}
