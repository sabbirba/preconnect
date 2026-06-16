import 'dart:async';

import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:preconnect/pages/ui_kit.dart';
import 'package:preconnect/api/profile.dart';
import 'package:preconnect/tools/network_assist.dart';
import 'package:preconnect/tools/wifi_http.dart';
import 'package:preconnect/tools/token_storage.dart';
import 'package:preconnect/tools/app_storage.dart';
import 'package:preconnect/tools/storage_keys.dart';

class CaptiveWifiPage extends StatefulWidget {
  const CaptiveWifiPage({super.key, this.autoOpenCaptiveWifiOnStart = false});

  final bool autoOpenCaptiveWifiOnStart;

  @override
  State<CaptiveWifiPage> createState() => _CaptiveWifiPageState();
}

class _CaptiveWifiPageState extends State<CaptiveWifiPage> {
  static const Duration _apiLoginTimeout = Duration(seconds: 45);
  static const Duration _wifiAssociationTimeout = Duration(seconds: 30);
  static const Duration _wifiAssociationPollInterval = Duration(
    milliseconds: 600,
  );

  final TextEditingController _ssidController = TextEditingController(
    text: CaptiveLoginStore.defaultCampusSsid,
  );
  final TextEditingController _passwordController = TextEditingController();
  final GlobalKey<ScaffoldMessengerState> _pageMessengerKey =
      GlobalKey<ScaffoldMessengerState>();

  bool _isConnecting = false;
  bool _autoExtendEnabled = true;
  bool _obscurePassword = true;
  StreamSubscription<AndroidNetworkStatus>? _networkStatusSubscription;
  String _studentId = '';

  @override
  void initState() {
    super.initState();
    if (AndroidNetworkAssist.isSupported) {
      _networkStatusSubscription = AndroidNetworkAssist.statusStream.listen(
        _handleNetworkStatusChanged,
      );
    }
    _loadStoredCredentials();
  }

  Future<void> _loadStoredCredentials() async {
    final autoExtendEnabled = await CaptiveLoginStore.instance
        .readAutoExtendEnabled();
    final creds = await CaptiveLoginStore.instance.read();
    var studentId =
        (await AppStorage.instance.getString(StorageKeys.studentId) ?? '')
            .trim();
    if (studentId.isEmpty) {
      final profile = await ProfileService().getProfile(fromFetch: true);
      studentId = (profile?['studentId'] ?? '').trim();
    }
    if (!mounted) return;
    setState(() {
      _autoExtendEnabled = autoExtendEnabled;
      _studentId = studentId;
      if (creds != null) {
        _passwordController.text = creds.password;
      }
    });
    await _autofillSsidFromSystem();
    unawaited(_checkPostConnectionEvent());
    final status = await AndroidNetworkAssist.getNetworkStatus();
    if (status != null && status.transport == 'wifi' && status.connected) {
      final hasPassword = _passwordController.text.isNotEmpty;
      final isCaptive = status.captive || !status.validated;
      if (isCaptive && hasPassword && !_isConnecting) {
        unawaited(_runOneTapConnect());
      }
    }
    if (widget.autoOpenCaptiveWifiOnStart) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        unawaited(_runOneTapConnect());
      });
    }
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
        _studentId.isNotEmpty &&
        _passwordController.text.isNotEmpty;
  }

  Future<String> _registerWifiSuggestion() async {
    final hasPerm = await _ensureWifiSuggestionPermissions();
    if (!hasPerm) return 'permission-required';
    final ssid = _ssidController.text.trim();
    if (ssid.isEmpty) return 'invalid';
    final securityType = _inferSecurityType(ssid);
    final suggestionPassword = securityType == 'wpa2'
        ? _passwordController.text
        : '';
    return AndroidNetworkAssist.addWifiSuggestion(
      ssid: ssid,
      password: suggestionPassword,
      securityType: securityType,
    );
  }

  String _inferSecurityType(String ssid) {
    final lowered = ssid.trim().toLowerCase();
    if (lowered == 'student-wifi') {
      return 'owe';
    }
    if (lowered.contains('wpa') || lowered.contains('secure')) {
      return 'wpa2';
    }
    return 'open';
  }

  Future<void> _waitForTargetWifiAssociation() async {
    if (!AndroidNetworkAssist.isSupported) return;
    final targetSsid = _ssidController.text.trim().toLowerCase();
    if (targetSsid.isEmpty) return;

    final initialStatus = await AndroidNetworkAssist.getNetworkStatus();
    if (initialStatus != null) {
      final currentSsid = (initialStatus.ssid ?? '').trim().toLowerCase();
      if (currentSsid == targetSsid) return;
      if (initialStatus.transport == 'wifi' &&
          (initialStatus.captive || !initialStatus.validated)) {
        return;
      }
    }

    final deadline = DateTime.now().add(_wifiAssociationTimeout);
    while (DateTime.now().isBefore(deadline)) {
      final status = await AndroidNetworkAssist.getNetworkStatus();
      final currentSsid = (status?.ssid ?? '').trim().toLowerCase();
      if (currentSsid == targetSsid) {
        return;
      }
      if (status != null &&
          status.transport == 'wifi' &&
          (status.captive || !status.validated)) {
        return;
      }
      await Future<void>.delayed(_wifiAssociationPollInterval);
    }
  }

  Future<bool> _ensureWifiSuggestionPermissions() async {
    if (!AndroidNetworkAssist.isSupported) return true;
    final status = await AndroidNetworkAssist.getNetworkStatus();
    final api = status?.androidApi ?? 0;
    if (api >= 33) {
      final nearbyOk = await _requestPermissionWithUx(
        permission: Permission.nearbyWifiDevices,
      );
      return nearbyOk;
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
      _showLocalSnackBar('Password is empty.');
      return;
    }

    setState(() {
      _isConnecting = true;
    });

    try {
      final studentId = _studentId.trim();
      final password = _passwordController.text;

      await CaptiveLoginStore.instance.save(password: password);

      final suggestion = await _registerWifiSuggestion();
      if (!mounted) return;
      if (suggestion == 'permission-required' || suggestion == 'invalid') {
        _showLocalSnackBar('Wi-Fi setup skipped: $suggestion');
      }

      await _waitForTargetWifiAssociation();

      final loggedIn =
          await _loginViaCaptiveApi(
            studentId: studentId,
            password: password,
          ).timeout(
            _apiLoginTimeout,
            onTimeout: () {
              CaptiveWifiHttp.instance.lastError =
                  'Connection/API login timed out after ${_apiLoginTimeout.inSeconds} seconds.';
              return false;
            },
          );
      if (!mounted) return;
      final status = await AndroidNetworkAssist.getNetworkStatus();
      final url = status != null
          ? CaptiveWifiHttp.resolvePortalUri(status)
          : null;
      final urlStr = url != null ? url.toString() : 'unknown';

      if (loggedIn) {
        _showLocalSnackBar('Login success. Internet validated.\nURL: $urlStr');
      } else {
        final err = CaptiveWifiHttp.instance.lastError;
        if (err != null && err.isNotEmpty) {
          _showLocalSnackBar('Login failed: $err\nURL: $urlStr');
        } else {
          _showLocalSnackBar('Login failed or timed out.\nURL: $urlStr');
        }
      }
    } finally {
      if (mounted) {
        setState(() {
          _isConnecting = false;
        });
      }
    }
  }

  Future<void> _handleNetworkStatusChanged(AndroidNetworkStatus status) async {
    if (!mounted) return;
    _setSsidFromStatus(status);
    final transport = status.transport.trim().toLowerCase();
    if (transport != 'wifi' || !status.connected) {
      return;
    }
    if (_isConnecting) return;

    final hasPassword = _passwordController.text.isNotEmpty;
    final isCaptive = status.captive || !status.validated;
    if (isCaptive && hasPassword) {
      unawaited(_runOneTapConnect());
    }
  }

  void _setSsidFromStatus(AndroidNetworkStatus status) {
    final ssid = (status.ssid ?? '').trim();
    if (ssid.isEmpty) return;
    final current = _ssidController.text.trim();
    if (current == ssid) return;
    final hasCustomValue =
        current.isNotEmpty && current != CaptiveLoginStore.defaultCampusSsid;
    if (hasCustomValue) return;
    _ssidController.text = ssid;
  }

  Future<void> _setAutoExtendEnabled(bool value) async {
    await CaptiveLoginStore.instance.saveAutoExtendEnabled(value);
    if (!mounted) return;
    setState(() {
      _autoExtendEnabled = value;
    });
  }

  Future<bool> _loginViaCaptiveApi({
    required String studentId,
    required String password,
  }) async {
    final status = await AndroidNetworkAssist.getNetworkStatus();
    if (status == null) {
      CaptiveWifiHttp.instance.lastError =
          'AndroidNetworkAssist.getNetworkStatus() returned null (disconnected or missing permissions)';
      return false;
    }
    final captiveWifiUrl = CaptiveWifiHttp.resolvePortalUri(status);
    if (captiveWifiUrl == null) {
      CaptiveWifiHttp.instance.lastError =
          'Could not resolve captive portal URL from network status (transport: ${status.transport}, captive: ${status.captive}, validated: ${status.validated})';
      return false;
    }
    await AndroidNetworkAssist.bindToWifiNetwork();
    try {
      return await CaptiveWifiHttp.instance.loginViaCaptiveApi(
        studentId: studentId,
        password: password,
        captiveWifiUrl: captiveWifiUrl,
      );
    } finally {
      await AndroidNetworkAssist.unbindFromWifiNetwork();
    }
  }

  void _showLocalSnackBar(String message) {
    final messenger = _pageMessengerKey.currentState;
    if (messenger == null) return;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    messenger.clearSnackBars();
    messenger.showSnackBar(
      SnackBar(
        content: Text(message, style: const TextStyle(color: Colors.white)),
        backgroundColor: isDark
            ? const Color(0xFF1E6BE3)
            : BracuPalette.primary,
        duration: const Duration(seconds: 2),
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
      title: 'Captive Wi-Fi',
      subtitle: 'API Based Session',
      icon: Icons.wifi_rounded,
      body: ScaffoldMessenger(
        key: _pageMessengerKey,
        child: Scaffold(
          backgroundColor: Colors.transparent,
          body: BracuRefreshList(
            onRefresh: _loadStoredCredentials,
            children: [
              Column(
                children: [
                  AutofillGroup(
                    child: Column(
                      children: [
                        TextField(
                          controller: _ssidController,
                          readOnly: true,
                          enableInteractiveSelection: false,
                          decoration: const InputDecoration(
                            labelText: 'SSID',
                            border: OutlineInputBorder(),
                          ),
                        ),
                        const SizedBox(height: 10),
                        InputDecorator(
                          decoration: const InputDecoration(
                            labelText: 'Student ID',
                            border: OutlineInputBorder(),
                          ),
                          child: Text(
                            _studentId.isEmpty ? 'Not available' : _studentId,
                          ),
                        ),
                        const SizedBox(height: 10),
                        TextField(
                          controller: _passwordController,
                          obscureText: _obscurePassword,
                          autofillHints: const <String>[AutofillHints.password],
                          decoration: InputDecoration(
                            labelText: 'Password',
                            border: const OutlineInputBorder(),
                            suffixIcon: IconButton(
                              icon: Icon(
                                _obscurePassword
                                    ? Icons.visibility_off_outlined
                                    : Icons.visibility_outlined,
                                color: Theme.of(context).hintColor,
                              ),
                              onPressed: () {
                                setState(() {
                                  _obscurePassword = !_obscurePassword;
                                });
                              },
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: BracuActionButton(
                      onPressed: _isConnecting
                          ? null
                          : () => unawaited(_runOneTapConnect()),
                      label: 'Connect',
                      isLoading: _isConnecting,
                      foregroundColor: BracuPalette.primary,
                      borderRadius: 18,
                    ),
                  ),
                  const SizedBox(height: 4),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Auto Extend Session'),
                    subtitle: const Text(
                      'Automatically repost the login API every 2 hours while connected',
                    ),
                    value: _autoExtendEnabled,
                    onChanged: _setAutoExtendEnabled,
                    activeThumbColor: BracuPalette.primary,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _networkStatusSubscription?.cancel();
    _ssidController.dispose();
    _passwordController.dispose();
    super.dispose();
  }
}
