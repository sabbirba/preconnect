import 'package:flutter/foundation.dart';

void reportLibSyncError(String operation, Object error, StackTrace stackTrace) {
  FlutterError.reportError(
    FlutterErrorDetails(
      exception: error,
      stack: stackTrace,
      context: ErrorDescription(operation),
      library: 'PreConnect LibSync',
    ),
  );
}
