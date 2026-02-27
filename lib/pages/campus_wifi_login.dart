import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:permission_handler/permission_handler.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';
import 'package:preconnect/pages/ui_kit.dart';
import 'package:preconnect/tools/android_network_assist.dart';
import 'package:preconnect/tools/captive_login_store.dart';
import 'package:preconnect/tools/user_agent.dart';

class CampusWifiLoginPage extends StatefulWidget {
  const CampusWifiLoginPage({super.key, this.autoOpenPortalOnStart = false});

  final bool autoOpenPortalOnStart;

  @override
  State<CampusWifiLoginPage> createState() => _CampusWifiLoginPageState();
}

class _CampusWifiLoginPageState extends State<CampusWifiLoginPage> {
  static const String _probeUrl =
      'http://connectivitycheck.gstatic.com/generate_204';
  final TextEditingController _ssidController = TextEditingController(
    text: CaptiveLoginStore.defaultCampusSsid,
  );
  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();

  WebViewController? _controller;
  bool _loading = true;
  bool _saving = false;
  bool _autoSubmit = true;
  bool _showPortal = false;
  bool _obscurePassword = true;

  @override
  void initState() {
    super.initState();
    _loadStoredCredentials();
    if (!kIsWeb) {
      _controller = _buildWebViewController();
    }
  }

  Future<void> _loadStoredCredentials() async {
    final creds = await CaptiveLoginStore.instance.read();
    if (!mounted) return;
    if (creds != null) {
      setState(() {
        _ssidController.text = creds.ssid;
        _usernameController.text = creds.username;
        _passwordController.text = creds.password;
      });
      unawaited(_registerWifiSuggestion(notify: false));
    }
    unawaited(_checkPostConnectionEvent());
    if (widget.autoOpenPortalOnStart && !kIsWeb) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        unawaited(_openPortal(silentIfMissingCredentials: true));
      });
    }
  }

  WebViewController _buildWebViewController() {
    final controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted);
    controller.setUserAgent(kPreconnectUserAgent);
    final platform = controller.platform;
    if (platform is AndroidWebViewController) {
      final androidCookieManager = AndroidWebViewCookieManager(
        PlatformWebViewCookieManagerCreationParams(),
      );
      androidCookieManager.setAcceptThirdPartyCookies(platform, true);
    }
    controller.setNavigationDelegate(
      NavigationDelegate(
        onPageStarted: (_) {
          if (!mounted) return;
          setState(() {
            _loading = true;
          });
        },
        onPageFinished: (url) async {
          if (!mounted) return;
          setState(() {
            _loading = false;
          });
          await _tryAutofill(url);
        },
      ),
    );
    return controller;
  }

  Future<void> _saveCredentials() async {
    final ssid = _ssidController.text.trim();
    final username = _usernameController.text.trim();
    final password = _passwordController.text;
    if (ssid.isEmpty || username.isEmpty || password.isEmpty) {
      showAppSnackBar(context, 'Enter campus SSID, Student ID, and password');
      return;
    }
    setState(() {
      _saving = true;
    });
    await CaptiveLoginStore.instance.save(
      ssid: ssid,
      username: username,
      password: password,
    );
    final suggestionStatus = await _registerWifiSuggestion(notify: false);
    if (!mounted) return;
    setState(() {
      _saving = false;
    });
    showAppSnackBar(
      context,
      suggestionStatus == 'success' || suggestionStatus == 'duplicate'
          ? 'Saved securely and Android Wi-Fi suggestion enabled'
          : 'Credentials saved securely',
    );
  }

  Future<void> _clearCredentials() async {
    await CaptiveLoginStore.instance.clear();
    final removeStatus = await AndroidNetworkAssist.removeAllWifiSuggestions();
    if (!mounted) return;
    _usernameController.clear();
    _passwordController.clear();
    _ssidController.text = CaptiveLoginStore.defaultCampusSsid;
    if (removeStatus == 'success' ||
        removeStatus == 'unsupported' ||
        removeStatus == 'unsupported-platform') {
      showAppSnackBar(context, 'Saved credentials cleared');
      return;
    }
    showAppSnackBar(
      context,
      'Credentials cleared (Wi-Fi suggestion remove: $removeStatus)',
    );
  }

  Future<String> _registerWifiSuggestion({bool notify = true}) async {
    final hasPerm = await _ensureWifiSuggestionPermissions();
    if (!hasPerm) {
      if (mounted && notify) {
        showAppSnackBar(
          context,
          'Permissions denied. Allow Nearby Wi-Fi and Location first.',
        );
      }
      return 'permission-required';
    }
    final ssid = _ssidController.text.trim();
    if (ssid.isEmpty) return 'invalid';
    final securityType = _inferSecurityType(ssid);
    final status = await AndroidNetworkAssist.addWifiSuggestion(
      ssid: ssid,
      password: '',
      securityType: securityType,
    );
    if (!mounted || !notify) return status;
    if (status == 'success' || status == 'duplicate') {
      showAppSnackBar(context, 'Campus Wi-Fi suggestion is active');
      return status;
    }
    if (status == 'permission-required') {
      showAppSnackBar(
        context,
        'Android denied Wi-Fi suggestion. Enable Nearby Wi-Fi and Location.',
      );
      return status;
    }
    showAppSnackBar(context, 'Wi-Fi suggestion status: $status');
    return status;
  }

  String _inferSecurityType(String ssid) {
    if (ssid.trim().toLowerCase() == 'student-wifi') {
      return 'owe';
    }
    return 'open';
  }

  Future<bool> _ensureWifiSuggestionPermissions() async {
    if (!AndroidNetworkAssist.isSupported) return true;
    final status = await AndroidNetworkAssist.getNetworkStatus();
    final api = status?.androidApi ?? 0;
    if (api >= 33) {
      final nearbyOk = await _requestPermissionWithUx(
        permission: Permission.nearbyWifiDevices,
        title: 'Nearby Wi-Fi Permission',
        rationale:
            'PreConnect needs Nearby Wi-Fi access to register Student-WiFi suggestions.',
      );
      if (!nearbyOk) return false;

      final locationOk = await _requestPermissionWithUx(
        permission: Permission.locationWhenInUse,
        title: 'Location Permission',
        rationale:
            'Android requires location permission for Wi-Fi suggestion and captive portal handoff.',
      );
      return locationOk;
    }
    return _requestPermissionWithUx(
      permission: Permission.locationWhenInUse,
      title: 'Location Permission',
      rationale:
          'Android requires location permission for Wi-Fi suggestion and captive portal handoff.',
    );
  }

  Future<bool> _requestPermissionWithUx({
    required Permission permission,
    required String title,
    required String rationale,
  }) async {
    var current = await permission.status;
    if (current.isGranted || current.isLimited) return true;

    current = await permission.request();
    if (current.isGranted || current.isLimited) return true;

    if (current.isPermanentlyDenied || current.isRestricted) {
      await openAppSettings();
      if (mounted) {
        showAppSnackBar(
          context,
          '$title required. Enable it in app settings and try again.',
        );
      }
      return false;
    }
    if (mounted) {
      showAppSnackBar(context, '$title denied. $rationale');
    }
    return false;
  }

  Future<void> _checkPostConnectionEvent() async {
    if (!AndroidNetworkAssist.isSupported) return;
    final event = await AndroidNetworkAssist.getAndClearPostConnectionEvent();
    final pending = event['pending'] == true;
    if (!pending || !mounted) return;
    final eventSsid = (event['ssid'] as String? ?? '').trim();
    final savedSsid = _ssidController.text.trim();
    if (eventSsid.isNotEmpty &&
        savedSsid.isNotEmpty &&
        eventSsid.toLowerCase() != savedSsid.toLowerCase()) {
      return;
    }
    unawaited(_openPortal(silentIfMissingCredentials: true));
  }

  Future<void> _openPortal({bool silentIfMissingCredentials = false}) async {
    if (_usernameController.text.trim().isEmpty ||
        _passwordController.text.isEmpty) {
      if (!silentIfMissingCredentials) {
        showAppSnackBar(context, 'Save credentials first');
      }
      return;
    }

    final controller = _controller;
    if (controller != null) {
      // Session reuse path: load probe inside app WebView first so existing
      // portal cookies can bypass login when still valid.
      setState(() {
        _showPortal = true;
      });
      await controller.loadRequest(Uri.parse(_probeUrl));
      return;
    }

    final openedSystem = await AndroidNetworkAssist.openCaptivePortal();
    if (!openedSystem && mounted) {
      showAppSnackBar(context, 'Unable to open captive login helper');
    }
  }

  Future<void> _tryAutofill(String url) async {
    final controller = _controller;
    if (controller == null) return;
    final username = _usernameController.text.trim();
    final password = _passwordController.text;
    if (username.isEmpty || password.isEmpty) return;

    final script =
        '''
(() => {
  const username = ${_jsString(username)};
  const password = ${_jsString(password)};
  const lower = (s) => (s || '').toLowerCase();
  const pickUser = () => {
    const candidates = Array.from(document.querySelectorAll('input[type="text"],input[type="email"],input:not([type])'));
    const ranked = candidates.filter((el) => {
      const hint = lower(el.name) + ' ' + lower(el.id) + ' ' + lower(el.placeholder) + ' ' + lower(el.autocomplete);
      return hint.includes('user') || hint.includes('id') || hint.includes('student') || hint.includes('email') || hint.includes('roll');
    });
    return ranked[0] || candidates[0] || null;
  };
  const user = pickUser();
  const pass = document.querySelector('input[type="password"]');
  if (!user || !pass) return 'missing-fields';
  user.focus();
  user.value = username;
  user.dispatchEvent(new Event('input', { bubbles: true }));
  user.dispatchEvent(new Event('change', { bubbles: true }));
  pass.focus();
  pass.value = password;
  pass.dispatchEvent(new Event('input', { bubbles: true }));
  pass.dispatchEvent(new Event('change', { bubbles: true }));
  if (${_autoSubmit ? 'true' : 'false'}) {
    const submit = pass.form?.querySelector('button[type="submit"],input[type="submit"]')
      || document.querySelector('button[type="submit"],input[type="submit"]');
    if (submit) {
      submit.click();
      return 'submitted';
    }
    if (pass.form) {
      pass.form.submit();
      return 'submitted';
    }
  }
  return 'filled';
})();
''';

    final result = await controller.runJavaScriptReturningResult(script);
    if (!mounted) return;
    final raw = result.toString().replaceAll('"', '');
    if (url.contains('generate_204')) {
      if (raw == 'missing-fields') {
        showAppSnackBar(context, 'Session active: no login needed right now');
      }
      return;
    }
  }

  String _jsString(String value) {
    final escaped = value
        .replaceAll(r'\', r'\\')
        .replaceAll("'", r"\'")
        .replaceAll('\n', r'\n')
        .replaceAll('\r', r'\r');
    return "'$escaped'";
  }

  @override
  Widget build(BuildContext context) {
    return BracuPageScaffold(
      title: 'Campus Wi-Fi Login',
      subtitle: 'One-tap Captive Helper',
      icon: Icons.wifi_rounded,
      body: BracuRefreshList(
        onRefresh: _loadStoredCredentials,
        children: [
          BracuCard(
            child: Column(
              children: [
                TextField(
                  controller: _ssidController,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                    labelText: 'Campus SSID',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _usernameController,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                    labelText: 'Student ID',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _passwordController,
                  obscureText: _obscurePassword,
                  decoration: InputDecoration(
                    labelText: 'Portal Password',
                    border: OutlineInputBorder(),
                    suffixIcon: IconButton(
                      onPressed: () {
                        setState(() {
                          _obscurePassword = !_obscurePassword;
                        });
                      },
                      icon: Icon(
                        _obscurePassword
                            ? Icons.visibility_off_outlined
                            : Icons.visibility_outlined,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _saving ? null : _saveCredentials,
                        child: Text(_saving ? 'Saving...' : 'Save'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _clearCredentials,
                        child: const Text('Clear'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () {
                          unawaited(_registerWifiSuggestion());
                        },
                        icon: const Icon(Icons.wifi_tethering_rounded),
                        label: const Text('Register Android Wi-Fi Suggestion'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                SwitchListTile(
                  value: _autoSubmit,
                  onChanged: (value) {
                    setState(() {
                      _autoSubmit = value;
                    });
                  },
                  title: const Text('Auto-submit form'),
                  subtitle: const Text(
                    'Turn off if portal changes unexpectedly',
                  ),
                  contentPadding: EdgeInsets.zero,
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: kIsWeb ? null : _openPortal,
                        icon: const Icon(Icons.login_rounded),
                        label: const Text('One-Tap Wi-Fi Login'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          if (_showPortal && !kIsWeb && _controller != null)
            SizedBox(
              height: 520,
              child: BracuCard(
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: WebViewWidget(controller: _controller!),
                      ),
                    ),
                    if (_loading)
                      Positioned.fill(
                        child: Container(
                          color: Colors.black.withValues(alpha: 0.06),
                          alignment: Alignment.topCenter,
                          child: const LinearProgressIndicator(minHeight: 2),
                        ),
                      ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _ssidController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }
}
