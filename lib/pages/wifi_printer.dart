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
import 'package:preconnect/tools/print_compose.dart';
import 'package:preconnect/tools/in_flight.dart';
import 'package:preconnect/tools/print_layout.dart';
import 'package:preconnect/tools/print_options.dart';
import 'package:preconnect/tools/storage_keys.dart';
import 'package:preconnect/tools/app_log.dart';
import 'package:preconnect/tools/string_utils.dart';

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
  static const String duplexKey = 'campus_printer_duplex';
  static const String collateKey = 'campus_printer_collate';
  static const String lastHostKey = 'campus_printer_last_host';
  static const String cachedBlankPagePdfKey = 'cached_blank_page_pdf';

  static Future<void> clearStoredState() async {
    await AppStorage.instance.remove(copiesKey);
    await AppStorage.instance.remove(duplexKey);
    await AppStorage.instance.remove(collateKey);
    await AppStorage.instance.remove(historyKey);
    await AppStorage.instance.remove(lastHostKey);
    await AppStorage.instance.remove(StorageKeys.studentId);
    await AppStorage.instance.remove(StorageKeys.fullName);
    await AppStorage.instance.remove(StorageKeys.shortCode);
    await AppStorage.instance.remove(StorageKeys.currentSemester);
    await AppStorage.instance.remove(cachedBlankPagePdfKey);
    await AppStorage.instance.remove('campus_printer_nup');
    await AppStorage.instance.remove('campus_printer_fit');
    await AppStorage.instance.remove('campus_printer_staple');
    await AppStorage.instance.remove('campus_printer_punch');
    await AppStorage.instance.remove('campus_printer_joboffset');
    await AppStorage.instance.remove('campus_printer_slipsheet');
    await AppStorage.instance.remove('campus_printer_booklet');
    invalidateCache();
  }

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
<< /Length 108 >>
stream
0 0 0 rg
10 831 0.5 0.5 re
584 831 0.5 0.5 re
297.25 420.75 0.5 0.5 re
10 10 0.5 0.5 re
584 10 0.5 0.5 re
f
endstream
endobj
xref
0 5
0000000000 65535 f 
0000000009 00000 n 
0000000058 00000 n 
0000000115 00000 n 
0000000218 00000 n 
trailer
<< /Size 5 /Root 1 0 R >>
startxref
376
%%EOF
''';
    return Uint8List.fromList(utf8.encode(pdfString));
  }

  static Future<void> _preloadBlankPage() async {
    cachedBlankPageBytes ??= _createLocalBlankPdf();
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

  static Future<bool> _isSignedIn() async {
    try {
      return await AuthService().isLoggedIn();
    } catch (error) {
      unawaited(AppLog.write('Printer sign-in check failed: $error'));
      return false;
    }
  }

  static Future<Map<String, String?>?> _loadProfile() async {
    try {
      return await ProfileService().getProfile();
    } catch (error) {
      unawaited(AppLog.write('Printer profile load failed: $error'));
      return null;
    }
  }

  static Future<_CampusPrinterBootstrap> _loadBootstrap() async {
    final storage = AppStorage.instance;
    final (copiesRaw, history, profile, isLoggedIn, saved) = await (
      storage.getInt('campus_printer_copies'),
      _loadHistorySnapshot(),
      _loadProfile(),
      _isSignedIn(),
      Future.wait<String?>([
        storage.getString(StorageKeys.studentId),
        storage.getString(StorageKeys.fullName),
        storage.getString(StorageKeys.shortCode),
        storage.getString(StorageKeys.currentSemester),
        storage.getString(duplexKey),
        storage.getString(collateKey),
        storage.getString('campus_printer_nup'),
        storage.getString('campus_printer_fit'),
        storage.getString('campus_printer_staple'),
        storage.getString('campus_printer_punch'),
        storage.getString('campus_printer_joboffset'),
        storage.getString('campus_printer_slipsheet'),
        storage.getString('campus_printer_booklet'),
      ]),
    ).wait;
    String identity(String key, String? stored) =>
        (profile?[key] ?? stored ?? '').trim();
    final studentId = identity('studentId', saved[0]);
    final fullName = identity('fullName', saved[1]);
    final shortCode = identity('shortCode', saved[2]);
    final currentSemester = identity('currentSemester', saved[3]);
    if (isLoggedIn && fullName.isNotEmpty) {
      await Future.wait<void>([
        storage.setString(StorageKeys.studentId, studentId),
        storage.setString(StorageKeys.fullName, fullName),
        storage.setString(StorageKeys.shortCode, shortCode),
        if (currentSemester.isNotEmpty)
          storage.setString(StorageKeys.currentSemester, currentSemester),
      ]);
    }
    final copiesValue = copiesRaw == null ? 1 : copiesRaw.clamp(1, 999);
    return _CampusPrinterBootstrap(
      copies: copiesValue,
      history: history,
      studentId: studentId,
      studentName: fullName,
      studentShortCode: shortCode,
      currentSemester: currentSemester,
      duplexMode: saved[4] ?? 'OFF',
      collateMode: saved[5] ?? 'OFF',
      pagesPerSheet: saved[6] ?? '1-in-1',
      fittingMode: saved[7] ?? 'Fit on Paper',
      staple: saved[8] ?? 'Off',
      punch: saved[9] ?? 'Off',
      jobOffset: saved[10] ?? 'Off',
      slipSheet: saved[11] ?? 'Off',
      booklet: saved[12] ?? 'Off',
      profile: profile,
      photoUrl: ApiConfig.photoUrl(profile?['photoFilePath']),
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
  String _pageRange = '';
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
      _duplexMode = bootstrap.duplexMode;
      _collateMode = bootstrap.collateMode;
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
      _duplexMode = bootstrap.duplexMode;
      _collateMode = bootstrap.collateMode;
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
    _warmPrepared();
    CampusPrinterPage.invalidateCache();
    await AppStorage.instance.setInt(_copiesKey, _copies);
    await AppStorage.instance.setString(
      CampusPrinterPage.duplexKey,
      _duplexMode,
    );
    await AppStorage.instance.setString(
      CampusPrinterPage.collateKey,
      _collateMode,
    );
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
    _warmTimer?.cancel();
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
          .timeout(const Duration(seconds: 10));
      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body);
        if (decoded is Map) {
          return decoded['status'] == 'online';
        }
        return false;
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

      final directHost = _CampusPrinterConfig.current.hosts.first;
      final directPort = _CampusPrinterConfig.current.port;

      final connectionCompleter = Completer<void>();

      final directProbeFuture = _WifiPrinterDiscovery._probe(
        directHost,
        directPort,
        const Duration(seconds: 10),
      );
      final workerStatusFuture = _checkWorkerStatus();

      var directPrinterOnline = false;
      var workerOnline = false;

      final directFuture = directProbeFuture
          .then((online) {
            directPrinterOnline = online;
            if (online && mounted) {
              setState(() {
                _printerHost = directHost;
                _workerAvailable = false;
                _discovering = false;
              });
              if (!connectionCompleter.isCompleted) {
                connectionCompleter.complete();
              }
            }
          })
          .catchError((_) {});

      final workerFuture = workerStatusFuture
          .then((online) {
            workerOnline = online;
            if (online && !directPrinterOnline && mounted) {
              setState(() {
                _printerHost = '';
                _workerAvailable = true;
                _discovering = false;
              });
              if (!connectionCompleter.isCompleted) {
                connectionCompleter.complete();
              }
            }
          })
          .catchError((_) {});

      final allDone = Future.wait([directFuture, workerFuture]);

      await Future.any([connectionCompleter.future, allDone]);

      if (mounted && _discovering) {
        setState(() {
          if (directPrinterOnline) {
            _printerHost = directHost;
            _workerAvailable = false;
          } else {
            _printerHost = '';
            _workerAvailable = workerOnline;
          }
          _discovering = false;
        });
      }
    } catch (e) {
      await AppLog.write('Printer discovery failed: $e');
    } finally {
      if (mounted && _discovering) {
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
            selected.pageCount =
                await PrintComposer.pageCount(bytes) ??
                (await _readPdfInfo(bytes)).pageCount;
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
      _warmPrepared();
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

  PrintComposeOptions get _composeOptions => PrintComposeOptions(
    pagesPerSheet: _pagesPerSheet,
    fittingMode: _fittingMode,
    booklet: _booklet == 'On',
    pageRange: _pageRange,
  );

  final Expando<Map<String, _PreparedPrint>> _preparedCache = Expando();
  final Expando<InFlight<String, _PreparedPrint>> _preparing = Expando();
  Timer? _warmTimer;

  void _warmPrepared() {
    if (kIsWeb) return;
    _warmTimer?.cancel();
    _warmTimer = Timer(const Duration(milliseconds: 500), () {
      if (!mounted || _busy) return;
      for (final file in _selectedFiles) {
        unawaited(
          _prepare(file).then<void>(
            (_) {},
            onError: (Object error) {
              unawaited(AppLog.write('Print warm-up failed: $error'));
            },
          ),
        );
      }
    });
  }

  Future<_PreparedPrint> _prepare(_SelectedFile file) {
    final key = '$_pagesPerSheet|$_fittingMode|$_booklet|$_pageRange';
    final cached = _preparedCache[file]?[key];
    if (cached != null) return SynchronousFuture(cached);
    final options = _composeOptions;
    return (_preparing[file] ??= InFlight<String, _PreparedPrint>()).run(
      key,
      () => _prepareNow(file, key, options),
    );
  }

  Future<_PreparedPrint> _prepareNow(
    _SelectedFile file,
    String key,
    PrintComposeOptions options,
  ) async {
    final isImage = _isJpegFile(file.name) || _isPngFile(file.name);
    if (!isImage && !_isPdfFile(file.name, file.bytes)) {
      return _PreparedPrint(
        bytes: file.bytes,
        fileName: file.name,
        baked: false,
        previewable: false,
      );
    }
    final source = isImage
        ? await PrintComposer.imagePdf(file.bytes)
        : file.bytes;
    final composed = await PrintComposer.compose(source, options);
    final prepared = _PreparedPrint(
      bytes: composed?.bytes ?? source,
      fileName: isImage ? '${_basePrintName(file.name)}.pdf' : file.name,
      baked: composed != null,
      previewable: true,
    );
    _preparedCache[file] = {key: prepared};
    return prepared;
  }

  Future<void> _editPageRange() async {
    final value = await showAppBottomSheet<String>(
      context,
      title: 'Pages',
      initialChildSize: 0.40,
      builder: (sheetContext, textPrimary, textSecondary) =>
          _PageRangeSheet(initial: _pageRange),
    );
    if (value == null || !mounted) return;
    setState(() => _pageRange = value);
    _warmPrepared();
  }

  Future<void> _showPreviewSheet(
    Future<List<Uint8List>> documents, {
    Future<Uint8List?>? firstPage,
    Uint8List? source,
  }) {
    return showAppCustomBottomSheet<void>(
      context: context,
      backgroundColor: AppPalette.card(context),
      initialChildSize: 0.92,
      builder: (sheetContext) {
        return SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 6, 18, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 36,
                    height: 3,
                    decoration: BoxDecoration(
                      color: AppPalette.textSecondary(
                        sheetContext,
                      ).withValues(alpha: 0.28),
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                ),
                const Gap(12),
                Expanded(
                  child: _PrintPreviewSheet(
                    documents: documents,
                    firstPage: firstPage,
                    source: source,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  bool _previewOpen = false;

  Future<List<Uint8List>> _previewDocuments(_SelectedFile file) async {
    final prepared = await _prepare(file);
    return prepared.previewable ? [prepared.bytes] : const [];
  }

  bool get _layoutUntouched =>
      PrintLayout.pagesPerSheetOf(_pagesPerSheet) == 1 &&
      _booklet != 'On' &&
      _pageRange.trim().isEmpty;

  Future<void> _previewFile(_SelectedFile file) async {
    if (_previewOpen || kIsWeb) return;
    _previewOpen = true;
    try {
      final quick =
          _layoutUntouched &&
              !_isJpegFile(file.name) &&
              !_isPngFile(file.name) &&
              _isPdfFile(file.name, file.bytes)
          ? PrintComposer.firstPage(file.bytes)
          : null;
      await _showPreviewSheet(
        _previewDocuments(file),
        firstPage: quick,
        source: file.bytes,
      );
    } finally {
      _previewOpen = false;
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
          final prepared = await _prepare(file);
          if (!mounted) return;
          await client.sendFile(
            bytes: prepared.bytes,
            fileName: prepared.fileName,
            user: user,
            clientName: clientName,
            preferences: prepared.baked
                ? preferences.withBakedLayout()
                : preferences,
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
        } on PrintComposeException catch (error) {
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
            showAppSnackBar(context, '${file.name}: ${error.message}');
          }
        } catch (error) {
          unawaited(AppLog.write('Print failed for ${file.name}: $error'));
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

    return AppPageScaffold(
      title: 'Printer',
      subtitle: printerSubtitle,
      subtitleColor: subtitleColor,
      icon: Icons.local_printshop_outlined,
      actions: [
        AppRefreshButton(
          onPressed: () => _refreshPrinterInfo(),
          isLoading: _discovering,
        ),
        IconButton(
          onPressed: () => _showHelpBottomSheet(context),
          style: appCompactIconButtonStyle(
            foregroundColor: AppPalette.primary,
            borderColor: Colors.transparent,
            padding: EdgeInsets.zero,
            borderRadius: 12,
          ),
          icon: const Icon(
            Icons.help_outline_rounded,
            color: AppPalette.primary,
          ),
          tooltip: 'Help',
        ),
      ],
      body: AppRefreshList(
        onRefresh: _refreshPrinterInfo,
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
        children: [
          if (_studentName.trim().isNotEmpty ||
              _studentId.trim().isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: CardSection(
                profile: _profile,
                photoUrl: _photoUrl,
                studentIdController: _studentIdController,
              ),
            ),
            const Gap(8),
          ],
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
                        child: AppActionButton(
                          onPressed: _busy ? null : _loadBlankPage,
                          label: 'Blank Page',
                          icon: Icons.download_rounded,
                          iconGap: 0,
                          foregroundColor: AppPalette.textPrimary(context),
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
                    onPreview: () => _previewFile(_selectedFiles[i]),
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
                  unawaited(_savePrinterPreferences());
                },
                onCollateChanged: (mode) {
                  setState(() => _collateMode = mode);
                  unawaited(_savePrinterPreferences());
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
                pageRange: _pageRange,
                onPageRangeTap: _editPageRange,
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
                    child: AppActionButton(
                      onPressed: _busy ? null : _pickPrintFile,
                      icon: Icons.picture_as_pdf_outlined,
                      label: 'Choose',
                    ),
                  ),
                  const Gap(12),
                  Expanded(
                    child: AppActionButton(
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
                  child: AppActionButton(
                    onPressed: _busy ? null : _clearHistory,
                    outlined: true,
                    backgroundColor: Colors.transparent,
                    foregroundColor: AppPalette.textSecondary(context),
                    label: 'Clear History',
                  ),
                ),
              ],
            ],
          ),
          const Gap(12),
          _buildEmailPrinting(context),
          if (_history.isNotEmpty) ...[
            const Gap(12),
            _PrintHistoryCard(history: _history),
          ],
          const Gap(16),
          Center(
            child: Text(
              "Making students' campus life better & easier.",
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AppPalette.textPrimary(context),
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmailPrinting(BuildContext context) {
    final emphasis = TextStyle(
      color: AppPalette.textPrimary(context),
      fontWeight: FontWeight.w700,
    );
    WidgetSpan emailLink(String label, String subject, {bool bold = false}) {
      return WidgetSpan(
        alignment: PlaceholderAlignment.baseline,
        baseline: TextBaseline.alphabetic,
        child: Semantics(
          link: true,
          child: InkWell(
            onTap: () => openMailComposer(
              context,
              'campus.printer@g.bracu.ac.bd',
              subject: subject,
            ),
            child: Text(
              label,
              style: TextStyle(
                color: AppPalette.primary,
                fontSize: 12,
                height: 1.4,
                fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ),
        ),
      );
    }

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Print By Email',
                  style: emphasis.copyWith(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Compose Email',
                icon: const Icon(Icons.mail_outline_rounded),
                color: AppPalette.primary,
                onPressed: () => openMailComposer(
                  context,
                  'campus.printer@g.bracu.ac.bd',
                  subject: 'Print documents',
                ),
              ),
            ],
          ),
          Text.rich(
            TextSpan(
              children: [
                const TextSpan(text: 'Printer '),
                TextSpan(text: 'not found', style: emphasis),
                const TextSpan(text: ' or '),
                TextSpan(text: 'off campus?', style: emphasis),
                const TextSpan(
                  text: ' Email from your @g.bracu.ac.bd account to ',
                ),
                emailLink(
                  'campus.printer@g.bracu.ac.bd',
                  'Print documents',
                  bold: true,
                ),
                const TextSpan(
                  text:
                      '.\n\nAttach PDF, DOCX, PPTX, or XLSX files (up to 25 MB total). Add ',
                ),
                emailLink('#duplex', '#duplex'),
                const TextSpan(
                  text:
                      ' to the subject line for double-sided printing.\n\n'
                      'Wait 3–5 minutes, then tap your ID card at a campus printer, '
                      'select your jobs, and print. Jobs expire after ',
                ),
                TextSpan(text: '4 hours', style: emphasis),
                const TextSpan(text: '.'),
              ],
            ),
            style: TextStyle(
              color: AppPalette.textSecondary(context),
              fontSize: 12,
              height: 1.4,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  void _showHelpBottomSheet(BuildContext context) {
    showAppBottomSheet<void>(
      context,
      title: 'Printer Instructions',
      initialChildSize: 0.75,
      builder: (sheetContext, textPrimary, textSecondary) {
        final dragController = bottomSheetScrollController(sheetContext);
        Widget heading(String text) => Text(
          text,
          style: TextStyle(
            color: textPrimary,
            fontSize: 16,
            fontWeight: FontWeight.w800,
          ),
        );
        Widget step(String number, String title, String body) =>
            buildInstructionStep(
              context,
              stepNumber: number,
              title: title,
              body: body,
            );
        return ListView(
          controller: dragController,
          physics: const ClampingScrollPhysics(),
          padding: const EdgeInsets.only(bottom: 24),
          children: [
            step(
              '1',
              'Connect to the Internet',
              'On campus Wi-Fi your phone talks to the printer directly. Anywhere else, PreConnect sends the job through its print relay, so an internet connection is enough.',
            ),
            const Gap(12),
            step(
              '2',
              'Check Your ID Card',
              'Your ID card at the top shows who the job is printed for. If it is missing, open Profile and pull down to refresh, then come back.',
            ),
            const Gap(12),
            step(
              '3',
              'Choose Documents',
              'Pick PDF, JPEG, or PNG files, or tap Blank Page to print one empty sheet. Blank Page replaces any files you already chose.',
            ),
            const Gap(12),
            step(
              '4',
              'Send Print Job',
              'Tap Print. Files are sent one by one. Print stays off until a file is chosen, your name and student ID are loaded, and the printer or print relay is found.',
            ),
            const Gap(12),
            step(
              '5',
              'Release Document',
              'Tap your physical ID card on any campus card-reader printer to release and print the files.',
            ),
            const Gap(16),
            heading('Connection Status'),
            const Gap(12),
            step(
              '•',
              'Scanning',
              'PreConnect is looking for the campus printer and the print relay.',
            ),
            const Gap(12),
            step(
              '•',
              'Connected',
              'The campus printer is reachable on your network, or the print relay is online. You can print.',
            ),
            const Gap(12),
            step(
              '•',
              'Not found',
              'Neither the campus printer nor the print relay could be reached. Tap the refresh icon or pull down to scan again, or use Print By Email at the bottom of the page.',
            ),
            const Gap(12),
            step(
              '•',
              'Offline',
              'Your device has no active internet connection.',
            ),
            const Gap(16),
            heading('Layout & Print Options'),
            const Gap(12),
            step(
              '•',
              'Copies',
              'Set the number of copies with the minus and plus buttons, or type it directly.',
            ),
            const Gap(12),
            step(
              '•',
              'One Side / Both Side',
              'Tap to switch between single-sided and double-sided printing. With 2-in-1, double-sided sheets bind on the short edge.',
            ),
            const Gap(12),
            step(
              '•',
              'Collate',
              'With several copies, print each full set in order instead of grouping identical pages.',
            ),
            const Gap(12),
            step(
              '•',
              'Pages Per Sheet',
              'Tap the layout button to cycle "1-in-1" (default), "2-in-1", "4-in-1" and "Booklet". Pages are placed on one A4 portrait sheet to save page quota. The layout is built on your phone, so the result is the same on any printer.',
            ),
            const Gap(12),
            step(
              '•',
              'Pages',
              'Print only part of a document, for example 1-5, 8, 11-13. Blank pages are skipped automatically. If every page you chose is blank, they are printed as they are.',
            ),
            const Gap(12),
            step(
              '•',
              'Preview',
              'Tap the eye on a file to see exactly how it will print. Swipe or use Previous and Next to move between sheets, and double-tap to zoom. Preview never sends anything to the printer; only the Print button does.',
            ),
            const Gap(12),
            step(
              '•',
              'Photos and PDFs',
              'JPEG and PNG photos are fitted to an A4 page. Password-protected or damaged PDFs cannot be read; remove the password first.',
            ),
            const Gap(12),
            step(
              '•',
              'Fit Paper / Fit Printable / Edge-to-Edge',
              'Fit Paper (default) scales the page to the sheet, Fit Printable scales it to the printable area, and Edge-to-Edge turns scaling off. The printer applies this only when your file prints as it is (1-in-1, no page range). With 2-in-1, 4-in-1, Booklet, or a page range, PreConnect fits every page itself and this button does not change the result.',
            ),
            const Gap(12),
            step(
              '•',
              'Finishing',
              'Tap Finishing to cycle Off, Staple Left, Staple Right, Punch 2 Holes and Punch 3 Holes. One finishing option is used at a time.',
            ),
            const Gap(12),
            step(
              '•',
              'Separate',
              'Tap Separate to cycle Off, Offset (shifts each printed set sideways), Slip Sheet (adds a blank sheet between jobs) and both together.',
            ),
            const Gap(12),
            buildInstructionStep(
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
                          'Choose "Booklet" on the layout button to arrange pages for folding down the center like a pamphlet. Two-sided printing is used automatically.\n',
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
                          'Missing pages at the end are left blank so the fold lines up.',
                    ),
                  ],
                ),
              ),
            ),
            const Gap(16),
            heading('History & Email'),
            const Gap(12),
            step(
              '•',
              'Print History',
              'Sent and failed jobs are listed below the Choose and Print buttons (the latest 100). Tap Clear History to remove them.',
            ),
            const Gap(12),
            step(
              '•',
              'Print By Email',
              'Email PDF, DOCX, PPTX, or XLSX files (up to 25 MB total) from your @g.bracu.ac.bd account to campus.printer@g.bracu.ac.bd. Add #duplex to the subject for double-sided printing. Wait 3 to 5 minutes, then tap your ID card at a campus printer. Jobs expire after 4 hours.',
            ),
          ],
        );
      },
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
    this.onPreview,
    this.onClear,
    this.emptyAction,
    this.borderRadius = 14,
  });

  final String title;
  final String subtitle;
  final bool isEmpty;
  final VoidCallback? onTap;
  final VoidCallback? onPreview;
  final VoidCallback? onClear;
  final Widget? emptyAction;
  final double borderRadius;

  Widget _actionIcon(
    BuildContext context,
    IconData icon,
    String tooltip,
    VoidCallback onPressed,
  ) {
    return IconButton(
      onPressed: onPressed,
      icon: Icon(icon),
      tooltip: tooltip,
      color: AppPalette.textSecondary(context),
      iconSize: 20,
      style: IconButton.styleFrom(
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      constraints: const BoxConstraints.tightFor(width: 28, height: 36),
      padding: EdgeInsets.zero,
    );
  }

  @override
  Widget build(BuildContext context) {
    final content = AppCard(
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
                    color: AppPalette.textSecondary(context),
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
                        ? AppPalette.textSecondary(context)
                        : AppPalette.textPrimary(context),
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          const Gap(8),
          if (isEmpty && emptyAction != null)
            emptyAction!
          else ...[
            if (onPreview != null)
              _actionIcon(
                context,
                Icons.visibility_outlined,
                'Preview',
                onPreview!,
              ),
            if (onClear != null)
              _actionIcon(context, Icons.close_rounded, 'Clear file', onClear!),
          ],
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
    final dataCommand = isPostScript ? 'o' : 'l';
    final copies = preferences.copies.clamp(1, 999);
    final duplexMode = preferences.duplexMode.trim().toUpperCase();

    try {
      final Uint8List sendBytes;
      if (isPostScript) {
        sendBytes = Uint8List.fromList([
          ..._ascii(preferences.postScriptPreamble),
          ...bytes,
        ]);
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
        layoutBaked: preferences.layoutBaked,
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
    builder.add(
      _ascii('\r\n\x1B%-12345X@PJL\r\n@PJL RESET\r\n@PJL EOJ\r\n\x1B%-12345X'),
    );
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
          Map<String, dynamic> data = const <String, dynamic>{};
          if (response.body.isNotEmpty) {
            final decoded = jsonDecode(response.body);
            if (decoded is Map) {
              data = decoded.cast<String, dynamic>();
            }
          }
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
                      child: AppActionButton(
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
                          color: AppPalette.textPrimary(context),
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
                      child: AppActionButton(
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
                    child: AppActionButton(
                      onPressed: () {
                        onDuplexChanged(duplexEnabled ? 'OFF' : 'LEFT');
                      },
                      outlined: true,
                      backgroundColor: duplexEnabled
                          ? AppPalette.primary.withValues(alpha: 0.12)
                          : Colors.transparent,
                      foregroundColor: duplexEnabled
                          ? AppPalette.primary
                          : AppPalette.textPrimary(context),
                      borderRadius: 12,
                      padding: togglePadding,
                      label: duplexEnabled ? 'Both Side' : 'One Side',
                      fontSize: toggleFont,
                    ),
                  ),
                  Gap(gap),
                  Expanded(
                    child: AppActionButton(
                      onPressed: () {
                        onCollateChanged(collateEnabled ? 'OFF' : 'ON');
                      },
                      outlined: true,
                      backgroundColor: collateEnabled
                          ? AppPalette.primary.withValues(alpha: 0.12)
                          : Colors.transparent,
                      foregroundColor: collateEnabled
                          ? AppPalette.primary
                          : AppPalette.textPrimary(context),
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
    required this.pageRange,
    required this.onPagesPerSheetChanged,
    required this.onFittingModeChanged,
    required this.onStapleChanged,
    required this.onPunchChanged,
    required this.onJobOffsetChanged,
    required this.onSlipSheetChanged,
    required this.onBookletChanged,
    required this.onPageRangeTap,
  });

  final String pageRange;
  final VoidCallback onPageRangeTap;
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
                    child: AppActionButton(
                      onPressed: () {
                        if (booklet == 'On') {
                          onBookletChanged('Off');
                          onPagesPerSheetChanged('1-in-1');
                        } else if (pagesPerSheet == '4-in-1') {
                          onPagesPerSheetChanged('1-in-1');
                          onBookletChanged('On');
                        } else {
                          onPagesPerSheetChanged(
                            pagesPerSheet == '1-in-1' ? '2-in-1' : '4-in-1',
                          );
                        }
                      },
                      outlined: true,
                      backgroundColor:
                          pagesPerSheet != '1-in-1' || booklet == 'On'
                          ? AppPalette.primary.withValues(alpha: 0.12)
                          : Colors.transparent,
                      foregroundColor:
                          pagesPerSheet != '1-in-1' || booklet == 'On'
                          ? AppPalette.primary
                          : AppPalette.textPrimary(context),
                      borderRadius: 12,
                      padding: buttonPadding,
                      label: booklet == 'On' ? 'Booklet' : pagesPerSheet,
                      fontSize: toggleFont,
                    ),
                  ),
                ),
                Gap(gap),
                Expanded(
                  child: Padding(
                    padding: EdgeInsets.symmetric(horizontal: gap / 2),
                    child: AppActionButton(
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
                          ? AppPalette.primary.withValues(alpha: 0.12)
                          : Colors.transparent,
                      foregroundColor: fittingMode != 'Fit on Paper'
                          ? AppPalette.primary
                          : AppPalette.textPrimary(context),
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
                    child: AppActionButton(
                      onPressed: () {
                        final next = PrintFinishing.after(staple, punch);
                        onStapleChanged(next.staple);
                        onPunchChanged(next.punch);
                      },
                      outlined: true,
                      backgroundColor: staple != 'Off' || punch != 'Off'
                          ? AppPalette.primary.withValues(alpha: 0.12)
                          : Colors.transparent,
                      foregroundColor: staple != 'Off' || punch != 'Off'
                          ? AppPalette.primary
                          : AppPalette.textPrimary(context),
                      borderRadius: 12,
                      padding: buttonPadding,
                      label: PrintFinishing.label(staple, punch),
                      fontSize: toggleFont,
                    ),
                  ),
                ),
                Gap(gap),
                Expanded(
                  child: Padding(
                    padding: EdgeInsets.symmetric(horizontal: gap / 2),
                    child: AppActionButton(
                      onPressed: () {
                        final next = PrintSeparation.after(
                          jobOffset == 'On',
                          slipSheet == 'On',
                        );
                        onJobOffsetChanged(next.offset ? 'On' : 'Off');
                        onSlipSheetChanged(next.slip ? 'On' : 'Off');
                      },
                      outlined: true,
                      backgroundColor: jobOffset == 'On' || slipSheet == 'On'
                          ? AppPalette.primary.withValues(alpha: 0.12)
                          : Colors.transparent,
                      foregroundColor: jobOffset == 'On' || slipSheet == 'On'
                          ? AppPalette.primary
                          : AppPalette.textPrimary(context),
                      borderRadius: 12,
                      padding: buttonPadding,
                      label: PrintSeparation.label(
                        jobOffset == 'On',
                        slipSheet == 'On',
                      ),
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
                    child: AppActionButton(
                      onPressed: onPageRangeTap,
                      outlined: true,
                      backgroundColor: pageRange.isNotEmpty
                          ? AppPalette.primary.withValues(alpha: 0.12)
                          : Colors.transparent,
                      foregroundColor: pageRange.isNotEmpty
                          ? AppPalette.primary
                          : AppPalette.textPrimary(context),
                      borderRadius: 12,
                      padding: buttonPadding,
                      label: pageRange.isEmpty
                          ? 'Pages'
                          : (pageRange.length > 16
                                ? '${pageRange.substring(0, 15)}…'
                                : pageRange),
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
    this.layoutBaked = false,
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
  final bool layoutBaked;

  _PrintTicket withBakedLayout() {
    return _PrintTicket(
      copies: copies,
      duplexMode: duplexMode,
      collateMode: collateMode,
      pagesPerSheet: pagesPerSheet,
      fittingMode: fittingMode,
      staple: staple,
      punch: punch,
      jobOffset: jobOffset,
      slipSheet: slipSheet,
      booklet: booklet,
      layoutBaked: true,
    );
  }

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
  return fileName.toLowerCase().endsWith('.pdf') || looksLikePdf(bytes);
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

class _PageRangeSheet extends StatefulWidget {
  const _PageRangeSheet({required this.initial});

  final String initial;

  @override
  State<_PageRangeSheet> createState() => _PageRangeSheetState();
}

class _PageRangeSheetState extends State<_PageRangeSheet> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initial,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _apply() {
    final text = _controller.text.trim();
    if (text.isNotEmpty && PrintLayout.parsePageRange(text, 1 << 20) == null) {
      return;
    }
    Navigator.of(context).pop(text);
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      controller: bottomSheetScrollController(context),
      physics: const ClampingScrollPhysics(),
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        TextField(
          controller: _controller,
          autofocus: true,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _apply(),
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'[0-9,\-\s]')),
          ],
          style: TextStyle(
            color: AppPalette.textPrimary(context),
            fontFamily: 'Outfit',
          ),
          decoration: appInputDecoration(
            context,
            hintText: '1-5, 8, 11-13',
            borderRadius: 14,
          ),
        ),
        const Gap(16),
        Row(
          children: [
            Expanded(
              child: AppActionButton(
                onPressed: () => Navigator.of(context).pop(''),
                label: 'All',
              ),
            ),
            const Gap(12),
            Expanded(
              child: AppActionButton(onPressed: _apply, label: 'Apply'),
            ),
          ],
        ),
        const Gap(16),
      ],
    );
  }
}

class _PrintPreviewSheet extends StatefulWidget {
  const _PrintPreviewSheet({
    required this.documents,
    this.firstPage,
    this.source,
  });

  final Future<List<Uint8List>> documents;
  final Future<Uint8List?>? firstPage;
  final Uint8List? source;

  @override
  State<_PrintPreviewSheet> createState() => _PrintPreviewSheetState();
}

class _PrintPreviewSheetState extends State<_PrintPreviewSheet> {
  final List<Uint8List> _pages = <Uint8List>[];
  final PageController _controller = PageController();
  final ValueNotifier<int> _current = ValueNotifier<int>(0);
  final TransformationController _zoom = TransformationController();
  String? _message;
  bool _zoomed = false;
  Offset _tapAt = Offset.zero;

  void _toggleZoom() {
    if (_zoomed) {
      setState(() => _zoomed = false);
      return;
    }
    const scale = 2.5;
    _zoom.value = Matrix4.identity()
      ..translateByDouble(
        -_tapAt.dx * (scale - 1),
        -_tapAt.dy * (scale - 1),
        0,
        1,
      )
      ..scaleByDouble(scale, scale, 1, 1);
    setState(() => _zoomed = true);
  }

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  bool _ready = false;

  Future<void> _showEarly(Future<Uint8List?> quick) async {
    final page = await quick;
    if (page == null || !mounted || _ready || _pages.isNotEmpty) return;
    await precacheImage(MemoryImage(page), context);
    if (!mounted || _ready || _pages.isNotEmpty) return;
    setState(() => _pages.add(page));
  }

  Future<void> _load() async {
    final quick = widget.firstPage;
    if (quick != null) unawaited(_showEarly(quick));
    try {
      final documents = await widget.documents;
      _ready = true;
      final untouched =
          documents.length == 1 && identical(documents.first, widget.source);
      var skip = 0;
      if (_pages.isNotEmpty) {
        if (untouched) {
          skip = 1;
        } else if (mounted) {
          setState(_pages.clear);
        }
      }
      for (final document in documents) {
        final stream = PrintComposer.previewPages(document);
        await for (final page in skip > 0 ? stream.skip(skip) : stream) {
          if (!mounted) return;
          await precacheImage(MemoryImage(page), context);
          if (!mounted) return;
          setState(() => _pages.add(page));
        }
        skip = 0;
      }
      if (mounted && _pages.isEmpty) {
        setState(() => _message = 'Nothing to preview');
      }
    } on PrintComposeException catch (error) {
      if (mounted) setState(() => _message = error.message);
    } catch (error) {
      unawaited(AppLog.write('Print preview failed: $error'));
      if (mounted) setState(() => _message = 'Preview is not available');
    }
  }

  void _goTo(int index) {
    unawaited(
      _controller.animateToPage(
        index,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    _current.dispose();
    _zoom.dispose();
    super.dispose();
  }

  Widget _placeholder(BuildContext context) {
    return Center(
      child: AspectRatio(
        aspectRatio: PrintLayout.a4Width / PrintLayout.a4Height,
        child: ColoredBox(
          color: Colors.white,
          child: Center(
            child: _message == null
                ? const SizedBox.square(
                    dimension: 22,
                    child: CircularProgressIndicator(strokeWidth: 2.5),
                  )
                : Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      _message!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.black54),
                    ),
                  ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: _pages.isEmpty
              ? _placeholder(context)
              : PageView.builder(
                  controller: _controller,
                  physics: _zoomed
                      ? const NeverScrollableScrollPhysics()
                      : const ClampingScrollPhysics(),
                  itemCount: _pages.length,
                  onPageChanged: (index) {
                    _current.value = index;
                    if (_zoomed) setState(() => _zoomed = false);
                  },
                  itemBuilder: (context, index) {
                    final page = Center(
                      child: RepaintBoundary(
                        child: ColoredBox(
                          color: Colors.white,
                          child: Image.memory(
                            _pages[index],
                            fit: BoxFit.contain,
                            gaplessPlayback: true,
                            filterQuality: FilterQuality.medium,
                          ),
                        ),
                      ),
                    );
                    return GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onDoubleTapDown: (details) =>
                          _tapAt = details.localPosition,
                      onDoubleTap: _toggleZoom,
                      child: _zoomed
                          ? InteractiveViewer(
                              transformationController: _zoom,
                              minScale: 1,
                              maxScale: 5,
                              child: page,
                            )
                          : page,
                    );
                  },
                ),
        ),
        const Gap(8),
        ValueListenableBuilder<int>(
          valueListenable: _current,
          builder: (context, current, _) => Row(
            children: [
              Expanded(
                child: AppActionButton(
                  onPressed: current > 0 ? () => _goTo(current - 1) : null,
                  icon: Icons.chevron_left_rounded,
                  label: 'Previous',
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: Text(
                  '${_pages.isEmpty ? 0 : current + 1} / ${_pages.length}',
                  style: TextStyle(color: AppPalette.textSecondary(context)),
                ),
              ),
              Expanded(
                child: AppActionButton(
                  onPressed: current < _pages.length - 1
                      ? () => _goTo(current + 1)
                      : null,
                  icon: Icons.chevron_right_rounded,
                  label: 'Next',
                ),
              ),
            ],
          ),
        ),
        const Gap(12),
        AppActionButton(
          onPressed: () => Navigator.of(context).pop(),
          label: 'Close',
        ),
      ],
    );
  }
}
