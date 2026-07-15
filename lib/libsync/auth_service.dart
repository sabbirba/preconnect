import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'libsync_config.dart';
import 'google_auth_helper.dart';
import 'libsync_api_client.dart';
import 'package:preconnect/libsync/libsync_page.dart';

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
  String? _lastProcessedCode;
  final ValueNotifier<LibSyncAuthState> state = ValueNotifier<LibSyncAuthState>(
    const LibSyncAuthState(status: LibSyncAuthStatus.loading),
  );

  Future<bool> loginSilentlyWithBackend() async {
    try {
      final localRefreshToken = await _apiClient.getGoogleRefreshToken();
      if (localRefreshToken != null && localRefreshToken.isNotEmpty) {
        try {
          final googleTokens = await GoogleAuthHelper.refreshAccessToken(
            localRefreshToken,
          );
          final googleAccessToken = googleTokens['access_token'] as String?;
          final newGoogleRefreshToken =
              googleTokens['refresh_token'] as String?;
          if (newGoogleRefreshToken != null &&
              newGoogleRefreshToken.isNotEmpty) {
            await _apiClient.storeGoogleRefreshToken(newGoogleRefreshToken);
          }
          if (googleAccessToken != null && googleAccessToken.isNotEmpty) {
            await authenticateWithAccessToken(googleAccessToken);
            return true;
          }
        } catch (_) {}
      }
    } catch (_) {}
    return false;
  }

  Future<void> initialize() async {
    state.value = const LibSyncAuthState(status: LibSyncAuthStatus.loading);
    try {
      final response = await _apiClient.get(Uri.parse(LibSyncConfig.userMeUrl));
      if (response.statusCode == 200) {
        final profile = jsonDecode(response.body) as Map<String, dynamic>;
        await _apiClient.saveCachedProfile(profile);
        state.value = LibSyncAuthState(
          status: LibSyncAuthStatus.authenticated,
          profile: profile,
        );
      } else if (response.statusCode == 401 || response.statusCode == 403) {
        final ok = await loginSilentlyWithBackend();
        if (!ok) {
          await _apiClient.clearAuthData();
          state.value = const LibSyncAuthState(
            status: LibSyncAuthStatus.unauthenticated,
          );
        }
      } else {
        throw Exception('Server returned ${response.statusCode}');
      }
    } catch (e) {
      final cookies = await _apiClient.getStoredCookies();
      if (cookies.isNotEmpty) {
        final cachedProfile = await _apiClient.getCachedProfile();
        state.value = LibSyncAuthState(
          status: LibSyncAuthStatus.authenticated,
          profile:
              cachedProfile ??
              const {'student_id': 'Cached User', 'name': 'Offline Mode'},
        );
      } else {
        final ok = await loginSilentlyWithBackend();
        if (!ok) {
          state.value = const LibSyncAuthState(
            status: LibSyncAuthStatus.unauthenticated,
          );
        }
      }
    }
  }

  Future<void> authenticateWithCode(String code, {String? redirectUri}) async {
    if (code == _lastProcessedCode) return;
    _lastProcessedCode = code;
    state.value = const LibSyncAuthState(status: LibSyncAuthStatus.loading);
    try {
      final googleTokens = await GoogleAuthHelper.exchangeCodeForTokens(
        code,
        redirectUri: redirectUri,
      );
      final googleAccessToken = googleTokens['access_token'] as String?;
      final googleRefreshToken = googleTokens['refresh_token'] as String?;
      if (googleRefreshToken != null && googleRefreshToken.isNotEmpty) {
        await _apiClient.storeGoogleRefreshToken(googleRefreshToken);
      }
      if (googleAccessToken != null && googleAccessToken.isNotEmpty) {
        await authenticateWithAccessToken(googleAccessToken);
      } else {
        throw Exception('No access token returned');
      }
    } catch (e) {
      await _apiClient.clearAuthData();
      state.value = LibSyncAuthState(
        status: LibSyncAuthStatus.error,
        errorMessage: e.toString(),
      );
    }
  }

  Future<void> authenticateWithAccessToken(String googleAccessToken) async {
    state.value = const LibSyncAuthState(status: LibSyncAuthStatus.loading);
    try {
      await _authenticateWithGoogleAccessToken(googleAccessToken);
    } catch (e) {
      await _apiClient.clearAuthData();
      state.value = LibSyncAuthState(
        status: LibSyncAuthStatus.error,
        errorMessage: e.toString(),
      );
    }
  }

  Future<void> authenticateWithTokens({
    required String googleAccessToken,
    String? googleRefreshToken,
  }) async {
    state.value = const LibSyncAuthState(status: LibSyncAuthStatus.loading);
    try {
      if (googleRefreshToken != null && googleRefreshToken.isNotEmpty) {
        await _apiClient.storeGoogleRefreshToken(googleRefreshToken);
      }
      await _authenticateWithGoogleAccessToken(googleAccessToken);
    } catch (e) {
      await _apiClient.clearAuthData();
      state.value = LibSyncAuthState(
        status: LibSyncAuthStatus.error,
        errorMessage: e.toString(),
      );
    }
  }

  Future<void> _authenticateWithGoogleAccessToken(
    String googleAccessToken,
  ) async {
    final libsyncAuthResponse = await _apiClient.post(
      Uri.parse(LibSyncConfig.authSocialGoogleUrl),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'access_token': googleAccessToken}),
    );

    if (libsyncAuthResponse.statusCode != 200) {
      throw Exception('LibSync sign in failed');
    }

    final Map<String, String> cookiesToSave = {};
    try {
      final body = jsonDecode(libsyncAuthResponse.body) as Map<String, dynamic>;
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

    state.value = const LibSyncAuthState(
      status: LibSyncAuthStatus.authenticated,
      profile: {'student_id': '', 'name': ''},
    );

    unawaited(
      _fetchUserProfile().then((profile) async {
        if (profile != null) {
          await _apiClient.saveCachedProfile(profile);
          state.value = LibSyncAuthState(
            status: LibSyncAuthStatus.authenticated,
            profile: profile,
          );
        }
      }),
    );
  }

  Future<void> logout() async {
    _lastProcessedCode = null;
    state.value = const LibSyncAuthState(status: LibSyncAuthStatus.loading);
    await _apiClient.clearAuthData();
    await LibSyncPage.clearReservationCache();
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
    final response = await _apiClient.get(
      Uri.parse(
        '${LibSyncConfig.apiBaseUrl}/api/reservation/check-availability/?'
        'start_date=$startDate&end_date=$endDate&'
        'start_time=$startTime&end_time=$endTime&'
        'capacity=$capacity&library=${Uri.encodeComponent(library)}',
      ),
    );

    final decoded = jsonDecode(response.body);
    if (response.statusCode == 200 && decoded is List) {
      return decoded;
    }

    throw Exception(
      _extractErrorMessage(
        decoded,
        'Failed to load availability data. Please try again.',
      ),
    );
  }

  Future<Map<String, dynamic>?> holdSlot({
    required int roomId,
    required String date,
    required List<int> slotIds,
    int memberCount = 1,
  }) async {
    final response = await _apiClient.post(
      Uri.parse('${LibSyncConfig.apiBaseUrl}/api/reservation/holdslot/create'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'member_count': memberCount,
        'room_no': roomId,
        'reserve_start_date': date,
        'reserve_end_date': date,
        'slot_ids': slotIds,
      }),
    );
    final decoded = jsonDecode(response.body);
    if (response.statusCode == 200 || response.statusCode == 201) {
      return decoded as Map<String, dynamic>;
    }
    throw Exception(
      _extractErrorMessage(decoded, 'Failed to hold slot. Please try again.'),
    );
  }

  Future<Map<String, dynamic>?> checkMember(String studentId) async {
    final response = await _apiClient.get(
      Uri.parse(
        '${LibSyncConfig.apiBaseUrl}/api/reservation/check-member/$studentId/',
      ),
    );
    if (response.statusCode == 200 || response.statusCode == 201) {
      final body = response.body.trim();
      if (body.isEmpty) {
        return null;
      }
      try {
        final decoded = jsonDecode(body);
        if (decoded is Map<String, dynamic>) {
          return decoded;
        }
      } catch (_) {}
      return null;
    }
    final decoded = jsonDecode(response.body);
    throw Exception(
      _extractErrorMessage(decoded, 'Failed to check member ID.'),
    );
  }

  Future<Map<String, dynamic>?> confirmReservation({
    required List<String> studentIds,
    String note = '',
  }) async {
    final response = await _apiClient.post(
      Uri.parse('${LibSyncConfig.apiBaseUrl}/api/reservation/'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'student_ids': studentIds, 'note': note}),
    );
    final decoded = jsonDecode(response.body);
    if (response.statusCode == 200 || response.statusCode == 201) {
      return decoded as Map<String, dynamic>;
    }
    throw Exception(
      _extractErrorMessage(
        decoded,
        'Failed to confirm reservation. Please try again.',
      ),
    );
  }

  Future<void> cancelReservation(String uniqueToken) async {
    final response = await _apiClient.delete(
      Uri.parse('${LibSyncConfig.apiBaseUrl}/api/reservation/$uniqueToken/'),
    );
    if (response.statusCode == 200 || response.statusCode == 204) {
      return;
    }
    final decoded = jsonDecode(response.body);
    throw Exception(
      _extractErrorMessage(
        decoded,
        'Failed to cancel reservation. Please try again.',
      ),
    );
  }

  Future<String> checkInAttendance(int reservationCode) async {
    final response = await _apiClient.patch(
      Uri.parse(
        '${LibSyncConfig.apiBaseUrl}/api/reservation/$reservationCode/public_attendance/',
      ),
      headers: {'Content-Type': 'application/json'},
    );
    final decoded = jsonDecode(response.body);

    String? serverMessage;
    if (decoded is Map) {
      if (decoded.containsKey('message')) {
        serverMessage = decoded['message'].toString();
      } else if (decoded.containsKey('detail')) {
        serverMessage = decoded['detail'].toString();
      }
    }

    if (response.statusCode == 200 || response.statusCode == 204) {
      return serverMessage ?? 'Attendance checked in successfully!';
    }
    throw Exception(
      _extractErrorMessage(decoded, 'Failed to check in. Please try again.'),
    );
  }

  String _extractErrorMessage(dynamic decoded, String defaultMessage) {
    if (decoded is Map) {
      if (decoded.containsKey('message')) return decoded['message'].toString();
      if (decoded.containsKey('detail')) return decoded['detail'].toString();
      if (decoded.containsKey('error')) return decoded['error'].toString();
    } else if (decoded is List && decoded.isNotEmpty) {
      final first = decoded.first;
      if (first is Map) {
        if (first.containsKey('message')) return first['message'].toString();
        if (first.containsKey('detail')) return first['detail'].toString();
        if (first.containsKey('error')) return first['error'].toString();
      }
    }
    return defaultMessage;
  }
}
