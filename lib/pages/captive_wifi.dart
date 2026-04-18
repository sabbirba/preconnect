import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:preconnect/pages/ui_kit.dart';
import 'package:preconnect/api/profile_service.dart';
import 'package:preconnect/tools/android_network_assist.dart';
import 'package:preconnect/tools/captive_wifi_http_service.dart';
import 'package:preconnect/tools/token_storage.dart';
import 'package:preconnect/tools/app_storage.dart';

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
  Timer? _autoSessionTimer;
  Timer? _liveSessionTimer;
  DateTime? _lastAutoExtendAt;
  int? _liveRemainingSeconds;
  String _studentId = '';

  @override
  void initState() {
    super.initState();
    _loadStoredCredentials();
  }

  Future<void> _loadStoredCredentials() async {
    final autoExtendEnabled = await CaptiveLoginStore.instance
        .readAutoExtendEnabled();
    final creds = await CaptiveLoginStore.instance.read();
    var studentId = (await AppStorage.instance.getString('studentId') ?? '')
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
      return _requestPermissionWithUx(permission: Permission.locationWhenInUse);
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
      _showLocalSnackBar('Student ID missing in app cache or password empty.');
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
    final status = _statusFromNetwork(networkStatus);
    if (status == null) {
      if (showSuccessSnackBar) {
        _showLocalSnackBar(
          'Captive Wi-Fi session data unavailable on current network.',
        );
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
      if (!mounted) return;
      setState(() {
        _sessionStatus = status;
        _liveRemainingSeconds = status.secondsRemaining;
      });
      _restartLiveSessionTicker();
      if (allowAutoExtend) {
        await _maybeAutoExtend(status);
      }
      if (showSuccessSnackBar) {
        _showLocalSnackBar('Session status updated.');
      }
    } catch (_) {
      if (!mounted) return;
      if (showErrorSnackBar) {
        _showLocalSnackBar('Unable to read captive Wi-Fi session status.');
      }
    } finally {
      if (mounted) {
        setState(() {
          _isCheckingSession = false;
        });
      }
    }
  }

  CaptiveWifiApiStatus? _statusFromNetwork(AndroidNetworkStatus? status) {
    if (status == null) return null;
    final parsedUrl = _currentPortalUriFromStatus(status);
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

  Uri? _validatedHttpUri(String raw) {
    if (raw.isEmpty) return null;
    final uri = Uri.tryParse(raw);
    if (uri == null || !uri.hasScheme || !uri.hasAuthority) return null;
    if (uri.scheme != 'http' && uri.scheme != 'https') return null;
    return uri;
  }

  Future<void> _openExtendSession(CaptiveWifiApiStatus status) async {
    if (!status.canExtendSession || status.sessionUrl == null) return;
    try {
      await CaptiveWifiHttpService.instance.requestSessionExtension(
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
      await CaptiveWifiHttpService.instance.requestSessionExtension(
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

    return BracuCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.timer_outlined, size: 18),
              const SizedBox(width: 8),
              Text(
                'Captive Wi-Fi Session',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: textPrimary,
                ),
              ),
              const Spacer(),
              if (_isCheckingSession)
                const BracuShimmer(
                  child: BracuSkeletonBox(width: 14, height: 14, radius: 7),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Remaining: $remainingLabel',
            style: TextStyle(fontSize: 13, color: textPrimary),
          ),
          const SizedBox(height: 2),
          Text(
            canExtend
                ? 'Session can be extended from Captive Wi-Fi.'
                : 'Session extension is not available.',
            style: TextStyle(fontSize: 12, color: textSecondary),
          ),
          if (expired) ...[
            const SizedBox(height: 6),
            Text(
              'Session has expired. Re-login or extend to continue internet access.',
              style: TextStyle(fontSize: 12, color: textSecondary),
            ),
          ],
          if (showExtend) ...[
            const SizedBox(height: 10),
            SizedBox(
              height: 34,
              child: ElevatedButton.icon(
                onPressed: _isCheckingSession
                    ? null
                    : () => unawaited(_openExtendSession(status!)),
                icon: const Icon(Icons.open_in_new_rounded, size: 16),
                label: const Text('Extend Session'),
              ),
            ),
          ],
        ],
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

  Future<bool> _loginViaCaptiveApi({
    required String studentId,
    required String password,
  }) async {
    final httpService = CaptiveWifiHttpService.instance;
    final captiveWifiUrl = await _currentCaptiveWifiApiUri();
    if (captiveWifiUrl == null) {
      return false;
    }
    final client = httpService.newClient();
    final cookies = <String, Cookie>{};

    try {
      final first = await httpService.getWithRedirects(
        client: client,
        uri: captiveWifiUrl,
        cookies: cookies,
      );
      if (first.statusCode == 204) {
        return true;
      }

      final form = _extractLoginForm(html: first.body, pageUri: first.uri);
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
    return _currentPortalUriFromStatus(status);
  }

  Uri? _currentPortalUriFromStatus(AndroidNetworkStatus status) {
    final parsedUrl = _validatedHttpUri(status.captiveWifiUrl?.trim() ?? '');
    if (parsedUrl != null) {
      return parsedUrl;
    }
    if (status.transport == 'wifi' && status.captive) {
      return CaptiveWifiHttpService.defaultProbeUri;
    }
    return null;
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
              BracuCard(
                child: Column(
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
                            autofillHints: const <String>[
                              AutofillHints.password,
                            ],
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
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: (_isCheckingSession || _isConnecting)
                            ? null
                            : () => unawaited(_refreshSessionStatus()),
                        icon: const Icon(Icons.refresh_rounded, size: 18),
                        label: Text(
                          _isCheckingSession
                              ? 'Checking...'
                              : 'Check Session Time',
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Auto Extend Session'),
                      subtitle: Text(
                        'Extend when time is <= ${_autoExtendThresholdSeconds}s',
                      ),
                      value: _autoExtendEnabled,
                      onChanged: _setAutoExtendEnabled,
                      activeThumbColor: BracuPalette.primary,
                    ),
                  ],
                ),
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
