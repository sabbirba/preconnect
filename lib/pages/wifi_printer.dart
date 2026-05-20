import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:dart_pdf_reader/dart_pdf_reader.dart';
import 'package:preconnect/api/auth_service.dart';
import 'package:preconnect/api/profile_service.dart';
import 'package:preconnect/pages/ui_kit.dart';
import 'package:preconnect/tools/app_storage.dart';
import 'package:preconnect/tools/android_network_assist.dart';
import 'package:preconnect/tools/storage_keys.dart';

class CampusPrinterPage extends StatefulWidget {
  const CampusPrinterPage({super.key});

  static _CampusPrinterBootstrap? _cachedBootstrap;
  static Future<_CampusPrinterBootstrap>? _preloadFuture;

  static Future<void> preload() async {
    await _preloadBootstrap();
  }

  static void invalidateCache() {
    _cachedBootstrap = null;
    _preloadFuture = null;
  }

  static Future<void> clearStoredState() async {
    await AppStorage.instance.remove('campus_printer_copies');
    await AppStorage.instance.remove('campus_printer_history');
    await AppStorage.instance.remove('campus_printer_last_host');
    await AppStorage.instance.remove('campus_printer_last_wifi');
    await AppStorage.instance.remove(StorageKeys.studentId);
    await AppStorage.instance.remove(StorageKeys.fullName);
    await AppStorage.instance.remove(StorageKeys.shortCode);
    await AppStorage.instance.remove(StorageKeys.currentSemester);
    invalidateCache();
  }

  static Future<_CampusPrinterBootstrap> _preloadBootstrap() async {
    final cached = _cachedBootstrap;
    if (cached != null) return cached;
    final inFlight = _preloadFuture;
    if (inFlight != null) return inFlight;

    final future = _loadBootstrap();
    _preloadFuture = future;
    try {
      final bootstrap = await future;
      _cachedBootstrap = bootstrap;
      return bootstrap;
    } finally {
      if (identical(_preloadFuture, future)) {
        _preloadFuture = null;
      }
    }
  }

  static Future<_CampusPrinterBootstrap> _loadBootstrap() async {
    final copiesRaw = await AppStorage.instance.getInt('campus_printer_copies');
    final history = await _loadHistorySnapshot();
    final isLoggedIn = await AuthService().isLoggedIn();
    final profile = await ProfileService().getProfile();
    final studentId =
        ((profile?['studentId'] ??
                await AppStorage.instance.getString(StorageKeys.studentId) ??
                ''))
            .trim();
    final fullName =
        ((profile?['fullName'] ??
                await AppStorage.instance.getString(StorageKeys.fullName) ??
                ''))
            .trim();
    final shortCode =
        ((profile?['shortCode'] ??
                await AppStorage.instance.getString(StorageKeys.shortCode) ??
                ''))
            .trim();
    final currentSemester =
        ((profile?['currentSemester'] ??
                await AppStorage.instance.getString(
                  StorageKeys.currentSemester,
                ) ??
                ''))
            .trim();
    final hasProfile = isLoggedIn && fullName.isNotEmpty;
    final guestName = hasProfile ? '' : 'Guest';
    int? guestIdNumber;
    final clientName = hasProfile ? fullName : guestName;
    if (hasProfile) {
      await AppStorage.instance.setString(StorageKeys.studentId, studentId);
      await AppStorage.instance.setString(StorageKeys.fullName, fullName);
      await AppStorage.instance.setString(StorageKeys.shortCode, shortCode);
      if (currentSemester.isNotEmpty) {
        await AppStorage.instance.setString(
          StorageKeys.currentSemester,
          currentSemester,
        );
      }
    }
    final copiesValue = copiesRaw == null
        ? 1
        : (copiesRaw < 1 ? 1 : (copiesRaw > 999 ? 999 : copiesRaw));
    return _CampusPrinterBootstrap(
      copies: copiesValue,
      history: history,
      studentId: studentId,
      studentName: fullName,
      studentShortCode: shortCode,
      currentSemester: currentSemester,
      guestName: guestName,
      guestId: guestIdNumber,
      clientName: clientName,
    );
  }

  static Future<List<_PrintHistoryEntry>> _loadHistorySnapshot() async {
    final raw =
        (await AppStorage.instance.getString('campus_printer_history') ?? '')
            .trim();
    if (raw.isEmpty) return const <_PrintHistoryEntry>[];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List<dynamic>) return const <_PrintHistoryEntry>[];
      return decoded
          .whereType<Map<String, dynamic>>()
          .map(_PrintHistoryEntry.fromJson)
          .where((entry) => entry.fileName.isNotEmpty)
          .toList(growable: false);
    } catch (_) {
      return const <_PrintHistoryEntry>[];
    }
  }

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
  static const String _snackWhitePageLoadFailed =
      "Couldn't load the white page";
  static const String _snackIdentityRequired = 'Profile data required';
  static const String _snackPrintSent = 'Print sent';
  static const String _snackPrintFailed = 'Print failed';
  static const String _whitePageUrl =
      'https://cdn.preconnect.app/WhitePage.pdf';

  Uint8List? _fileBytes;
  String _fileName = '';
  int? _filePageCount;
  String? _filePdfVersion;
  String _studentId = '';
  String _studentName = '';
  String _studentShortCode = '';
  String _currentSemester = '';
  String _guestName = '';
  int? _guestId;
  String _clientName = '';
  String _duplexMode = 'OFF';
  String _printerHost = '';
  List<_PrintHistoryEntry> _history = const <_PrintHistoryEntry>[];
  int _copies = 1;
  bool _busy = false;
  bool _discovering = false;
  bool _loadingPreset = false;
  bool _syncingCopiesController = false;
  final TextEditingController _copiesController = TextEditingController(
    text: '1',
  );

  @override
  void initState() {
    super.initState();
    _copiesController.addListener(_handleCopiesControllerChanged);
    _bootstrap();
  }

  void _handleCopiesControllerChanged() {
    if (_syncingCopiesController) return;
    final parsed = int.tryParse(_copiesController.text.trim()) ?? 1;
    final nextCopies = parsed.clamp(1, 999);
    if (nextCopies == _copies) return;
    setState(() {
      _copies = nextCopies;
    });
    unawaited(_savePrinterPreferences());
  }

  void _setCopiesControllerText(int copies) {
    final nextText = copies.toString();
    if (_copiesController.text == nextText) return;
    _syncingCopiesController = true;
    _copiesController.value = TextEditingValue(
      text: nextText,
      selection: TextSelection.collapsed(offset: nextText.length),
      composing: TextRange.empty,
    );
    _syncingCopiesController = false;
  }

  Future<void> _bootstrap() async {
    final bootstrap = await CampusPrinterPage._preloadBootstrap();
    if (!mounted) return;
    setState(() {
      _copies = bootstrap.copies;
      _history = bootstrap.history;
      _studentId = bootstrap.studentId;
      _studentName = bootstrap.studentName;
      _studentShortCode = bootstrap.studentShortCode;
      _currentSemester = bootstrap.currentSemester;
      _guestName = bootstrap.guestName;
      _guestId = bootstrap.guestId;
      _clientName = bootstrap.clientName;
    });
    _setCopiesControllerText(bootstrap.copies);
    unawaited(_discoverPrinter().catchError((e) {}));
  }

  Future<void> _refreshPrinterInfo() async {
    final bootstrap = await CampusPrinterPage._loadBootstrap();
    if (!mounted) return;
    setState(() {
      _copies = bootstrap.copies;
      _history = bootstrap.history;
      _studentId = bootstrap.studentId;
      _studentName = bootstrap.studentName;
      _studentShortCode = bootstrap.studentShortCode;
      _currentSemester = bootstrap.currentSemester;
      _guestName = bootstrap.guestName;
      _guestId = bootstrap.guestId;
      _clientName = bootstrap.clientName;
    });
    _setCopiesControllerText(bootstrap.copies);
    await _discoverPrinter();
  }

  Future<void> _savePrinterPreferences() async {
    await AppStorage.instance.setInt(_copiesKey, _copies);
  }

  @override
  void dispose() {
    _copiesController.removeListener(_handleCopiesControllerChanged);
    _copiesController.dispose();
    super.dispose();
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
      await AppStorage.instance.setString(_lastPrinterWifiKey, wifiFingerprint);
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

  Future<void> _loadWhitePage() async {
    if (_busy || _loadingPreset) return;
    setState(() {
      _loadingPreset = true;
    });
    try {
      final response = await http
          .get(Uri.parse(_whitePageUrl))
          .timeout(const Duration(seconds: 15));
      if (response.statusCode != 200 || response.bodyBytes.isEmpty) {
        throw const FormatException('Unexpected response');
      }

      final bytes = response.bodyBytes;
      if (!mounted) return;
      setState(() {
        _fileBytes = bytes;
        _fileName = 'WhitePage.pdf';
        if (_isPdfFile(_fileName, bytes)) {
          _filePageCount = 1;
          _filePdfVersion = _readPdfHeaderVersion(bytes) ?? 'PDF';
        } else {
          _filePageCount = null;
          _filePdfVersion = null;
        }
      });
    } catch (_) {
      if (mounted) {
        showAppSnackBar(context, _snackWhitePageLoadFailed);
      }
    } finally {
      if (mounted) {
        setState(() {
          _loadingPreset = false;
        });
      }
    }
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

  Future<({int? pageCount, String? version})> _readPdfInfo(
    Uint8List bytes,
  ) async {
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
        : (_guestId != null ? _guestId.toString() : '');
    final user = studentId.isEmpty ? 'guest' : studentId;
    final clientName = _clientName.trim().isNotEmpty
        ? _clientName.trim()
        : (_studentName.trim().isNotEmpty
              ? _studentName.trim()
              : (_guestName.trim().isNotEmpty ? _guestName.trim() : studentId));
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
      final copies = _copies < 1 ? 1 : _copies;
      final preferences = _PrintTicket(copies: copies, duplexMode: _duplexMode);
      await client.sendFile(
        bytes: bytes,
        fileName: _fileName,
        user: user,
        clientName: clientName,
        preferences: preferences,
        onStatus: (message) {
          if (!mounted) return;
          _showPrintProgress(message, duration: _progressSnackDuration(copies));
        },
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

  Duration _progressSnackDuration(int copies) {
    if (copies >= 10) return const Duration(seconds: 5);
    if (copies >= 5) return const Duration(seconds: 4);
    if (copies > 1) return const Duration(seconds: 3);
    return const Duration(seconds: 2);
  }

  void _showPrintProgress(String message, {required Duration duration}) {
    if (!mounted) return;
    final trimmed = message.trim();
    if (trimmed.isEmpty) return;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final messenger = ScaffoldMessenger.of(context);
    messenger.clearSnackBars();
    messenger.showSnackBar(
      SnackBar(
        content: Text(trimmed, style: const TextStyle(color: Colors.white)),
        backgroundColor: isDark
            ? const Color(0xFF1E6BE3)
            : BracuPalette.primary,
        duration: duration,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final canPrint =
        !_busy &&
        !_discovering &&
        _printerHost.isNotEmpty &&
        (_studentId.isNotEmpty || _guestId != null) &&
        (_studentName.isNotEmpty || _guestName.isNotEmpty);
    final printerSubtitle = _discovering
        ? 'Scanning...'
        : _printerHost.isNotEmpty
        ? 'Connected'
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
                if (_studentName.trim().isNotEmpty ||
                    _studentId.trim().isNotEmpty) ...[
                  const SizedBox(height: 2),
                  _StudentPrintDetails(
                    name: _studentName,
                    shortCode: _studentShortCode,
                    semester: _currentSemester,
                    studentId: _studentId,
                  ),
                  const SizedBox(height: 12),
                ],
                if (_studentName.trim().isEmpty && _studentId.trim().isEmpty)
                  _PrinterIdentityPanel(
                    guestName: _guestName,
                    guestId: _guestId,
                    onGuestNameChanged: (value) {
                      setState(() {
                        _guestName = value;
                        _clientName = value.trim().isEmpty ? 'Guest' : value;
                      });
                    },
                    onGuestIdChanged: (value) {
                      setState(() => _guestId = value);
                    },
                  ),
                if (_studentName.trim().isEmpty && _studentId.trim().isEmpty)
                  const SizedBox(height: 12),
                _PrinterPreferencesPanel(
                  copiesController: _copiesController,
                  mode: _duplexMode,
                  onDuplexChanged: (mode) {
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
                  emptyAction: _fileName.isEmpty
                      ? Align(
                          alignment: Alignment.centerRight,
                          child: SizedBox(
                            width: 168,
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              alignment: Alignment.centerRight,
                              child: OutlinedButton(
                                onPressed: (_busy || _loadingPreset)
                                    ? null
                                    : _loadWhitePage,
                                style: bracuCompactOutlinedButtonStyle(
                                  context,
                                  foregroundColor: BracuPalette.textPrimary(
                                    context,
                                  ),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 10,
                                  ),
                                  borderRadius: 12,
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.download_rounded, size: 22),
                                    const SizedBox(width: 0),
                                    const Text(
                                      'White Page',
                                      style: TextStyle(fontSize: 16),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        )
                      : null,
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: BracuActionButton(
                        onPressed: _busy ? null : _pickPrintFile,
                        icon: Icons.picture_as_pdf_outlined,
                        label: 'Choose',
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

class _CampusPrinterBootstrap {
  const _CampusPrinterBootstrap({
    required this.copies,
    required this.history,
    required this.studentId,
    required this.studentName,
    required this.studentShortCode,
    required this.currentSemester,
    required this.guestName,
    required this.guestId,
    required this.clientName,
  });

  final int copies;
  final List<_PrintHistoryEntry> history;
  final String studentId;
  final String studentName;
  final String studentShortCode;
  final String currentSemester;
  final String guestName;
  final int? guestId;
  final String clientName;
}

class _StudentPrintDetails extends StatelessWidget {
  const _StudentPrintDetails({
    required this.name,
    required this.shortCode,
    required this.semester,
    required this.studentId,
  });

  final String name;
  final String shortCode;
  final String semester;
  final String studentId;

  @override
  Widget build(BuildContext context) {
    final rows = <({String label, String value})>[
      (label: 'Name', value: name.trim()),
      (label: 'Program', value: shortCode.trim()),
      (label: 'Semester', value: semester.trim()),
      (label: 'Student ID', value: studentId.trim()),
    ].where((row) => row.value.isNotEmpty).toList();

    if (rows.isEmpty) {
      return const SizedBox.shrink();
    }

    return Table(
      columnWidths: const <int, TableColumnWidth>{
        0: FixedColumnWidth(84),
        1: FlexColumnWidth(),
      },
      defaultVerticalAlignment: TableCellVerticalAlignment.middle,
      children: [
        for (final row in rows)
          TableRow(
            children: [
              Padding(
                padding: const EdgeInsets.only(right: 10, bottom: 4),
                child: Text(
                  row.label,
                  style: TextStyle(
                    color: BracuPalette.textSecondary(context),
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  row.value,
                  style: TextStyle(
                    color: BracuPalette.textPrimary(context),
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
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
  final int? guestId;
  final ValueChanged<String> onGuestNameChanged;
  final ValueChanged<int?> onGuestIdChanged;

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
          initialValue: guestId?.toString() ?? '',
          decoration: const InputDecoration(
            labelText: 'Student ID / PIN',
            border: OutlineInputBorder(),
            isDense: true,
          ),
          keyboardType: TextInputType.number,
          inputFormatters: <TextInputFormatter>[
            FilteringTextInputFormatter.digitsOnly,
          ],
          onChanged: (value) {
            final trimmed = value.trim();
            if (trimmed.isEmpty) {
              onGuestIdChanged(null);
              return;
            }
            final parsed = int.tryParse(trimmed);
            onGuestIdChanged(parsed);
          },
        ),
      ],
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
    this.emptyAction,
  });

  final String title;
  final String subtitle;
  final bool isEmpty;
  final VoidCallback? onClear;
  final Widget? emptyAction;

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
          if (isEmpty && emptyAction != null)
            emptyAction!
          else if (onClear != null)
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
    void Function(String message)? onStatus,
  }) async {
    final printerHost = host.trim();
    if (printerHost.isEmpty) {
      throw const _LprPrintException(_errPrinterHostRequired);
    }

    final printerQueue = queue;
    final owner = user;
    final client = _lprSafeToken(
      clientName.trim().isEmpty ? user : clientName,
      fallback: user,
    );
    final safeFileName = fileName.trim();
    final printableJobName = _basePrintName(safeFileName);
    final isPostScript = _looksLikePostScript(safeFileName, bytes);
    final dataCommand = isPostScript ? 'o' : 'l';
    final copies = preferences.copies < 1 ? 1 : preferences.copies;
    final duplexMode = preferences.duplexMode.trim().toUpperCase();

    try {
      final sendBytes = isPostScript
          ? Uint8List.fromList([
              ..._ascii(preferences.postScriptPreamble),
              ...bytes,
            ])
          : bytes;
      onStatus?.call(_jobStartMessage(copies, duplexMode));
      final jobSuffix = _jobSuffix();
      final controlFileName = _jobFileName(client, jobSuffix: jobSuffix);
      final dataFileName = _jobFileName(
        client,
        prefix: 'df',
        jobSuffix: jobSuffix,
      );
      final control = _ascii(
        [
          'H$client',
          'P$owner',
          'J$printableJobName',
          'C$printableJobName',
          '$dataCommand$dataFileName',
          'U$dataFileName',
          'N$safeFileName',
          '',
        ].join('\n'),
      );

      await _sendLprJob(
        printerHost: printerHost,
        printerQueue: printerQueue,
        controlFileName: controlFileName,
        dataFileName: dataFileName,
        control: control,
        payload: _buildPjlPayload(
          bytes: sendBytes,
          jobName: printableJobName,
          copies: copies,
          duplexMode: duplexMode,
          isPostScript: isPostScript,
        ),
      );
    } on _LprPrintException {
      rethrow;
    } on TimeoutException {
      throw const _LprPrintException(_errPrinterConnectionTimedOut);
    } on SocketException catch (error) {
      throw _LprPrintException(error.message);
    }
  }

  String _jobStartMessage(int copies, String duplexMode) {
    final duplex = duplexMode.trim().toUpperCase();
    final duplexLabel = duplex == 'OFF' ? 'One Side' : 'Both Side';
    if (copies <= 1) {
      return 'Sending $duplexLabel print...';
    }
    return 'Sending $copies $duplexLabel copies...';
  }

  String _jobSuffix() {
    final number = DateTime.now().microsecondsSinceEpoch % 1000;
    return number.toString().padLeft(3, '0');
  }

  String _jobFileName(
    String client, {
    String prefix = 'cf',
    String? jobSuffix,
  }) {
    final suffix = jobSuffix ?? _jobSuffix();
    return '${prefix}A$suffix$client';
  }

  Uint8List _buildPjlPayload({
    required Uint8List bytes,
    required String jobName,
    required int copies,
    required String duplexMode,
    required bool isPostScript,
  }) {
    final language = isPostScript ? 'POSTSCRIPT' : 'PDF';
    final duplex = duplexMode.trim().toUpperCase();
    final useDuplex = duplex != 'OFF';
    final builder = BytesBuilder(copy: false);
    builder.add(_ascii('\x1B%-12345X'));
    builder.add(_ascii('@PJL JOB NAME = "${_escapePjlValue(jobName)}"\r\n'));
    builder.add(_ascii('@PJL SET COPIES = $copies\r\n'));
    builder.add(_ascii('@PJL SET COLLATE = ON\r\n'));
    builder.add(_ascii('@PJL SET DUPLEX = ${useDuplex ? 'ON' : 'OFF'}\r\n'));
    if (useDuplex) {
      builder.add(_ascii('@PJL SET BINDING = LONGEDGE\r\n'));
    }
    builder.add(_ascii('@PJL ENTER LANGUAGE = $language\r\n'));
    builder.add(bytes);
    builder.add(_ascii('\r\n\x1B%-12345X@PJL EOJ\r\n\x1B%-12345X'));
    return builder.takeBytes();
  }

  Future<void> _sendLprJob({
    required String printerHost,
    required String printerQueue,
    required String controlFileName,
    required String dataFileName,
    required List<int> control,
    required Uint8List payload,
  }) async {
    Socket? socket;
    _LprAckReader? ackReader;
    try {
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
          ..._ascii('${control.length} $controlFileName'),
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
          ..._ascii('${payload.length} $dataFileName'),
          0x0A,
        ]),
      );
      await _writeAndAck(
        socket,
        ackReader,
        Uint8List.fromList([...payload, 0x00]),
      );
      await ackReader.cancel();
      await socket.close();
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

  String _lprSafeToken(String value, {required String fallback}) {
    final normalized = value
        .trim()
        .replaceAll(RegExp(r'[^A-Za-z0-9._-]+'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');
    final safeFallback = fallback
        .trim()
        .replaceAll(RegExp(r'[^A-Za-z0-9._-]+'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');
    final token = normalized.isNotEmpty ? normalized : safeFallback;
    if (token.isEmpty) return 'preconnect';
    return token.length > 31 ? token.substring(0, 31) : token;
  }

  String _escapePjlValue(String value) {
    return value.replaceAll('\\', '\\\\').replaceAll('"', '\\"');
  }
}

class _PrinterPreferencesPanel extends StatelessWidget {
  const _PrinterPreferencesPanel({
    required this.copiesController,
    required this.mode,
    required this.onDuplexChanged,
  });

  final TextEditingController copiesController;
  final String mode;
  final ValueChanged<String> onDuplexChanged;

  @override
  Widget build(BuildContext context) {
    Widget buildOption(String value, String label, {required bool first}) {
      final selected = mode == value;
      return Expanded(
        child: Padding(
          padding: EdgeInsets.only(left: first ? 0 : 8),
          child: BracuActionButton(
            onPressed: () => onDuplexChanged(value),
            outlined: true,
            backgroundColor: selected
                ? BracuPalette.primary.withValues(alpha: 0.12)
                : Colors.transparent,
            foregroundColor: selected
                ? BracuPalette.primary
                : BracuPalette.textPrimary(context),
            borderRadius: 4,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            label: label,
          ),
        ),
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        SizedBox(
          width: 108,
          child: TextFormField(
            controller: copiesController,
            keyboardType: TextInputType.number,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
            decoration: InputDecoration(
              labelText: 'Copies',
              border: const OutlineInputBorder(),
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 10,
                vertical: 10,
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Row(
            children: [
              buildOption('OFF', '1', first: true),
              buildOption('LEFT', '2', first: false),
            ],
          ),
        ),
      ],
    );
  }
}

class _PrintTicket {
  const _PrintTicket({required this.copies, required this.duplexMode});

  final int copies;
  final String duplexMode;

  String get postScriptPreamble => '%!PS-Adobe-3.0';
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
