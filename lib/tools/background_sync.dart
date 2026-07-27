import 'dart:async';

class BackgroundSyncService {
  BackgroundSyncService._();
  static final BackgroundSyncService instance = BackgroundSyncService._();

  void initialize() {}

  Future<bool> performBackgroundSync({bool force = false}) async {
    return false;
  }

  void dispose() {}
}
