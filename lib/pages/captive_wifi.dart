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
  static const Duration _autoSessionCheckInterval = Duration(seconds: 30);
  static const Duration _autoExtendCooldown = Duration(seconds: 60);
  static const int _autoExtendThresholdSeconds = 21600;
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
  bool _isCheckingSession = false;
  bool _isAutoExtending = false;
  bool _autoExtendEnabled = true;
  StreamSubscription<AndroidNetworkStatus>? _networkStatusSubscription;
  Timer? _autoSessionTimer;
  Timer? _liveSessionTimer;
  DateTime? _lastAutoExtendAt;
  int? _liveRemainingSeconds;
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
    _restartAutoSessionMonitor();
    unawaited(
      _refreshSessionStatus(
        showSuccessSnackBar: false,
        showErrorSnackBar: false,
        allowAutoExtend: true,
      ),
    );
    unawaited(_checkPostConnectionEvent());
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
    final deadline = DateTime.now().add(_wifiAssociationTimeout);
    while (DateTime.now().isBefore(deadline)) {
      final status = await AndroidNetworkAssist.getNetworkStatus();
      final currentSsid = (status?.ssid ?? '').trim().toLowerCase();
      if (currentSsid == targetSsid) {
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

      final loggedIn = await _loginViaCaptiveApi(
        studentId: studentId,
        password: password,
      ).timeout(_apiLoginTimeout, onTimeout: () => false);
      if (!mounted) return;
      if (loggedIn) {
        _showLocalSnackBar('Login success. Internet validated.');
        await _refreshSessionStatus(showSuccessSnackBar: false);
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

  Future<void> _refreshSessionStatus({
    bool showSuccessSnackBar = true,
    bool showErrorSnackBar = true,
    bool allowAutoExtend = true,
  }) async {
    final networkStatus = await AndroidNetworkAssist.getNetworkStatus();

    final hasPassword = _passwordController.text.isNotEmpty;
    final isCaptive =
        networkStatus?.captive == true ||
        (networkStatus?.connected == true && networkStatus?.validated == false);
    if (isCaptive && hasPassword && !_isConnecting) {
      unawaited(_runOneTapConnect());
      return;
    }

    final initialStatus = _statusFromNetwork(networkStatus);
    if (initialStatus == null) {
      if (showSuccessSnackBar) {
        _showLocalSnackBar('Session data unavailable.');
      }
      return;
    }
    _restartAutoSessionMonitor();

    if (mounted) {
      setState(() {
        _isCheckingSession = true;
      });
    }
    try {
      var currentStatus = initialStatus;
      if (currentStatus.sessionUrl != null) {
        try {
          final client = await CaptiveWifiHttp.instance.newClient();
          final targetUri = currentStatus.sessionUrl!;

          CaptiveWifiHttpResult res;
          if (targetUri.path.contains('/portalpage/')) {
            final syncUri = targetUri.replace(
              path: '/portalauth/syncPortalResult',
              queryParameters: {},
            );
            res = await CaptiveWifiHttp.instance.postOnce(
              client: client,
              uri: syncUri,
              body: '',
              cookies: CaptiveWifiHttp.instance.sessionCookies,
              referer: targetUri,
            );
          } else {
            res = await CaptiveWifiHttp.instance.getWithRedirects(
              client: client,
              uri: targetUri,
              cookies: CaptiveWifiHttp.instance.sessionCookies,
            );
          }

          client.close(force: true);
          if (res.statusCode == 200) {
            final dynamic decoded = jsonDecode(res.body);
            if (decoded is Map) {
              if (targetUri.path.contains('/portalpage/')) {
                final isSuccess = decoded['success'] == true;
                final data = decoded['data'] as Map?;
                final validPeriodStr = data?['validPeriod']?.toString() ?? '0';
                final validPeriod = int.tryParse(validPeriodStr) ?? 0;
                final seconds = (isSuccess && validPeriod > 0)
                    ? validPeriod
                    : (isSuccess ? null : 0);

                currentStatus = CaptiveWifiApiStatus(
                  secondsRemaining: seconds,
                  canExtendSession: false,
                  sessionUrl: targetUri,
                );
              } else {
                final secondsRemaining =
                    decoded['seconds-remaining'] ?? decoded['secondsRemaining'];
                final canExtend =
                    decoded['can-extend-session'] ??
                    decoded['canExtendSession'];
                final userPortalUrl =
                    decoded['user-portal-url'] ?? decoded['userPortalUrl'];
                int? seconds;
                if (secondsRemaining is num) {
                  seconds = secondsRemaining.toInt();
                }
                currentStatus = CaptiveWifiApiStatus(
                  secondsRemaining: seconds ?? currentStatus.secondsRemaining,
                  canExtendSession: canExtend == true,
                  sessionUrl:
                      userPortalUrl is String && userPortalUrl.isNotEmpty
                      ? Uri.tryParse(userPortalUrl) ?? currentStatus.sessionUrl
                      : currentStatus.sessionUrl,
                );
              }
            }
          }
        } catch (_) {}
      }

      if (!mounted) return;
      setState(() {
        _liveRemainingSeconds = currentStatus.secondsRemaining;
      });
      _restartLiveSessionTicker();
      if (allowAutoExtend) {
        await _maybeAutoExtend(currentStatus);
      }
      if (showSuccessSnackBar) {
        _showLocalSnackBar('Session status updated.');
      }
    } catch (_) {
      if (!mounted) return;
      if (showErrorSnackBar) {
        _showLocalSnackBar('Unable to read session status.');
      }
    } finally {
      if (mounted) {
        setState(() {
          _isCheckingSession = false;
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
    if (_isConnecting || _isCheckingSession) return;
    unawaited(
      _refreshSessionStatus(
        showSuccessSnackBar: false,
        showErrorSnackBar: false,
        allowAutoExtend: true,
      ),
    );
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

  CaptiveWifiApiStatus? _statusFromNetwork(AndroidNetworkStatus? status) {
    if (status == null) return null;
    final parsedUrl = CaptiveWifiHttp.resolvePortalUri(status);
    if (parsedUrl == null) return null;

    final expiry = status.sessionExpiryTimeMillis;
    int? secondsRemaining;
    if (expiry != null && expiry > 0) {
      final nowMillis = DateTime.now().millisecondsSinceEpoch;
      final diff = ((expiry - nowMillis) / 1000).floor();
      secondsRemaining = diff < 0 ? 0 : diff;
    }
    return CaptiveWifiApiStatus(
      secondsRemaining: secondsRemaining,
      canExtendSession: status.canExtendSession == true,
      sessionUrl: parsedUrl,
    );
  }

  void _restartAutoSessionMonitor() {
    _autoSessionTimer?.cancel();
    if (!_autoExtendEnabled) return;
    _autoSessionTimer = Timer.periodic(_autoSessionCheckInterval, (_) {
      if (!mounted || _isCheckingSession || _isConnecting) return;
      unawaited(
        _refreshSessionStatus(
          showSuccessSnackBar: false,
          showErrorSnackBar: false,
          allowAutoExtend: true,
        ),
      );
    });
  }

  void _restartLiveSessionTicker() {
    _liveSessionTimer?.cancel();
    final seconds = _liveRemainingSeconds;
    if (seconds == null || seconds <= 0) return;
    _liveSessionTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      final current = _liveRemainingSeconds;
      if (current == null || current <= 0) {
        _liveSessionTimer?.cancel();
        return;
      }
      setState(() {
        _liveRemainingSeconds = current - 1;
      });
    });
  }

  Future<void> _setAutoExtendEnabled(bool value) async {
    await CaptiveLoginStore.instance.saveAutoExtendEnabled(value);
    if (!mounted) return;
    setState(() {
      _autoExtendEnabled = value;
    });
    _restartAutoSessionMonitor();
    if (value) {
      unawaited(
        _refreshSessionStatus(
          showSuccessSnackBar: false,
          showErrorSnackBar: false,
          allowAutoExtend: true,
        ),
      );
    }
  }

  Future<void> _maybeAutoExtend(CaptiveWifiApiStatus status) async {
    if (!_autoExtendEnabled) return;
    if (_isAutoExtending) return;
    if (!status.canExtendSession || status.sessionUrl == null) return;
    final remaining = status.secondsRemaining;
    if (remaining == null) return;
    if (remaining > _autoExtendThresholdSeconds) return;

    final now = DateTime.now();
    if (_lastAutoExtendAt != null &&
        now.difference(_lastAutoExtendAt!) < _autoExtendCooldown) {
      return;
    }

    _isAutoExtending = true;
    _lastAutoExtendAt = now;
    try {
      await CaptiveWifiHttp.instance.requestSessionExtension(
        status.sessionUrl!,
      );
      if (!mounted) return;
      _showLocalSnackBar('Session extended automatically.');
      await _refreshSessionStatus(
        showSuccessSnackBar: false,
        showErrorSnackBar: false,
        allowAutoExtend: false,
      );
    } catch (_) {
      if (!mounted) return;
      _showLocalSnackBar('Auto-extend failed. Tap Extend Session manually.');
    } finally {
      _isAutoExtending = false;
    }
  }

  String _formatThresholdHours(int seconds) {
    final safeSeconds = seconds < 0 ? 0 : seconds;
    final hours = safeSeconds ~/ 3600;
    final mins = (safeSeconds % 3600) ~/ 60;
    if (mins == 0) {
      return '${hours}h';
    }
    return '${hours}h ${mins}m';
  }

  String _formatSessionTime(int seconds) {
    final safe = seconds < 0 ? 0 : seconds;
    final h = safe ~/ 3600;
    final m = (safe % 3600) ~/ 60;
    final s = safe % 60;
    if (h > 0) {
      return '${h}h ${m.toString().padLeft(2, '0')}m ${s.toString().padLeft(2, '0')}s';
    }
    return '${m}m ${s.toString().padLeft(2, '0')}s';
  }

  Future<bool> _loginViaCaptiveApi({
    required String studentId,
    required String password,
  }) async {
    final captiveWifiUrl = await _currentCaptiveWifiApiUri();
    if (captiveWifiUrl == null) return false;
    return CaptiveWifiHttp.instance.loginViaCaptiveApi(
      studentId: studentId,
      password: password,
      captiveWifiUrl: captiveWifiUrl,
    );
  }

  Future<Uri?> _currentCaptiveWifiApiUri() async {
    if (!AndroidNetworkAssist.isSupported) return null;
    final status = await AndroidNetworkAssist.getNetworkStatus();
    if (status == null) return null;
    return CaptiveWifiHttp.resolvePortalUri(status);
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
                          obscureText: true,
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
                  if (_liveRemainingSeconds != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(
                        children: [
                          const Icon(Icons.timer_outlined, size: 18),
                          const SizedBox(width: 6),
                          Text(
                            'Session time: ${_formatSessionTime(_liveRemainingSeconds!)}',
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                        ],
                      ),
                    ),
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
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: BracuActionButton(
                      onPressed: (_isCheckingSession || _isConnecting)
                          ? null
                          : () => unawaited(_refreshSessionStatus()),
                      label: 'Check Session Time',
                      isLoading: _isCheckingSession,
                      foregroundColor: BracuPalette.primary,
                      borderRadius: 18,
                    ),
                  ),
                  const SizedBox(height: 4),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Auto Extend Session'),
                    subtitle: Text(
                      'Extend when time is <= ${_formatThresholdHours(_autoExtendThresholdSeconds)}',
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
    _autoSessionTimer?.cancel();
    _liveSessionTimer?.cancel();
    _ssidController.dispose();
    _passwordController.dispose();
    super.dispose();
  }
}

class CaptiveWifiApiStatus {
  const CaptiveWifiApiStatus({
    required this.secondsRemaining,
    required this.canExtendSession,
    required this.sessionUrl,
  });

  final int? secondsRemaining;
  final bool canExtendSession;
  final Uri? sessionUrl;
}
