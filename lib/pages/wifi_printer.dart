import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dart_pdf_reader/dart_pdf_reader.dart' deferred as pdf_reader;
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:preconnect/api/api_config.dart';
import 'package:preconnect/api/auth.dart';
import 'package:preconnect/api/profile.dart';
import 'package:preconnect/pages/ui_kit.dart';
import 'package:preconnect/tools/android_network_assist.dart';
import 'package:preconnect/tools/app_storage.dart';
import 'package:preconnect/tools/http/http_utils.dart';
import 'package:preconnect/tools/storage_keys.dart';

class CampusPrinterPage extends StatefulWidget {
  const CampusPrinterPage({super.key});

  static const String blankPageUrl =
      '${ApiConfig.websiteBase}/WhitePage.pdf';
  static Uint8List? cachedBlankPageBytes;

  static _CampusPrinterBootstrap? _cachedBootstrap;
  static Future<_CampusPrinterBootstrap>? _preloadFuture;

  static Future<void> preload() async {
    await Future.wait([_preloadBootstrap(), _preloadBlankPage()]);
  }

  static void invalidateCache() {
    _cachedBootstrap = null;
    _preloadFuture = null;
    cachedBlankPageBytes = null;
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
    await AppStorage.instance.remove('cached_blank_page_pdf');
    invalidateCache();
  }

  static Future<void> _preloadBlankPage() async {
    if (cachedBlankPageBytes != null) return;
    try {
      final cachedBase64 = await AppStorage.instance.getString(
        'cached_blank_page_pdf',
      );
      if (cachedBase64 != null && cachedBase64.isNotEmpty) {
        cachedBlankPageBytes = base64Decode(cachedBase64);
        return;
      }
    } catch (_) {}

    try {
      final uri = Uri.parse(blankPageUrl);
      final response = await HttpUtils.client
          .get(uri, headers: const <String, String>{'Accept-Encoding': 'gzip'})
          .timeout(const Duration(seconds: 15));
      if (response.statusCode == 200 && response.bodyBytes.isNotEmpty) {
        final bytes = response.bodyBytes;
        cachedBlankPageBytes = bytes;
        await AppStorage.instance.setString(
          'cached_blank_page_pdf',
          base64Encode(bytes),
        );
      }
    } catch (_) {}
  }

  static Future<_CampusPrinterBootstrap> _preloadBootstrap() async {
    unawaited(_preloadBlankPage());
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
  static const String _snackBlankPageLoadFailed =
      "Couldn't load the blank page";
  static const String _snackIdentityRequired = 'Profile data required';
  static const String _snackPrintSent = 'Print sent';
  static const String _snackPrintFailed = 'Print failed';
  static const String _snackPrinterConnectionFailed =
      'Printer connection failed';

  Uint8List? _fileBytes;
  String _fileName = '';
  int? _filePageCount;
  String _studentId = '';
  String _studentName = '';
  String _studentShortCode = '';
  String _currentSemester = '';
  String _guestName = '';
  int? _guestId;
  String _clientName = '';
  String _wifiName = '';
  String _duplexMode = 'OFF';
  String _collateMode = 'OFF';
  String _printerHost = '';
  List<_PrintHistoryEntry> _history = const <_PrintHistoryEntry>[];
  int _copies = 1;
  bool _busy = false;
  bool _discovering = false;
  bool _loadingPreset = false;
  bool _syncingCopiesController = false;
  StreamSubscription<AndroidNetworkStatus>? _networkStatusSubscription;
  String _lastNetworkFingerprint = '';
  final TextEditingController _copiesController = TextEditingController(
    text: '1',
  );

  @override
  void initState() {
    super.initState();
    _copiesController.addListener(_handleCopiesControllerChanged);
    if (AndroidNetworkAssist.isSupported) {
      _networkStatusSubscription = AndroidNetworkAssist.statusStream.listen(
        (status) => unawaited(_handleNetworkStatusChanged(status)),
      );
    }
    _bootstrap();
  }

  void _handleCopiesControllerChanged() {
    if (_syncingCopiesController) return;
    final parsed = int.tryParse(_copiesController.text.trim()) ?? 0;
    final nextCopies = parsed.clamp(0, 999);
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

  void _adjustCopies(int delta) {
    final next = (_copies + delta).clamp(0, 999);
    if (next == _copies) return;
    setState(() {
      _copies = next;
    });
    _setCopiesControllerText(next);
    unawaited(_savePrinterPreferences());
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
    unawaited(_refreshWifiName());
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
    unawaited(_refreshWifiName());
    await _discoverPrinter(forceRescan: true);
  }

  Future<void> _savePrinterPreferences() async {
    await AppStorage.instance.setInt(_copiesKey, _copies);
  }

  @override
  void dispose() {
    _networkStatusSubscription?.cancel();
    _copiesController.removeListener(_handleCopiesControllerChanged);
    _copiesController.dispose();
    super.dispose();
  }

  Future<void> _handleNetworkStatusChanged(AndroidNetworkStatus status) async {
    if (!mounted) return;
    _setWifiNameFromStatus(status);
    if (status.transport.trim().toLowerCase() != 'wifi' || !status.connected) {
      if (_printerHost.isNotEmpty) {
        setState(() {
          _printerHost = '';
        });
      }
      return;
    }
    final currentNetworkFingerprint = await _currentNetworkFingerprint();
    if (currentNetworkFingerprint.isEmpty ||
        currentNetworkFingerprint == _lastNetworkFingerprint) {
      return;
    }
    _lastNetworkFingerprint = currentNetworkFingerprint;
    unawaited(_discoverPrinter(forceRescan: true));
  }

  Future<void> _discoverPrinter({bool forceRescan = false}) async {
    if (_discovering) return;
    setState(() {
      _discovering = true;
    });
    try {
      final wifiStatus = await AndroidNetworkAssist.getNetworkStatus();
      if (wifiStatus == null ||
          wifiStatus.transport.trim().toLowerCase() != 'wifi' ||
          !wifiStatus.connected) {
        if (!mounted) return;
        setState(() {
          _printerHost = '';
        });
        return;
      }
      _setWifiNameFromStatus(wifiStatus);
      final networkKey = await _currentNetworkFingerprint();
      _lastNetworkFingerprint = networkKey;
      final savedHost =
          (await AppStorage.instance.getString(_lastPrinterHostKey) ?? '')
              .trim();
      final printers = await _WifiPrinterDiscovery.findLprPrinters(
        port: _printerPort,
        preferredHosts: savedHost.isEmpty
            ? const <String>[]
            : <String>[savedHost],
      );
      if (!mounted) return;
      if (printers.isEmpty) {
        setState(() {
          _printerHost = '';
        });
        return;
      }
      final printer = printers.first;
      await AppStorage.instance.setString(_lastPrinterHostKey, printer.address);
      await AppStorage.instance.setString(_lastPrinterWifiKey, networkKey);
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

  Future<String> _currentNetworkFingerprint() async {
    final prefixes = await _currentLocalIpv4Prefixes();
    if (prefixes.isEmpty) return '';
    return prefixes.join('|');
  }

  Future<void> _refreshWifiName() async {
    final status = await AndroidNetworkAssist.getNetworkStatus();
    if (!mounted || status == null) return;
    _setWifiNameFromStatus(status);
  }

  void _setWifiNameFromStatus(AndroidNetworkStatus status) {
    final wifiName = (status.ssid ?? '').trim();
    if (!mounted || wifiName == _wifiName) return;
    setState(() {
      _wifiName = wifiName;
    });
  }

  Future<List<String>> _currentLocalIpv4Prefixes() async {
    final subnets = await _WifiPrinterDiscovery._localIpv4Subnets();
    final prefixes = subnets.map((subnet) => subnet.prefix).toSet().toList()
      ..sort();
    return prefixes;
  }

  String _sanitizePrinterMessage(String message) {
    final trimmed = message.trim();
    if (trimmed.isEmpty) return trimmed;

    final withoutIp = trimmed.replaceAll(
      RegExp(r'\b(?:\d{1,3}\.){3}\d{1,3}\b'),
      '',
    );
    final withoutPort = withoutIp.replaceAll(RegExp(r':\d{2,5}\b'), '');
    final cleaned = withoutPort.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (cleaned.isEmpty) return _snackPrinterConnectionFailed;

    final lowered = cleaned.toLowerCase();
    if (lowered.contains('socketexception') ||
        lowered.contains('connection refused') ||
        lowered.contains('timed out') ||
        lowered.contains('connection reset') ||
        lowered.contains('broken pipe')) {
      return _snackPrinterConnectionFailed;
    }
    return cleaned;
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
        }
      });
    } catch (_) {}
  }

  Future<void> _loadBlankPage() async {
    if (_busy || _loadingPreset) return;

    final cached = CampusPrinterPage.cachedBlankPageBytes;
    if (cached != null && cached.isNotEmpty) {
      setState(() {
        _fileBytes = cached;
        _fileName = 'Blank Page.pdf';
        _filePageCount = 1;
      });
      return;
    }

    setState(() {
      _loadingPreset = true;
    });
    try {
      final uri = Uri.parse(CampusPrinterPage.blankPageUrl);
      final response = await HttpUtils.client
          .get(uri, headers: const <String, String>{'Accept-Encoding': 'gzip'})
          .timeout(const Duration(seconds: 15));
      if (response.statusCode != 200 || response.bodyBytes.isEmpty) {
        throw const FormatException('Unexpected response');
      }

      final bytes = response.bodyBytes;
      CampusPrinterPage.cachedBlankPageBytes = bytes;
      unawaited(
        AppStorage.instance.setString(
          'cached_blank_page_pdf',
          base64Encode(bytes),
        ),
      );

      if (!mounted) return;
      setState(() {
        _fileBytes = bytes;
        _fileName = 'Blank Page.pdf';
        if (_isPdfFile(_fileName, bytes)) {
          _filePageCount = 1;
        } else {
          _filePageCount = null;
        }
      });
    } catch (_) {
      if (mounted) {
        showAppSnackBar(context, _snackBlankPageLoadFailed);
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

  String _fileStatusLabel() {
    return _fileName.isEmpty ? 'Choose File' : _fileName;
  }

  void _setPdfInfoFromBytes(Uint8List bytes) {
    unawaited(() async {
      final pdfInfo = await _readPdfInfo(bytes);
      if (!mounted) return;
      setState(() {
        _filePageCount = pdfInfo.pageCount;
      });
    }());
  }

  Future<({int? pageCount})> _readPdfInfo(Uint8List bytes) async {
    try {
      await pdf_reader.loadLibrary();
      final stream = pdf_reader.ByteStream(bytes);
      final document = await pdf_reader.PDFParser(stream).parse();
      final catalog = await document.catalog;
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
      return (pageCount: count > 0 ? count : null);
    } catch (_) {
      return (pageCount: null);
    }
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
    final copies = _copies;
    try {
      final client = _LprPrintClient(
        host: host,
        port: _printerPort,
        queue: _printerQueue,
      );
      final preferences = _PrintTicket(
        copies: copies,
        duplexMode: _duplexMode,
        collateMode: _collateMode,
      );
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
          copies: copies,
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
          copies: copies,
          status: 'Failed',
          message: error.message,
          createdAt: DateTime.now(),
        ),
      );
      if (!mounted) return;
      showAppSnackBar(context, _sanitizePrinterMessage(error.message));
    } catch (_) {
      if (!mounted) return;
      await _addHistory(
        _PrintHistoryEntry(
          fileName: _fileName,
          printerHost: host,
          copies: copies,
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
    if (copies > 1) return const Duration(seconds: 2);
    return const Duration(seconds: 2);
  }

  void _showPrintProgress(String message, {required Duration duration}) {
    if (!mounted) return;
    final trimmed = _sanitizePrinterMessage(message);
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
          onPressed: _busy || _discovering
              ? null
              : () => unawaited(_discoverPrinter(forceRescan: true)),
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
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (_studentName.trim().isNotEmpty ||
                    _studentId.trim().isNotEmpty) ...[
                  _StudentPrintDetails(
                    name: _studentName,
                    shortCode: _studentShortCode,
                    semester: _currentSemester,
                    studentId: _studentId,
                    wifiName: _wifiName,
                    printerHost: _printerHost,
                  ),
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
              ],
            ),
          ),
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _PrinterFileCard(
                  title: _fileStatusLabel(),
                  subtitle:
                      '${_formatFileSizeMb(_fileBytes)} • ${_fileKindLabel()}',
                  isEmpty: _fileName.isEmpty,
                  onTap: _fileName.isEmpty && !_busy ? _pickPrintFile : null,
                  onClear: _fileName.isNotEmpty ? _clearPickedFile : null,
                  borderRadius: 8,
                  emptyAction: _fileName.isEmpty
                      ? Align(
                          alignment: Alignment.centerRight,
                          child: SizedBox(
                            width: 168,
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              alignment: Alignment.centerRight,
                              child: BracuActionButton(
                                onPressed: (_busy || _loadingPreset)
                                    ? null
                                    : _loadBlankPage,
                                label: 'Blank Page',
                                icon: Icons.download_rounded,
                                isLoading: _loadingPreset,
                                iconGap: 0,
                                foregroundColor: BracuPalette.textPrimary(
                                  context,
                                ),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 10,
                                ),
                                borderRadius: 12,
                                iconSize: 22,
                                fontSize: 16,
                              ),
                            ),
                          ),
                        )
                      : null,
                ),
                const SizedBox(height: 6),
                _PrinterPreferencesPanel(
                  copiesController: _copiesController,
                  copies: _copies,
                  mode: _duplexMode,
                  collateMode: _collateMode,
                  onCopiesStep: _adjustCopies,
                  onDuplexChanged: (mode) {
                    setState(() => _duplexMode = mode);
                  },
                  onCollateChanged: (mode) {
                    setState(() => _collateMode = mode);
                  },
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
    required this.wifiName,
    required this.printerHost,
  });

  final String name;
  final String shortCode;
  final String semester;
  final String studentId;
  final String wifiName;
  final String printerHost;

  @override
  Widget build(BuildContext context) {
    final rows = <({String label, String value})>[
      (label: 'Name', value: name.trim()),
      (label: 'Program', value: shortCode.trim()),
      (label: 'Semester', value: semester.trim()),
      (label: 'Student ID', value: studentId.trim()),
      (label: 'Printer', value: printerHost.trim()),
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
    this.onTap,
    this.onClear,
    this.emptyAction,
    this.borderRadius = 14,
  });

  final String title;
  final String subtitle;
  final bool isEmpty;
  final VoidCallback? onTap;
  final VoidCallback? onClear;
  final Widget? emptyAction;
  final double borderRadius;

  @override
  Widget build(BuildContext context) {
    final content = Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(borderRadius),
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

    if (onTap == null) {
      return content;
    }

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(borderRadius),
        child: content,
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
    final client = HttpUtils.sanitizeLprToken(
      clientName.trim().isEmpty ? user : clientName,
      fallback: user,
    );
    final safeFileName = fileName.trim();
    final printableJobName = _basePrintName(safeFileName);
    final isPostScript = _looksLikePostScript(safeFileName, bytes);
    final dataCommand = isPostScript ? 'o' : 'l';
    final copies = preferences.copies.clamp(0, 999);
    final duplexMode = preferences.duplexMode.trim().toUpperCase();
    final collateMode = preferences.collateMode.trim().toUpperCase();

    try {
      final sendBytes = isPostScript
          ? Uint8List.fromList([
              ..._ascii(preferences.postScriptPreamble),
              ...bytes,
            ])
          : bytes;
      onStatus?.call(_jobStartMessage(copies, duplexMode));
      final jobSuffix = _jobSuffix();
      final controlFileName = HttpUtils.lprJobFileName(
        client,
        prefix: 'cf',
        suffix: jobSuffix,
      );
      final dataFileName = HttpUtils.lprJobFileName(
        client,
        prefix: 'df',
        suffix: jobSuffix,
      );
      final controlText = HttpUtils.lprControlFile(
        client: client,
        owner: owner,
        printableJobName: printableJobName,
        dataCommand: dataCommand,
        dataFileName: dataFileName,
        safeFileName: safeFileName,
      );
      final control = _ascii(controlText);
      final pjlPrefix = HttpUtils.pjlPrefix(
        jobName: printableJobName,
        copies: copies,
        duplexMode: duplexMode,
        collateMode: collateMode,
        isPostScript: isPostScript,
      );

      await _sendLprJob(
        printerHost: printerHost,
        printerQueue: printerQueue,
        controlFileName: controlFileName,
        dataFileName: dataFileName,
        control: control,
        payload: _buildPjlPayload(bytes: sendBytes, prefix: pjlPrefix),
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

  Uint8List _buildPjlPayload({
    required Uint8List bytes,
    required String prefix,
  }) {
    final builder = BytesBuilder(copy: false);
    builder.add(_ascii(prefix));
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
}

class _PrinterPreferencesPanel extends StatelessWidget {
  const _PrinterPreferencesPanel({
    required this.copiesController,
    required this.copies,
    required this.mode,
    required this.collateMode,
    required this.onCopiesStep,
    required this.onDuplexChanged,
    required this.onCollateChanged,
  });

  final TextEditingController copiesController;
  final int copies;
  final String mode;
  final String collateMode;
  final ValueChanged<int> onCopiesStep;
  final ValueChanged<String> onDuplexChanged;
  final ValueChanged<String> onCollateChanged;

  @override
  Widget build(BuildContext context) {
    final duplexEnabled = mode == 'LEFT';
    final collateEnabled = collateMode == 'ON';

    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 420;
        final gap = compact ? 6.0 : 8.0;
        final buttonPadding = EdgeInsets.symmetric(
          horizontal: compact ? 6 : 8,
          vertical: compact ? 8 : 9,
        );
        final controlHeight = compact ? 36.0 : 40.0;
        final controlFont = compact ? 16.0 : 18.0;
        final toggleFont = compact ? 13.0 : 14.0;
        final togglePadding = EdgeInsets.symmetric(
          horizontal: compact ? 6 : 8,
          vertical: compact ? 8 : 9,
        );

        return Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              flex: 42,
              child: Row(
                children: [
                  Expanded(
                    flex: 42,
                    child: BracuActionButton(
                      onPressed: copies <= 0 ? null : () => onCopiesStep(-1),
                      outlined: true,
                      borderRadius: 4,
                      padding: buttonPadding,
                      label: '−',
                      fontSize: controlFont,
                    ),
                  ),
                  SizedBox(width: gap),
                  Expanded(
                    flex: 52,
                    child: SizedBox(
                      height: controlHeight,
                      child: Center(
                        child: TextField(
                          controller: copiesController,
                          keyboardType: TextInputType.number,
                          textInputAction: TextInputAction.done,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                            LengthLimitingTextInputFormatter(3),
                          ],
                          textAlign: TextAlign.center,
                          textAlignVertical: TextAlignVertical.center,
                          maxLines: 1,
                          expands: false,
                          onSubmitted: (_) => FocusScope.of(context).unfocus(),
                          style: TextStyle(
                            fontSize: compact ? 16 : 18,
                            fontWeight: FontWeight.w700,
                            color: BracuPalette.textPrimary(context),
                          ),
                          decoration: const InputDecoration(
                            border: InputBorder.none,
                            isDense: true,
                            contentPadding: EdgeInsets.symmetric(vertical: 8),
                          ),
                        ),
                      ),
                    ),
                  ),
                  SizedBox(width: gap),
                  Expanded(
                    flex: 42,
                    child: BracuActionButton(
                      onPressed: copies >= 999 ? null : () => onCopiesStep(1),
                      outlined: true,
                      borderRadius: 4,
                      padding: buttonPadding,
                      label: '+',
                      fontSize: controlFont,
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(width: compact ? 8 : 10),
            Expanded(
              flex: 58,
              child: Row(
                children: [
                  Expanded(
                    child: BracuActionButton(
                      onPressed: () {
                        onDuplexChanged(duplexEnabled ? 'OFF' : 'LEFT');
                      },
                      outlined: true,
                      backgroundColor: duplexEnabled
                          ? BracuPalette.primary.withValues(alpha: 0.12)
                          : Colors.transparent,
                      foregroundColor: duplexEnabled
                          ? BracuPalette.primary
                          : BracuPalette.textPrimary(context),
                      borderRadius: 4,
                      padding: togglePadding,
                      label: duplexEnabled ? 'Both Side' : 'One Side',
                      fontSize: toggleFont,
                    ),
                  ),
                  SizedBox(width: gap),
                  Expanded(
                    child: BracuActionButton(
                      onPressed: () {
                        onCollateChanged(collateEnabled ? 'OFF' : 'ON');
                      },
                      outlined: true,
                      backgroundColor: collateEnabled
                          ? BracuPalette.primary.withValues(alpha: 0.12)
                          : Colors.transparent,
                      foregroundColor: collateEnabled
                          ? BracuPalette.primary
                          : BracuPalette.textPrimary(context),
                      borderRadius: 4,
                      padding: togglePadding,
                      label: 'Collate',
                      fontSize: toggleFont,
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

class _PrintTicket {
  const _PrintTicket({
    required this.copies,
    required this.duplexMode,
    required this.collateMode,
  });

  final int copies;
  final String duplexMode;
  final String collateMode;

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
