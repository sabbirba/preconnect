import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:gap/gap.dart';
import 'package:archive/archive.dart';
import 'package:preconnect/tools/token_storage.dart';
import 'package:preconnect/tools/preconnect_constants.dart';
import 'package:preconnect/pages/ui_kit.dart';
import 'package:flutter/services.dart';

class ImportSessionDialog extends StatefulWidget {
  const ImportSessionDialog({
    super.key,
    this.showCancelButton = true,
    this.showCloseButton = true,
  });

  final bool showCancelButton;
  final bool showCloseButton;

  static Future<bool?> show(BuildContext context) async {
    return await showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (_) => const Dialog(child: ImportSessionDialog()),
    );
  }

  @override
  State<ImportSessionDialog> createState() => _ImportSessionDialogState();
}

class _ImportSessionDialogState extends State<ImportSessionDialog> {
  bool _isProcessing = false;
  String? _errorMessage;
  String? _clipboardSyncCode;

  @override
  void initState() {
    super.initState();
    _checkClipboardForSyncCode();
  }

  Future<void> _checkClipboardForSyncCode() async {
    try {
      final data = await Clipboard.getData(Clipboard.kTextPlain);
      final text = data?.text;
      if (text != null && text.trim().isNotEmpty) {
        if (_isValidSyncCodeFormat(text.trim())) {
          if (mounted) {
            setState(() {
              _clipboardSyncCode = text.trim();
            });
          }
        }
      }
    } catch (_) {}
  }

  bool _isValidSyncCodeFormat(String code) {
    try {
      final decodedBytes = base64.decode(code);
      final decompressed = GZipDecoder().decodeBytes(decodedBytes);
      final decodedStr = utf8.decode(decompressed);
      final dynamic data = jsonDecode(decodedStr);
      if (data is Map<String, dynamic>) {
        return data.containsKey('accessToken') &&
            data.containsKey('refreshToken') &&
            data.containsKey('timestamp');
      }
    } catch (_) {}
    return false;
  }

  @override
  void dispose() {
    super.dispose();
  }

  Future<void> _importFromClipboard() async {
    setState(() {
      _isProcessing = true;
      _errorMessage = null;
    });
    try {
      final data = await Clipboard.getData(Clipboard.kTextPlain);
      final text = data?.text;
      if (text == null || text.trim().isEmpty) {
        setState(() {
          _errorMessage = 'Clipboard is empty.';
        });
        return;
      }
      await _processImportCode(text.trim());
    } catch (e) {
      setState(() {
        _errorMessage = 'Could not read clipboard.';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isProcessing = false;
        });
      }
    }
  }

  Future<void> _processImportCode(String code) async {
    if (code.trim().isEmpty) {
      setState(() {
        _errorMessage = 'Code is empty.';
      });
      return;
    }

    setState(() {
      _isProcessing = true;
      _errorMessage = null;
    });

    try {
      final decodedBytes = base64.decode(code.trim());
      final decompressed = GZipDecoder().decodeBytes(decodedBytes);
      final decodedStr = utf8.decode(decompressed);
      final dynamic data = jsonDecode(decodedStr);

      if (data is! Map<String, dynamic>) {
        throw const FormatException('Invalid sync code.');
      }

      final accessToken = data['accessToken'] as String?;
      final refreshToken = data['refreshToken'] as String?;
      final idToken = data['idToken'] as String?;
      final timestamp = data['timestamp'] as int?;

      if (accessToken == null ||
          accessToken.isEmpty ||
          refreshToken == null ||
          refreshToken.isEmpty ||
          timestamp == null) {
        throw const FormatException('Invalid sync code.');
      }



      final storage = TokenStorage.instance;
      await storage.write(
        key: PreConnectStorageKeys.accessToken,
        value: accessToken,
      );
      await storage.write(
        key: PreConnectStorageKeys.refreshToken,
        value: refreshToken,
      );
      if (idToken != null && idToken.isNotEmpty) {
        await storage.write(key: PreConnectStorageKeys.idToken, value: idToken);
      }

      if (mounted) {
        Navigator.pop(context, true);
      }
    } on FormatException catch (_) {
      setState(() {
        _errorMessage = 'Invalid sync code. Copy again.';
      });

    } catch (e) {
      setState(() {
        _errorMessage = 'Import failed.';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isProcessing = false;
        });
      }
    }
  }

  Future<void> _pickAndScanQrImage() async {
    setState(() {
      _isProcessing = true;
      _errorMessage = null;
    });

    try {
      final value = await pickQrFromSystemImage();
      if (value == null || value.trim().isEmpty) {
        setState(() {
          _errorMessage = 'No QR code found in image.';
        });
        return;
      }
      await _processImportCode(value);
    } catch (e) {
      setState(() {
        _errorMessage = 'Failed to scan QR code.';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isProcessing = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final textSecondary = BracuPalette.textSecondary(context);
    final cardBg = BracuPalette.card(context);
    final hasValidClipboard = _clipboardSyncCode != null;

    return Container(
      width: 380,
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(24),
      ),
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Import Session',
                  style: TextStyle(
                    color: BracuPalette.textPrimary(context),
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              if (widget.showCloseButton)
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close_rounded),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
            ],
          ),
          const Gap(16),
          BracuActionButton(
            onPressed: _isProcessing ? null : _importFromClipboard,
            label: _isProcessing ? 'Importing...' : 'Import from Clipboard',
            outlined: false,
            backgroundColor: BracuPalette.primary,
            foregroundColor: Colors.white,
            borderRadius: 24,
          ),
          if (hasValidClipboard) ...[
            const Gap(8),
            const Center(
              child: Text(
                'Sync code detected in clipboard',
                style: TextStyle(
                  color: BracuPalette.accent,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
          const Gap(10),
          BracuActionButton(
            onPressed: _isProcessing ? null : _pickAndScanQrImage,
            label: 'Select QR Image',
            outlined: true,
            foregroundColor: BracuPalette.textPrimary(context),
            borderRadius: 24,
          ),
          const Gap(14),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: BracuPalette.primary.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: BracuPalette.primary.withValues(alpha: 0.16),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'How to get code:',
                  style: TextStyle(
                    fontSize: 13,
                    color: BracuPalette.primary,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Gap(8),
                Text(
                  '1. Open app on phone\n'
                  '2. Go to Settings > Sync Session\n'
                  '3. Authenticate and copy code or QR',
                  style: TextStyle(
                    fontSize: 12,
                    color: textSecondary,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
          if (_errorMessage != null) ...[
            const Gap(10),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: BracuPalette.danger.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: BracuPalette.danger.withValues(alpha: 0.2),
                ),
              ),
              child: Text(
                _errorMessage!,
                style: TextStyle(
                  color: BracuPalette.danger,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
          if (widget.showCancelButton) ...[
            const Gap(12),
            BracuActionButton(
              onPressed: () => Navigator.pop(context),
              label: 'Cancel',
              outlined: true,
              borderRadius: 24,
            ),
          ],
        ],
      ),
    );
  }
}
