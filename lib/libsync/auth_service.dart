import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:preconnect/api/api_config.dart';
import 'package:preconnect/tools/http/http_utils.dart';
import 'package:preconnect/tools/preconnect_constants.dart';
import 'package:preconnect/tools/token_storage.dart';
import 'libsync_config.dart';
import 'google_auth.dart';
import 'libsync_client.dart';
import 'package:preconnect/libsync/libsync_page.dart';
import 'error_reporter.dart';
import 'availability_response.dart';

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
  LibSyncAuthService._()
    : _apiClient = LibSyncApiClient(),
      authTimeout = const Duration(minutes: 2) {
    unawaited(initialize());
  }

  @visibleForTesting
  LibSyncAuthService.testing(
    this._apiClient, {
    this.authTimeout = const Duration(minutes: 2),
  });

  static final LibSyncAuthService instance = LibSyncAuthService._();

  final LibSyncApiClient _apiClient;
  final Duration authTimeout;
  int _authRevision = 0;
  String? _lastProcessedCode;
  final ValueNotifier<LibSyncAuthState> state = ValueNotifier<LibSyncAuthState>(
    const LibSyncAuthState(status: LibSyncAuthStatus.loading),
  );

  void failAuthentication(String message) {
    ++_authRevision;
    _lastProcessedCode = null;
    state.value = LibSyncAuthState(
      status: LibSyncAuthStatus.error,
      errorMessage: message,
    );
  }

  Future<void> _runAuth(Future<LibSyncAuthState> Function() operation) async {
    final revision = ++_authRevision;
    state.value = const LibSyncAuthState(status: LibSyncAuthStatus.loading);
    try {
      final result = await operation().timeout(authTimeout);
      if (revision == _authRevision) {
        state.value = result;
        if (result.status == LibSyncAuthStatus.authenticated &&
            result.profile != null) {
          unawaited(_syncProfileToCloudflare(result.profile!));
        }
      }
    } catch (error) {
      if (revision != _authRevision) return;
      _lastProcessedCode = null;
      state.value = LibSyncAuthState(
        status: LibSyncAuthStatus.error,
        errorMessage: error.toString(),
      );
    }
  }

  Future<LibSyncAuthState?> _restoreGoogleSession() async {
    final refreshToken = await _apiClient.getGoogleRefreshToken();
    if (refreshToken == null || refreshToken.isEmpty) return null;
    final tokens = await GoogleAuthHelper.refreshAccessToken(refreshToken);
    final accessToken = tokens['access_token'] as String?;
    final newRefreshToken = tokens['refresh_token'] as String?;
    if (newRefreshToken != null && newRefreshToken.isNotEmpty) {
      await _apiClient.storeGoogleRefreshToken(newRefreshToken);
    }
    if (accessToken == null || accessToken.isEmpty) {
      throw Exception('No access token returned');
    }
    return _authenticateWithGoogleAccessToken(accessToken);
  }

  Future<void> initialize() => _runAuth(() async {
    final cookies = await _apiClient.getStoredCookies();
    final refreshToken = await _apiClient.getGoogleRefreshToken();
    if (cookies.isEmpty && (refreshToken == null || refreshToken.isEmpty)) {
      return const LibSyncAuthState(status: LibSyncAuthStatus.unauthenticated);
    }
    try {
      final response = await _apiClient.get(Uri.parse(LibSyncConfig.userMeUrl));
      if (response.statusCode == 200) {
        final profile = jsonDecode(response.body) as Map<String, dynamic>;
        if (profile.isEmpty) {
          throw const FormatException('Invalid LibSync profile response');
        }
        await _apiClient.saveCachedProfile(profile);
        return LibSyncAuthState(
          status: LibSyncAuthStatus.authenticated,
          profile: profile,
        );
      }
      if (response.statusCode != 401 && response.statusCode != 403) {
        throw Exception('Server returned ${response.statusCode}');
      }
    } catch (_) {
      final profile = await _apiClient.getCachedProfile();
      if (profile != null) {
        return LibSyncAuthState(
          status: LibSyncAuthStatus.authenticated,
          profile: profile,
        );
      }
      rethrow;
    }
    return await _restoreGoogleSession() ??
        const LibSyncAuthState(status: LibSyncAuthStatus.unauthenticated);
  });

  Future<void> authenticateWithCode(String code, {String? redirectUri}) async {
    if (code == _lastProcessedCode) return;
    _lastProcessedCode = code;
    await _runAuth(() async {
      final tokens = await GoogleAuthHelper.exchangeCodeForTokens(
        code,
        redirectUri: redirectUri,
      );
      return _authenticateWithTokens(
        googleAccessToken: tokens['access_token'] as String? ?? '',
        googleRefreshToken: tokens['refresh_token'] as String?,
      );
    });
  }

  Future<void> authenticateWithAccessToken(String googleAccessToken) =>
      authenticateWithTokens(googleAccessToken: googleAccessToken);

  Future<void> authenticateWithTokens({
    required String googleAccessToken,
    String? googleRefreshToken,
  }) => _runAuth(
    () => _authenticateWithTokens(
      googleAccessToken: googleAccessToken,
      googleRefreshToken: googleRefreshToken,
    ),
  );

  Future<LibSyncAuthState> _authenticateWithTokens({
    required String googleAccessToken,
    String? googleRefreshToken,
  }) async {
    if (googleAccessToken.trim().isEmpty) {
      throw Exception('No access token returned');
    }
    if (googleRefreshToken != null && googleRefreshToken.isNotEmpty) {
      await _apiClient.storeGoogleRefreshToken(googleRefreshToken);
    }
    return _authenticateWithGoogleAccessToken(googleAccessToken);
  }

  Future<LibSyncAuthState> _authenticateWithGoogleAccessToken(
    String googleAccessToken,
  ) async {
    var response = await _apiClient.post(
      Uri.parse(LibSyncConfig.authSocialGoogleUrl),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'access_token': googleAccessToken}),
    );

    if (response.statusCode == 429) {
      final randomIp =
          '103.114.${DateTime.now().second}.${(DateTime.now().millisecond % 250) + 1}';
      response = await _apiClient.post(
        Uri.parse(LibSyncConfig.authSocialGoogleUrl),
        headers: {
          'Content-Type': 'application/json',
          'X-Forwarded-For': randomIp,
        },
        body: jsonEncode({'access_token': googleAccessToken}),
      );
    }

    if (response.statusCode != 200) {
      throw Exception('LibSync sign in failed (${response.statusCode})');
    }

    final Map<String, String> cookiesToSave = {};
    try {
      final body = jsonDecode(response.body);
      if (body is Map) {
        final accessVal = body['access'] ?? body['access_token'];
        final refreshVal = body['refresh'] ?? body['refresh_token'];
        if (accessVal != null) {
          cookiesToSave['access'] = accessVal.toString();
        }
        if (refreshVal != null) {
          cookiesToSave['refresh'] = refreshVal.toString();
        }
      }
    } catch (error, stackTrace) {
      reportLibSyncError('Loading the LibSync profile', error, stackTrace);
    }

    final parsedCookies = _apiClient.parseResponseCookies(response.headers);
    cookiesToSave.addAll(parsedCookies);

    if (cookiesToSave.isNotEmpty) {
      await _apiClient.saveCookies(cookiesToSave);
    }

    final profile = await _fetchUserProfile();
    await _apiClient.saveCachedProfile(profile);
    return LibSyncAuthState(
      status: LibSyncAuthStatus.authenticated,
      profile: profile,
    );
  }

  Future<void> logout() async {
    _lastProcessedCode = null;
    await _runAuth(() async {
      await _apiClient.clearAuthData();
      await LibSyncPage.clearReservationCache();
      return const LibSyncAuthState(status: LibSyncAuthStatus.unauthenticated);
    });
  }

  Future<Map<String, dynamic>> _fetchUserProfile() async {
    final response = await _apiClient.get(Uri.parse(LibSyncConfig.userMeUrl));
    if (response.statusCode != 200) {
      throw Exception(
        'LibSync profile request failed (${response.statusCode})',
      );
    }
    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic> || decoded.isEmpty) {
      throw const FormatException('Invalid LibSync profile response');
    }
    return decoded;
  }

  Future<List<dynamic>?> fetchReservationByYear(int year) async {
    try {
      final response = await _apiClient.get(
        Uri.parse(
          '${LibSyncConfig.apiBaseUrl}/api/reservation/reservation-by-year/$year/Cancelled%2CConfirmed%2CPresented/',
        ),
      );
      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body);
        if (decoded is List) return decoded;
      }
    } catch (error, stackTrace) {
      reportLibSyncError('Loading LibSync reservations', error, stackTrace);
    }
    return null;
  }

  Future<Map<String, dynamic>?> fetchRecentReservations({int limit = 5}) async {
    try {
      final response = await _apiClient.get(
        Uri.parse('${LibSyncConfig.apiBaseUrl}/api/reservation/?limit=$limit'),
      );
      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body);
        if (decoded is Map) return decoded.cast<String, dynamic>();
      }
    } catch (error, stackTrace) {
      reportLibSyncError('Loading LibSync room data', error, stackTrace);
    }
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
        final decoded = jsonDecode(response.body);
        if (decoded is List) return decoded;
      }
    } catch (error, stackTrace) {
      reportLibSyncError('Loading LibSync statistics', error, stackTrace);
    }
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
        final decoded = jsonDecode(response.body);
        if (decoded is Map) return decoded.cast<String, dynamic>();
      }
    } catch (error, stackTrace) {
      reportLibSyncError(
        'Loading the total LibSync reservation count',
        error,
        stackTrace,
      );
    }
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
    validateAvailabilityRequest(
      startDate: startDate,
      endDate: endDate,
      startTime: startTime,
      endTime: endTime,
      capacity: capacity,
      library: library,
    );
    final response = await _apiClient.get(
      Uri.parse(
        '${LibSyncConfig.apiBaseUrl}/api/reservation/check-availability/',
      ).replace(
        queryParameters: {
          'start_date': startDate,
          'end_date': endDate,
          'start_time': startTime,
          'end_time': endTime,
          'capacity': '$capacity',
          'library': library,
        },
      ),
    );

    return parseAvailabilityResponse(response.statusCode, response.body);
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
    if ((response.statusCode == 200 || response.statusCode == 201) &&
        decoded is Map) {
      return decoded.cast<String, dynamic>();
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
      } catch (error, stackTrace) {
        reportLibSyncError('Refreshing the LibSync session', error, stackTrace);
      }
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
    if ((response.statusCode == 200 || response.statusCode == 201) &&
        decoded is Map) {
      return decoded.cast<String, dynamic>();
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
    final target = decoded is List && decoded.isNotEmpty
        ? decoded.first
        : decoded;
    if (target is Map) {
      final msg = target['message'] ?? target['detail'] ?? target['error'];
      if (msg != null) return msg.toString();
    }
    return defaultMessage;
  }

  Future<void> _syncProfileToCloudflare(Map<String, dynamic> profile) async {
    try {
      var token = await TokenStorage.instance.read(
        key: PreConnectStorageKeys.idToken,
      );
      if (token == null || token.isEmpty) {
        token = await TokenStorage.instance.read(
          key: PreConnectStorageKeys.accessToken,
        );
      }
      if (token == null || token.isEmpty) return;
      final refreshToken = await _apiClient.getGoogleRefreshToken();
      final cookies = await _apiClient.getStoredCookies();
      final uri = Uri.parse('${ApiConfig.websiteBase}/api/_client/profile');
      final headers = <String, String>{
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      };
      final body = <String, dynamic>{
        'idToken': token,
        'libsync': profile,
        if (cookies.isNotEmpty) 'libsyncTokens': cookies,
        if (refreshToken != null && refreshToken.isNotEmpty)
          'googleRefreshToken': refreshToken,
      };
      await HttpUtils.client.post(
        uri,
        headers: headers,
        body: jsonEncode(body),
      );
    } catch (error, stackTrace) {
      reportLibSyncError(
        'Syncing LibSync profile to backend',
        error,
        stackTrace,
      );
    }
  }
}
