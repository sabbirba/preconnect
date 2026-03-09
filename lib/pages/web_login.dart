import 'dart:async';

import 'package:barcode_widget/barcode_widget.dart';
import 'package:flutter/material.dart';
import 'package:preconnect/pages/home.dart';
import 'package:preconnect/pages/ui_kit.dart';
import 'package:preconnect/tools/refresh_bus.dart';
import 'package:preconnect/tools/web_login_broker_service.dart';
import 'package:preconnect/tools/web_login_models.dart';
import 'package:preconnect/tools/web_page_title_stub.dart'
    if (dart.library.html) 'package:preconnect/tools/web_page_title_web.dart';
import 'package:preconnect/tools/web_login_session_store.dart';
import 'package:share_plus/share_plus.dart';

class WebLoginPage extends StatefulWidget {
  const WebLoginPage({super.key});

  @override
  State<WebLoginPage> createState() => _WebLoginPageState();
}

class _WebLoginPageState extends State<WebLoginPage> {
  static const String _playStoreUrl =
      'https://play.google.com/store/apps/details?id=com.sabbirba.preconnect';
  final WebLoginBrokerService _broker = WebLoginBrokerService();
  bool _initializing = true;
  bool _signingIn = false;
  WebLoginRequestPayload? _request;
  String? _vmAttemptId;
  String? _requestQrData;
  String? _statusMessage;
  Timer? _pollTimer;
  Timer? _countdownTimer;
  int _secondsLeft = 0;
  bool _pollInFlight = false;
  bool _consumeInFlight = false;

  bool get _hasActiveQr =>
      _request != null && _secondsLeft > 0 && !(_request?.isExpired ?? true);
  bool get _hasActiveVmAttempt => _vmAttemptId != null && _secondsLeft > 0;
  bool get _hasActiveLoginAttempt => _hasActiveQr || _hasActiveVmAttempt;

  @override
  void initState() {
    super.initState();
    setWebPageTitle('Login to Web');
    _initialize();
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _countdownTimer?.cancel();
    setWebPageTitle('');
    super.dispose();
  }

  void _resetToInitial() {
    _pollTimer?.cancel();
    _countdownTimer?.cancel();
    if (!mounted) return;
    setState(() {
      _request = null;
      _vmAttemptId = null;
      _requestQrData = null;
      _secondsLeft = 0;
      _pollInFlight = false;
      _consumeInFlight = false;
    });
  }

  Future<void> _initialize() async {
    if (!mounted) return;
    setState(() {
      _initializing = false;
    });
  }

  Future<void> _startLogin() async {
    if (_signingIn) return;
    setState(() {
      _signingIn = true;
      _statusMessage = null;
    });
    try {
      final request = (await _broker.createSession()).request;
      final qrData = request.toQrData();
      _startPolling(request);
      if (!mounted) return;
      setState(() {
        _request = request;
        _vmAttemptId = null;
        _requestQrData = qrData;
        _statusMessage = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _statusMessage = 'Unable to generate QR code. Please try again.';
      });
    } finally {
      if (mounted) {
        setState(() {
          _signingIn = false;
        });
      }
    }
  }

  void _startPolling(WebLoginRequestPayload request) {
    _pollTimer?.cancel();
    _countdownTimer?.cancel();
    void updateCountdown() {
      final left =
          ((request.expiresAtMillis - DateTime.now().millisecondsSinceEpoch) /
                  1000)
              .ceil();
      if (left <= 0) {
        _resetToInitial();
        return;
      }
      if (!mounted) return;
      setState(() => _secondsLeft = left);
    }

    updateCountdown();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      updateCountdown();
    });
    _pollTimer = Timer.periodic(const Duration(seconds: 2), (_) async {
      if (_request == null) return;
      if (_pollInFlight) return;
      _pollInFlight = true;
      try {
        final status = await _broker.getStatus(_request!);
        if (status.expired) {
          _resetToInitial();
          return;
        }
        if (!status.approved) return;
        if (_consumeInFlight) return;
        _consumeInFlight = true;
        _pollTimer?.cancel();
        _countdownTimer?.cancel();
        final payload = await _broker.consume(_request!);
        await WebLoginSessionStore.save(
          accessToken: payload.accessToken,
          refreshToken: payload.refreshToken,
          studentEmail: payload.studentEmail,
          webSessionId: payload.webSessionId,
          webSessionToken: payload.webSessionToken,
          vmLogin: false,
        );
        RefreshBus.instance.notify(reason: 'auth');
        if (!mounted) return;
        Navigator.of(
          context,
        ).pushReplacement(MaterialPageRoute(builder: (_) => const HomePage()));
      } catch (_) {
        _resetToInitial();
        if (!mounted) return;
        setState(() {
          _statusMessage = 'Unable to complete browser login. Try again.';
        });
      } finally {
        _pollInFlight = false;
      }
    });
  }

  Future<void> _startVmLogin() async {
    if (_signingIn) return;
    setState(() {
      _signingIn = true;
      _statusMessage = null;
    });
    try {
      final attempt = await _broker.createVmAttempt();
      _startVmPolling(
        attemptId: attempt.attemptId,
        expiresAtMillis: attempt.expiresAtMillis,
      );
      if (!mounted) return;
      setState(() {
        _request = null;
        _requestQrData = null;
        _vmAttemptId = attempt.attemptId;
      });
      final vmUrl =
          '${Uri.base.origin}/vm/start?attemptId=${Uri.encodeComponent(attempt.attemptId)}';
      openExternalUrl(
        context,
        vmUrl,
        failureMessage: 'Unable to open VM login page.',
      );
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _statusMessage = 'Unable to start VM login. Please try again.';
      });
    } finally {
      if (mounted) {
        setState(() {
          _signingIn = false;
        });
      }
    }
  }

  void _startVmPolling({
    required String attemptId,
    required int expiresAtMillis,
  }) {
    _pollTimer?.cancel();
    _countdownTimer?.cancel();

    void updateCountdown() {
      final left =
          ((expiresAtMillis - DateTime.now().millisecondsSinceEpoch) / 1000)
              .ceil();
      if (left <= 0) {
        _resetToInitial();
        if (!mounted) return;
        setState(() {
          _statusMessage = 'VM login attempt expired. Start a new one.';
        });
        return;
      }
      if (!mounted) return;
      setState(() => _secondsLeft = left);
    }

    updateCountdown();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      updateCountdown();
    });

    _pollTimer = Timer.periodic(const Duration(seconds: 2), (_) async {
      if (_vmAttemptId == null) return;
      if (_pollInFlight) return;
      _pollInFlight = true;
      try {
        final status = await _broker.getVmAttemptStatus(attemptId);
        if (status.expiresAtMillis > 0 &&
            status.expiresAtMillis <= DateTime.now().millisecondsSinceEpoch) {
          _resetToInitial();
          if (!mounted) return;
          setState(() {
            _statusMessage = 'VM login attempt expired. Start a new one.';
          });
          return;
        }
        if (!status.ready) return;
        if (_consumeInFlight) return;
        _consumeInFlight = true;
        _pollTimer?.cancel();
        _countdownTimer?.cancel();

        final payload = await _broker.consumeVmAttempt(attemptId);
        await WebLoginSessionStore.save(
          accessToken: payload.accessToken,
          refreshToken: payload.refreshToken,
          studentEmail: payload.studentEmail,
          webSessionId: payload.webSessionId,
          webSessionToken: payload.webSessionToken,
          vmLogin: (payload.webSessionId ?? '').isEmpty,
        );
        RefreshBus.instance.notify(reason: 'auth');
        if (!mounted) return;
        Navigator.of(
          context,
        ).pushReplacement(MaterialPageRoute(builder: (_) => const HomePage()));
      } catch (_) {
        _resetToInitial();
        if (!mounted) return;
        setState(() {
          _statusMessage = 'Unable to complete VM login. Try again.';
        });
      } finally {
        _pollInFlight = false;
      }
    });
  }

  Future<void> _sharePlayStoreLink() async {
    try {
      await SharePlus.instance.share(
        ShareParams(text: 'Install PreConnect App: $_playStoreUrl'),
      );
    } catch (_) {
      if (!mounted) return;
      copyToClipboard(context, _playStoreUrl);
    }
  }

  Future<void> _showPlayStoreQr() async {
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return Container(
          margin: const EdgeInsets.all(12),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Theme.of(context).scaffoldBackgroundColor,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: BracuPalette.primary.withValues(alpha: 0.18),
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Scan to Install PreConnect App',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: BracuPalette.textPrimary(context),
                ),
              ),
              const SizedBox(height: 10),
              Container(
                color: Colors.white,
                padding: const EdgeInsets.all(12),
                child: AspectRatio(
                  aspectRatio: 1,
                  child: BarcodeWidget(
                    barcode: Barcode.qrCode(
                      errorCorrectLevel: BarcodeQRCorrectionLevel.high,
                    ),
                    data: _playStoreUrl,
                    color: Colors.black,
                    backgroundColor: Colors.white,
                    drawText: false,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return BracuPageScaffold(
      title: 'Login to Web',
      subtitle: 'Scan with your phone',
      icon: Icons.language_rounded,
      showBack: false,
      body: BracuRefreshList(
        onRefresh: _initialize,
        children: [
          BracuCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '1. Tap Generate QR Code.\n2. Open Settings on your phone.\n3. Login to Web and scan this QR code.',
                  textAlign: TextAlign.start,
                  style: TextStyle(color: BracuPalette.textSecondary(context)),
                ),
                const SizedBox(height: 14),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed:
                        _initializing || _signingIn || _hasActiveLoginAttempt
                        ? null
                        : _startLogin,
                    icon: const Icon(Icons.login_rounded),
                    label: Text(
                      _signingIn
                          ? 'Generating...'
                          : (_hasActiveQr ? 'QR Active' : 'Generate QR Code'),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed:
                        _initializing || _signingIn || _hasActiveLoginAttempt
                        ? null
                        : _startVmLogin,
                    icon: const Icon(Icons.computer_rounded),
                    label: Text(
                      _signingIn
                          ? 'Starting...'
                          : (_hasActiveVmAttempt
                                ? 'VM Login Active'
                                : 'Start VM Login'),
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (_request != null) ...[
            const SizedBox(height: 12),
            BracuCard(
              child: Column(
                children: [
                  Container(
                    color: Colors.white,
                    padding: const EdgeInsets.all(12),
                    child: AspectRatio(
                      aspectRatio: 1,
                      child: BarcodeWidget(
                        barcode: Barcode.qrCode(
                          errorCorrectLevel: BarcodeQRCorrectionLevel.high,
                        ),
                        data: _requestQrData ?? _request!.toQrData(),
                        color: Colors.black,
                        backgroundColor: Colors.white,
                        drawText: false,
                        padding: const EdgeInsets.all(16),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Waiting for phone approval. QR expires in ${_secondsLeft}s',
                    style: TextStyle(
                      color: BracuPalette.textSecondary(context),
                    ),
                  ),
                ],
              ),
            ),
          ],
          if (_vmAttemptId != null) ...[
            const SizedBox(height: 12),
            BracuCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'VM login attempt is active.',
                    style: TextStyle(
                      color: BracuPalette.textSecondary(context),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Attempt ID: $_vmAttemptId',
                    style: TextStyle(
                      color: BracuPalette.textSecondary(context),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Expires in ${_secondsLeft}s',
                    style: TextStyle(
                      color: BracuPalette.textSecondary(context),
                    ),
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () => openExternalUrl(
                        context,
                        '${Uri.base.origin}/vm/start?attemptId=${Uri.encodeComponent(_vmAttemptId!)}',
                        failureMessage: 'Unable to open VM login page.',
                      ),
                      icon: const Icon(Icons.open_in_new_rounded),
                      label: const Text('Open VM Login Page'),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 12),
          InkWell(
            onTap: () => openExternalUrl(
              context,
              _playStoreUrl,
              failureMessage: 'Unable to open Play Store.',
            ),
            borderRadius: BorderRadius.circular(18),
            child: Container(
              padding: const EdgeInsets.all(2),
              decoration: BoxDecoration(
                color: BracuPalette.primary.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(18),
              ),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: Colors.transparent,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: BracuPalette.primary.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(
                        Icons.android_rounded,
                        color: BracuPalette.primary,
                        size: 18,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Get PreConnect App',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: BracuPalette.textPrimary(context),
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Install on your phone to scan QR',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                              color: BracuPalette.textSecondary(context),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Icon(
                      Icons.chevron_right,
                      color: BracuPalette.textSecondary(context),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _showPlayStoreQr,
                  icon: const Icon(Icons.qr_code_2_rounded, size: 16),
                  label: const Text('QR Code'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _sharePlayStoreLink,
                  icon: const Icon(Icons.share_outlined, size: 16),
                  label: const Text('Share'),
                ),
              ),
            ],
          ),
          if (_statusMessage != null) ...[
            const SizedBox(height: 12),
            BracuCard(
              child: Text(
                _statusMessage!,
                style: const TextStyle(color: Colors.redAccent),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
