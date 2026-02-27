import 'package:preconnect/tools/token_storage.dart';

class CaptiveLoginCredentials {
  const CaptiveLoginCredentials({
    required this.ssid,
    required this.username,
    required this.password,
  });

  final String ssid;
  final String username;
  final String password;
}

class CaptiveLoginStore {
  CaptiveLoginStore._();

  static final CaptiveLoginStore instance = CaptiveLoginStore._();
  static const String _ssidKey = 'wifi_captive_ssid';
  static const String _usernameKey = 'wifi_captive_username';
  static const String _passwordKey = 'wifi_captive_password';
  static const String defaultCampusSsid = 'Student-WiFi';

  final TokenStorage _storage = TokenStorage.instance;

  Future<CaptiveLoginCredentials?> read() async {
    final ssid = (await _storage.read(key: _ssidKey) ?? defaultCampusSsid)
        .trim();
    final username = (await _storage.read(key: _usernameKey) ?? '').trim();
    final password = await _storage.read(key: _passwordKey) ?? '';
    if (username.isEmpty || password.isEmpty) return null;
    return CaptiveLoginCredentials(
      ssid: ssid.isEmpty ? defaultCampusSsid : ssid,
      username: username,
      password: password,
    );
  }

  Future<void> save({
    required String ssid,
    required String username,
    required String password,
  }) async {
    final cleanedSsid = ssid.trim();
    final trimmed = username.trim();
    await _storage.write(
      key: _ssidKey,
      value: cleanedSsid.isEmpty ? defaultCampusSsid : cleanedSsid,
    );
    await _storage.write(key: _usernameKey, value: trimmed);
    await _storage.write(key: _passwordKey, value: password);
  }

  Future<void> clear() async {
    await _storage.write(key: _ssidKey, value: null);
    await _storage.write(key: _usernameKey, value: null);
    await _storage.write(key: _passwordKey, value: null);
  }
}
