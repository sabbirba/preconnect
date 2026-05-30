import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:preconnect/pages/ui_kit.dart';
import 'package:preconnect/api/profile.dart';
import 'package:preconnect/tools/android_network_assist.dart';
import 'package:preconnect/tools/captive_wifi_http.dart';
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
  static const Duration _apiLoginTimeout = Duration(seconds: 18);
  static const Duration _autoSessionCheckInterval = Duration(seconds: 30);
  static const Duration _autoExtendCooldown = Duration(seconds: 60);
  static const int _autoExtendThresholdSeconds = 21600;
  static const Duration _wifiAssociationTimeout = Duration(seconds: 12);
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
  CaptiveWifiApiStatus? _sessionStatus;
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
          final res = await CaptiveWifiHttp.instance.getWithRedirects(
            client: client,
            uri: currentStatus.sessionUrl!,
            cookies: const {},
          );
          client.close(force: true);
          if (res.statusCode == 200) {
            final dynamic decoded = jsonDecode(res.body);
            if (decoded is Map) {
              final secondsRemaining = decoded['seconds-remaining'] ?? decoded['secondsRemaining'];
              final canExtend = decoded['can-extend-session'] ?? decoded['canExtendSession'];
              final userPortalUrl = decoded['user-portal-url'] ?? decoded['userPortalUrl'];
              int? seconds;
              if (secondsRemaining is num) {
                seconds = secondsRemaining.toInt();
              }
              currentStatus = CaptiveWifiApiStatus(
                secondsRemaining: seconds ?? currentStatus.secondsRemaining,
                canExtendSession: canExtend == true,
                sessionUrl: userPortalUrl is String && userPortalUrl.isNotEmpty
                    ? Uri.tryParse(userPortalUrl) ?? currentStatus.sessionUrl
                    : currentStatus.sessionUrl,
              );
            }
          }
        } catch (_) {}
      }

      if (!mounted) return;
      setState(() {
        _sessionStatus = currentStatus;
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

  Future<void> _openExtendSession(CaptiveWifiApiStatus status) async {
    if (!status.canExtendSession || status.sessionUrl == null) return;
    try {
      await CaptiveWifiHttp.instance.requestSessionExtension(
        status.sessionUrl!,
      );
      if (!mounted) return;
      _showLocalSnackBar('Session extended.');
      await _refreshSessionStatus(
        showSuccessSnackBar: false,
        showErrorSnackBar: false,
        allowAutoExtend: false,
      );
    } catch (_) {
      if (!mounted) return;
      _showLocalSnackBar('Session extend failed.');
    }
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

  Widget _sessionInfoCard(BuildContext context) {
    final status = _sessionStatus;
    if (status == null && !_isCheckingSession) {
      return const SizedBox.shrink();
    }
    final textPrimary = BracuPalette.textPrimary(context);
    final textSecondary = BracuPalette.textSecondary(context);
    final expiresIn = _liveRemainingSeconds ?? status?.secondsRemaining;
    final expired = expiresIn != null && expiresIn <= 0;
    final canExtend = status?.canExtendSession == true;
    final showExtend = canExtend && status?.sessionUrl != null;
    final remainingLabel = expiresIn == null
        ? 'Unknown'
        : expiresIn <= 0
        ? 'Expired'
        : _formatSeconds(expiresIn);

    final statusColor = expired
        ? BracuPalette.danger
        : (expiresIn != null && expiresIn < 600)
            ? BracuPalette.warning
            : BracuPalette.accent;

    final statusIcon = expired
        ? Icons.error_outline_rounded
        : (expiresIn != null && expiresIn < 600)
            ? Icons.warning_amber_rounded
            : Icons.wifi_tethering_rounded;

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: statusColor.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(statusIcon, color: statusColor, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Captive Wi-Fi Session',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: textPrimary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        expired ? 'Session expired' : 'Session active',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: statusColor,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Remaining Time',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: textSecondary,
                  ),
                ),
                Text(
                  remainingLabel,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: textPrimary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    canExtend
                        ? 'Session can be extended.'
                        : 'Session extension not available.',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: textSecondary,
                    ),
                  ),
                ),
              ],
            ),
            if (expired) ...[
              const SizedBox(height: 12),
              Text(
                'Please re-login or extend the session to continue using Wi-Fi.',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: textSecondary,
                ),
              ),
            ],
            if (showExtend) ...[
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                height: 38,
                child: BracuActionButton(
                  onPressed: _isCheckingSession
                      ? null
                      : () => unawaited(_openExtendSession(status!)),
                  icon: Icons.open_in_new_rounded,
                  label: 'Extend Session',
                  foregroundColor: statusColor,
                  borderRadius: 12,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _formatSeconds(int seconds) {
    final safeSeconds = seconds < 0 ? 0 : seconds;
    final hours = safeSeconds ~/ 3600;
    final mins = (safeSeconds % 3600) ~/ 60;
    final secs = safeSeconds % 60;
    if (hours > 0) {
      return '${hours}h ${mins}m ${secs}s';
    }
    if (mins > 0) {
      return '${mins}m ${secs}s';
    }
    return '${secs}s';
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

  Future<bool> _loginViaCaptiveApi({
    required String studentId,
    required String password,
  }) async {
    final httpService = CaptiveWifiHttp.instance;
    final captiveWifiUrl = await _currentCaptiveWifiApiUri();
    if (captiveWifiUrl == null) {
      return false;
    }
    final client = await httpService.newClient();
    final cookies = <String, Cookie>{};

    try {
      var first = await httpService.getWithRedirects(
        client: client,
        uri: captiveWifiUrl,
        cookies: cookies,
      );
      if (first.statusCode == 204) {
        return true;
      }

      var loginUri = first.uri;
      var htmlBody = first.body;
      try {
        final dynamic decoded = jsonDecode(first.body);
        if (decoded is Map) {
          final userPortalUrl = decoded['user-portal-url'] ?? decoded['userPortalUrl'];
          if (userPortalUrl is String && userPortalUrl.isNotEmpty) {
            loginUri = Uri.parse(userPortalUrl);
            final second = await httpService.getWithRedirects(
              client: client,
              uri: loginUri,
              cookies: cookies,
            );
            htmlBody = second.body;
            loginUri = second.uri;
          }
        }
      } catch (_) {}

      final form = _extractLoginForm(html: htmlBody, pageUri: loginUri);
      if (form == null) {
        return false;
      }

      final payload = <String, String>{
        ...form.hiddenFields,
        form.studentIdField: studentId,
        form.passwordField: password,
      };

      final encoded = Uri(queryParameters: payload).query;
      final response = await httpService.postOnce(
        client: client,
        uri: form.action,
        body: encoded,
        cookies: cookies,
      );

      if (response.location != null) {
        final redirected = response.location!.isAbsolute
            ? response.location!
            : form.action.resolveUri(response.location!);
        await httpService.getWithRedirects(
          client: client,
          uri: redirected,
          cookies: cookies,
        );
      }

      return await httpService.isValidatedViaProbe(
        client: client,
        cookies: cookies,
      );
    } catch (_) {
      return false;
    } finally {
      client.close(force: true);
    }
  }

  Future<Uri?> _currentCaptiveWifiApiUri() async {
    if (!AndroidNetworkAssist.isSupported) return null;
    final status = await AndroidNetworkAssist.getNetworkStatus();
    if (status == null) return null;
    return CaptiveWifiHttp.resolvePortalUri(status);
  }

  _CaptiveWifiForm? _extractLoginForm({
    required String html,
    required Uri pageUri,
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
      String? studentIdField;
      var studentIdScore = -1;
      final hidden = <String, String>{};

      for (final input in inputs) {
        final tag = input.group(0) ?? '';
        final name = _attrValue(tag, 'name')?.trim();
        if (name == null || name.isEmpty) continue;

        final type = (_attrValue(tag, 'type') ?? 'text').trim().toLowerCase();
        final id = (_attrValue(tag, 'id') ?? '').toLowerCase();
        final placeholder = (_attrValue(tag, 'placeholder') ?? '')
            .toLowerCase();
        final autocomplete = (_attrValue(tag, 'autocomplete') ?? '')
            .toLowerCase();
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
        final looksId =
            hint.contains('id') ||
            hint.contains('student') ||
            hint.contains('roll');
        if (!looksId) continue;
        if (hint.contains('student')) score += 60;
        if (hint.contains('id')) score += 30;
        if (hint.contains('roll')) score += 20;

        if (score > studentIdScore) {
          studentIdScore = score;
          studentIdField = name;
        }
      }

      if (studentIdField != null && passwordField != null) {
        return _CaptiveWifiForm(
          action: action,
          studentIdField: studentIdField,
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
        backgroundColor: isDark
            ? const Color(0xFF1E6BE3)
            : BracuPalette.primary,
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
              const SizedBox(height: 10),
              _sessionInfoCard(context),
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

class _CaptiveWifiForm {
  const _CaptiveWifiForm({
    required this.action,
    required this.studentIdField,
    required this.passwordField,
    required this.hiddenFields,
  });

  final Uri action;
  final String studentIdField;
  final String passwordField;
  final Map<String, String> hiddenFields;
}
