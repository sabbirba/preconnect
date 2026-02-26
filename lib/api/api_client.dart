import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:http/http.dart' as http;
import 'package:preconnect/api/api_config.dart';
import 'package:preconnect/api/api_exceptions.dart';
import 'package:preconnect/api/auth_service.dart';
import 'package:preconnect/tools/play_install_referrer.dart';
import 'package:preconnect/tools/play_integrity.dart';
import 'package:preconnect/tools/token_storage.dart';

class ApiClient {
  static final ApiClient _instance = ApiClient._internal();
  factory ApiClient() => _instance;
  ApiClient._internal();

  final TokenStorage _storage = TokenStorage.instance;
  static const Duration _requestTimeout = Duration(seconds: 12);
  static const Duration _connectivityCacheTtl = Duration(seconds: 10);
  DateTime? _lastConnectivityCheckedAt;
  bool? _lastConnectivityResult;

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
