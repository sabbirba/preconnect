import 'package:shared_preferences/shared_preferences.dart';
import 'package:preconnect/tools/token_storage.dart';

class WebLoginSessionStore {
  WebLoginSessionStore._();

  static const String _studentEmailKey = 'web_login_student_email';
  static const String _webSessionIdKey = 'web_login_session_id';
  static const String _webSessionTokenKey = 'web_login_session_token';
  static const String _loginModeKey = 'web_login_mode';
  static const String _modeBroker = 'broker';
  static const String _modeVm = 'vm';

  static Future<void> save({
    required String accessToken,
    required String refreshToken,
    required String studentEmail,
    String? webSessionId,
    String? webSessionToken,
    bool vmLogin = false,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await TokenStorage.instance.write(key: 'access_token', value: accessToken);
    await TokenStorage.instance.write(
      key: 'refresh_token',
      value: refreshToken,
    );
    await prefs.setString(_studentEmailKey, studentEmail.trim());
    final normalizedSessionId = (webSessionId ?? '').trim();
    final normalizedSessionToken = (webSessionToken ?? '').trim();
    if (normalizedSessionId.isNotEmpty && normalizedSessionToken.isNotEmpty) {
      await prefs.setString(_webSessionIdKey, normalizedSessionId);
      await prefs.setString(_webSessionTokenKey, normalizedSessionToken);
      await prefs.setString(_loginModeKey, _modeBroker);
      return;
    }
    await prefs.remove(_webSessionIdKey);
    await prefs.remove(_webSessionTokenKey);
    await prefs.setString(_loginModeKey, vmLogin ? _modeVm : _modeBroker);
  }

  static Future<bool> hasValidSession() async {
    final mode = await getLoginMode();
    if (mode == _modeVm) return true;
    final sessionId = await getWebSessionId();
    final sessionToken = await getWebSessionToken();
    return (sessionId ?? '').isNotEmpty && (sessionToken ?? '').isNotEmpty;
  }

  static Future<String> getLoginMode() async {
    final prefs = await SharedPreferences.getInstance();
    final value = prefs.getString(_loginModeKey)?.trim();
    if (value == _modeVm) return _modeVm;
    return _modeBroker;
  }

  static Future<String?> getWebSessionId() async {
    final prefs = await SharedPreferences.getInstance();
    final value = prefs.getString(_webSessionIdKey)?.trim();
    if (value == null || value.isEmpty) return null;
    return value;
  }

  static Future<String?> getWebSessionToken() async {
    final prefs = await SharedPreferences.getInstance();
    final value = prefs.getString(_webSessionTokenKey)?.trim();
    if (value == null || value.isEmpty) return null;
    return value;
  }

  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_studentEmailKey);
    await prefs.remove(_webSessionIdKey);
    await prefs.remove(_webSessionTokenKey);
    await prefs.remove(_loginModeKey);
  }
}
