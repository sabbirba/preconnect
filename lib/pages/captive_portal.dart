import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:preconnect/pages/ui_kit.dart';
import 'package:preconnect/tools/android_network_assist.dart';
import 'package:preconnect/tools/captive_login_store.dart';
import 'package:preconnect/tools/user_agent.dart';

class CaptivePortalPage extends StatefulWidget {
  const CaptivePortalPage({super.key, this.autoOpenPortalOnStart = false});

  final bool autoOpenPortalOnStart;

  @override
  State<CaptivePortalPage> createState() => _CaptivePortalPageState();
}

class _CaptivePortalPageState extends State<CaptivePortalPage> {
  static final Uri _probeUri = Uri.parse(
    'http://connectivitycheck.gstatic.com/generate_204',
  );
  static const Duration _passwordRevealDuration = Duration(milliseconds: 900);
  static const Duration _apiLoginTimeout = Duration(seconds: 18);

  final TextEditingController _ssidController = TextEditingController(
    text: CaptiveLoginStore.defaultCampusSsid,
  );
  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final FocusNode _passwordFocusNode = FocusNode();
  final GlobalKey<ScaffoldMessengerState> _pageMessengerKey =
      GlobalKey<ScaffoldMessengerState>();

  bool _showPasswordWhileTyping = false;
  bool _isConnecting = false;
  Timer? _passwordRevealTimer;

  @override
  void initState() {
    super.initState();
    _passwordFocusNode.addListener(() {
      if (!_passwordFocusNode.hasFocus) _hidePasswordReveal();
    });
    _loadStoredCredentials();
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
    }
    await _autofillSsidFromSystem();
    unawaited(_checkPostConnectionEvent());
    if (widget.autoOpenPortalOnStart) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        unawaited(_runOneTapConnect());
      });
    }
  }

  void _hidePasswordReveal() {
    _passwordRevealTimer?.cancel();
    if (!_showPasswordWhileTyping || !mounted) return;
    setState(() {
      _showPasswordWhileTyping = false;
    });
  }

  void _showPasswordTemporarily() {
    _passwordRevealTimer?.cancel();
    if (!_showPasswordWhileTyping && mounted) {
      setState(() {
        _showPasswordWhileTyping = true;
      });
    }
    _passwordRevealTimer = Timer(_passwordRevealDuration, _hidePasswordReveal);
  }

  Future<void> _autofillSsidFromSystem({bool force = false}) async {
    if (!AndroidNetworkAssist.isSupported) return;
    final status = await AndroidNetworkAssist.getNetworkStatus();
    if (!mounted) return;
    final ssid = (status?.ssid ?? '').trim();
    if (ssid.isEmpty) return;
    final current = _ssidController.text.trim();
    final hasCustomValue =
        current.isNotEmpty && current != CaptiveLoginStore.defaultCampusSsid;
    if (!force && hasCustomValue) return;
    if (current == ssid) return;
    setState(() {
      _ssidController.text = ssid;
    });
  }

  bool _validateRequiredInputs() {
    return _ssidController.text.trim().isNotEmpty &&
        _usernameController.text.trim().isNotEmpty &&
        _passwordController.text.isNotEmpty;
  }

  Future<String> _registerWifiSuggestion() async {
    final hasPerm = await _ensureWifiSuggestionPermissions();
    if (!hasPerm) return 'permission-required';
    final ssid = _ssidController.text.trim();
    if (ssid.isEmpty) return 'invalid';
    final securityType = _inferSecurityType(ssid);
    return AndroidNetworkAssist.addWifiSuggestion(
      ssid: ssid,
      password: '',
      securityType: securityType,
    );
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
      );
      if (!nearbyOk) return false;
      return _requestPermissionWithUx(
        permission: Permission.locationWhenInUse,
      );
    }
    return _requestPermissionWithUx(permission: Permission.locationWhenInUse);
  }

  Future<bool> _requestPermissionWithUx({
    required Permission permission,
  }) async {
    var current = await permission.status;
    if (current.isGranted || current.isLimited) return true;

    current = await permission.request();
    if (current.isGranted || current.isLimited) return true;

    if (current.isPermanentlyDenied || current.isRestricted) {
      await openAppSettings();
      return false;
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
    unawaited(_runOneTapConnect());
  }

  Future<void> _runOneTapConnect() async {
    if (!mounted || _isConnecting) return;
    if (!_validateRequiredInputs()) {
      _showLocalSnackBar('Fill SSID, ID/Email and Password.');
      return;
    }

    setState(() {
      _isConnecting = true;
    });

    try {
      final ssid = _ssidController.text.trim();
      final username = _usernameController.text.trim();
      final password = _passwordController.text;

      await CaptiveLoginStore.instance.save(
        ssid: ssid,
        username: username,
        password: password,
      );

      final suggestion = await _registerWifiSuggestion();
      if (!mounted) return;
      if (suggestion == 'permission-required' || suggestion == 'invalid') {
        _showLocalSnackBar('Wi-Fi setup failed: $suggestion');
        return;
      }

      final loggedIn = await _loginViaCaptiveApi(
        username: username,
        password: password,
      ).timeout(_apiLoginTimeout, onTimeout: () => false);
      if (!mounted) return;
      if (loggedIn) {
        _showLocalSnackBar('Login success. Internet validated.');
      } else {
        _showLocalSnackBar('Login failed or timed out.');
      }
    } finally {
      if (mounted) {
        setState(() {
          _isConnecting = false;
        });
      }
    }
  }

  Future<bool> _loginViaCaptiveApi({
    required String username,
    required String password,
  }) async {
    final client = HttpClient()..userAgent = kPreconnectUserAgent;
    client.connectionTimeout = const Duration(seconds: 10);
    final cookies = <String, Cookie>{};

    try {
      final first = await _getWithRedirects(client, _probeUri, cookies);
      if (first.statusCode == 204) {
        return true;
      }

      final form = _extractLoginForm(
        html: first.body,
        pageUri: first.uri,
        username: username,
      );
      if (form == null) {
        return false;
      }

      final payload = <String, String>{
        ...form.hiddenFields,
        form.usernameField: username,
        form.passwordField: password,
      };

      final encoded = Uri(queryParameters: payload).query;
      final response = await _postOnce(
        client,
        form.action,
        encoded,
        cookies,
      );

      if (response.location != null) {
        final redirected = response.location!.isAbsolute
            ? response.location!
            : form.action.resolveUri(response.location!);
        await _getWithRedirects(client, redirected, cookies);
      }

      final verify = await _getWithRedirects(client, _probeUri, cookies);
      return verify.statusCode == 204;
    } catch (_) {
      return false;
    } finally {
      client.close(force: true);
    }
  }

  Future<_HttpResult> _getWithRedirects(
    HttpClient client,
    Uri uri,
    Map<String, Cookie> cookies,
  ) async {
    var current = uri;
    for (var i = 0; i < 8; i++) {
      final request = await client.getUrl(current);
      request.followRedirects = false;
      final cookieHeader = _cookieHeader(cookies);
      if (cookieHeader != null) {
        request.headers.set(HttpHeaders.cookieHeader, cookieHeader);
      }
      final response = await request.close();
      _captureCookies(response, cookies);

      final status = response.statusCode;
      final location = response.headers.value(HttpHeaders.locationHeader);
      final body = await response.transform(utf8.decoder).join();

      if (status >= 300 && status < 400 && location != null) {
        current = Uri.parse(location).isAbsolute
            ? Uri.parse(location)
            : current.resolve(location);
        continue;
      }

      return _HttpResult(
        statusCode: status,
        uri: current,
        body: body,
        location: location == null ? null : Uri.parse(location),
      );
    }
    return _HttpResult(statusCode: 0, uri: current, body: '', location: null);
  }

  Future<_HttpResult> _postOnce(
    HttpClient client,
    Uri uri,
    String body,
    Map<String, Cookie> cookies,
  ) async {
    final request = await client.postUrl(uri);
    request.followRedirects = false;
    request.headers.set(
      HttpHeaders.contentTypeHeader,
      'application/x-www-form-urlencoded',
    );
    final cookieHeader = _cookieHeader(cookies);
    if (cookieHeader != null) {
      request.headers.set(HttpHeaders.cookieHeader, cookieHeader);
    }
    request.write(body);
    final response = await request.close();
    _captureCookies(response, cookies);
    final location = response.headers.value(HttpHeaders.locationHeader);
    final text = await response.transform(utf8.decoder).join();

    return _HttpResult(
      statusCode: response.statusCode,
      uri: uri,
      body: text,
      location: location == null ? null : Uri.parse(location),
    );
  }

  void _captureCookies(
    HttpClientResponse response,
    Map<String, Cookie> jar,
  ) {
    for (final cookie in response.cookies) {
      jar[cookie.name] = cookie;
    }
  }

  String? _cookieHeader(Map<String, Cookie> jar) {
    if (jar.isEmpty) return null;
    return jar.values.map((c) => '${c.name}=${c.value}').join('; ');
  }

  _PortalForm? _extractLoginForm({
    required String html,
    required Uri pageUri,
    required String username,
  }) {
    if (html.trim().isEmpty) return null;

    final formRe = RegExp(
      r'<form\b([^>]*)>(.*?)</form>',
      caseSensitive: false,
      dotAll: true,
    );
    final forms = formRe.allMatches(html).toList();
    if (forms.isEmpty) return null;

    for (final match in forms) {
      final attrs = match.group(1) ?? '';
      final body = match.group(2) ?? '';
      final actionRaw = _attrValue(attrs, 'action')?.trim();
      final action = (actionRaw == null || actionRaw.isEmpty)
          ? pageUri
          : pageUri.resolve(actionRaw);

      final inputs = RegExp(
        r'<input\b[^>]*>',
        caseSensitive: false,
        dotAll: true,
      ).allMatches(body).toList();
      String? passwordField;
      String? usernameField;
      var usernameScore = -1;
      final hidden = <String, String>{};

      for (final input in inputs) {
        final tag = input.group(0) ?? '';
        final name = _attrValue(tag, 'name')?.trim();
        if (name == null || name.isEmpty) continue;

        final type = (_attrValue(tag, 'type') ?? 'text').trim().toLowerCase();
        final id = (_attrValue(tag, 'id') ?? '').toLowerCase();
        final placeholder = (_attrValue(tag, 'placeholder') ?? '').toLowerCase();
        final autocomplete = (_attrValue(tag, 'autocomplete') ?? '').toLowerCase();
        final hint = '$name $id $placeholder $autocomplete'.toLowerCase();

        if (type == 'hidden') {
          hidden[name] = _attrValue(tag, 'value') ?? '';
          continue;
        }

        if (type == 'password') {
          passwordField = name;
          continue;
        }

        var score = 0;
        final wantsEmail = username.contains('@');
        final looksEmail = hint.contains('email') || hint.contains('mail') || type == 'email';
        final looksId = hint.contains('id') || hint.contains('student') || hint.contains('roll');
        final looksUser = hint.contains('user') || hint.contains('username') || hint.contains('login');

        if (wantsEmail) {
          if (looksEmail) score += 100;
          if (looksUser) score += 25;
          if (looksId) score += 10;
        } else {
          if (looksId) score += 100;
          if (looksUser) score += 50;
          if (looksEmail) score += 10;
        }

        if (score > usernameScore) {
          usernameScore = score;
          usernameField = name;
        }
      }

      if (usernameField != null && passwordField != null) {
        return _PortalForm(
          action: action,
          usernameField: usernameField,
          passwordField: passwordField,
          hiddenFields: hidden,
        );
      }
    }

    return null;
  }

  String? _attrValue(String source, String name) {
    final re = RegExp("$name\\s*=\\s*([\"'])(.*?)\\1", caseSensitive: false);
    final m = re.firstMatch(source);
    if (m != null) return m.group(2);

    final unquoted = RegExp('$name\\s*=\\s*([^\\s>]+)', caseSensitive: false);
    final um = unquoted.firstMatch(source);
    return um?.group(1);
  }

  void _showLocalSnackBar(String message) {
    final messenger = _pageMessengerKey.currentState;
    if (messenger == null) return;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    messenger.clearSnackBars();
    messenger.showSnackBar(
      SnackBar(
        content: Text(message, style: const TextStyle(color: Colors.white)),
        backgroundColor: isDark ? const Color(0xFF1E6BE3) : BracuPalette.primary,
        duration: const Duration(seconds: 3),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        action: SnackBarAction(
          label: 'Close',
          textColor: Colors.white,
          onPressed: () {
            messenger.hideCurrentSnackBar();
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return BracuPageScaffold(
      title: 'Captive Portal',
      subtitle: 'API Auto Login',
      icon: Icons.wifi_rounded,
      body: ScaffoldMessenger(
        key: _pageMessengerKey,
        child: Scaffold(
          backgroundColor: Colors.transparent,
          body: BracuRefreshList(
            onRefresh: _loadStoredCredentials,
            children: [
              BracuCard(
                child: Column(
                  children: [
                    AutofillGroup(
                      child: Column(
                        children: [
                          TextField(
                            controller: _ssidController,
                            textInputAction: TextInputAction.next,
                            decoration: const InputDecoration(
                              labelText: 'SSID',
                              border: OutlineInputBorder(),
                            ),
                          ),
                          const SizedBox(height: 10),
                          TextField(
                            controller: _usernameController,
                            textInputAction: TextInputAction.next,
                            autofillHints: const <String>[
                              AutofillHints.username,
                              AutofillHints.email,
                            ],
                            decoration: const InputDecoration(
                              labelText: 'ID or Email',
                              border: OutlineInputBorder(),
                            ),
                          ),
                          const SizedBox(height: 10),
                          TextField(
                            controller: _passwordController,
                            focusNode: _passwordFocusNode,
                            onChanged: (_) => _showPasswordTemporarily(),
                            obscureText: !_showPasswordWhileTyping,
                            autofillHints: const <String>[AutofillHints.password],
                            decoration: const InputDecoration(
                              labelText: 'Password',
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: _isConnecting
                            ? null
                            : () => unawaited(_runOneTapConnect()),
                        child: Text(
                          _isConnecting ? 'Connecting...' : 'One Tap Connect',
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _hidePasswordReveal();
    _ssidController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    _passwordFocusNode.dispose();
    super.dispose();
  }
}

class _HttpResult {
  const _HttpResult({
    required this.statusCode,
    required this.uri,
    required this.body,
    required this.location,
  });

  final int statusCode;
  final Uri uri;
  final String body;
  final Uri? location;
}

class _PortalForm {
  const _PortalForm({
    required this.action,
    required this.usernameField,
    required this.passwordField,
    required this.hiddenFields,
  });

  final Uri action;
  final String usernameField;
  final String passwordField;
  final Map<String, String> hiddenFields;
}
