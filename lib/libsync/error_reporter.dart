import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:preconnect/tools/app_log.dart';

void reportLibSyncError(String operation, Object error, StackTrace stackTrace) {
  if (kDebugMode) {
    unawaited(AppLog.write('LibSync [$operation]: $error'));
  }
}
