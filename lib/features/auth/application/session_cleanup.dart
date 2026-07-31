import 'package:preconnect/tools/token_storage.dart';

Future<void> clearAuthenticationState({
  TokenStorage? storage,
  void Function()? clearTransientCaches,
  Future<void> Function()? clearUiArtifacts,
}) async {
  await (storage ?? TokenStorage.instance).deleteAll();
  clearTransientCaches?.call();
  await clearUiArtifacts?.call();
}
