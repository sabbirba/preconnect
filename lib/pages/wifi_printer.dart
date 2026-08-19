import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:gap/gap.dart';
import 'package:flutter/services.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:preconnect/api/api_config.dart';
import 'package:preconnect/api/auth.dart';
import 'package:preconnect/api/profile.dart';
import 'package:preconnect/pages/card_section.dart';
import 'package:preconnect/pages/ui_kit.dart';
import 'package:preconnect/tools/app_storage.dart';
import 'package:preconnect/tools/http/http_utils.dart';
import 'package:preconnect/tools/storage_keys.dart';
import 'package:preconnect/tools/app_log.dart';

part 'printer_sections/printer_models.dart';

class CampusPrinterPage extends StatefulWidget {
  const CampusPrinterPage({super.key});

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

  static const String historyKey = 'printer_history';
  static const String copiesKey = 'campus_printer_copies';
  static const String lastHostKey = 'campus_printer_last_host';
  static const String cachedBlankPagePdfKey = 'cached_blank_page_pdf';

  static Future<void> clearStoredState() async {
    await AppStorage.instance.remove(copiesKey);
    await AppStorage.instance.remove(historyKey);
    await AppStorage.instance.remove(lastHostKey);
    await AppStorage.instance.remove(StorageKeys.studentId);
    await AppStorage.instance.remove(StorageKeys.fullName);
    await AppStorage.instance.remove(StorageKeys.shortCode);
    await AppStorage.instance.remove(StorageKeys.currentSemester);
    await AppStorage.instance.remove(cachedBlankPagePdfKey);
    invalidateCache();
  }

  @visibleForTesting
  static Uint8List createLocalBlankPdfForTesting() => _createLocalBlankPdf();

  @visibleForTesting
  static Uint8List wrapJpegInPdfForTesting(Uint8List jpeg) =>
      _wrapJpegInPdf(jpeg);

  static Uint8List _createLocalBlankPdf() {
    const pdfString = '''%PDF-1.4
1 0 obj
<< /Type /Catalog /Pages 2 0 R >>
endobj
2 0 obj
<< /Type /Pages /Kids [3 0 R] /Count 1 >>
endobj
3 0 obj
<< /Type /Page /Parent 2 0 R /MediaBox [0 0 595 842] /Contents 4 0 R /Resources <<>> >>
endobj
4 0 obj
<< /Length 23 >>
stream
0 0 0 rg 590 835 1 1 re f
endstream
endobj
xref
0 5
0000000000 65535 f 
0000000009 00000 n 
0000000058 00000 n 
0000000115 00000 n 
0000000227 00000 n 
trailer
<< /Size 5 /Root 1 0 R >>
startxref
299
%%EOF
''';
    return Uint8List.fromList(utf8.encode(pdfString));
  }

  static Future<void> _preloadBlankPage() async {
    if (cachedBlankPageBytes != null) return;
    try {
      final cachedBase64 = await AppStorage.instance.getString(
        cachedBlankPagePdfKey,
      );
      if (cachedBase64 != null && cachedBase64.isNotEmpty) {
        cachedBlankPageBytes = base64Decode(cachedBase64);
        return;
      }
    } catch (_) {}
    final bytes = _createLocalBlankPdf();
    cachedBlankPageBytes = bytes;
    unawaited(
      AppStorage.instance.setString(cachedBlankPagePdfKey, base64Encode(bytes)),
    );
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
    final pagesPerSheet =
        await AppStorage.instance.getString('campus_printer_nup') ?? '1-in-1';
    final fittingMode =
        await AppStorage.instance.getString('campus_printer_fit') ??
        'Fit on Paper';
    final staple =
        await AppStorage.instance.getString('campus_printer_staple') ?? 'Off';
    final punch =
        await AppStorage.instance.getString('campus_printer_punch') ?? 'Off';
    final jobOffset =
        await AppStorage.instance.getString('campus_printer_joboffset') ??
        'Off';
    final slipSheet =
        await AppStorage.instance.getString('campus_printer_slipsheet') ??
        'Off';
    final booklet =
        await AppStorage.instance.getString('campus_printer_booklet') ?? 'Off';
    final photoUrl = ApiConfig.photoUrl(profile?['photoFilePath']);
    return _CampusPrinterBootstrap(
      copies: copiesValue,
      history: history,
      studentId: studentId,
      studentName: fullName,
      studentShortCode: shortCode,
      currentSemester: currentSemester,
      pagesPerSheet: pagesPerSheet,
      fittingMode: fittingMode,
      staple: staple,
      punch: punch,
      jobOffset: jobOffset,
      slipSheet: slipSheet,
      booklet: booklet,
      profile: profile,
      photoUrl: photoUrl,
    );
  }

  static List<_PrintHistoryEntry> _deduplicateHistory(
    List<_PrintHistoryEntry> list,
  ) {
    final seen = <String>{};
    final result = <_PrintHistoryEntry>[];
    for (final entry in list) {
      final timeBucket = entry.createdAt.millisecondsSinceEpoch ~/ 10000;
      final key = '${entry.fileName}:${entry.status}:$timeBucket';
      if (seen.add(key)) {
        result.add(entry);
      }
    }
    return result;
  }

  static Future<List<_PrintHistoryEntry>> _loadHistorySnapshot() async {
    final raw = (await AppStorage.instance.getString('printer_history') ?? '')
        .trim();
    if (raw.isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List<dynamic>) {
        final entries = decoded
            .whereType<Map>()
            .map((e) => e.cast<String, dynamic>())
            .map(_PrintHistoryEntry.fromJson)
            .where((entry) => entry.fileName.isNotEmpty)
            .toList(growable: false);
        return _deduplicateHistory(entries);
      }
    } catch (_) {}
    return const [];
  }

  @override
  State<CampusPrinterPage> createState() => _CampusPrinterPageState();
}

class _CampusPrinterPageState extends State<CampusPrinterPage> {
  static const String _historyKey = CampusPrinterPage.historyKey;
  static const int _maxHistoryEntries = 100;
  static const String _copiesKey = CampusPrinterPage.copiesKey;
  static const String _snackFileReadFailed =
      'Unable to read the selected file. Please select a valid document.';
  static const String _snackChooseFile =
      'Please select a document file to print.';
  static const String _snackIdentityRequired =
      'Student ID and profile data are required to submit print jobs.';
  static const String _snackPrintSent = 'Sent to campus printer successfully.';
  static const String _snackPrintFailed =
      'Unable to complete print job. Please check your connection.';
  static const String _snackPrinterConnectionFailed =
      'Failed to connect to printer. Connect to Student-WiFi or check your internet connection.';

  List<_SelectedFile> _selectedFiles = const <_SelectedFile>[];
  Map<String, String?>? _profile;
  String? _photoUrl;
  String _studentId = '';
  String _studentName = '';
  String _duplexMode = 'OFF';
  String _collateMode = 'OFF';
  String _pagesPerSheet = '1-in-1';
  String _fittingMode = 'Fit on Paper';
  String _staple = 'Off';
  String _punch = 'Off';
  String _jobOffset = 'Off';
  String _slipSheet = 'Off';
  String _booklet = 'Off';
  String _printerHost = '';
  List<_PrintHistoryEntry> _history = const <_PrintHistoryEntry>[];
  int _copies = 1;
  bool _busy = false;
  bool _discovering = false;
  bool _workerAvailable = false;
  bool _syncingCopiesController = false;
  bool _hasInternet = true;
  StreamSubscription? _networkStatusSubscription;

  String _lastNetworkFingerprint = '';
  final TextEditingController _copiesController = TextEditingController(
    text: '1',
  );
  final TextEditingController _studentIdController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _copiesController.addListener(_handleCopiesControllerChanged);
    _studentIdController.addListener(_handleStudentIdControllerChanged);
    _networkStatusSubscription = Connectivity().onConnectivityChanged.listen((
      results,
    ) {
      unawaited(_handleConnectivityChanged(results));
    });

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

  void _handleStudentIdControllerChanged() {
    final value = _studentIdController.text.trim();
    if (value != _studentId) {
      setState(() {
        _studentId = value;
      });
      AppStorage.instance.setString(StorageKeys.studentId, value);
    }
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
      _profile = bootstrap.profile;
      _photoUrl = bootstrap.photoUrl;
      _copies = bootstrap.copies;
      _history = bootstrap.history;
      _studentId = bootstrap.studentId;
      _studentIdController.text = bootstrap.studentId;
      _studentName = bootstrap.studentName;
      _pagesPerSheet = bootstrap.pagesPerSheet;
      _fittingMode = bootstrap.fittingMode;
      _staple = bootstrap.staple;
      _punch = bootstrap.punch;
      _jobOffset = bootstrap.jobOffset;
      _slipSheet = bootstrap.slipSheet;
      _booklet = bootstrap.booklet;
    });
    _setCopiesControllerText(bootstrap.copies);
    unawaited(_discoverPrinter().catchError((e) {}));
  }

  Future<void> _refreshPrinterInfo() async {
    final bootstrap = await CampusPrinterPage._loadBootstrap();
    if (!mounted) return;
    setState(() {
      _profile = bootstrap.profile;
      _photoUrl = bootstrap.photoUrl;
      _copies = bootstrap.copies;
      _history = bootstrap.history;
      _studentId = bootstrap.studentId;
      _studentIdController.text = bootstrap.studentId;
      _studentName = bootstrap.studentName;
      _pagesPerSheet = bootstrap.pagesPerSheet;
      _fittingMode = bootstrap.fittingMode;
      _staple = bootstrap.staple;
      _punch = bootstrap.punch;
      _jobOffset = bootstrap.jobOffset;
      _slipSheet = bootstrap.slipSheet;
      _booklet = bootstrap.booklet;
    });
    _setCopiesControllerText(bootstrap.copies);
    await _discoverPrinter();
  }

  Future<void> _savePrinterPreferences() async {
    await AppStorage.instance.setInt(_copiesKey, _copies);
    await AppStorage.instance.setString('campus_printer_nup', _pagesPerSheet);
    await AppStorage.instance.setString('campus_printer_fit', _fittingMode);
    await AppStorage.instance.setString('campus_printer_staple', _staple);
    await AppStorage.instance.setString('campus_printer_punch', _punch);
    await AppStorage.instance.setString('campus_printer_joboffset', _jobOffset);
    await AppStorage.instance.setString('campus_printer_slipsheet', _slipSheet);
    await AppStorage.instance.setString('campus_printer_booklet', _booklet);
  }

  @override
  void dispose() {
    _networkStatusSubscription?.cancel().catchError((_) {});

    _copiesController.removeListener(_handleCopiesControllerChanged);
    _copiesController.dispose();
    _studentIdController.removeListener(_handleStudentIdControllerChanged);
    _studentIdController.dispose();
    super.dispose();
  }

  Future<void> _handleConnectivityChanged(
    List<ConnectivityResult> results,
  ) async {
    if (!mounted) return;
    final isNone =
        results.isEmpty || results.every((r) => r == ConnectivityResult.none);
    if (isNone) {
      setState(() {
        _hasInternet = false;
        _printerHost = '';
      });
      return;
    }
    setState(() {
      _hasInternet = true;
    });
    final currentNetworkFingerprint = await _currentNetworkFingerprint();
    if (currentNetworkFingerprint.isEmpty ||
        currentNetworkFingerprint == _lastNetworkFingerprint) {
      return;
    }
    _lastNetworkFingerprint = currentNetworkFingerprint;
    unawaited(_discoverPrinter());
  }

  Future<bool> _checkWorkerStatus() async {
    try {
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final url = Uri.parse(
        '${ApiConfig.realtimeApiBase}/print/stats?ts=$timestamp',
      );
      final response = await HttpUtils.client
          .get(
            url,
            headers: const <String, String>{
              'Accept': 'application/json',
              'Cache-Control': 'no-cache, no-store, must-revalidate',
              'Pragma': 'no-cache',
              'Expires': '0',
            },
          )
          .timeout(const Duration(milliseconds: 2000));
      if (response.statusCode == 200) {
        final Map<String, dynamic> data =
            jsonDecode(response.body) as Map<String, dynamic>;
        return data['status'] == 'online';
      }
    } catch (_) {}
    return false;
  }

  Future<void> _discoverPrinter() async {
    if (_discovering) return;
    setState(() {
      _discovering = true;
    });
    try {
      final networkKey = await _currentNetworkFingerprint();
      _lastNetworkFingerprint = networkKey;

      final results = await Future.wait([
        _WifiPrinterDiscovery._probe(
          _CampusPrinterConfig.current.hosts.first,
          _CampusPrinterConfig.current.port,
          const Duration(milliseconds: 1200),
        ),
        _checkWorkerStatus(),
      ]);

      final directPrinterOnline = results[0];
      final workerOnline = results[1];

      if (mounted) {
        setState(() {
          if (directPrinterOnline) {
            _printerHost = _CampusPrinterConfig.current.hosts.first;
            _workerAvailable = false;
          } else {
            _printerHost = '';
            _workerAvailable = workerOnline;
          }
        });
      }
    } catch (e) {
      await AppLog.write('Printer discovery failed: $e');
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
    final next = CampusPrinterPage._deduplicateHistory([entry, ..._history]);
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
      final List<XFile> picked = await openFiles(
        acceptedTypeGroups: const <XTypeGroup>[
          XTypeGroup(
            label: 'PDF',
            extensions: <String>['pdf'],
            mimeTypes: <String>['application/pdf'],
            uniformTypeIdentifiers: <String>['com.adobe.pdf'],
          ),
          XTypeGroup(
            label: 'Images',
            extensions: <String>['jpg', 'jpeg', 'png'],
            mimeTypes: <String>['image/jpeg', 'image/png'],
            uniformTypeIdentifiers: <String>['public.jpeg', 'public.png'],
          ),
        ],
      );
      if (!mounted || picked.isEmpty) return;
      final nextFiles = <_SelectedFile>[];
      for (final file in picked) {
        var bytes = await file.readAsBytes();
        if (bytes.isEmpty) {
          final path = file.path;
          if (path.isNotEmpty) {
            bytes = await File(path).readAsBytes();
          }
        }
        if (bytes.isNotEmpty) {
          final selected = _SelectedFile(name: file.name.trim(), bytes: bytes);
          if (_isPdfFile(selected.name, bytes)) {
            final pdfInfo = await _readPdfInfo(bytes);
            selected.pageCount = pdfInfo.pageCount;
          } else if (_isJpegFile(selected.name) || _isPngFile(selected.name)) {
            selected.pageCount = 1;
          }
          nextFiles.add(selected);
        }
      }
      if (nextFiles.isEmpty) {
        if (mounted) showAppSnackBar(context, _snackFileReadFailed);
        return;
      }
      setState(() {
        _selectedFiles = List<_SelectedFile>.from(_selectedFiles)
          ..addAll(nextFiles);
      });
    } catch (e) {
      await AppLog.write('Failed to add selected files: $e');
    }
  }

  Future<void> _loadBlankPage() async {
    if (_busy) return;

    final cached =
        CampusPrinterPage.cachedBlankPageBytes ??
        CampusPrinterPage._createLocalBlankPdf();
    CampusPrinterPage.cachedBlankPageBytes = cached;
    setState(() {
      _selectedFiles = [
        _SelectedFile(name: 'Blank Page.pdf', bytes: cached, pageCount: 1),
      ];
    });
  }

  void _clearFileAt(int index) {
    if (_busy) return;
    setState(() {
      final next = List<_SelectedFile>.from(_selectedFiles);
      next.removeAt(index);
      _selectedFiles = next;
    });
  }

  String _formatFileSizeMb(Uint8List bytes) {
    final length = bytes.lengthInBytes;
    if (length <= 0) return '0 MB';
    final mb = length / (1024 * 1024);
    return '${mb.toStringAsFixed(mb >= 10 ? 1 : 2)} MB';
  }

  String _fileKindLabelFor(_SelectedFile file) {
    if (file.name.trim().isEmpty) return 'File';
    if (file.pageCount != null) {
      return file.pageCount == 1 ? '1 Page' : '${file.pageCount} Pages';
    }
    if (_isJpegFile(file.name)) return '1 Page';
    if (_isPngFile(file.name)) return '1 Page';
    return '1 Page';
  }

  Future<({int? pageCount})> _readPdfInfo(Uint8List bytes) async {
    try {
      final content = latin1.decode(bytes, allowInvalid: true);
      final pagesCountRegExp = RegExp(r'/Type\s*/Pages\b[^]*?/Count\s+(\d+)');
      final match = pagesCountRegExp.firstMatch(content);
      if (match != null) {
        final count = int.tryParse(match.group(1) ?? '');
        if (count != null && count > 0) {
          return (pageCount: count);
        }
      }

      final pageObjRegExp = RegExp(r'/Type\s*/Page\b');
      final matches = pageObjRegExp.allMatches(content).length;
      if (matches > 0) {
        return (pageCount: matches);
      }

      return (pageCount: null);
    } catch (_) {
      return (pageCount: null);
    }
  }

  Future<void> _sendToPrinter() async {
    if (_busy) return;
    final host = _printerHost.trim();
    final studentId = _studentId.trim();
    final user = studentId;
    final clientName = _studentName.trim().isNotEmpty
        ? _studentName.trim()
        : studentId;

    if (_selectedFiles.isEmpty) {
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
        port: _CampusPrinterConfig.current.port,
        queue: _CampusPrinterConfig.current.queue,
      );
      final preferences = _PrintTicket(
        copies: copies,
        duplexMode: _duplexMode,
        collateMode: _collateMode,
        pagesPerSheet: _pagesPerSheet,
        fittingMode: _fittingMode,
        staple: _staple,
        punch: _punch,
        jobOffset: _jobOffset,
        slipSheet: _slipSheet,
        booklet: _booklet,
      );

      for (int i = 0; i < _selectedFiles.length; i++) {
        final file = _selectedFiles[i];
        if (!mounted) return;
        try {
          await client.sendFile(
            bytes: file.bytes,
            fileName: file.name,
            user: user,
            clientName: clientName,
            preferences: preferences,
          );
          if (!mounted) return;
          const statusLabel = 'Sent';
          const messageLabel = 'Sent to campus printer.';

          await _addHistory(
            _PrintHistoryEntry(
              fileName: file.name,
              printerHost: host,
              copies: copies,
              status: statusLabel,
              message: messageLabel,
              createdAt: DateTime.now(),
            ),
          );
        } on _LprPrintException catch (error) {
          if (!mounted) return;
          await _addHistory(
            _PrintHistoryEntry(
              fileName: file.name,
              printerHost: host,
              copies: copies,
              status: 'Failed',
              message: error.message,
              createdAt: DateTime.now(),
            ),
          );
          if (mounted) {
            showAppSnackBar(
              context,
              '${file.name}: ${_sanitizePrinterMessage(error.message)}',
            );
          }
        } catch (_) {
          if (!mounted) return;
          await _addHistory(
            _PrintHistoryEntry(
              fileName: file.name,
              printerHost: host,
              copies: copies,
              status: 'Failed',
              message: _snackPrintFailed,
              createdAt: DateTime.now(),
            ),
          );
          if (mounted) {
            showAppSnackBar(context, '${file.name}: $_snackPrintFailed');
          }
        }
      }
      if (mounted) {
        showAppSnackBar(context, _snackPrintSent);
      }
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
    final hasConnection = _printerHost.isNotEmpty || _workerAvailable;
    final canPrint =
        _hasInternet &&
        !_busy &&
        !_discovering &&
        _selectedFiles.isNotEmpty &&
        _studentId.isNotEmpty &&
        _studentName.isNotEmpty &&
        hasConnection;

    final String printerSubtitle;
    final Color? subtitleColor;

    if (!_hasInternet) {
      printerSubtitle = 'Offline';
      subtitleColor = null;
    } else if (_discovering) {
      printerSubtitle = 'Scanning..';
      subtitleColor = null;
    } else if (_printerHost.isNotEmpty || _workerAvailable) {
      printerSubtitle = 'Connected';
      subtitleColor = const Color(0xFF22B573);
    } else {
      printerSubtitle = 'Not found';
      subtitleColor = null;
    }

    return BracuPageScaffold(
      title: 'Printer',
      subtitle: printerSubtitle,
      subtitleColor: subtitleColor,
      icon: Icons.local_printshop_outlined,
      actions: [
        BracuRefreshButton(
          onPressed: () => _refreshPrinterInfo(),
          isLoading: _discovering,
        ),
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
                  CardSection(
                    profile: _profile,
                    photoUrl: _photoUrl,
                    studentIdController: _studentIdController,
                  ),
                ],
              ],
            ),
          ),
          const Gap(8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (_selectedFiles.isEmpty) ...[
                _PrinterFileCard(
                  title: 'Choose Files',
                  subtitle: '0 MB • Files',
                  isEmpty: true,
                  onTap: !_busy ? _pickPrintFile : null,
                  borderRadius: 16,
                  emptyAction: Align(
                    alignment: Alignment.centerRight,
                    child: SizedBox(
                      width: 168,
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerRight,
                        child: BracuActionButton(
                          onPressed: _busy ? null : _loadBlankPage,
                          label: 'Blank Page',
                          icon: Icons.download_rounded,
                          iconGap: 0,
                          foregroundColor: BracuPalette.textPrimary(context),
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
                  ),
                ),
              ] else ...[
                for (int i = 0; i < _selectedFiles.length; i++) ...[
                  _PrinterFileCard(
                    title: _selectedFiles[i].name,
                    subtitle:
                        '${_formatFileSizeMb(_selectedFiles[i].bytes)} • ${_fileKindLabelFor(_selectedFiles[i])}',
                    isEmpty: false,
                    onTap: null,
                    onClear: !_busy ? () => _clearFileAt(i) : null,
                    borderRadius: 16,
                  ),
                  if (i < _selectedFiles.length - 1) const Gap(12),
                ],
              ],
              const Gap(8),
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
              const Gap(8),
              _PrinterLayoutPreferencesPanel(
                pagesPerSheet: _pagesPerSheet,
                fittingMode: _fittingMode,
                staple: _staple,
                punch: _punch,
                jobOffset: _jobOffset,
                slipSheet: _slipSheet,
                booklet: _booklet,
                onPagesPerSheetChanged: (value) {
                  setState(() {
                    _pagesPerSheet = value;
                  });
                  unawaited(_savePrinterPreferences());
                },
                onFittingModeChanged: (value) {
                  setState(() {
                    _fittingMode = value;
                  });
                  unawaited(_savePrinterPreferences());
                },
                onStapleChanged: (value) {
                  setState(() {
                    _staple = value;
                  });
                  unawaited(_savePrinterPreferences());
                },
                onPunchChanged: (value) {
                  setState(() {
                    _punch = value;
                  });
                  unawaited(_savePrinterPreferences());
                },
                onJobOffsetChanged: (value) {
                  setState(() {
                    _jobOffset = value;
                  });
                  unawaited(_savePrinterPreferences());
                },
                onSlipSheetChanged: (value) {
                  setState(() {
                    _slipSheet = value;
                  });
                  unawaited(_savePrinterPreferences());
                },
                onBookletChanged: (value) {
                  setState(() {
                    _booklet = value;
                  });
                  unawaited(_savePrinterPreferences());
                },
              ),
              const Gap(12),
              Row(
                children: [
                  Expanded(
                    child: BracuActionButton(
                      onPressed: _busy ? null : _pickPrintFile,
                      icon: Icons.picture_as_pdf_outlined,
                      label: 'Choose',
                    ),
                  ),
                  const Gap(12),
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
                const Gap(12),
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
          const Gap(12),
          _PrintHistoryCard(history: _history),
        ],
      ),
    );
  }

  void _showHelpBottomSheet(BuildContext context) {
    showBracuBottomSheet<void>(
      context,
      title: 'Printer Instructions',
      initialChildSize: 0.75,
      builder: (sheetContext, textPrimary, textSecondary) {
        final dragController = bracuBottomSheetScrollController(sheetContext);
        return ListView(
          controller: dragController,
          physics: const ClampingScrollPhysics(),
          padding: const EdgeInsets.only(bottom: 24),
          children: [
            _buildStepItem(
              context,
              stepNumber: '1',
              title: 'Connect to Wi-Fi',
              body:
                  'Make sure your device is connected to the Student-WiFi or university network.',
            ),
            const Gap(12),
            _buildStepItem(
              context,
              stepNumber: '2',
              title: 'Set Student ID',
              body:
                  'Ensure your student ID is entered correctly in the printer identity section above.',
            ),
            const Gap(12),
            _buildStepItem(
              context,
              stepNumber: '3',
              title: 'Choose Documents',
              body:
                  'Pick the files you want to print. You can select multiple PDF, JPEG, or PNG files.',
            ),
            const Gap(12),
            _buildStepItem(
              context,
              stepNumber: '4',
              title: 'Send Print Job',
              body: 'Tap the Print button. Files will be sent sequentially ',
            ),
            const Gap(12),
            _buildStepItem(
              context,
              stepNumber: '5',
              title: 'Release Document',
              body:
                  'Tap your physical ID card on any campus card-reader printer to release and print the files.',
            ),
            const Gap(16),
            Text(
              'Connection Status',
              style: TextStyle(
                color: textPrimary,
                fontSize: 16,
                fontWeight: FontWeight.w800,
              ),
            ),
            const Gap(12),
            _buildStepItem(
              context,
              stepNumber: '•',
              title: 'Connected',
              body:
                  'The printer is connected and ready. Your print job will be sent instantly.',
            ),
            const Gap(12),
            _buildStepItem(
              context,
              stepNumber: '•',
              title: 'Not found',
              body: 'No printer found on your network.',
            ),
            const Gap(12),
            _buildStepItem(
              context,
              stepNumber: '•',
              title: 'Offline',
              body: 'Your device has no active internet connection.',
            ),
            const Gap(16),
            Text(
              'Layout & Print Options',
              style: TextStyle(
                color: textPrimary,
                fontSize: 16,
                fontWeight: FontWeight.w800,
              ),
            ),
            const Gap(12),
            _buildStepItem(
              context,
              stepNumber: '•',
              title: 'Copies',
              body:
                  'Specify the exact number of page copies to print by tapping the minus/plus buttons or typing directly.',
            ),
            const Gap(12),
            _buildStepItem(
              context,
              stepNumber: '•',
              title: 'Duplex Mode - One or Both Side',
              body:
                  'Toggle between single-sided or double-sided printing to save paper.',
            ),
            const Gap(12),
            _buildStepItem(
              context,
              stepNumber: '•',
              title: 'Collate Mode',
              body:
                  'Sort pages in multi-page documents sequentially instead of grouping identical pages.',
            ),
            const Gap(12),
            _buildStepItem(
              context,
              stepNumber: '•',
              title: 'Pages Per Sheet',
              body:
                  'Choose "1-in-1" (default) for standard layout. Use "2-in-1" or "4-in-1" to fit multiple pages on a single sheet of paper to save page quota.',
            ),
            const Gap(12),
            _buildStepItem(
              context,
              stepNumber: '•',
              title: 'Fitting Mode',
              body:
                  'Select "Fit Paper" (default) for normal margins, "Fit Printable" to shrink to margins, or "Edge-to-Edge" to print borderless full pages.',
            ),
            const Gap(12),
            _buildStepItem(
              context,
              stepNumber: '•',
              title: 'Stapling & Hole Punching',
              body:
                  'Configure staple location or punch hole counts for automatic document binding.',
            ),
            const Gap(12),
            _buildStepItem(
              context,
              stepNumber: '•',
              title: 'Offset & Slip Sheets',
              body:
                  'Toggle "Offset" to shift printed sets sideways for easy separation. Toggle "Slip Sheet" to insert blank separator sheets between print jobs.',
            ),
            const Gap(12),
            _buildStepItem(
              context,
              stepNumber: '•',
              title: 'Booklet Printing',
              bodyWidget: Text.rich(
                TextSpan(
                  style: TextStyle(
                    color: textSecondary,
                    fontSize: 12,
                    height: 1.4,
                    fontWeight: FontWeight.w500,
                  ),
                  children: [
                    const TextSpan(
                      text:
                          'Enable "Booklet" to auto-impose document pages, fold them down the center, and saddle-stitch them like a booklet/pamphlet.\n',
                    ),
                    TextSpan(
                      text: 'Note: ',
                      style: TextStyle(
                        color: textSecondary,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const TextSpan(
                      text:
                          'Total pages should be a multiple of 4 for ideal saddle stitching.',
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildStepItem(
    BuildContext context, {
    required String stepNumber,
    required String title,
    String? body,
    Widget? bodyWidget,
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
              bodyWidget ??
                  Text(
                    body ?? '',
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
            if (index != history.length - 1) const Gap(8),
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
    final copiesLabel = entry.copies == 1 ? '1 Copy' : '${entry.copies} Copies';
    return _PrinterFileCard(
      title: entry.fileName,
      subtitle:
          '${entry.status} • $copiesLabel • ${formatDateTimeLabel(entry.createdAt)}',
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
    final content = BracuCard(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
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
                const Gap(2),
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
          const Gap(8),
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
    this.queue = 'secure',
  });

  final String host;
  final int port;
  final String queue;
  static const Duration _timeout = Duration(seconds: 5);
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

    final printerQueue = queue;
    final owner = user;
    const client = 'PreConnect-App';
    final safeFileName = fileName.trim();
    final printableJobName = _basePrintName(safeFileName);
    final isPostScript = _looksLikePostScript(safeFileName, bytes);
    final dataCommand = isPostScript ? 'o' : 'f';
    final copies = preferences.copies.clamp(0, 999);
    final duplexMode = preferences.duplexMode.trim().toUpperCase();

    try {
      final Uint8List sendBytes;
      if (isPostScript) {
        sendBytes = Uint8List.fromList([
          ..._ascii(preferences.postScriptPreamble),
          ...bytes,
        ]);
      } else if (_isJpegFile(fileName)) {
        sendBytes = _wrapJpegInPdf(bytes);
      } else {
        sendBytes = bytes;
      }
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

      final collateMode = preferences.collateMode.trim().toUpperCase();
      final pjlPrefix = HttpUtils.pjlPrefix(
        jobName: printableJobName,
        copies: copies,
        duplexMode: duplexMode,
        collateMode: collateMode,
        isPostScript: isPostScript,
        pagesPerSheet: preferences.pagesPerSheet,
        fittingMode: preferences.fittingMode,
        staple: preferences.staple,
        punch: preferences.punch,
        jobOffset: preferences.jobOffset,
        slipSheet: preferences.slipSheet,
        booklet: preferences.booklet,
      );
      final payload = _buildPjlPayload(bytes: sendBytes, prefix: pjlPrefix);

      await _sendLprJob(
        printerHost: printerHost,
        printerQueue: printerQueue,
        controlFileName: controlFileName,
        dataFileName: dataFileName,
        control: control,
        payload: payload,
        studentId: user,
      );
    } on _LprPrintException {
      rethrow;
    } on TimeoutException {
      throw const _LprPrintException(_errPrinterConnectionTimedOut);
    } on SocketException catch (error) {
      throw _LprPrintException(error.message);
    }
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

  String _jobSuffix() {
    final number = DateTime.now().microsecondsSinceEpoch % 1000;
    return number.toString().padLeft(3, '0');
  }

  Future<void> _sendLprJob({
    required String printerHost,
    required String printerQueue,
    required String controlFileName,
    required String dataFileName,
    required List<int> control,
    required Uint8List payload,
    String studentId = '',
  }) async {
    Socket? socket;
    _LprAckReader? ackReader;
    try {
      try {
        Socket? connectedSocket;
        if (printerHost.trim().isNotEmpty) {
          try {
            connectedSocket = await Socket.connect(
              printerHost,
              port,
              timeout: const Duration(seconds: 1),
            );
          } catch (_) {}
        }
        if (connectedSocket == null) {
          final url = Uri.parse('${ApiConfig.realtimeApiBase}/print');
          final gzippedPayload = GZipCodec().encode(payload);
          final response = await HttpUtils.client
              .post(
                url,
                headers: <String, String>{
                  'Accept': 'application/json',
                  'Connection': 'keep-alive',
                  'Content-Type': 'application/octet-stream',
                  'Content-Encoding': 'gzip',
                  'X-Control-File': base64Encode(control),
                  'X-Printer-Host': printerHost.trim().isNotEmpty
                      ? printerHost.trim()
                      : _CampusPrinterConfig.current.hosts.first,
                  'X-Printer-Queue': printerQueue.trim().isNotEmpty
                      ? printerQueue.trim()
                      : _CampusPrinterConfig.current.queue,
                  'X-Worker-OS': kIsWeb ? 'web' : Platform.operatingSystem,
                  'X-Device-OS': kIsWeb ? 'web' : Platform.operatingSystem,
                  if (studentId.isNotEmpty) 'X-Student-ID': studentId,
                },
                body: gzippedPayload,
              )
              .timeout(const Duration(minutes: 3));
          final Map<String, dynamic> data = response.body.isNotEmpty
              ? (jsonDecode(response.body) as Map<String, dynamic>)
              : <String, dynamic>{};
          if (response.statusCode != 200 || data['success'] == false) {
            final serverErr = data['error']?.toString().trim() ?? '';
            unawaited(
              AppLog.write(
                'Printer Job: Relay failed ($printerHost) - $serverErr',
              ),
            );
            if (serverErr.isNotEmpty) {
              throw _LprPrintException(serverErr);
            }
            throw const _LprPrintException(
              _CampusPrinterPageState._snackPrinterConnectionFailed,
            );
          }
          unawaited(
            AppLog.write(
              'Printer Job: Delivered via relay API ($printerHost, bytes: ${payload.length})',
            ),
          );
          return;
        }
        final activeSocket = connectedSocket;
        socket = activeSocket;
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
        final dynamicTimeout = Duration(
          seconds: (30 + (payload.length / (1024 * 1024)) * 10).toInt().clamp(
            30,
            600,
          ),
        );
        socket.add(payload);
        socket.add(const <int>[0x00]);
        await socket.flush().timeout(dynamicTimeout);
        final ack = await ackReader.readByte().timeout(dynamicTimeout);
        if (ack != 0) {
          unawaited(
            AppLog.write(
              'Printer Job: Direct socket rejected by printer ($printerHost, ack: $ack)',
            ),
          );
          throw const _LprPrintException(_errPrinterRejectedJob);
        }
        unawaited(
          AppLog.write(
            'Printer Job: Delivered via direct TCP socket ($printerHost, bytes: ${payload.length})',
          ),
        );
        await ackReader.cancel();
        await socket.close();
        return;
      } catch (e) {
        if (e is _LprPrintException) rethrow;
        throw const _LprPrintException(
          _CampusPrinterPageState._snackPrinterConnectionFailed,
        );
      }
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
              flex: 32,
              child: Container(
                height: controlHeight,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      flex: 42,
                      child: BracuActionButton(
                        onPressed: copies <= 0 ? null : () => onCopiesStep(-1),
                        outlined: false,
                        borderRadius: 12,
                        padding: EdgeInsets.zero,
                        label: '−',
                        fontSize: controlFont,
                      ),
                    ),
                    Expanded(
                      flex: 52,
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
                        style: TextStyle(
                          fontSize: compact ? 16 : 18,
                          fontWeight: FontWeight.w700,
                          color: BracuPalette.textPrimary(context),
                        ),
                        decoration: const InputDecoration(
                          border: InputBorder.none,
                          isDense: true,
                          contentPadding: EdgeInsets.zero,
                        ),
                      ),
                    ),
                    Expanded(
                      flex: 42,
                      child: BracuActionButton(
                        onPressed: copies >= 999 ? null : () => onCopiesStep(1),
                        outlined: false,
                        borderRadius: 12,
                        padding: EdgeInsets.zero,
                        label: '+',
                        fontSize: controlFont,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Gap(compact ? 8 : 10),
            Expanded(
              flex: 68,
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
                      borderRadius: 12,
                      padding: togglePadding,
                      label: duplexEnabled ? 'Both Side' : 'One Side',
                      fontSize: toggleFont,
                    ),
                  ),
                  Gap(gap),
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
                      borderRadius: 12,
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

class _PrinterLayoutPreferencesPanel extends StatelessWidget {
  const _PrinterLayoutPreferencesPanel({
    required this.pagesPerSheet,
    required this.fittingMode,
    required this.staple,
    required this.punch,
    required this.jobOffset,
    required this.slipSheet,
    required this.booklet,
    required this.onPagesPerSheetChanged,
    required this.onFittingModeChanged,
    required this.onStapleChanged,
    required this.onPunchChanged,
    required this.onJobOffsetChanged,
    required this.onSlipSheetChanged,
    required this.onBookletChanged,
  });

  final String pagesPerSheet;
  final String fittingMode;
  final String staple;
  final String punch;
  final String jobOffset;
  final String slipSheet;
  final String booklet;
  final ValueChanged<String> onPagesPerSheetChanged;
  final ValueChanged<String> onFittingModeChanged;
  final ValueChanged<String> onStapleChanged;
  final ValueChanged<String> onPunchChanged;
  final ValueChanged<String> onJobOffsetChanged;
  final ValueChanged<String> onSlipSheetChanged;
  final ValueChanged<String> onBookletChanged;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 420;
        final gap = compact ? 6.0 : 8.0;
        final toggleFont = compact ? 12.0 : 13.0;
        final buttonPadding = EdgeInsets.symmetric(
          horizontal: compact ? 4 : 6,
          vertical: compact ? 8 : 9,
        );

        return Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: Padding(
                    padding: EdgeInsets.symmetric(horizontal: gap / 2),
                    child: BracuActionButton(
                      onPressed: () {
                        final nextVal = pagesPerSheet == '1-in-1'
                            ? '2-in-1'
                            : (pagesPerSheet == '2-in-1' ? '4-in-1' : '1-in-1');
                        onPagesPerSheetChanged(nextVal);
                      },
                      outlined: true,
                      backgroundColor: pagesPerSheet != '1-in-1'
                          ? BracuPalette.primary.withValues(alpha: 0.12)
                          : Colors.transparent,
                      foregroundColor: pagesPerSheet != '1-in-1'
                          ? BracuPalette.primary
                          : BracuPalette.textPrimary(context),
                      borderRadius: 12,
                      padding: buttonPadding,
                      label: pagesPerSheet,
                      fontSize: toggleFont,
                    ),
                  ),
                ),
                Gap(gap),
                Expanded(
                  child: Padding(
                    padding: EdgeInsets.symmetric(horizontal: gap / 2),
                    child: BracuActionButton(
                      onPressed: () {
                        final nextVal = fittingMode == 'Fit on Paper'
                            ? 'Fit on Printable Area'
                            : (fittingMode == 'Fit on Printable Area'
                                  ? 'Edge-to-Edge'
                                  : 'Fit on Paper');
                        onFittingModeChanged(nextVal);
                      },
                      outlined: true,
                      backgroundColor: fittingMode != 'Fit on Paper'
                          ? BracuPalette.primary.withValues(alpha: 0.12)
                          : Colors.transparent,
                      foregroundColor: fittingMode != 'Fit on Paper'
                          ? BracuPalette.primary
                          : BracuPalette.textPrimary(context),
                      borderRadius: 12,
                      padding: buttonPadding,
                      label: fittingMode == 'Fit on Paper'
                          ? 'Fit Paper'
                          : (fittingMode == 'Fit on Printable Area'
                                ? 'Fit Printable'
                                : 'Edge-to-Edge'),
                      fontSize: toggleFont,
                    ),
                  ),
                ),
              ],
            ),
            Gap(gap),
            Row(
              children: [
                Expanded(
                  child: Padding(
                    padding: EdgeInsets.symmetric(horizontal: gap / 2),
                    child: BracuActionButton(
                      onPressed: () {
                        final nextVal = staple == 'Off'
                            ? 'Left Corner'
                            : (staple == 'Left Corner'
                                  ? 'Right Corner'
                                  : 'Off');
                        onStapleChanged(nextVal);
                      },
                      outlined: true,
                      backgroundColor: staple != 'Off'
                          ? BracuPalette.primary.withValues(alpha: 0.12)
                          : Colors.transparent,
                      foregroundColor: staple != 'Off'
                          ? BracuPalette.primary
                          : BracuPalette.textPrimary(context),
                      borderRadius: 12,
                      padding: buttonPadding,
                      label: staple == 'Off'
                          ? 'Staple Off'
                          : (staple == 'Left Corner'
                                ? 'Staple Left'
                                : 'Staple Right'),
                      fontSize: toggleFont,
                    ),
                  ),
                ),
                Gap(gap),
                Expanded(
                  child: Padding(
                    padding: EdgeInsets.symmetric(horizontal: gap / 2),
                    child: BracuActionButton(
                      onPressed: () {
                        final nextVal = punch == 'Off'
                            ? '2 Holes'
                            : (punch == '2 Holes' ? '3 Holes' : 'Off');
                        onPunchChanged(nextVal);
                      },
                      outlined: true,
                      backgroundColor: punch != 'Off'
                          ? BracuPalette.primary.withValues(alpha: 0.12)
                          : Colors.transparent,
                      foregroundColor: punch != 'Off'
                          ? BracuPalette.primary
                          : BracuPalette.textPrimary(context),
                      borderRadius: 12,
                      padding: buttonPadding,
                      label: punch == 'Off' ? 'Punch Off' : punch,
                      fontSize: toggleFont,
                    ),
                  ),
                ),
              ],
            ),
            Gap(gap),
            Row(
              children: [
                Expanded(
                  child: Padding(
                    padding: EdgeInsets.symmetric(horizontal: gap / 2),
                    child: BracuActionButton(
                      onPressed: () {
                        onJobOffsetChanged(jobOffset == 'On' ? 'Off' : 'On');
                      },
                      outlined: true,
                      backgroundColor: jobOffset == 'On'
                          ? BracuPalette.primary.withValues(alpha: 0.12)
                          : Colors.transparent,
                      foregroundColor: jobOffset == 'On'
                          ? BracuPalette.primary
                          : BracuPalette.textPrimary(context),
                      borderRadius: 12,
                      padding: buttonPadding,
                      label: 'Offset',
                      fontSize: toggleFont,
                    ),
                  ),
                ),
                Gap(gap),
                Expanded(
                  child: Padding(
                    padding: EdgeInsets.symmetric(horizontal: gap / 2),
                    child: BracuActionButton(
                      onPressed: () {
                        onSlipSheetChanged(slipSheet == 'On' ? 'Off' : 'On');
                      },
                      outlined: true,
                      backgroundColor: slipSheet == 'On'
                          ? BracuPalette.primary.withValues(alpha: 0.12)
                          : Colors.transparent,
                      foregroundColor: slipSheet == 'On'
                          ? BracuPalette.primary
                          : BracuPalette.textPrimary(context),
                      borderRadius: 12,
                      padding: buttonPadding,
                      label: 'Slip Sheet',
                      fontSize: toggleFont,
                    ),
                  ),
                ),
                Gap(gap),
                Expanded(
                  child: Padding(
                    padding: EdgeInsets.symmetric(horizontal: gap / 2),
                    child: BracuActionButton(
                      onPressed: () {
                        onBookletChanged(booklet == 'On' ? 'Off' : 'On');
                      },
                      outlined: true,
                      backgroundColor: booklet == 'On'
                          ? BracuPalette.primary.withValues(alpha: 0.12)
                          : Colors.transparent,
                      foregroundColor: booklet == 'On'
                          ? BracuPalette.primary
                          : BracuPalette.textPrimary(context),
                      borderRadius: 12,
                      padding: buttonPadding,
                      label: 'Booklet',
                      fontSize: toggleFont,
                    ),
                  ),
                ),
              ],
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
    required this.pagesPerSheet,
    required this.fittingMode,
    required this.staple,
    required this.punch,
    required this.jobOffset,
    required this.slipSheet,
    required this.booklet,
  });

  final int copies;
  final String duplexMode;
  final String collateMode;
  final String pagesPerSheet;
  final String fittingMode;
  final String staple;
  final String punch;
  final String jobOffset;
  final String slipSheet;
  final String booklet;

  String get postScriptPreamble => '%!PS-Adobe-3.0';

  bool get hasAdvancedFinishingOptions {
    return staple != 'Off' ||
        punch != 'Off' ||
        booklet == 'On' ||
        pagesPerSheet != '1-in-1' ||
        fittingMode != 'Fit on Paper' ||
        jobOffset == 'On' ||
        slipSheet == 'On' ||
        duplexMode != 'OFF' ||
        collateMode == 'ON';
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

class _WifiPrinterDiscovery {
  _WifiPrinterDiscovery._();

  static Future<bool> _probe(String address, int port, Duration timeout) async {
    Socket? socket;
    try {
      socket = await Socket.connect(address, port, timeout: timeout);
      unawaited(AppLog.write('Printer Socket Probe Success: $address:$port'));
      return true;
    } catch (_) {
      return false;
    } finally {
      socket?.destroy();
    }
  }

  static Future<List<_Ipv4Subnet>> _localIpv4Subnets() async {
    if (kIsWeb) return <_Ipv4Subnet>[];
    final subnets = <_Ipv4Subnet>[];
    final seen = <String>{};
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLoopback: false,
      );
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
    } catch (_) {}
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

Uint8List _wrapJpegInPdf(Uint8List jpegBytes) {
  int width = 595;
  int height = 842;

  if (jpegBytes.length > 4) {
    for (int i = 0; i < jpegBytes.length - 8; i++) {
      if (jpegBytes[i] == 0xFF &&
          (jpegBytes[i + 1] == 0xC0 || jpegBytes[i + 1] == 0xC2)) {
        height = (jpegBytes[i + 5] << 8) + jpegBytes[i + 6];
        width = (jpegBytes[i + 7] << 8) + jpegBytes[i + 8];
        break;
      }
    }
  }

  const obj1 = '1 0 obj\n<< /Type /Catalog /Pages 2 0 R >>\nendobj\n';
  const obj2 = '2 0 obj\n<< /Type /Pages /Kids [3 0 R] /Count 1 >>\nendobj\n';
  const obj3 =
      '3 0 obj\n<< /Type /Page /Parent 2 0 R /MediaBox [0 0 595 842] /Contents 4 0 R /Resources << /XObject << /Im1 5 0 R >> >> >>\nendobj\n';
  const obj4Stream = 'q 595 0 0 842 0 0 cm /Im1 Do Q\n';
  final obj4 =
      '4 0 obj\n<< /Length ${obj4Stream.length} >>\nstream\n${obj4Stream}endstream\nendobj\n';

  final header = ascii.encode('%PDF-1.4\n');
  final b1 = ascii.encode(obj1);
  final b2 = ascii.encode(obj2);
  final b3 = ascii.encode(obj3);
  final b4 = ascii.encode(obj4);

  final obj5Header = ascii.encode(
    '5 0 obj\n<< /Type /XObject /Subtype /Image /Width $width /Height $height /ColorSpace /DeviceRGB /BitsPerComponent 8 /Filter /DCTDecode /Length ${jpegBytes.length} >>\nstream\n',
  );
  final obj5Footer = ascii.encode('\nendstream\nendobj\n');

  final offset1 = header.length;
  final offset2 = offset1 + b1.length;
  final offset3 = offset2 + b2.length;
  final offset4 = offset3 + b3.length;
  final offset5 = offset4 + b4.length;
  final startXref =
      offset5 + obj5Header.length + jpegBytes.length + obj5Footer.length;

  final xrefStr =
      'xref\n0 6\n0000000000 65535 f \n'
      '${offset1.toString().padLeft(10, '0')} 00000 n \n'
      '${offset2.toString().padLeft(10, '0')} 00000 n \n'
      '${offset3.toString().padLeft(10, '0')} 00000 n \n'
      '${offset4.toString().padLeft(10, '0')} 00000 n \n'
      '${offset5.toString().padLeft(10, '0')} 00000 n \n'
      'trailer\n<< /Size 6 /Root 1 0 R >>\nstartxref\n$startXref\n%%EOF\n';

  final builder = BytesBuilder(copy: false)
    ..add(header)
    ..add(b1)
    ..add(b2)
    ..add(b3)
    ..add(b4)
    ..add(obj5Header)
    ..add(jpegBytes)
    ..add(obj5Footer)
    ..add(ascii.encode(xrefStr));

  return builder.takeBytes();
}
