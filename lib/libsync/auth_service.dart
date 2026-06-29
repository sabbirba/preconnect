import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'libsync_config.dart';
import 'google_auth_helper.dart';
import 'libsync_api_client.dart';

enum LibSyncAuthStatus { authenticated, unauthenticated, loading, error }

class LibSyncAuthState {
  const LibSyncAuthState({
    required this.status,
    this.profile,
    this.errorMessage,
  });

  final LibSyncAuthStatus status;
  final Map<String, dynamic>? profile;
  final String? errorMessage;
}

class LibSyncAuthService extends ChangeNotifier {
  LibSyncAuthService._() : _apiClient = LibSyncApiClient() {
    initialize();
  }

  static final LibSyncAuthService instance = LibSyncAuthService._();

  final LibSyncApiClient _apiClient;
  final ValueNotifier<LibSyncAuthState> state = ValueNotifier<LibSyncAuthState>(
    const LibSyncAuthState(status: LibSyncAuthStatus.loading),
  );

  Future<void> initialize() async {
    state.value = const LibSyncAuthState(status: LibSyncAuthStatus.loading);
    try {
      final profile = await _fetchUserProfile();
      if (profile != null) {
        state.value = LibSyncAuthState(
          status: LibSyncAuthStatus.authenticated,
          profile: profile,
        );
      } else {
        state.value = const LibSyncAuthState(
          status: LibSyncAuthStatus.unauthenticated,
        );
      }
    } catch (e) {
      state.value = LibSyncAuthState(
        status: LibSyncAuthStatus.error,
        errorMessage: e.toString(),
      );
    }
  }

  Future<void> authenticateWithCode(String code) async {
    state.value = const LibSyncAuthState(status: LibSyncAuthStatus.loading);
    try {
      final googleTokens = await GoogleAuthHelper.exchangeCode(code);
      final googleAccessToken = googleTokens['access_token'] as String?;
      final googleRefreshToken = googleTokens['refresh_token'] as String?;

      if (googleAccessToken == null) {
        throw Exception('Google Access Token not returned');
      }

      if (googleRefreshToken != null) {
        await _apiClient.storeGoogleRefreshToken(googleRefreshToken);
      }

      final libsyncAuthResponse = await _apiClient.post(
        Uri.parse(LibSyncConfig.authSocialGoogleUrl),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'access_token': googleAccessToken}),
      );

      if (libsyncAuthResponse.statusCode != 200) {
        throw Exception(
          'LibSync social auth failed: ${libsyncAuthResponse.body}',
        );
      }

      final Map<String, String> cookiesToSave = {};
      try {
        final body =
            jsonDecode(libsyncAuthResponse.body) as Map<String, dynamic>;
        final accessVal = body['access'] ?? body['access_token'];
        final refreshVal = body['refresh'] ?? body['refresh_token'];
        if (accessVal != null) {
          cookiesToSave['access'] = accessVal.toString();
        }
        if (refreshVal != null) {
          cookiesToSave['refresh'] = refreshVal.toString();
        }
      } catch (_) {}

      final parsedCookies = _apiClient.parseResponseCookies(
        libsyncAuthResponse.headers,
      );
      cookiesToSave.addAll(parsedCookies);

      if (cookiesToSave.isNotEmpty) {
        await _apiClient.saveCookies(cookiesToSave);
      }

      final profile = await _fetchUserProfile();
      if (profile != null) {
        state.value = LibSyncAuthState(
          status: LibSyncAuthStatus.authenticated,
          profile: profile,
        );
      } else {
        throw Exception('Failed to fetch profile after login');
      }
    } catch (e) {
      await _apiClient.clearAuthData();
      state.value = LibSyncAuthState(
        status: LibSyncAuthStatus.error,
        errorMessage: e.toString(),
      );
    }
  }

  Future<void> logout() async {
    state.value = const LibSyncAuthState(status: LibSyncAuthStatus.loading);
    await _apiClient.clearAuthData();
    state.value = const LibSyncAuthState(
      status: LibSyncAuthStatus.unauthenticated,
    );
  }

  Future<Map<String, dynamic>?> _fetchUserProfile() async {
    try {
      final response = await _apiClient.get(Uri.parse(LibSyncConfig.userMeUrl));
      if (response.statusCode == 200) {
        return jsonDecode(response.body) as Map<String, dynamic>;
      }
    } catch (_) {}
    return null;
  }

  Future<List<dynamic>?> fetchReservationByYear(int year) async {
    try {
      final response = await _apiClient.get(
        Uri.parse(
          '${LibSyncConfig.apiBaseUrl}/api/reservation/reservation-by-year/$year/Cancelled%2CConfirmed%2CPresented/',
        ),
      );
      if (response.statusCode == 200) {
        return jsonDecode(response.body) as List<dynamic>;
      }
    } catch (_) {}
    return null;
  }

  Future<Map<String, dynamic>?> fetchRecentReservations({int limit = 5}) async {
    try {
      final response = await _apiClient.get(
        Uri.parse('${LibSyncConfig.apiBaseUrl}/api/reservation/?limit=$limit'),
      );
      if (response.statusCode == 200) {
        return jsonDecode(response.body) as Map<String, dynamic>;
      }
    } catch (_) {}
    return null;
  }

  Future<List<dynamic>?> fetchCheckQuota(String dateStr) async {
    try {
      final response = await _apiClient.get(
        Uri.parse(
          '${LibSyncConfig.apiBaseUrl}/api/reservation/check-quota/$dateStr/',
        ),
      );
      if (response.statusCode == 200) {
        return jsonDecode(response.body) as List<dynamic>;
      }
    } catch (_) {}
    return null;
  }

  Future<Map<String, dynamic>?> fetchTotalReservationCount() async {
    try {
      final response = await _apiClient.get(
        Uri.parse(
          '${LibSyncConfig.apiBaseUrl}/api/reservation/total-reservation-count/',
        ),
      );
      if (response.statusCode == 200) {
        return jsonDecode(response.body) as Map<String, dynamic>;
      }
    } catch (_) {}
    return null;
  }

  Future<List<dynamic>?> fetchCheckAvailability({
    required String startDate,
    required String endDate,
    required String startTime,
    required String endTime,
    int capacity = 1,
    String library = 'Ayesha Abed Library (Main Campus)',
  }) async {
    try {
      final response = await _apiClient.get(
        Uri.parse(
          '${LibSyncConfig.apiBaseUrl}/api/reservation/check-availability/?'
          'start_date=$startDate&end_date=$endDate&'
          'start_time=$startTime&end_time=$endTime&'
          'capacity=$capacity&library=${Uri.encodeComponent(library)}',
        ),
      );
      if (response.statusCode == 200) {
        return jsonDecode(response.body) as List<dynamic>;
      }
    } catch (_) {}
    return null;
  }
}
