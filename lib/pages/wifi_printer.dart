import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:dart_pdf_reader/dart_pdf_reader.dart';
import 'package:preconnect/api/profile_service.dart';
import 'package:preconnect/pages/ui_kit.dart';
import 'package:preconnect/tools/app_storage.dart';
import 'package:preconnect/tools/android_network_assist.dart';
import 'package:preconnect/tools/storage_keys.dart';
import 'package:preconnect/tools/token_storage.dart';

class CampusPrinterPage extends StatefulWidget {
  const CampusPrinterPage({super.key});

  @override
  State<CampusPrinterPage> createState() => _CampusPrinterPageState();
}

class _CampusPrinterPageState extends State<CampusPrinterPage> {
  static const int _printerPort = 515;
  static const String _printerQueue = 'secure';
  static const String _historyKey = 'campus_printer_history';
  static const String _lastPrinterHostKey = 'campus_printer_last_host';
  static const String _lastPrinterWifiKey = 'campus_printer_last_wifi';
  static const int _maxHistoryEntries = 50;
  static const String _copiesKey = 'campus_printer_copies';
  static const String _snackFileReadFailed = "Couldn't read selected file";
  static const String _snackNoPrinter = 'No printer detected';
  static const String _snackChooseFile = 'Select a file first';
  static const String _snackIdentityRequired = 'Name + Student ID required';
  static const String _snackPrintSent = 'Print sent';
  static const String _snackPrintFailed = 'Print failed';

  Uint8List? _fileBytes;
  String _fileName = '';
  int? _filePageCount;
  String? _filePdfVersion;
  String _studentId = '';
  String _studentName = '';
  String _studentShortCode = '';
  String _guestName = '';
  String _guestId = '';
  String _clientName = '';
  String _duplexMode = 'OFF';
  String _printerHost = '';
  bool _hasSignedInProfile = false;
  List<_PrintHistoryEntry> _history = const <_PrintHistoryEntry>[];
  int _copies = 1;
  bool _busy = false;
  bool _discovering = false;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    final hasSession = await TokenStorage.instance.readCachedHasSession();
    await Future.wait([
      _loadStudentProfile().catchError((e) {}),
      _loadHistory().catchError((e) {}),
      _loadPrinterPreferences().catchError((e) {}),
    ]);
    if (!mounted) return;
    setState(() {
      _hasSignedInProfile = hasSession ?? false;
    });
    unawaited(_discoverPrinter().catchError((e) {}));
  }

  Future<void> _refreshPrinterInfo() async {
    await _loadHistory();
    await _loadStudentProfile();
    await _loadPrinterPreferences();
    await _discoverPrinter();
  }

  Future<void> _loadPrinterPreferences() async {
    final copies = await AppStorage.instance.getString(_copiesKey);
    if (!mounted) return;
    setState(() {
      _copies = int.tryParse(copies ?? '')?.clamp(1, 999) ?? 1;
    });
  }

  Future<void> _savePrinterPreferences() async {
    await AppStorage.instance.setString(_copiesKey, _copies.toString());
  }

  Future<void> _loadStudentProfile() async {
    var studentId =
        (await AppStorage.instance.getString(StorageKeys.studentId) ?? '')
            .trim();
    var fullName =
        (await AppStorage.instance.getString(StorageKeys.fullName) ?? '')
            .trim();
    var shortCode =
        (await AppStorage.instance.getString(StorageKeys.shortCode) ?? '')
            .trim();

    if (studentId.isEmpty || fullName.isEmpty || shortCode.isEmpty) {
      final profile = await ProfileService().getProfile(fromFetch: true);
      studentId = studentId.isEmpty
          ? (profile?['studentId'] ?? '').trim()
          : studentId;
      fullName = fullName.isEmpty
          ? (profile?['fullName'] ?? '').trim()
          : fullName;
      shortCode = shortCode.isEmpty
          ? (profile?['shortCode'] ?? '').trim()
          : shortCode;
    }
    if (!mounted) return;
    setState(() {
      _studentId = studentId;
      _studentName = fullName;
      _studentShortCode = shortCode;
      _clientName = _clientName.trim().isEmpty ? studentId : _clientName;
      if (_guestName.trim().isEmpty) {
        _guestName = fullName.isNotEmpty ? fullName : 'Guest';
      }
      if (_guestId.trim().isEmpty) {
        _guestId = studentId;
      }
    });
  }

  Future<void> _discoverPrinter() async {
    if (_discovering) return;
    setState(() {
      _discovering = true;
      _printerHost = '';
    });
    try {
      final wifiFingerprint = await _currentWifiFingerprint();
      final savedHost =
          (await AppStorage.instance.getString(_lastPrinterHostKey) ?? '')
              .trim();
      final savedWifi =
          (await AppStorage.instance.getString(_lastPrinterWifiKey) ?? '')
              .trim();
      if (savedHost.isNotEmpty &&
          savedWifi.isNotEmpty &&
          savedWifi == wifiFingerprint) {
        if (!mounted) return;
        setState(() {
          _printerHost = savedHost;
        });
        return;
      }
      final printers = await _WifiPrinterDiscovery.findLprPrinters(
        port: _printerPort,
        preferredHosts: savedHost.isEmpty
            ? const <String>[]
            : <String>[savedHost],
      );
      if (!mounted) return;
      if (printers.isEmpty) {
        return;
      }
      final printer = printers.first;
      await AppStorage.instance.setString(_lastPrinterHostKey, printer.address);
      await AppStorage.instance.setString(
        _lastPrinterWifiKey,
        wifiFingerprint,
      );
      setState(() {
        _printerHost = printer.address;
      });
    } catch (_) {
    } finally {
      if (mounted) {
        setState(() {
          _discovering = false;
        });
      }
    }
  }

  Future<String> _currentWifiFingerprint() async {
    final status = await AndroidNetworkAssist.getNetworkStatus();
    if (status == null) return 'unknown';
    final ssid = (status.ssid ?? '').trim();
    final transport = status.transport.trim();
    final connected = status.connected ? '1' : '0';
    final validated = status.validated ? '1' : '0';
    final captive = status.captive ? '1' : '0';
    return '$transport|$connected|$validated|$captive|$ssid';
  }

  Future<void> _loadHistory() async {
    final raw = (await AppStorage.instance.getString(_historyKey) ?? '').trim();
    if (raw.isEmpty) return;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List<dynamic>) return;
      final history = decoded
          .whereType<Map<String, dynamic>>()
          .map(_PrintHistoryEntry.fromJson)
          .where((entry) => entry.fileName.isNotEmpty)
          .toList();
      if (!mounted) return;
      setState(() {
        _history = history;
      });
    } catch (_) {}
  }

  Future<void> _addHistory(_PrintHistoryEntry entry) async {
    final next = <_PrintHistoryEntry>[entry, ..._history];
    await _saveHistory(next);
  }

  Future<void> _saveHistory(List<_PrintHistoryEntry> history) async {
    final trimmed = history.take(_maxHistoryEntries).toList(growable: false);
    setState(() {
      _history = trimmed;
    });
    await AppStorage.instance.setString(
      _historyKey,
      jsonEncode(trimmed.map((item) => item.toJson()).toList()),
    );
  }

  Future<void> _clearHistory() async {
    if (!mounted) return;
    setState(() {
      _history = const <_PrintHistoryEntry>[];
    });
    await AppStorage.instance.setString(_historyKey, '[]');
  }

  Future<void> _pickPrintFile() async {
    try {
      final XFile? picked = await openFile(
        acceptedTypeGroups: const <XTypeGroup>[
          XTypeGroup(label: 'PDF', extensions: <String>['pdf']),
          XTypeGroup(label: 'JPEG', extensions: <String>['jpg', 'jpeg']),
          XTypeGroup(label: 'PNG', extensions: <String>['png']),
        ],
      );
      if (!mounted || picked == null) return;
      var bytes = await picked.readAsBytes();
      if (bytes.isEmpty) {
        final path = picked.path;
        if (path.isNotEmpty) {
          bytes = await File(path).readAsBytes();
        }
      }
      if (bytes.isEmpty) {
        if (mounted) showAppSnackBar(context, _snackFileReadFailed);
        return;
      }

      setState(() {
        _fileBytes = bytes;
        _fileName = picked.name.trim();
      });
      if (!mounted) return;
      setState(() {
        if (_isPdfFile(_fileName, bytes)) {
          _setPdfInfoFromBytes(bytes);
        } else {
          _filePageCount = null;
          _filePdfVersion = null;
        }
      });
    } catch (_) {}
  }

  void _clearPickedFile() {
    if (_busy) return;
    setState(() {
      _fileBytes = null;
      _fileName = '';
      _filePageCount = null;
      _filePdfVersion = null;
    });
  }

  String _formatFileSizeMb(Uint8List? bytes) {
    final length = bytes?.lengthInBytes ?? 0;
    if (length <= 0) return '0 MB';
    final mb = length / (1024 * 1024);
    return '${mb.toStringAsFixed(mb >= 10 ? 1 : 2)} MB';
  }

  String _fileKindLabel() {
    if (_fileName.trim().isEmpty) return 'File';
    if (_isJpegFile(_fileName)) return 'JPEG';
    if (_isPngFile(_fileName)) return 'PNG';
    if (_filePageCount == null) return 'File';
    return _filePageCount == 1 ? '1 Page' : '$_filePageCount Pages';
  }

  String _fileVersionLabel() {
    if (_fileName.trim().isEmpty) return 'PDF/IMAGE';
    if (_isJpegFile(_fileName)) return 'Image';
    if (_isPngFile(_fileName)) return 'Image';
    final version = _filePdfVersion?.trim();
    if (version == null || version.isEmpty) return 'PDF';
    return 'PDF $version';
  }

  String _fileStatusLabel() {
    return _fileName.isEmpty ? 'No file selected' : _fileName;
  }

  void _setPdfInfoFromBytes(Uint8List bytes) {
    unawaited(() async {
      final pdfInfo = await _readPdfInfo(bytes);
      if (!mounted) return;
      setState(() {
        _filePageCount = pdfInfo.pageCount;
        _filePdfVersion = pdfInfo.version;
      });
    }());
  }

  Future<({int? pageCount, String? version})> _readPdfInfo(Uint8List bytes) async {
    try {
      final header = _readPdfHeaderVersion(bytes);
      final stream = ByteStream(bytes);
      final document = await PDFParser(stream).parse();
      final catalog = await document.catalog;
      final version = header ?? (await catalog.getVersion());
      final pages = await catalog.getPages();
      var count = 0;
      while (true) {
        try {
          pages.getPageAtIndex(count);
          count++;
        } catch (_) {
          break;
        }
      }
      return (
        pageCount: count > 0 ? count : null,
        version: version?.trim().isNotEmpty == true ? version!.trim() : null,
      );
    } catch (_) {
      return (pageCount: null, version: null);
    }
  }

  String? _readPdfHeaderVersion(Uint8List bytes) {
    if (bytes.isEmpty) return null;
    final sampleLength = bytes.length < 64 ? bytes.length : 64;
    final header = String.fromCharCodes(bytes.take(sampleLength));
    final match = RegExp(r'%PDF-(\d+\.\d+)').firstMatch(header);
    final version = match?.group(1)?.trim();
    return version?.isNotEmpty == true ? version : null;
  }

  Future<void> _sendToPrinter() async {
    if (_busy) return;
    final host = _printerHost.trim();
    final studentId = _studentId.trim().isNotEmpty
        ? _studentId.trim()
        : _guestId.trim();
    final user = studentId.isEmpty ? 'guest' : studentId;
    final clientName = _clientName.trim().isNotEmpty
        ? _clientName.trim()
        : (_guestName.trim().isNotEmpty ? _guestName.trim() : studentId);
    final bytes = _fileBytes;

    if (host.isEmpty) {
      showAppSnackBar(context, _snackNoPrinter);
      return;
    }
    if (bytes == null || bytes.isEmpty) {
      showAppSnackBar(context, _snackChooseFile);
      return;
    }
    if (studentId.isEmpty) {
      showAppSnackBar(context, _snackIdentityRequired);
      return;
    }
    if (clientName.isEmpty) {
      showAppSnackBar(context, _snackIdentityRequired);
      return;
    }

    setState(() {
      _busy = true;
    });
    try {
      final client = _LprPrintClient(
        host: host,
        port: _printerPort,
        queue: _printerQueue,
      );
      final preferences = _PrintTicket(
        copies: _copies,
        duplexMode: _duplexMode,
      );
      await client.sendFile(
        bytes: bytes,
        fileName: _fileName,
        user: user,
        clientName: clientName,
        preferences: preferences,
      );
      if (!mounted) return;
      await _addHistory(
        _PrintHistoryEntry(
          fileName: _fileName,
          printerHost: host,
          copies: _copies,
          status: 'Sent',
          message: 'Sent to campus printer',
          createdAt: DateTime.now(),
        ),
      );
      if (!mounted) return;
      showAppSnackBar(context, _snackPrintSent);
    } on _LprPrintException catch (error) {
      if (!mounted) return;
      await _addHistory(
        _PrintHistoryEntry(
          fileName: _fileName,
          printerHost: host,
          copies: _copies,
          status: 'Failed',
          message: error.message,
          createdAt: DateTime.now(),
        ),
      );
      if (!mounted) return;
      showAppSnackBar(context, error.message);
    } catch (_) {
      if (!mounted) return;
      await _addHistory(
        _PrintHistoryEntry(
          fileName: _fileName,
          printerHost: host,
          copies: _copies,
          status: 'Failed',
          message: _snackPrintFailed,
          createdAt: DateTime.now(),
        ),
      );
      if (!mounted) return;
      showAppSnackBar(context, _snackPrintFailed);
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final displayGuestName = _guestName.trim().isNotEmpty
        ? _guestName.trim()
        : 'Guest';
    final displayGuestId = _guestId.trim();
    final showIdentityFields =
        !_hasSignedInProfile &&
        _studentName.trim().isEmpty &&
        _studentId.trim().isEmpty;
    final canPrint =
        !_busy &&
        !_discovering &&
        _printerHost.isNotEmpty &&
        (_guestId.isNotEmpty || _studentId.isNotEmpty) &&
        (_guestName.isNotEmpty || _studentName.isNotEmpty);
    final printerSubtitle = _discovering
        ? 'Scanning...'
        : _printerHost.isNotEmpty
        ? 'Printer found'
        : 'Not found';
    return BracuPageScaffold(
      title: 'Printer',
      subtitle: printerSubtitle,
      icon: Icons.local_printshop_outlined,
      actions: [
        IconButton(
          onPressed: _busy || _discovering ? null : _discoverPrinter,
          style: bracuCompactIconButtonStyle(
            foregroundColor: BracuPalette.primary,
            borderColor: Colors.transparent,
            padding: EdgeInsets.zero,
            borderRadius: 12,
          ),
          icon: _discovering
              ? SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: _printerHost.isNotEmpty
                        ? const Color(0xFF22B573)
                        : BracuPalette.primary,
                  ),
                )
              : Icon(
                  _printerHost.isNotEmpty
                      ? Icons.wifi_tethering_rounded
                      : Icons.wifi_find_outlined,
                  color: _printerHost.isNotEmpty
                      ? const Color(0xFF22B573)
                      : BracuPalette.primary,
                ),
          tooltip: 'Scan',
        ),
      ],
      body: BracuRefreshList(
        onRefresh: _refreshPrinterInfo,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 10),
                _StudentPrintDetails(
                  name: _studentName,
                  shortCode: _studentShortCode,
                  studentId: _studentId,
                ),
                const SizedBox(height: 12),
                if (showIdentityFields) ...[
                  _PrinterIdentityPanel(
                    guestName: displayGuestName,
                    guestId: displayGuestId,
                    onGuestNameChanged: (value) {
                      setState(() => _guestName = value);
                    },
                    onGuestIdChanged: (value) {
                      setState(() => _guestId = value);
                    },
                  ),
                  const SizedBox(height: 12),
                ],
                _PrinterPreferencesPanel(
                  copies: _copies,
                  onCopiesChanged: (value) {
                    setState(() => _copies = value);
                    unawaited(_savePrinterPreferences());
                  },
                ),
                const SizedBox(height: 12),
                _PrinterDuplexPanel(
                  mode: _duplexMode,
                  onChanged: (mode) {
                    setState(() => _duplexMode = mode);
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _PrinterFileCard(
                  title: _fileStatusLabel(),
                  subtitle:
                      '${_formatFileSizeMb(_fileBytes)} • ${_fileKindLabel()} • ${_fileVersionLabel()}',
                  isEmpty: _fileName.isEmpty,
                  onClear: _fileName.isNotEmpty ? _clearPickedFile : null,
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: BracuActionButton(
                        onPressed: _busy ? null : _pickPrintFile,
                        icon: Icons.picture_as_pdf_outlined,
                        label: 'Choose',
                        isLoading: _busy,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: BracuActionButton(
                        onPressed: canPrint ? _sendToPrinter : null,
                        icon: Icons.print_rounded,
                        label: 'Print',
                        isLoading: _busy,
                      ),
                    ),
                  ],
                ),
                if (_history.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: BracuActionButton(
                      onPressed: _busy ? null : _clearHistory,
                      outlined: true,
                      backgroundColor: Colors.transparent,
                      foregroundColor: BracuPalette.textSecondary(context),
                      label: 'Clear History',
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 12),
          _PrintHistoryCard(history: _history),
        ],
      ),
    );
  }
}

class _StudentPrintDetails extends StatelessWidget {
  const _StudentPrintDetails({
    required this.name,
    required this.shortCode,
    required this.studentId,
  });

  final String name;
  final String shortCode;
  final String studentId;

  @override
  Widget build(BuildContext context) {
    final rows = <({String label, String value})>[
      (label: 'Name', value: name.trim()),
      (label: 'Program', value: shortCode.trim()),
      (label: 'Student ID', value: studentId.trim()),
    ].where((row) => row.value.isNotEmpty).toList();

    if (rows.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final row in rows) ...[
          _StudentDetailLine(label: row.label, value: row.value),
          if (row != rows.last) const SizedBox(height: 4),
        ],
      ],
    );
  }
}

class _StudentDetailLine extends StatelessWidget {
  const _StudentDetailLine({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: null,
      borderRadius: BorderRadius.circular(8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 82,
            child: Text(
              label,
              style: TextStyle(
                color: BracuPalette.textSecondary(context),
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                color: BracuPalette.textPrimary(context),
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PrintHistoryCard extends StatelessWidget {
  const _PrintHistoryCard({required this.history});

  final List<_PrintHistoryEntry> history;

  @override
  Widget build(BuildContext context) {
    if (history.isEmpty) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var index = 0; index < history.length; index++) ...[
            _PrintHistoryRow(entry: history[index]),
            if (index != history.length - 1) const SizedBox(height: 8),
          ],
        ],
      ),
    );
  }
}

class _PrintHistoryRow extends StatelessWidget {
  const _PrintHistoryRow({required this.entry});

  final _PrintHistoryEntry entry;

  @override
  Widget build(BuildContext context) {
    final failed = entry.status.toLowerCase() == 'failed';
    final copiesLabel = entry.copies == 1 ? '1 Copy' : '${entry.copies} Copies';
    return _PrinterFileCard(
      title: entry.fileName,
      subtitle:
          '${failed ? 'Failed' : 'Sent'} • $copiesLabel • ${formatDateTimeLabel(entry.createdAt, includeYear: true)}',
      isEmpty: false,
    );
  }
}

class _PrinterFileCard extends StatelessWidget {
  const _PrinterFileCard({
    required this.title,
    required this.subtitle,
    required this.isEmpty,
    this.onClear,
  });

  final String title;
  final String subtitle;
  final bool isEmpty;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: BracuPalette.textSecondary(context).withValues(alpha: 0.20),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  subtitle,
                  style: TextStyle(
                    color: BracuPalette.textSecondary(context),
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: isEmpty
                        ? BracuPalette.textSecondary(context)
                        : BracuPalette.textPrimary(context),
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          if (onClear != null)
            IconButton(
              onPressed: onClear,
              icon: const Icon(Icons.close_rounded),
              tooltip: 'Clear file',
              color: BracuPalette.textSecondary(context),
              iconSize: 20,
              constraints: const BoxConstraints.tightFor(width: 36, height: 36),
              padding: EdgeInsets.zero,
            ),
        ],
      ),
    );
  }
}

class _PrintHistoryEntry {
  const _PrintHistoryEntry({
    required this.fileName,
    required this.printerHost,
    required this.copies,
    required this.status,
    required this.message,
    required this.createdAt,
  });

  final String fileName;
  final String printerHost;
  final int copies;
  final String status;
  final String message;
  final DateTime createdAt;

  factory _PrintHistoryEntry.fromJson(Map<String, dynamic> json) {
    return _PrintHistoryEntry(
      fileName: (json['fileName'] ?? '').toString(),
      printerHost: (json['printerHost'] ?? '').toString(),
      copies: int.tryParse((json['copies'] ?? '').toString()) ?? 1,
      status: (json['status'] ?? '').toString(),
      message: (json['message'] ?? '').toString(),
      createdAt:
          DateTime.tryParse((json['createdAt'] ?? '').toString()) ??
          DateTime.fromMillisecondsSinceEpoch(0),
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'fileName': fileName,
      'printerHost': printerHost,
      'copies': copies,
      'status': status,
      'message': message,
      'createdAt': createdAt.toIso8601String(),
    };
  }
}

class _LprPrintException implements Exception {
  const _LprPrintException(this.message);

  final String message;

  @override
  String toString() => message;
}

class _LprPrintClient {
  const _LprPrintClient({
    required this.host,
    this.port = 515,
    this.queue = 'lp',
  });

  final String host;
  final int port;
  final String queue;
  static const Duration _timeout = Duration(seconds: 15);
  static const String _errPrinterHostRequired = 'Printer host is required';
  static const String _errPrinterConnectionTimedOut =
      'Printer connection timed out';
  static const String _errPrinterRejectedJob = 'Printer rejected the job';

  Future<void> sendFile({
    required Uint8List bytes,
    required String fileName,
    required String user,
    required String clientName,
    required _PrintTicket preferences,
  }) async {
    final printerHost = host.trim();
    if (printerHost.isEmpty) {
      throw const _LprPrintException(_errPrinterHostRequired);
    }

    final printerQueue = queue;
    final owner = user;
    final client = clientName.trim().isEmpty ? user : clientName.trim();
    final safeFileName = fileName.trim();
    final printableJobName = _basePrintName(safeFileName);
    final isPostScript = _looksLikePostScript(safeFileName, bytes);
    final dataCommand = isPostScript ? 'o' : 'l';
    final jobToken =
        'dfA${(DateTime.now().microsecondsSinceEpoch % 999 + 1).toString().padLeft(3, '0')}$client';

    Socket? socket;
    _LprAckReader? ackReader;
    try {
      final sendBytes = isPostScript
          ? Uint8List.fromList([
              ..._ascii(preferences.postScriptPreamble),
              ...bytes,
            ])
          : bytes;
      final control = _ascii(
        [
          'H$client',
          'P$owner',
          'J$printableJobName',
          'C$printableJobName',
          '$dataCommand$jobToken',
          'U$jobToken',
          'N$safeFileName',
          '',
        ].join('\n'),
      );

      socket = await Socket.connect(printerHost, port, timeout: _timeout);
      ackReader = _LprAckReader(socket);
      await _writeAndAck(
        socket,
        ackReader,
        Uint8List.fromList([0x02, ..._ascii(printerQueue), 0x0A]),
      );
      await _writeAndAck(
        socket,
        ackReader,
        Uint8List.fromList([
          0x02,
          ..._ascii('${control.length} $jobToken'),
          0x0A,
        ]),
      );
      await _writeAndAck(
        socket,
        ackReader,
        Uint8List.fromList([...control, 0x00]),
      );
      await _writeAndAck(
        socket,
        ackReader,
        Uint8List.fromList([
          0x03,
          ..._ascii('${sendBytes.length} $jobToken'),
          0x0A,
        ]),
      );
      await _writeAndAck(
        socket,
        ackReader,
        Uint8List.fromList([...sendBytes, 0x00]),
      );
    } on _LprPrintException {
      rethrow;
    } on TimeoutException {
      throw const _LprPrintException(_errPrinterConnectionTimedOut);
    } on SocketException catch (error) {
      throw _LprPrintException(error.message);
    } finally {
      await ackReader?.cancel();
      socket?.destroy();
    }
  }

  Future<void> _writeAndAck(
    Socket socket,
    _LprAckReader ackReader,
    List<int> data,
  ) async {
    socket.add(data);
    await socket.flush().timeout(_timeout);
    final ack = await ackReader.readByte().timeout(_timeout);
    if (ack != 0) {
      throw const _LprPrintException(_errPrinterRejectedJob);
    }
  }
}

class _PrinterPreferencesPanel extends StatelessWidget {
  const _PrinterPreferencesPanel({
    required this.copies,
    required this.onCopiesChanged,
  });

  final int copies;
  final ValueChanged<int> onCopiesChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextFormField(
          initialValue: copies.toString(),
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: 'Copies',
            border: OutlineInputBorder(),
            isDense: true,
          ),
          onChanged: (value) {
            final parsed = int.tryParse(value.trim());
            onCopiesChanged((parsed ?? 1).clamp(1, 999));
          },
        ),
      ],
    );
  }
}

class _PrintTicket {
  const _PrintTicket({required this.copies, required this.duplexMode});

  final String paperSize = 'A4';
  final String orientation = 'Portrait';
  final int copies;
  final String duplexMode;

  String get postScriptPreamble => '%!PS-Adobe-3.0';
}

class _PrinterDuplexPanel extends StatelessWidget {
  const _PrinterDuplexPanel({required this.mode, required this.onChanged});

  final String mode;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    Widget buildOption(String value, String label, {required bool first}) {
      final selected = mode == value;
      return Expanded(
        child: Padding(
          padding: EdgeInsets.only(left: first ? 0 : 8),
          child: BracuActionButton(
            onPressed: () => onChanged(value),
            outlined: true,
            backgroundColor: selected
                ? BracuPalette.primary.withValues(alpha: 0.12)
                : Colors.transparent,
            foregroundColor: selected
                ? BracuPalette.primary
                : BracuPalette.textPrimary(context),
            borderRadius: 18,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            label: label,
          ),
        ),
      );
    }

    return Row(
      children: [
        buildOption('OFF', 'Single Side', first: true),
        buildOption('LEFT', 'Double Sided', first: false),
      ],
    );
  }
}

class _PrinterIdentityPanel extends StatelessWidget {
  const _PrinterIdentityPanel({
    required this.guestName,
    required this.guestId,
    required this.onGuestNameChanged,
    required this.onGuestIdChanged,
  });

  final String guestName;
  final String guestId;
  final ValueChanged<String> onGuestNameChanged;
  final ValueChanged<String> onGuestIdChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextFormField(
          initialValue: guestName,
          decoration: const InputDecoration(
            labelText: 'Name',
            border: OutlineInputBorder(),
            isDense: true,
          ),
          onChanged: onGuestNameChanged,
        ),
        const SizedBox(height: 10),
        TextFormField(
          initialValue: guestId,
          decoration: const InputDecoration(
            labelText: 'Student ID / PIN',
            border: OutlineInputBorder(),
            isDense: true,
          ),
          onChanged: onGuestIdChanged,
        ),
      ],
    );
  }
}

class _LprAckReader {
  _LprAckReader(Socket socket) : _iterator = StreamIterator<List<int>>(socket);

  static const String _errPrinterClosedConnection =
      'Printer closed the connection';

  final StreamIterator<List<int>> _iterator;
  final List<int> _buffer = <int>[];

  Future<int> readByte() async {
    while (_buffer.isEmpty) {
      final hasData = await _iterator.moveNext();
      if (!hasData) {
        throw const _LprPrintException(_errPrinterClosedConnection);
      }
      _buffer.addAll(_iterator.current);
    }
    return _buffer.removeAt(0);
  }

  Future<void> cancel() => _iterator.cancel();
}

class _WifiPrinterCandidate {
  const _WifiPrinterCandidate({
    required this.address,
    required this.interfaceName,
  });

  final String address;
  final String interfaceName;
}

class _WifiPrinterDiscovery {
  _WifiPrinterDiscovery._();

  static const List<String> _campusPrinterHosts = <String>['172.16.0.111'];

  static Future<List<_WifiPrinterCandidate>> findLprPrinters({
    int port = 515,
    Duration timeout = const Duration(milliseconds: 260),
    int concurrency = 48,
    int limit = 3,
    int maxSubnets = 2,
    List<String> preferredHosts = const <String>[],
  }) async {
    final subnets = await _localIpv4Subnets();
    final found = <_WifiPrinterCandidate>[];
    final seen = <String>{};
    final active = <Future<void>>{};

    for (final address in preferredHosts) {
      final host = address.trim();
      if (host.isEmpty || !seen.add(host)) continue;
      final open = await _probe(host, port, timeout);
      if (open) {
        found.add(_WifiPrinterCandidate(address: host, interfaceName: 'saved'));
        if (found.length >= limit) return found;
      }
    }

    for (final address in _campusPrinterHosts) {
      if (!seen.add(address)) continue;
      final open = await _probe(address, port, timeout);
      if (open) {
        found.add(
          _WifiPrinterCandidate(address: address, interfaceName: 'campus'),
        );
        if (found.length >= limit) return found;
      }
    }

    var subnetCount = 0;
    for (final subnet in subnets) {
      subnetCount++;
      if (subnetCount > maxSubnets) break;
      for (var host = 1; host <= 254; host++) {
        if (host == subnet.hostOctet) continue;
        final address = '${subnet.prefix}.$host';
        if (!seen.add(address)) continue;
        late Future<void> probe;
        probe = _probe(address, port, timeout)
            .then((open) {
              if (open && found.length < limit) {
                found.add(
                  _WifiPrinterCandidate(
                    address: address,
                    interfaceName: subnet.interfaceName,
                  ),
                );
              }
            })
            .whenComplete(() => active.remove(probe));

        active.add(probe);
        if (active.length >= concurrency) {
          await Future.any(active);
        }
        if (found.length >= limit) break;
      }
      if (found.length >= limit) break;
    }

    await Future.wait(active);
    return found;
  }

  static Future<bool> _probe(String address, int port, Duration timeout) async {
    Socket? socket;
    try {
      socket = await Socket.connect(address, port, timeout: timeout);
      return true;
    } catch (_) {
      return false;
    } finally {
      socket?.destroy();
    }
  }

  static Future<List<_Ipv4Subnet>> _localIpv4Subnets() async {
    final interfaces = await NetworkInterface.list(
      type: InternetAddressType.IPv4,
      includeLoopback: false,
    );
    final subnets = <_Ipv4Subnet>[];
    final seen = <String>{};
    for (final interface in interfaces) {
      for (final address in interface.addresses) {
        final parts = address.address.split('.');
        if (parts.length != 4) continue;
        final octets = parts.map(int.tryParse).toList();
        if (octets.any((part) => part == null)) continue;
        final first = octets[0]!;
        final second = octets[1]!;
        if (first == 127 || first == 169 && second == 254) continue;
        final prefix = '${octets[0]}.${octets[1]}.${octets[2]}';
        if (!seen.add(prefix)) continue;
        subnets.add(
          _Ipv4Subnet(
            prefix: prefix,
            hostOctet: octets[3]!,
            interfaceName: interface.name,
          ),
        );
      }
    }
    return subnets;
  }
}

class _Ipv4Subnet {
  const _Ipv4Subnet({
    required this.prefix,
    required this.hostOctet,
    required this.interfaceName,
  });

  final String prefix;
  final int hostOctet;
  final String interfaceName;
}

List<int> _ascii(String value) {
  return value.codeUnits.map((unit) => unit <= 0x7F ? unit : 0x3F).toList();
}

bool _isPdfFile(String fileName, Uint8List bytes) {
  final lower = fileName.toLowerCase();
  if (lower.endsWith('.pdf')) return true;
  if (bytes.length >= 4 &&
      bytes[0] == 0x25 &&
      bytes[1] == 0x50 &&
      bytes[2] == 0x44 &&
      bytes[3] == 0x46) {
    return true;
  }
  return false;
}

bool _isJpegFile(String fileName) {
  final lower = fileName.toLowerCase();
  return lower.endsWith('.jpg') || lower.endsWith('.jpeg');
}

bool _isPngFile(String fileName) {
  return fileName.toLowerCase().endsWith('.png');
}

String _basePrintName(String fileName) {
  final trimmed = fileName.trim();
  if (trimmed.isEmpty) return 'document';
  final lastDot = trimmed.lastIndexOf('.');
  if (lastDot <= 0) return trimmed;
  return trimmed.substring(0, lastDot);
}

bool _looksLikePostScript(String fileName, Uint8List bytes) {
  final lower = fileName.toLowerCase();
  if (lower.endsWith('.ps') || lower.endsWith('.eps')) return true;
  if (bytes.length >= 2 && bytes[0] == 0x25 && bytes[1] == 0x21) return true;
  return false;
}
