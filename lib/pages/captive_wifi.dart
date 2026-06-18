import 'dart:async';
import 'dart:convert';

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
  bool _isDisconnecting = false;
  bool _autoExtendEnabled = true;
  bool _obscurePassword = true;
  StreamSubscription<AndroidNetworkStatus>? _networkStatusSubscription;
  String _studentId = '';
  Map<String, String>? _extractedParams;
  String _responseLog = '';
  AndroidNetworkStatus? _currentStatus;

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
    final responseLog = await AppStorage.instance.getString(StorageKeys.wifiCaptiveLastResponseLog) ?? '';
    if (!mounted) return;
    setState(() {
      _autoExtendEnabled = autoExtendEnabled;
      _studentId = studentId;
      _responseLog = responseLog;
      if (creds != null) {
        _passwordController.text = creds.password;
      }
    });
    await _autofillSsidFromSystem();
    unawaited(_checkPostConnectionEvent());
    final status = await AndroidNetworkAssist.getNetworkStatus();
    if (mounted) {
      setState(() {
        _currentStatus = status;
      });
    }
    if (status != null) {
      final captiveWifiUrl = CaptiveWifiHttp.resolvePortalUri(status);
      if (captiveWifiUrl != null && mounted) {
        setState(() {
          _extractedParams = captiveWifiUrl.queryParameters;
        });
      }
      if (status.transport == 'wifi' && status.connected) {
        final hasPassword = _passwordController.text.isNotEmpty;
        final isCaptive = status.captive || !status.validated;
        if (isCaptive && hasPassword && !_isConnecting) {
          unawaited(_runOneTapConnect());
        }
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
    debugPrint('[CaptiveWifiUI] _runOneTapConnect triggered');
    if (!mounted || _isConnecting) {
      debugPrint('[CaptiveWifiUI] _runOneTapConnect aborted: mounted=$mounted, _isConnecting=$_isConnecting');
      return;
    }
    if (!_validateRequiredInputs()) {
      debugPrint('[CaptiveWifiUI] _runOneTapConnect validation failed: SSID=${_ssidController.text}, StudentID=$_studentId, PasswordLength=${_passwordController.text.length}');
      _showLocalSnackBar('Required credentials or SSID are missing.');
      return;
    }

    setState(() {
      _isConnecting = true;
    });

    try {
      final studentId = _studentId.trim();
      final password = _passwordController.text;

      debugPrint('[CaptiveWifiUI] Saving credentials password...');
      await CaptiveLoginStore.instance.save(password: password);

      debugPrint('[CaptiveWifiUI] Registering WiFi suggestion...');
      final suggestion = await _registerWifiSuggestion();
      debugPrint('[CaptiveWifiUI] WiFi suggestion result: $suggestion');
      if (!mounted) return;
      if (suggestion == 'permission-required' || suggestion == 'invalid') {
        _showLocalSnackBar('Wi-Fi setup skipped: $suggestion');
      }

      debugPrint('[CaptiveWifiUI] Waiting for association with target SSID...');
      await _waitForTargetWifiAssociation();

      debugPrint('[CaptiveWifiUI] Triggering loginViaCaptiveApi...');
      final loggedIn =
          await _loginViaCaptiveApi(
            studentId: studentId,
            password: password,
          ).timeout(
            _apiLoginTimeout,
            onTimeout: () {
              debugPrint('[CaptiveWifiUI] loginViaCaptiveApi timed out after ${_apiLoginTimeout.inSeconds} seconds');
              CaptiveWifiHttp.instance.lastError =
                  'Connection/API login timed out after ${_apiLoginTimeout.inSeconds} seconds.';
              return false;
            },
          );
      debugPrint('[CaptiveWifiUI] loginViaCaptiveApi returned: $loggedIn');
      if (!mounted) return;
      if (loggedIn) {
        _showLocalSnackBar('Login success. Internet validated.');
        unawaited(AndroidNetworkAssist.reportCaptivePortalDismissed());
      } else {
        final err = CaptiveWifiHttp.instance.lastError;
        debugPrint('[CaptiveWifiUI] Login failed with error: $err');
        _showLocalSnackBar(_toFriendlyError(err));
      }
    } catch (e, stack) {
      debugPrint('[CaptiveWifiUI] Exception in _runOneTapConnect: $e\n$stack');
      _showLocalSnackBar('Exception: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isConnecting = false;
          _responseLog = CaptiveWifiHttp.instance.lastResponseLog;
        });
        unawaited(AppStorage.instance.setString(StorageKeys.wifiCaptiveLastResponseLog, _responseLog));
      }
    }
  }

  Future<void> _savePassword() async {
    final password = _passwordController.text;
    if (password.isEmpty) {
      _showLocalSnackBar('Password is empty.');
      return;
    }
    await CaptiveLoginStore.instance.save(password: password);
    _showLocalSnackBar('Password saved successfully.');
  }

  Future<void> _runDisconnect() async {
    debugPrint('[CaptiveWifiUI] _runDisconnect triggered');
    if (!mounted || _isDisconnecting) {
      debugPrint('[CaptiveWifiUI] _runDisconnect aborted: mounted=$mounted, _isDisconnecting=$_isDisconnecting');
      return;
    }

    setState(() {
      _isDisconnecting = true;
    });

    try {
      debugPrint('[CaptiveWifiUI] Fetching network status for disconnect...');
      final status = await AndroidNetworkAssist.getNetworkStatus();
      if (status == null) {
        debugPrint('[CaptiveWifiUI] Network status is null. Cannot disconnect.');
        _showLocalSnackBar('Not connected to Wi-Fi.');
        return;
      }
      debugPrint('[CaptiveWifiUI] Network status: connected=${status.connected}, transport=${status.transport}, ssid=${status.ssid}');
      final captiveWifiUrl = CaptiveWifiHttp.resolvePortalUri(status);
      debugPrint('[CaptiveWifiUI] Resolved portal URI: $captiveWifiUrl');
      if (captiveWifiUrl == null) {
        _showLocalSnackBar('Could not resolve captive portal URL.');
        return;
      }

      debugPrint('[CaptiveWifiUI] Binding to Wi-Fi network...');
      await AndroidNetworkAssist.bindToWifiNetwork();
      bool loggedOut = false;
      try {
        debugPrint('[CaptiveWifiUI] Triggering logoutViaCaptiveApi...');
        loggedOut = await CaptiveWifiHttp.instance.logoutViaCaptiveApi(
          captiveWifiUrl: captiveWifiUrl,
        );
      } finally {
        debugPrint('[CaptiveWifiUI] Unbinding from Wi-Fi network...');
        await AndroidNetworkAssist.unbindFromWifiNetwork();
      }

      debugPrint('[CaptiveWifiUI] logoutViaCaptiveApi returned: $loggedOut');
      if (!mounted) return;
      if (loggedOut) {
        _showLocalSnackBar('Disconnected from portal successfully.');
      } else {
        final err = CaptiveWifiHttp.instance.lastError;
        debugPrint('[CaptiveWifiUI] Logout failed with error: $err');
        _showLocalSnackBar(_toFriendlyDisconnectError(err));
      }
    } catch (e, stack) {
      debugPrint('[CaptiveWifiUI] Exception in _runDisconnect: $e\n$stack');
      if (mounted) {
        _showLocalSnackBar(_toFriendlyDisconnectError(e.toString()));
      }
    } finally {
      if (mounted) {
        setState(() {
          _isDisconnecting = false;
          _responseLog = CaptiveWifiHttp.instance.lastResponseLog;
        });
        unawaited(AppStorage.instance.setString(StorageKeys.wifiCaptiveLastResponseLog, _responseLog));
      }
    }
  }

  Future<void> _handleNetworkStatusChanged(AndroidNetworkStatus status) async {
    if (!mounted) return;
    setState(() {
      _currentStatus = status;
    });
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
      CaptiveWifiHttp.instance.lastError = 'disconnected';
      return false;
    }
    final captiveWifiUrl = CaptiveWifiHttp.resolvePortalUri(status);
    if (captiveWifiUrl == null) {
      CaptiveWifiHttp.instance.lastError = 'socketexception';
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
    final bool isCorrectSsid = !AndroidNetworkAssist.isSupported ||
        (_currentStatus != null &&
            _currentStatus!.connected &&
            _currentStatus!.transport == 'wifi' &&
            _currentStatus!.ssid?.trim().toLowerCase() == _ssidController.text.trim().toLowerCase());

    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) {
          unawaited(AndroidNetworkAssist.ignoreNetwork());
        }
      },
      child: BracuPageScaffold(
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
                        InputDecorator(
                          decoration: const InputDecoration(
                            labelText: 'SSID',
                            border: OutlineInputBorder(),
                          ),
                          child: Text(
                            _ssidController.text.isEmpty
                                ? 'Not available'
                                : _ssidController.text,
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
                  if (AndroidNetworkAssist.isSupported && !isCorrectSsid) ...[
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      decoration: BoxDecoration(
                        color: Colors.transparent,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.amber.withValues(alpha: 0.4)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.warning_amber_rounded, color: Colors.amber, size: 20),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'Please connect to ${_ssidController.text} to manage connection.',
                              style: const TextStyle(
                                fontSize: 13,
                                color: Colors.amber,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: BracuActionButton(
                          onPressed: _isConnecting || _isDisconnecting
                              ? null
                              : () => unawaited(_savePassword()),
                          label: 'Save',
                          foregroundColor: Colors.grey,
                          borderRadius: 18,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: BracuActionButton(
                          onPressed: _isConnecting || _isDisconnecting || !isCorrectSsid
                              ? null
                              : () => unawaited(_runOneTapConnect()),
                          label: 'Connect',
                          isLoading: _isConnecting,
                          foregroundColor: BracuPalette.primary,
                          borderRadius: 18,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: BracuActionButton(
                      onPressed: _isConnecting || _isDisconnecting || !isCorrectSsid
                          ? null
                          : () => unawaited(_runDisconnect()),
                      label: 'Disconnect',
                      isLoading: _isDisconnecting,
                      foregroundColor: Colors.redAccent,
                      borderRadius: 18,
                    ),
                  ),
                  const SizedBox(height: 4),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Auto Extend Session'),
                    value: _autoExtendEnabled,
                    onChanged: _setAutoExtendEnabled,
                    activeThumbColor: BracuPalette.primary,
                  ),
                  if (_extractedParams != null && _extractedParams!.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    _buildPortalParamsCard(context),
                  ],
                  if (_responseLog.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    _buildGatewayResponsesCard(context),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    ),
    );
  }

  List<Map<String, String>> _parseResponseLog(String log) {
    final sections = <Map<String, String>>[];
    final blocks = log.split('--- ');
    for (final block in blocks) {
      if (block.trim().isEmpty) continue;
      final lines = block.split('\n');
      final header = lines[0].replaceAll(' ---', '').trim();
      var status = '';
      var body = '';
      for (var i = 1; i < lines.length; i++) {
        final line = lines[i].trim();
        if (line.startsWith('Status:')) {
          status = line.replaceFirst('Status:', '').trim();
        } else if (line.startsWith('Body:')) {
          body = lines.sublist(i).join('\n').replaceFirst('Body:', '').trim();
          break;
        }
      }
      sections.add({
        'title': header,
        'status': status,
        'body': body,
      });
    }
    return sections;
  }

  String _tryPrettyPrintJson(String rawBody) {
    try {
      final dynamic decoded = jsonDecode(rawBody);
      final pretty = const JsonEncoder.withIndent('  ').convert(decoded);
      return pretty;
    } catch (_) {
      return rawBody;
    }
  }

  String _toFriendlyError(String? err) {
    if (err == null || err.isEmpty) return 'An unknown error occurred.';
    final lower = err.toLowerCase();
    if (lower.contains('incorrect student id') || lower.contains('password')) {
      return 'Incorrect Student ID or password.';
    }
    if (lower.contains('locked')) {
      return 'Account is locked. Please try again later.';
    }
    if (lower.contains('expired')) {
      return 'Your password has expired.';
    }
    if (lower.contains('exceeded the limit') || lower.contains('limit reached')) {
      return 'Terminal limit reached. Disconnect another device.';
    }
    if (lower.contains('socketexception') || lower.contains('connection refused') || lower.contains('unreachable')) {
      return 'Cannot reach the campus network. Make sure you are connected to Student-WiFi.';
    }
    if (lower.contains('time out') || lower.contains('timeout')) {
      return 'The connection request timed out. Please try again.';
    }
    if (lower.contains('probe to generate_204 failed') || lower.contains('still captive')) {
      return 'Logged in, but no internet access detected.';
    }
    if (lower.contains('http status')) {
      return 'Portal server returned an error. Please try again.';
    }
    return 'Unable to connect to Wi-Fi portal.';
  }

  String _toFriendlyDisconnectError(String? err) {
    if (err == null || err.isEmpty) return 'An unknown error occurred.';
    final lower = err.toLowerCase();
    if (lower.contains('socketexception') || lower.contains('unreachable')) {
      return 'Cannot reach the campus network.';
    }
    if (lower.contains('time out') || lower.contains('timeout')) {
      return 'The request timed out.';
    }
    return 'Failed to disconnect from Wi-Fi portal.';
  }

  Widget _buildPortalParamsCard(BuildContext context) {
    if (_extractedParams == null || _extractedParams!.isEmpty) {
      return const SizedBox.shrink();
    }
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final borderColor = BracuPalette.textSecondary(context)
        .withValues(alpha: isDark ? 0.35 : 0.18);

    final parameterLabels = {
      'pushPageId': 'Page Transaction ID',
      'apmac': 'Access Point MAC',
      'uaddress': 'Client IP Address',
      'umac': 'Client MAC Address',
      'ssid': 'SSID',
      'authType': 'Authentication Type',
    };

    final rows = _extractedParams!.entries.map((entry) {
      final label = parameterLabels[entry.key] ?? entry.key;
      return (label: label, value: entry.value);
    }).toList();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: BracuPalette.card(context),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: borderColor),
        boxShadow: isDark
            ? const []
            : [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.06),
                  blurRadius: 16,
                  offset: const Offset(0, 8),
                ),
              ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.info_outline, size: 18, color: BracuPalette.primary),
              const SizedBox(width: 8),
              Text(
                'Captured Portal Parameters',
                style: TextStyle(
                  color: BracuPalette.textPrimary(context),
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          for (var i = 0; i < rows.length; i++) ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 5,
                  child: Text(
                    rows[i].label,
                    style: TextStyle(
                      color: BracuPalette.textSecondary(context),
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  flex: 6,
                  child: Text(
                    rows[i].value,
                    textAlign: TextAlign.right,
                    style: TextStyle(
                      color: BracuPalette.textPrimary(context),
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      fontFamily: 'monospace',
                    ),
                  ),
                ),
              ],
            ),
            if (i != rows.length - 1)
              Divider(
                height: 18,
                thickness: 1,
                color: BracuPalette.textSecondary(context)
                    .withValues(alpha: isDark ? 0.22 : 0.14),
              ),
          ],
        ],
      ),
    );
  }

  Widget _buildGatewayResponsesCard(BuildContext context) {
    if (_responseLog.isEmpty) {
      return const SizedBox.shrink();
    }
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final borderColor = BracuPalette.textSecondary(context)
        .withValues(alpha: isDark ? 0.35 : 0.18);
    final sections = _parseResponseLog(_responseLog);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: BracuPalette.card(context),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: borderColor),
        boxShadow: isDark
            ? const []
            : [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.06),
                  blurRadius: 16,
                  offset: const Offset(0, 8),
                ),
              ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.history_edu, size: 18, color: BracuPalette.primary),
              const SizedBox(width: 8),
              Text(
                'Last Gateway Responses',
                style: TextStyle(
                  color: BracuPalette.textPrimary(context),
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          for (var i = 0; i < sections.length; i++) ...[
            _buildResponseSection(context, sections[i], isDark),
            if (i != sections.length - 1)
              const SizedBox(height: 16),
          ],
        ],
      ),
    );
  }

  Widget _buildResponseSection(BuildContext context, Map<String, String> section, bool isDark) {
    final title = section['title'] ?? '';
    final status = section['status'] ?? '';
    final body = section['body'] ?? '';
    final statusCode = int.tryParse(status) ?? 0;
    final isError = statusCode == 0 || statusCode >= 400;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              title,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 13,
                color: BracuPalette.primary,
              ),
            ),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: isError
                    ? Colors.red.withValues(alpha: 0.1)
                    : Colors.green.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                'Status $status',
                style: TextStyle(
                  color: isError ? Colors.redAccent : Colors.green,
                  fontWeight: FontWeight.bold,
                  fontSize: 11,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: isDark ? Colors.black26 : Colors.grey.shade100,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: Theme.of(context).dividerColor.withValues(alpha: 0.05),
            ),
          ),
          child: Text(
            _tryPrettyPrintJson(body),
            style: const TextStyle(
              fontFamily: 'monospace',
              fontSize: 11,
            ),
          ),
        ),
      ],
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
