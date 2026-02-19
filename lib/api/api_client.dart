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

  Future<bool> hasConnection() async {
    final result = await Connectivity().checkConnectivity();
    return !result.contains(ConnectivityResult.none);
  }

  Future<String?> getAccessToken() async {
    return _storage.read(key: 'access_token');
  }

  Future<http.Response> authenticatedGet(String url) async {
    final token = await getAccessToken();
    if (token == null || token.isEmpty) {
      throw const UnauthenticatedException();
    }

    final response = await http.get(
      Uri.parse(url),
      headers: await _authHeaders(token, method: 'GET', url: url),
    );

    if (response.statusCode == 200) return response;

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

      final retryResponse = await http.get(
        Uri.parse(url),
        headers: await _authHeaders(newToken, method: 'GET', url: url),
      );

      if (retryResponse.statusCode == 200) return retryResponse;
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
