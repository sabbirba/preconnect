import 'dart:async';

import 'package:flutter/material.dart';
import 'package:gap/gap.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:preconnect/pages/ui_kit.dart';
import 'package:preconnect/api/profile.dart';
import 'package:preconnect/tools/network_assist.dart';
import 'package:preconnect/tools/wifi_http.dart';
import 'package:preconnect/tools/token_storage.dart';
import 'package:preconnect/tools/app_storage.dart';
import 'package:preconnect/tools/storage_keys.dart';
import 'package:preconnect/tools/polling_timer.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:preconnect/libsync/flow_stub.dart'
    if (dart.library.js_interop) 'package:preconnect/libsync/flow_web.dart';

class CaptiveWifiPage extends StatefulWidget {
  const CaptiveWifiPage({super.key, this.autoOpenCaptiveWifiOnStart = false});

  final bool autoOpenCaptiveWifiOnStart;

  @override
  State<CaptiveWifiPage> createState() => _CaptiveWifiPageState();
}

class _CaptiveWifiPageState extends State<CaptiveWifiPage> {
  static const Duration _apiLoginTimeout = Duration(seconds: 45);
  final TextEditingController _passwordController = TextEditingController();
  final GlobalKey<ScaffoldMessengerState> _pageMessengerKey =
      GlobalKey<ScaffoldMessengerState>();

  bool _isConnecting = false;
  bool _isDisconnecting = false;
  bool _autoExtendEnabled = true;
  bool _obscurePassword = true;
  bool _scanning = false;
  StreamSubscription<AndroidNetworkStatus>? _networkStatusSubscription;
  PollingTimer? _iosProbeTimer;
  Timer? _heartbeatTimer;
  String? _lastObservedApMac;
  Uri? _detectedPortalUri;
  bool _isOnCampusNetwork = false;
  final TextEditingController _studentIdController = TextEditingController();
  Map<String, String>? _extractedParams;
  AndroidNetworkStatus? _currentStatus;
  String? _rawResponseLog;

  @override
  void initState() {
    super.initState();
    if (identical(openCaptivePortalFlow, null)) {
      assert(true);
    }
    _studentIdController.addListener(_handleStudentIdChanged);
    _passwordController.addListener(_handlePasswordChanged);
    if (AndroidNetworkAssist.isSupported) {
      _networkStatusSubscription = AndroidNetworkAssist.statusStream.listen(
        _handleNetworkStatusChanged,
      );
    } else {
      _startIosProbeTimer();
    }
    _loadStoredCredentials();
  }

  void _handlePasswordChanged() {
    if (mounted) setState(() {});
  }

  void _startIosProbeTimer() {
    _iosProbeTimer?.cancel();
    _iosProbeTimer = PollingTimer(const Duration(seconds: 10), (_) async {
      if (!mounted || _isConnecting || _isDisconnecting) return;
      final onCampus = await CaptiveWifiHttp.checkIfOnCampusNetwork();
      final portalUri = await CaptiveWifiHttp.detectCaptivePortal();
      if (mounted) {
        setState(() {
          _isOnCampusNetwork = onCampus;
          _detectedPortalUri = portalUri;
        });
        if (portalUri != null) {
          final hasPassword = _passwordController.text.isNotEmpty;
          if (hasPassword && !_isConnecting) {
            unawaited(_runOneTapConnect());
          }
        }
      }
    });
  }

  void _handleStudentIdChanged() {
    final value = _studentIdController.text.trim();
    AppStorage.instance.setString(StorageKeys.studentId, value);
  }

  Future<void> _loadStoredCredentials() async {
    if (!mounted) return;
    setState(() {
      _scanning = true;
    });
    try {
      final autoExtendEnabled = await CaptiveLoginStore.instance
          .readAutoExtendEnabled();
      final creds = await CaptiveLoginStore.instance.read();
      final validPeriod = await CaptiveLoginStore.instance.readValidPeriod();
      final remainTime = await CaptiveLoginStore.instance.readRemainTime();
      var studentId =
          (await AppStorage.instance.getString(StorageKeys.studentId) ?? '')
              .trim();
      if (studentId.isEmpty) {
        final profile = await ProfileService().getProfile(fromFetch: true);
        studentId = (profile?['studentId'] ?? '').trim();
      }
      if (!mounted) return;
      _studentIdController.text = studentId;
      setState(() {
        _autoExtendEnabled = autoExtendEnabled;
        if (creds != null) {
          _passwordController.text = creds.password;
        }
        if (validPeriod != null || remainTime != null) {
          _extractedParams = {
            ...?_extractedParams,
            if (validPeriod != null && validPeriod.isNotEmpty)
              'validPeriod': validPeriod,
            if (remainTime != null && remainTime.isNotEmpty)
              'remainTime': remainTime,
          };
        }
      });
      unawaited(_checkPostConnectionEvent());

      if (IosNetworkAssist.isSupported) {
        final onCampus = await CaptiveWifiHttp.checkIfOnCampusNetwork();
        final portalUri = await CaptiveWifiHttp.detectCaptivePortal();
        if (mounted) {
          setState(() {
            _isOnCampusNetwork = onCampus;
            _detectedPortalUri = portalUri;
          });
        }
        if (portalUri != null &&
            (widget.autoOpenCaptiveWifiOnStart ||
                (_passwordController.text.isNotEmpty && !_isConnecting))) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            unawaited(_runOneTapConnect());
          });
        }
      } else {
        final status =
            await CaptiveWifiHttp.retryOperation<AndroidNetworkStatus>(
              () async {
                final st = await AndroidNetworkAssist.getNetworkStatus();
                if (st != null && mounted) {
                  setState(() => _currentStatus = st);
                  final captiveWifiUrl = CaptiveWifiHttp.resolvePortalUri(st);
                  if (captiveWifiUrl != null &&
                      captiveWifiUrl != CaptiveWifiHttp.defaultProbeUri) {
                    setState(
                      () => _extractedParams = captiveWifiUrl.queryParameters,
                    );
                  }
                }
                return st;
              },
              isSuccess: (st) => st != null && (!st.captive && st.validated),
            );

        if (status != null) {
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
    } finally {
      if (mounted) {
        setState(() {
          _scanning = false;
        });
      }
    }
  }

  bool _validateRequiredInputs() {
    return _studentIdController.text.trim().isNotEmpty &&
        _passwordController.text.isNotEmpty;
  }

  Future<String> _registerWifiSuggestion() async {
    final hasPerm = await _ensureWifiSuggestionPermissions();
    if (!hasPerm) return 'permission-required';
    return AndroidNetworkAssist.addWifiSuggestion(
      ssid: CaptiveLoginStore.defaultCampusSsid,
      password: '',
      securityType: 'owe',
    );
  }

  Future<void> _waitForTargetWifiAssociation() async {
    if (!AndroidNetworkAssist.isSupported) return;
    final targetSsid = CaptiveLoginStore.defaultCampusSsid.toLowerCase();

    final status = await AndroidNetworkAssist.getNetworkStatus();
    if (status != null) {
      final currentSsid = (status.ssid ?? '').trim().toLowerCase();
      if (currentSsid == targetSsid) {
        return;
      }
      if (status.transport == 'wifi' && (status.captive || !status.validated)) {
        return;
      }
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
    return true;
  }

  Future<bool> _requestPermissionWithUx({
    required Permission permission,
  }) async {
    final current = await permission.status;
    if (current.isGranted || current.isLimited) return true;

    final requested = await permission.request();
    return requested.isGranted || requested.isLimited;
  }

  Future<void> _checkPostConnectionEvent() async {
    if (!AndroidNetworkAssist.isSupported) return;
    final event = await AndroidNetworkAssist.getAndClearPostConnectionEvent();
    final pending = event['pending'] == true;
    if (!pending || !mounted) return;
    final eventSsid = (event['ssid'] as String? ?? '').trim();
    if (eventSsid.isNotEmpty &&
        eventSsid.toLowerCase() !=
            CaptiveLoginStore.defaultCampusSsid.toLowerCase()) {
      return;
    }
    unawaited(_runOneTapConnect());
  }

  Future<void> _runOneTapConnect({bool isManual = false}) async {
    if (!mounted || _isConnecting) {
      return;
    }

    if (!_validateRequiredInputs()) {
      _showLocalSnackBar('Please enter your Student ID and Password.');
      return;
    }

    setState(() {
      _isConnecting = true;
    });

    try {
      final studentId = _studentIdController.text.trim();
      final password = _passwordController.text;

      await CaptiveLoginStore.instance.save(password: password);

      final suggestion = await _registerWifiSuggestion();

      if (!mounted) return;
      if (suggestion == 'permission-required' || suggestion == 'invalid') {
        _showLocalSnackBar('Wi-Fi setup skipped: $suggestion');
      }

      await _waitForTargetWifiAssociation();

      var loggedIn = false;
      while (_isConnecting && !loggedIn && mounted) {
        loggedIn =
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

        if (loggedIn) break;

        if (CaptiveWifiHttp.instance.isLastFatal) {
          break;
        }

        if (!_isConnecting || !mounted) break;
        await Future<void>.delayed(const Duration(seconds: 1));
      }

      if (!mounted) return;
      setState(() {
        _rawResponseLog = CaptiveWifiHttp.instance.lastResponseLog.isNotEmpty
            ? CaptiveWifiHttp.instance.lastResponseLog
            : (CaptiveWifiHttp.instance.lastError ?? 'No response received.');
      });
      if (loggedIn) {
        final validPeriod = await CaptiveLoginStore.instance.readValidPeriod();
        final remainTime = await CaptiveLoginStore.instance.readRemainTime();
        if (mounted) {
          setState(() {
            _isOnCampusNetwork = true;
            _detectedPortalUri = null;
            if (validPeriod != null || remainTime != null) {
              _extractedParams = {
                ...?_extractedParams,
                if (validPeriod != null && validPeriod.isNotEmpty)
                  'validPeriod': validPeriod,
                if (remainTime != null && remainTime.isNotEmpty)
                  'remainTime': remainTime,
              };
            }
          });
        }
        unawaited(AndroidNetworkAssist.reportCaptivePortalDismissed());
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _rawResponseLog = 'Exception: $e';
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isConnecting = false;
        });
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
    if (_isConnecting) {
      setState(() {
        _isConnecting = false;
      });
      return;
    }
    if (!mounted || _isDisconnecting) {
      return;
    }

    setState(() {
      _isDisconnecting = true;
    });

    try {
      final status = await AndroidNetworkAssist.getNetworkStatus();
      if (status == null) {
        _showLocalSnackBar('Not connected to Wi-Fi.');
        return;
      }

      final captiveWifiUrl = CaptiveWifiHttp.resolvePortalUri(status);

      if (captiveWifiUrl == null) {
        _showLocalSnackBar('Could not resolve captive portal URL.');
        return;
      }

      await AndroidNetworkAssist.bindToWifiNetwork();
      bool loggedOut = false;
      try {
        loggedOut = await CaptiveWifiHttp.instance.logoutViaCaptiveApi(
          captiveWifiUrl: captiveWifiUrl,
        );
      } finally {
        await AndroidNetworkAssist.unbindFromWifiNetwork();
      }

      if (!mounted) return;
      setState(() {
        _rawResponseLog = CaptiveWifiHttp.instance.lastResponseLog.isNotEmpty
            ? CaptiveWifiHttp.instance.lastResponseLog
            : (CaptiveWifiHttp.instance.lastError ?? 'No response received.');
      });
      if (loggedOut) {
        if (mounted) {
          setState(() {
            _isOnCampusNetwork = false;
          });
        }
        unawaited(_loadStoredCredentials());
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _rawResponseLog = 'Exception: $e';
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isDisconnecting = false;
        });
      }
    }
  }

  void _updateHeartbeatTimer({required bool isSessionActive}) {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    if (_autoExtendEnabled && isSessionActive) {
      _heartbeatTimer = Timer.periodic(const Duration(minutes: 10), (_) async {
        if (!mounted) return;
        final success = await CaptiveWifiHttp.instance.sendKeepAliveHeartbeat(
          captiveWifiUrl: _detectedPortalUri,
        );
        if (success && mounted) {
          final remainTime = await CaptiveLoginStore.instance.readRemainTime();
          setState(() {
            if (remainTime != null && remainTime.isNotEmpty) {
              _extractedParams = {
                ...?_extractedParams,
                'remainTime': remainTime,
              };
            }
          });
        }
      });
    }
  }

  Future<void> _handleNetworkStatusChanged(AndroidNetworkStatus status) async {
    if (!mounted) return;
    final apMac = status.apMac;
    final roamedAp =
        _lastObservedApMac != null &&
        apMac != null &&
        apMac != _lastObservedApMac;
    _lastObservedApMac = apMac;

    setState(() {
      _currentStatus = status;
      if (status.transport.trim().toLowerCase() != 'wifi' ||
          !status.connected) {
        _extractedParams = null;
      }
    });
    final transport = status.transport.trim().toLowerCase();
    if (transport != 'wifi' || !status.connected) {
      _updateHeartbeatTimer(isSessionActive: false);
      return;
    }

    final isSessionActive = !status.captive && status.validated;
    _updateHeartbeatTimer(isSessionActive: isSessionActive);

    if (isSessionActive && !roamedAp) {
      return;
    }
    if (_isConnecting) return;

    final hasPassword = _passwordController.text.isNotEmpty;
    final isCaptive = status.captive || !status.validated;
    if (isCaptive &&
        (status.captiveWifiUrl == null || status.captiveWifiUrl!.isEmpty)) {
      final probed = await CaptiveWifiHttp.detectCaptivePortal();
      if (probed != null && mounted) {
        setState(() {
          _detectedPortalUri = probed;
          _extractedParams = probed.queryParameters;
        });
      }
    }
    if (isCaptive && hasPassword) {
      final isOnline = await CaptiveWifiHttp.checkInternetAccess();
      if (!isOnline && mounted) {
        unawaited(_runOneTapConnect());
      }
    }
  }

  Future<void> _setAutoExtendEnabled(bool value) async {
    await CaptiveLoginStore.instance.saveAutoExtendEnabled(value);
    if (!mounted) return;
    setState(() {
      _autoExtendEnabled = value;
    });
    final isSessionActive =
        _currentStatus != null &&
        !_currentStatus!.captive &&
        _currentStatus!.validated;
    _updateHeartbeatTimer(isSessionActive: isSessionActive);
  }

  Future<bool> _loginViaCaptiveApi({
    required String studentId,
    required String password,
  }) async {
    final status = AndroidNetworkAssist.isSupported
        ? await AndroidNetworkAssist.getNetworkStatus()
        : null;
    var captiveWifiUrl = CaptiveWifiHttp.resolvePortalUri(status);
    if (captiveWifiUrl == null ||
        captiveWifiUrl == CaptiveWifiHttp.defaultProbeUri) {
      final freshlyDetected = await CaptiveWifiHttp.detectCaptivePortal();
      if (freshlyDetected != null) {
        captiveWifiUrl = freshlyDetected;
        if (mounted) {
          setState(() {
            _detectedPortalUri = freshlyDetected;
          });
        }
      }
    }
    if (captiveWifiUrl == null) {
      CaptiveWifiHttp.instance.lastError = 'socketexception';
      return false;
    }
    if (AndroidNetworkAssist.isSupported) {
      final bound = await AndroidNetworkAssist.bindToWifiNetwork();
      if (!bound) {
        CaptiveWifiHttp.instance.lastError =
            'Could not bind to the Wi-Fi network. If you also have mobile '
            'data on, the login request may go out over data instead.';
      }
    }
    try {
      return await CaptiveWifiHttp.instance.loginViaCaptiveApi(
        studentId: studentId,
        password: password,
        captiveWifiUrl: captiveWifiUrl,
      );
    } finally {
      if (AndroidNetworkAssist.isSupported) {
        await AndroidNetworkAssist.unbindFromWifiNetwork();
      }
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
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool isCorrectSsid =
        !AndroidNetworkAssist.isSupported ||
        (_currentStatus != null &&
            _currentStatus!.connected &&
            _currentStatus!.transport == 'wifi' &&
            ((_currentStatus!.ssid ?? '').isEmpty ||
                _currentStatus!.ssid!.trim().toLowerCase() ==
                    CaptiveLoginStore.defaultCampusSsid.toLowerCase()));

    final bool isBehindPortal = AndroidNetworkAssist.isSupported
        ? (isCorrectSsid &&
              _currentStatus != null &&
              (_currentStatus!.captive || !_currentStatus!.validated))
        : (_isOnCampusNetwork && _detectedPortalUri != null);

    final bool isSessionActive = AndroidNetworkAssist.isSupported
        ? (isCorrectSsid &&
              _currentStatus != null &&
              !_currentStatus!.captive &&
              _currentStatus!.validated)
        : (_isOnCampusNetwork && _detectedPortalUri == null);

    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) {
          unawaited(AndroidNetworkAssist.ignoreNetwork());
        }
      },
      child: BracuPageScaffold(
        title: 'Captive Wi-Fi',
        subtitle: _scanning ? 'Scanning..' : 'API Based Session',
        icon: Icons.wifi_rounded,
        actions: [
          IconButton(
            onPressed: () => _showHelpBottomSheet(context),
            style: bracuCompactIconButtonStyle(
              foregroundColor: BracuPalette.primary,
              borderColor: Colors.transparent,
              padding: EdgeInsets.zero,
              borderRadius: 12,
            ),
            icon: const Icon(
              Icons.help_outline_rounded,
              color: BracuPalette.primary,
            ),
            tooltip: 'Help',
          ),
        ],
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
                          TextFormField(
                            initialValue: CaptiveLoginStore.defaultCampusSsid,
                            readOnly: true,
                            style: TextStyle(
                              color: BracuPalette.textPrimary(context),
                              fontFamily: 'Outfit',
                            ),
                            decoration: bracuInputDecoration(
                              context,
                              labelText: 'SSID',
                              borderRadius: 14,
                            ),
                          ),
                          const Gap(12),
                          TextField(
                            controller: _studentIdController,
                            style: TextStyle(
                              color: BracuPalette.textPrimary(context),
                              fontFamily: 'Outfit',
                            ),
                            decoration: bracuInputDecoration(
                              context,
                              labelText: 'Student ID',
                              borderRadius: 14,
                            ),
                          ),
                          const Gap(12),
                          TextField(
                            controller: _passwordController,
                            obscureText: _obscurePassword,
                            autofillHints: const <String>[
                              AutofillHints.password,
                            ],
                            style: TextStyle(
                              color: BracuPalette.textPrimary(context),
                              fontFamily: 'Outfit',
                            ),
                            decoration: bracuInputDecoration(
                              context,
                              labelText: 'Password',
                              borderRadius: 14,
                              suffixIcon: IconButton(
                                icon: Icon(
                                  _obscurePassword
                                      ? Icons.visibility_off_outlined
                                      : Icons.visibility_outlined,
                                  color: BracuPalette.textSecondary(context),
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
                    const Gap(12),
                    Row(
                      children: [
                        Expanded(
                          child: BracuActionButton(
                            onPressed: _isConnecting || _isDisconnecting
                                ? null
                                : () => unawaited(_savePassword()),
                            icon: Icons.save_rounded,
                            label: 'Save',
                          ),
                        ),
                        if (isBehindPortal ||
                            isSessionActive ||
                            _isConnecting) ...[
                          const Gap(12),
                          Expanded(
                            child: BracuActionButton(
                              onPressed: _isDisconnecting
                                  ? null
                                  : (_isConnecting
                                        ? () => unawaited(_runDisconnect())
                                        : (isSessionActive
                                              ? () =>
                                                    unawaited(_runDisconnect())
                                              : () => unawaited(
                                                  _runOneTapConnect(
                                                    isManual: true,
                                                  ),
                                                ))),
                              icon: _isConnecting
                                  ? Icons.stop_rounded
                                  : (isSessionActive
                                        ? Icons.wifi_off_rounded
                                        : Icons.wifi_rounded),
                              label: _isConnecting
                                  ? 'Cancel'
                                  : (isSessionActive
                                        ? 'Disconnect'
                                        : 'Connect'),
                              isLoading: isSessionActive && _isDisconnecting,
                            ),
                          ),
                        ],
                      ],
                    ),
                    if (isBehindPortal) ...[
                      const Gap(12),
                      SizedBox(
                        width: double.infinity,
                        child: BracuActionButton(
                          onPressed: () async {
                            final status =
                                await AndroidNetworkAssist.getNetworkStatus();
                            Uri? url;
                            if (status != null) {
                              url = CaptiveWifiHttp.resolvePortalUri(status);
                            }
                            if (url == null ||
                                url == CaptiveWifiHttp.defaultProbeUri) {
                              url = _detectedPortalUri;
                            }
                            if (url == null ||
                                url == CaptiveWifiHttp.defaultProbeUri) {
                              final saved = await CaptiveLoginStore.instance
                                  .readLastPortalUrl();
                              if (saved != null && saved.isNotEmpty) {
                                url = Uri.tryParse(saved);
                              }
                            }
                            url ??= CaptiveWifiHttp.defaultProbeUri;
                            if (!context.mounted) return;
                            if (kIsWeb) {
                              unawaited(openCaptivePortalFlow(url.toString()));
                              return;
                            }
                            await Navigator.of(context).push(
                              MaterialPageRoute<void>(
                                builder: (context) =>
                                    CaptivePortalWebView(portalUrl: url!),
                              ),
                            );
                          },
                          icon: Icons.language_rounded,
                          label: 'Open Portal In App',
                        ),
                      ),
                    ],
                    const Gap(12),
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Auto Extend Session',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: BracuPalette.textPrimary(context),
                                ),
                              ),
                              const Gap(2),
                              Text(
                                'Automatically keep session active.',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: BracuPalette.textSecondary(context),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const Gap(12),
                        Switch(
                          value: _autoExtendEnabled,
                          onChanged: _setAutoExtendEnabled,
                          activeThumbColor: BracuPalette.primary,
                          activeTrackColor: BracuPalette.primary.withValues(
                            alpha: 0.2,
                          ),
                          inactiveThumbColor: BracuPalette.textSecondary(
                            context,
                          ),
                          inactiveTrackColor: BracuPalette.textSecondary(
                            context,
                          ).withValues(alpha: 0.1),
                        ),
                      ],
                    ),
                    if ((_extractedParams != null &&
                            _extractedParams!.isNotEmpty) ||
                        _currentStatus != null) ...[
                      const Gap(12),
                      _buildPortalParamsCard(context),
                    ],
                    if (_rawResponseLog != null) ...[
                      const Gap(12),
                      _buildRawResponseCard(context),
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

  Widget _buildRawResponseCard(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final borderColor = BracuPalette.textSecondary(
      context,
    ).withValues(alpha: isDark ? 0.35 : 0.18);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: BracuPalette.card(context),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: borderColor),
      ),
      child: SelectableText(
        _rawResponseLog ?? '',
        style: TextStyle(
          color: BracuPalette.textPrimary(context),
          fontSize: 12,
          fontFamily: 'monospace',
          height: 1.4,
        ),
      ),
    );
  }

  Widget _buildPortalParamsCard(BuildContext context) {
    final params = Map<String, String>.from(_extractedParams ?? {});
    if (_currentStatus != null) {
      if (!params.containsKey('uaddress') &&
          _currentStatus!.ipAddress != null) {
        params['uaddress'] = _currentStatus!.ipAddress!;
      }
      if (!params.containsKey('umac') && _currentStatus!.clientMac != null) {
        params['umac'] = _currentStatus!.clientMac!;
      }
      if (!params.containsKey('apmac') && _currentStatus!.apMac != null) {
        params['apmac'] = _currentStatus!.apMac!;
      }
      if (!params.containsKey('ssid') && _currentStatus!.ssid != null) {
        params['ssid'] = _currentStatus!.ssid!;
      }
      if (!params.containsKey('gatewayAddress') &&
          _currentStatus!.gatewayAddress != null) {
        params['gatewayAddress'] = _currentStatus!.gatewayAddress!;
      }
    }
    if (params.isEmpty) {
      return const SizedBox.shrink();
    }
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final borderColor = BracuPalette.textSecondary(
      context,
    ).withValues(alpha: isDark ? 0.35 : 0.18);

    final rows = params.entries
        .where((entry) => entry.key != 'redirect-url')
        .map((entry) {
          final label = entry.key;
          var val = entry.value;
          if (entry.key == 'validPeriod' ||
              entry.key == 'remainTime' ||
              entry.key == 'remainFlow') {
            if (val == '0' || val.trim().isEmpty) {
              val = 'Unlimited';
            }
          }
          return (label: label, value: val);
        })
        .toList();
    if (CaptiveWifiHttp.instance.lastRequestUrl != null &&
        CaptiveWifiHttp.instance.lastRequestUrl!.isNotEmpty) {
      rows.add((
        label: 'requestUrl',
        value: CaptiveWifiHttp.instance.lastRequestUrl!,
      ));
    }

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
                const Gap(12),
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
                color: BracuPalette.textSecondary(
                  context,
                ).withValues(alpha: isDark ? 0.22 : 0.14),
              ),
          ],
        ],
      ),
    );
  }

  @override
  void dispose() {
    _networkStatusSubscription?.cancel().catchError((_) {});
    _iosProbeTimer?.cancel();
    _heartbeatTimer?.cancel();
    _studentIdController.removeListener(_handleStudentIdChanged);
    _passwordController.removeListener(_handlePasswordChanged);
    _studentIdController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _showHelpBottomSheet(BuildContext context) {
    showBracuBottomSheet<void>(
      context,
      title: 'Captive Wi-Fi Information',
      initialChildSize: 0.65,
      builder: (sheetContext, textPrimary, textSecondary) {
        final dragController = bracuBottomSheetScrollController(sheetContext);
        return ListView(
          controller: dragController,
          physics: const ClampingScrollPhysics(),
          padding: const EdgeInsets.only(bottom: 24),
          children: [
            Text(
              'How It Works',
              style: TextStyle(
                color: textPrimary,
                fontSize: 15,
                fontWeight: FontWeight.w700,
              ),
            ),
            const Gap(12),
            _buildStepItem(
              context,
              stepNumber: '1',
              title: 'Connect to Wi-Fi',
              body:
                  'Ensure your device Wi-Fi is turned on and connected to the Student-WiFi network.',
            ),
            const Gap(12),
            _buildStepItem(
              context,
              stepNumber: '2',
              title: 'Enter Credentials',
              body:
                  'Provide your campus Student ID and Portal password correctly in the input fields.',
            ),
            const Gap(12),
            _buildStepItem(
              context,
              stepNumber: '3',
              title: 'Connect Session',
              body:
                  'Tap the Connect button. PreConnect will automatically configure parameters and authenticate with the campus gateway.',
            ),
            const Gap(12),
            _buildStepItem(
              context,
              stepNumber: '4',
              title: 'Auto Extend Session',
              body:
                  'Enable Auto Extend to allow PreConnect to run in the background and keep your connectivity active.',
            ),
            const Gap(12),
            _buildStepItem(
              context,
              stepNumber: '5',
              title: 'Disconnect',
              body:
                  'Tap Disconnect to log out of the active captive portal network session immediately.',
            ),
            const Gap(20),
            Divider(height: 1, color: textSecondary.withValues(alpha: 0.18)),
            const Gap(16),
            Text(
              'Portal Parameters Explained',
              style: TextStyle(
                color: textPrimary,
                fontSize: 15,
                fontWeight: FontWeight.w700,
              ),
            ),
            const Gap(10),
            _buildParamItem(
              context,
              param: 'uaddress',
              meaning:
                  'Your device IP address assigned by the campus router on the local Wi-Fi subnet.',
            ),
            const Gap(8),
            _buildParamItem(
              context,
              param: 'umac',
              meaning:
                  'Your device physical or randomized MAC address registered with the portal gateway.',
            ),
            const Gap(8),
            _buildParamItem(
              context,
              param: 'apmac',
              meaning:
                  'The radio MAC address of the campus Access Point router currently connected to your device.',
            ),
            const Gap(8),
            _buildParamItem(
              context,
              param: 'pushPageId',
              meaning:
                  'Unique portal authentication template pushed by the campus network controller.',
            ),
            const Gap(8),
            _buildParamItem(
              context,
              param: 'ssid',
              meaning: 'Identifier for the Student-WiFi network SSID.',
            ),
            const Gap(8),
            _buildParamItem(
              context,
              param: 'psessionid',
              meaning:
                  'Cryptographic session identifiers returned after successful authentication.',
            ),
            const Gap(8),
            _buildParamItem(
              context,
              param: 'validPeriod',
              meaning: 'Total account or policy validity lifespan.',
            ),
            const Gap(8),
            _buildParamItem(
              context,
              param: 'remainTime',
              meaning:
                  'Dynamic session countdown timer showing remaining online time.',
            ),
            const Gap(8),
            _buildParamItem(
              context,
              param: 'remainFlow',
              meaning:
                  'Remaining data bandwidth quota allocated for the current network session.',
            ),
            const Gap(20),
            Divider(height: 1, color: textSecondary.withValues(alpha: 0.18)),
            const Gap(16),
            Text(
              'Common Gateway Response Codes',
              style: TextStyle(
                color: textPrimary,
                fontSize: 15,
                fontWeight: FontWeight.w700,
              ),
            ),
            const Gap(10),
            _buildParamItem(
              context,
              param: '0 (Success)',
              meaning:
                  'Login handshake accepted and authenticated session established.',
            ),
            const Gap(8),
            _buildParamItem(
              context,
              param: '10105 (Already Online)',
              meaning:
                  'Device is already authorized on the campus network, full internet access is active.',
            ),
            const Gap(8),
            _buildParamItem(
              context,
              param: '10503 / 10501',
              meaning:
                  'Incorrect Student ID or password, or student account was not found.',
            ),
            const Gap(8),
            _buildParamItem(
              context,
              param: '10505 / 4015',
              meaning:
                  'Account temporarily locked due to consecutive wrong password attempts.',
            ),
            const Gap(8),
            _buildParamItem(
              context,
              param: '10516 / 10711',
              meaning:
                  'Maximum concurrent terminal limit or network capacity reached.',
            ),
            const Gap(8),
            _buildParamItem(
              context,
              param: '20102 / 20104',
              meaning:
                  'Gateway busy or request timed out; PreConnect automatically retries every second.',
            ),
          ],
        );
      },
    );
  }

  Widget _buildParamItem(
    BuildContext context, {
    required String param,
    required String meaning,
  }) {
    final textPrimary = BracuPalette.textPrimary(context);
    final textSecondary = BracuPalette.textSecondary(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          param,
          style: TextStyle(
            color: textPrimary,
            fontSize: 13,
            fontWeight: FontWeight.w700,
            fontFamily: 'monospace',
          ),
        ),
        const Gap(2),
        Text(
          meaning,
          style: TextStyle(
            color: textSecondary,
            fontSize: 12,
            height: 1.35,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  Widget _buildStepItem(
    BuildContext context, {
    required String stepNumber,
    required String title,
    required String body,
  }) {
    final textPrimary = BracuPalette.textPrimary(context);
    final textSecondary = BracuPalette.textSecondary(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Container(
            width: 20,
            height: 20,
            decoration: BoxDecoration(
              color: BracuPalette.primary.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: Text(
              stepNumber,
              style: const TextStyle(
                color: BracuPalette.primary,
                fontSize: 10,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ),
        const Gap(12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  color: textPrimary,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Gap(2),
              Text(
                body,
                style: TextStyle(
                  color: textSecondary,
                  fontSize: 12,
                  height: 1.4,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class CaptivePortalWebView extends StatefulWidget {
  const CaptivePortalWebView({required this.portalUrl, super.key});

  final Uri portalUrl;

  @override
  State<CaptivePortalWebView> createState() => _CaptivePortalWebViewState();
}

class _CaptivePortalWebViewState extends State<CaptivePortalWebView> {
  late final WebViewController _controller;
  bool _loading = true;
  bool _successHandled = false;

  @override
  void initState() {
    super.initState();
    unawaited(AndroidNetworkAssist.bindToWifiNetwork());
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..enableZoom(true)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (String url) {
            if (mounted) {
              setState(() {
                _loading = true;
              });
            }
          },
          onPageFinished: (String url) {
            if (mounted) {
              setState(() {
                _loading = false;
              });
            }
            if (url.contains('/portalpage/')) {
              unawaited(CaptiveLoginStore.instance.saveLastPortalUrl(url));
            }
            unawaited(_checkForLoginSuccess());
          },
          onSslAuthError: (SslAuthError error) {
            unawaited(error.proceed());
          },
        ),
      )
      ..loadRequest(widget.portalUrl);
  }

  Future<void> _checkForLoginSuccess() async {
    if (_successHandled || !mounted) return;
    final isOnline = await CaptiveWifiHttp.retryOperation<bool>(() async {
      if (_successHandled || !mounted) return true;
      final portal = await CaptiveWifiHttp.detectCaptivePortal();
      return portal == null;
    }, isSuccess: (online) => online == true);

    if (isOnline == true && !_successHandled && mounted) {
      _successHandled = true;
      unawaited(AndroidNetworkAssist.reportCaptivePortalDismissed());
      showAppSnackBar(context, 'Connected to the internet.');
      Navigator.of(context).pop(true);
    }
  }

  @override
  void dispose() {
    unawaited(AndroidNetworkAssist.unbindFromWifiNetwork());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SafeArea(
        child: Stack(
          children: [
            Positioned.fill(child: WebViewWidget(controller: _controller)),
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: Container(
                height: 48,
                color: Colors.transparent,
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.arrow_back_rounded),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                    const Spacer(),
                    BracuRefreshButton(
                      onPressed: () => _controller.reload(),
                      isLoading: _loading,
                      color: BracuPalette.textPrimary(context),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
