import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:archive/archive.dart';
import 'package:barcode_widget/barcode_widget.dart';
import 'package:preconnect/tools/token_storage.dart';
import 'package:preconnect/tools/preconnect_constants.dart';
import 'package:preconnect/pages/ui_kit.dart';

class ExportSessionBottomSheet extends StatefulWidget {
  const ExportSessionBottomSheet({super.key});

  static Future<void> show(BuildContext context) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const ExportSessionBottomSheet(),
    );
  }

  @override
  State<ExportSessionBottomSheet> createState() =>
      _ExportSessionBottomSheetState();
}

class _ExportSessionBottomSheetState extends State<ExportSessionBottomSheet> {
  Timer? _countdownTimer;
  Timer? _clipboardClearTimer;
  int _secondsRemaining = 60;
  bool _expired = false;
  String? _base64Payload;
  bool _isLoading = true;
  bool _copied = false;

  bool _checkingAuth = true;
  bool _biometricsAvailable = false;
  bool _isAuthenticated = false;

  @override
  void initState() {
    super.initState();
    unawaited(_checkAndAuthenticate());
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    _clipboardClearTimer?.cancel();
    super.dispose();
  }

  Future<void> _checkAndAuthenticate() async {
    if (!mounted) return;
    setState(() {
      _checkingAuth = true;
      _isLoading = true;
    });

    final lockService = AppLockService();
    final available = await lockService.isBiometricAvailable();
    if (!available) {
      if (mounted) {
        setState(() {
          _biometricsAvailable = false;
          _checkingAuth = false;
          _isLoading = false;
        });
      }
      return;
    }

    if (mounted) {
      setState(() {
        _biometricsAvailable = true;
      });
    }

    final verified = await lockService.authenticateBiometricOnly(
      reason: 'Authenticate to export session credentials',
    );

    if (mounted) {
      setState(() {
        _isAuthenticated = verified;
        _checkingAuth = false;
      });
      if (verified) {
        unawaited(_generatePayload());
      } else {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _generatePayload() async {
    setState(() {
      _isLoading = true;
      _expired = false;
      _copied = false;
      _secondsRemaining = 60;
    });

    try {
      final storage = TokenStorage.instance;
      final accessToken = await storage.read(
        key: PreconnectStorageKeys.accessToken,
      );
      final refreshToken = await storage.read(
        key: PreconnectStorageKeys.refreshToken,
      );
      final idToken = await storage.read(key: PreconnectStorageKeys.idToken);

      if (accessToken == null || refreshToken == null) {
        if (mounted) {
          showAppSnackBar(context, 'No active session found.');
          Navigator.pop(context);
        }
        return;
      }

      final payload = {
        'accessToken': accessToken,
        'refreshToken': refreshToken,
        'idToken': idToken ?? '',
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      };

      final jsonStr = jsonEncode(payload);
      final utf8Bytes = utf8.encode(jsonStr);
      final gzipBytes = GZipEncoder().encode(utf8Bytes);
      final encoded = base64.encode(gzipBytes);

      if (mounted) {
        setState(() {
          _base64Payload = encoded;
          _isLoading = false;
        });
        _startTimer();
      }
    } catch (_) {
      if (mounted) {
        showAppSnackBar(context, 'Failed to generate sync code.');
        Navigator.pop(context);
      }
    }
  }

  void _startTimer() {
    _countdownTimer?.cancel();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return;
      setState(() {
        if (_secondsRemaining > 1) {
          _secondsRemaining--;
        } else {
          _secondsRemaining = 0;
          _expired = true;
          _countdownTimer?.cancel();
        }
      });
    });
  }

  Future<void> _copyToClipboard() async {
    if (_base64Payload == null || _expired) return;

    await Clipboard.setData(ClipboardData(text: _base64Payload!));
    if (!mounted) return;

    setState(() {
      _copied = true;
    });

    showAppSnackBar(
      context,
      'Session code copied. Clipboard will clear in 60s.',
    );

    _clipboardClearTimer?.cancel();
    _clipboardClearTimer = Timer(const Duration(seconds: 60), () async {
      await Clipboard.setData(const ClipboardData(text: ''));
    });
  }

  @override
  Widget build(BuildContext context) {
    final textSecondary = BracuPalette.textSecondary(context);
    final bottomPadding = MediaQuery.viewInsetsOf(context).bottom;

    Widget bodyContent;

    if (_checkingAuth) {
      bodyContent = const SizedBox(
        height: 200,
        child: Center(child: CircularProgressIndicator()),
      );
    } else if (!_biometricsAvailable) {
      bodyContent = Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Text(
          'Biometric authentication must be enabled to share your session. Please set up Face ID or fingerprint lock in device settings.',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: BracuPalette.textSecondary(context),
            fontSize: 14,
            height: 1.5,
          ),
        ),
      );
    } else if (!_isAuthenticated) {
      bodyContent = Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Column(
          children: [
            Text(
              'Biometric authentication is required to share your session.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: BracuPalette.textSecondary(context),
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 16),
            BracuActionButton(
              onPressed: _checkAndAuthenticate,
              label: 'Authenticate',
              outlined: false,
            ),
          ],
        ),
      );
    } else if (_isLoading) {
      bodyContent = const SizedBox(
        height: 200,
        child: Center(child: CircularProgressIndicator()),
      );
    } else {
      bodyContent = Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_expired)
            BracuActionButton(
              onPressed: _generatePayload,
              label: 'Generate New Code',
              outlined: false,
              backgroundColor: BracuPalette.primary,
              foregroundColor: Colors.white,
            ),
          if (_expired) const SizedBox(height: 20),
          Center(
            child: Stack(
              alignment: Alignment.center,
              children: [
                SizedBox(
                  width: 280,
                  height: 280,
                  child: Container(
                    decoration: const BoxDecoration(color: Colors.white),
                    padding: const EdgeInsets.all(12),
                    child: Opacity(
                      opacity: _expired ? 0.08 : 1.0,
                      child: BarcodeWidget(
                        barcode: Barcode.qrCode(),
                        data: _base64Payload!,
                        color: Colors.black,
                        backgroundColor: Colors.white,
                        errorBuilder: (context, error) =>
                            const Center(child: Text('QR generation failed')),
                      ),
                    ),
                  ),
                ),
                if (_expired)
                  Positioned.fill(
                    child: Center(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: BracuPalette.danger.withValues(alpha: 0.9),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Text(
                          'Expired',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    _expired
                        ? 'Code expired.'
                        : 'Expires in $_secondsRemaining seconds',
                    style: TextStyle(
                      color: _expired
                          ? BracuPalette.danger
                          : BracuPalette.primary,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              if (!_expired) ...[
                const SizedBox(height: 16),
                BracuActionButton(
                  onPressed: _copyToClipboard,
                  label: _copied ? 'Copied' : 'Copy Code',
                  icon: _copied ? Icons.check_circle_rounded : Icons.copy_rounded,
                  outlined: false,
                  backgroundColor: _copied
                      ? BracuPalette.accent
                      : BracuPalette.primary,
                  foregroundColor: Colors.white,
                ),
              ],
              const SizedBox(height: 16),
              BracuActionBannerCard(
                icon: Icons.language_rounded,
                title: 'Web App',
                subtitle: 'web.preconnect.app',
                onTap: () =>
                    openExternalUrl(context, 'https://web.preconnect.app'),
              ),
              const SizedBox(height: 18),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: BracuPalette.danger.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: BracuPalette.danger.withValues(alpha: 0.16),
                  ),
                ),
                child: Text(
                  'Never share this code with anyone.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 12,
                    color: BracuPalette.danger,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: BracuActionButton(
                      onPressed: () => Navigator.pop(context),
                      label: 'Close',
                      outlined: true,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      );
    }

    return Padding(
      padding: EdgeInsets.only(bottom: bottomPadding),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 24),
        decoration: BoxDecoration(
          color: BracuPalette.card(context),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.14),
              blurRadius: 30,
              offset: const Offset(0, -14),
            ),
          ],
        ),
        child: SafeArea(
          top: false,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 430),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Align(
                  alignment: Alignment.center,
                  child: Container(
                    width: 36,
                    height: 3,
                    decoration: BoxDecoration(
                      color: textSecondary.withValues(alpha: 0.28),
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Sync Session',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: BracuPalette.textPrimary(context),
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                  ),
                ),

                const SizedBox(height: 18),
                bodyContent,
              ],
            ),
          ),
        ),
      ),
    );
  }
}
