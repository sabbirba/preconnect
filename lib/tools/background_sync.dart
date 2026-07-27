import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:preconnect/api/profile.dart';
import 'package:preconnect/api/schedule.dart';
import 'package:preconnect/pages/home.dart';
import 'package:preconnect/tools/app_storage.dart';

class BackgroundSyncService {
  BackgroundSyncService._();
  static final BackgroundSyncService instance = BackgroundSyncService._();

  static const String _lastSyncKey = 'background_last_sync_timestamp';
  static const Duration _minSyncInterval = Duration(minutes: 15);

  StreamSubscription<List<ConnectivityResult>>? _connectivitySub;
  bool _isSyncing = false;

  void initialize() {
    if (kIsWeb) return;
    _connectivitySub?.cancel();
    _connectivitySub = Connectivity().onConnectivityChanged.listen((results) {
      final isConnected = results.any((r) => r != ConnectivityResult.none);
      if (isConnected) {
        unawaited(performBackgroundSync());
      }
    });
  }

  Future<bool> performBackgroundSync({bool force = false}) async {
    if (_isSyncing) return false;
    final prefs = AppStorage.instance;
    final lastSyncMillis = prefs.getIntSync(_lastSyncKey) ?? 0;
    final now = DateTime.now().millisecondsSinceEpoch;

    if (!force && (now - lastSyncMillis) < _minSyncInterval.inMilliseconds) {
      return false;
    }

    _isSyncing = true;
    try {
      await prefs.setInt(_lastSyncKey, now);

      await Future.wait([
        preloadHomeDashboardData(forceRefresh: true).then((_) {}),
        ProfileService().getProfile(fromFetch: true).then((_) {}),
        ScheduleService().preloadAllSemesters(forceRefresh: true),
      ]);

      return true;
    } catch (_) {
      return false;
    } finally {
      _isSyncing = false;
    }
  }

  void dispose() {
    _connectivitySub?.cancel();
  }
}
