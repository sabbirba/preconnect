import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:gap/gap.dart';
import 'package:flutter/services.dart';
import 'package:archive/archive.dart';
import 'package:preconnect/tools/token_storage.dart';
import 'package:preconnect/tools/preconnect_constants.dart';
import 'package:preconnect/pages/ui_kit.dart';
import 'package:preconnect/pages/shared_widgets/qr_card.dart';

class ExportSessionBottomSheet extends StatefulWidget {
  const ExportSessionBottomSheet({super.key});

  static Future<void> show(BuildContext context) async {
    await showBracuBottomSheet<void>(
      context,
      title: 'Sync Session',
      initialChildSize: 0.75,
      builder: (sheetContext, textPrimary, textSecondary) {
        return const ExportSessionBottomSheet();
      },
    );
  }

  @override
  State<ExportSessionBottomSheet> createState() =>
      _ExportSessionBottomSheetState();
}

class _ExportSessionBottomSheetState extends State<ExportSessionBottomSheet> {
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
      _copied = false;
    });

    try {
      final storage = TokenStorage.instance;
      final accessToken = await storage.read(
        key: PreConnectStorageKeys.accessToken,
      );
      final refreshToken = await storage.read(
        key: PreConnectStorageKeys.refreshToken,
      );
      final idToken = await storage.read(key: PreConnectStorageKeys.idToken);

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
      }
    } catch (_) {
      if (mounted) {
        showAppSnackBar(context, 'Failed to generate sync code.');
        Navigator.pop(context);
      }
    }
  }

  Future<void> _copyToClipboard() async {
    if (_base64Payload == null) return;

    await Clipboard.setData(ClipboardData(text: _base64Payload!));
    if (!mounted) return;

    setState(() {
      _copied = true;
    });

    showAppSnackBar(context, 'Session code copied.');
  }

  @override
  Widget build(BuildContext context) {
    final bottomPadding = MediaQuery.viewInsetsOf(context).bottom;

    Widget bodyContent;

    if (_checkingAuth) {
      bodyContent = const SizedBox(
        height: 200,
        child: Center(child: BracuLoading()),
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
            const Gap(16),
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
        child: Center(child: BracuLoading()),
      );
    } else {
      final dragController = bracuBottomSheetScrollController(context);
      bodyContent = ListView(
        controller: dragController,
        physics: const ClampingScrollPhysics(),
        children: [
          BracuQrCard(data: _base64Payload!),
          const Gap(16),
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
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
              const Gap(16),
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
              const Gap(16),
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
      child: bodyContent,
    );
  }
}
