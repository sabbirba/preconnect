import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:preconnect/api/profile_service.dart';
import 'package:preconnect/api/sembast_cache.dart';
import 'package:preconnect/pages/ui_kit.dart';
import 'package:shared_preferences/shared_preferences.dart';

class CampusPrinterPage extends StatefulWidget {
  const CampusPrinterPage({super.key});

  @override
  State<CampusPrinterPage> createState() => _CampusPrinterPageState();
}

class _CampusPrinterPageState extends State<CampusPrinterPage> {
  static const int _printerPort = 515;
  static const String _printerQueue = 'lp';
  static const String _historyKey = 'campus_printer_history';

  Uint8List? _fileBytes;
  String _fileName = '';
  String _studentId = '';
  String _studentName = '';
  String _studentShortCode = '';
  String _printerHost = '';
  String _printerStatus = 'Detecting campus printer...';
  List<_PrintHistoryEntry> _history = const <_PrintHistoryEntry>[];
  bool _busy = false;
  bool _discovering = false;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  @override
  void dispose() {
    super.dispose();
  }

  Future<void> _bootstrap() async {
    await Future.wait([_loadStudentProfile(), _loadHistory()]);
    if (!mounted) return;
    unawaited(_discoverPrinter());
  }

  Future<void> _refreshPrinterInfo() async {
    await _loadHistory();
    await _loadStudentProfile();
    await _discoverPrinter();
  }

  Future<void> _loadStudentProfile() async {
    final cache = SembastCache();
    final prefs = SharedPreferencesAsync();
    var studentId = (await cache.getString('studentId') ?? '').trim();
    var fullName = (await cache.getString('fullName') ?? '').trim();
    var shortCode = (await cache.getString('shortCode') ?? '').trim();

    if (studentId.isEmpty) {
      studentId = (await prefs.getString('studentId') ?? '').trim();
    }
    if (fullName.isEmpty) {
      fullName = (await prefs.getString('fullName') ?? '').trim();
    }
    if (shortCode.isEmpty) {
      shortCode = (await prefs.getString('shortCode') ?? '').trim();
    }

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
    });
  }

  Future<void> _discoverPrinter() async {
    if (_discovering) return;
    setState(() {
      _discovering = true;
      _printerHost = '';
      _printerStatus = 'Scanning...';
    });
    try {
      final printers = await _WifiPrinterDiscovery.findLprPrinters(
        port: _printerPort,
      );
      if (!mounted) return;
      if (printers.isEmpty) {
        setState(() {
          _printerStatus = 'No printer found';
        });
        return;
      }
      final printer = printers.first;
      setState(() {
        _printerHost = printer.address;
        _printerStatus = 'Campus Printer found';
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _printerStatus = 'Campus printer scan failed.';
      });
    } finally {
      if (mounted) {
        setState(() {
          _discovering = false;
        });
      }
    }
  }

  Future<void> _loadHistory() async {
    final prefs = SharedPreferencesAsync();
    final raw = (await prefs.getString(_historyKey) ?? '').trim();
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

  Future<void> _deleteHistory(_PrintHistoryEntry entry) async {
    final next = _history
        .where((item) => !_sameHistoryEntry(item, entry))
        .toList();
    await _saveHistory(next);
  }

  Future<void> _saveHistory(List<_PrintHistoryEntry> history) async {
    setState(() {
      _history = history;
    });
    final prefs = SharedPreferencesAsync();
    await prefs.setString(
      _historyKey,
      jsonEncode(history.map((item) => item.toJson()).toList()),
    );
  }

  Future<void> _pickPrintFile() async {
    final picked = await FilePicker.pickFiles(
      type: FileType.any,
      allowMultiple: false,
      withData: true,
    );
    if (!mounted || picked == null || picked.files.isEmpty) return;
    final file = picked.files.first;
    var bytes = file.bytes;
    final path = file.path;
    if ((bytes == null || bytes.isEmpty) && path != null && path.isNotEmpty) {
      bytes = await File(path).readAsBytes();
    }
    if (bytes == null || bytes.isEmpty) {
      if (mounted) showAppSnackBar(context, 'Unable to read selected file');
      return;
    }
    setState(() {
      _fileBytes = bytes;
      _fileName = file.name.trim().isEmpty ? 'document.pdf' : file.name.trim();
    });
  }

  Future<void> _sendToPrinter() async {
    if (_busy) return;
    final host = _printerHost.trim();
    final user = _studentId.trim().isEmpty ? 'student' : _studentId.trim();
    final bytes = _fileBytes;

    if (host.isEmpty) {
      showAppSnackBar(context, 'No printer found');
      return;
    }
    if (bytes == null || bytes.isEmpty) {
      showAppSnackBar(context, 'Choose a file first');
      return;
    }
    if (_studentId.trim().isEmpty) {
      showAppSnackBar(context, 'Student ID not found. Refresh profile first.');
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
      await client.sendFile(
        bytes: bytes,
        fileName: _fileName,
        user: user,
        sourceHost: Platform.localHostname,
      );
      if (!mounted) return;
      await _addHistory(
        _PrintHistoryEntry(
          fileName: _fileName,
          printerHost: host,
          status: 'Sent',
          message: 'Sent to campus printer',
          createdAt: DateTime.now(),
        ),
      );
      if (!mounted) return;
      showAppSnackBar(context, 'File sent to campus printer');
    } on _LprPrintException catch (error) {
      if (!mounted) return;
      await _addHistory(
        _PrintHistoryEntry(
          fileName: _fileName,
          printerHost: host,
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
          status: 'Failed',
          message: 'Unable to send file to campus printer',
          createdAt: DateTime.now(),
        ),
      );
      if (!mounted) return;
      showAppSnackBar(context, 'Unable to send file to campus printer');
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
    final selected = _fileName.isEmpty ? 'No file selected' : _fileName;
    final canPrint =
        !_busy &&
        !_discovering &&
        _printerHost.isNotEmpty &&
        _studentId.isNotEmpty;
    return BracuPageScaffold(
      title: 'Printer',
      subtitle: 'Print File',
      icon: Icons.local_printshop_outlined,
      body: BracuRefreshList(
        onRefresh: _refreshPrinterInfo,
        children: [
          BracuCard(
            padding: const EdgeInsets.fromLTRB(14, 8, 14, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      _printerHost.isEmpty
                          ? Icons.wifi_find_outlined
                          : Icons.local_printshop_outlined,
                      color: BracuPalette.textSecondary(context),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        _printerStatus,
                        style: TextStyle(
                          color: BracuPalette.textPrimary(context),
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    TextButton.icon(
                      onPressed: _busy || _discovering
                          ? null
                          : () => _discoverPrinter(),
                      style: bracuNoSplashTextButtonStyle(),
                      icon: _discovering
                          ? const SizedBox.shrink()
                          : const Icon(Icons.wifi_find_outlined),
                      label: _discovering
                          ? const BracuShimmerLabel(label: 'Scanning')
                          : const Text('Scan'),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                _StudentPrintDetails(
                  name: _studentName,
                  shortCode: _studentShortCode,
                  studentId: _studentId,
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          BracuCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  selected,
                  style: TextStyle(
                    color: BracuPalette.textPrimary(context),
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _busy ? null : _pickPrintFile,
                        icon: const Icon(
                          Icons.picture_as_pdf_outlined,
                          size: 18,
                        ),
                        label: const Text('Choose'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: canPrint ? _sendToPrinter : null,
                        icon: _busy
                            ? const BracuShimmer(
                                child: BracuSkeletonBox(
                                  width: 16,
                                  height: 16,
                                  radius: 8,
                                ),
                              )
                            : const Icon(Icons.print_rounded, size: 18),
                        label: Text(_busy ? 'Sending...' : 'Print'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          _PrintHistoryCard(history: _history, onDelete: _deleteHistory),
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
      return Text(
        'Student details not available',
        style: TextStyle(
          color: BracuPalette.textSecondary(context),
          fontWeight: FontWeight.w700,
        ),
      );
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
    return Row(
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
    );
  }
}

class _PrintHistoryCard extends StatelessWidget {
  const _PrintHistoryCard({required this.history, required this.onDelete});

  final List<_PrintHistoryEntry> history;
  final ValueChanged<_PrintHistoryEntry> onDelete;

  @override
  Widget build(BuildContext context) {
    if (history.isEmpty) {
      return BracuCard(
        child: Text(
          'No print history yet',
          style: TextStyle(
            color: BracuPalette.textSecondary(context),
            fontWeight: FontWeight.w700,
          ),
        ),
      );
    }

    return BracuCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'History',
            style: TextStyle(
              color: BracuPalette.textPrimary(context),
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          for (var index = 0; index < history.length; index++) ...[
            _PrintHistoryRow(entry: history[index], onDelete: onDelete),
            if (index != history.length - 1)
              Divider(
                height: 10,
                thickness: 0.7,
                color: BracuPalette.textSecondary(
                  context,
                ).withValues(alpha: 0.18),
              ),
          ],
        ],
      ),
    );
  }
}

class _PrintHistoryRow extends StatelessWidget {
  const _PrintHistoryRow({required this.entry, required this.onDelete});

  final _PrintHistoryEntry entry;
  final ValueChanged<_PrintHistoryEntry> onDelete;

  @override
  Widget build(BuildContext context) {
    final failed = entry.status.toLowerCase() == 'failed';
    final statusColor = failed ? Colors.redAccent : Colors.greenAccent;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        SizedBox(
          width: 22,
          height: 22,
          child: Icon(
            failed ? Icons.error_outline : Icons.check_circle_outline,
            color: statusColor,
            size: 18,
          ),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                entry.fileName,
                softWrap: true,
                style: TextStyle(
                  color: BracuPalette.textPrimary(context),
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                _formatHistoryTime(entry.createdAt),
                style: TextStyle(
                  color: BracuPalette.textSecondary(context),
                  fontSize: 10,
                ),
              ),
            ],
          ),
        ),
        IconButton(
          onPressed: () => onDelete(entry),
          icon: const Icon(Icons.delete_outline_rounded),
          color: BracuPalette.textSecondary(context),
          iconSize: 18,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints.tightFor(width: 34, height: 34),
          tooltip: 'Delete',
        ),
      ],
    );
  }
}

class _PrintHistoryEntry {
  const _PrintHistoryEntry({
    required this.fileName,
    required this.printerHost,
    required this.status,
    required this.message,
    required this.createdAt,
  });

  final String fileName;
  final String printerHost;
  final String status;
  final String message;
  final DateTime createdAt;

  factory _PrintHistoryEntry.fromJson(Map<String, dynamic> json) {
    return _PrintHistoryEntry(
      fileName: (json['fileName'] ?? '').toString(),
      printerHost: (json['printerHost'] ?? '').toString(),
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

  Future<void> sendFile({
    required Uint8List bytes,
    required String fileName,
    required String user,
    required String sourceHost,
  }) async {
    final printerHost = host.trim();
    if (printerHost.isEmpty) {
      throw const _LprPrintException('Printer host is required');
    }

    final printerQueue = queue;
    final owner = user;
    final origin = sourceHost;
    final safeFileName = fileName.split(Platform.pathSeparator).last;
    final jobToken =
        'dfA${(DateTime.now().microsecondsSinceEpoch % 999 + 1).toString().padLeft(3, '0')}$origin';

    Socket? socket;
    _LprAckReader? ackReader;
    try {
      final sendBytes = bytes;
      final control = _ascii(
        [
          'H$origin',
          'P$owner',
          'l$jobToken',
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
      throw const _LprPrintException('Printer connection timed out');
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
      throw const _LprPrintException('Printer rejected the job');
    }
  }
}

class _LprAckReader {
  _LprAckReader(Socket socket) : _iterator = StreamIterator<List<int>>(socket);

  final StreamIterator<List<int>> _iterator;
  final List<int> _buffer = <int>[];

  Future<int> readByte() async {
    while (_buffer.isEmpty) {
      final hasData = await _iterator.moveNext();
      if (!hasData) {
        throw const _LprPrintException('Printer closed the connection');
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
  }) async {
    final subnets = await _localIpv4Subnets();
    final found = <_WifiPrinterCandidate>[];
    final seen = <String>{};
    final active = <Future<void>>{};

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

    for (final subnet in subnets) {
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

bool _sameHistoryEntry(_PrintHistoryEntry a, _PrintHistoryEntry b) {
  return a.fileName == b.fileName &&
      a.printerHost == b.printerHost &&
      a.status == b.status &&
      a.message == b.message &&
      a.createdAt.isAtSameMomentAs(b.createdAt);
}

List<int> _ascii(String value) {
  return value.codeUnits.map((unit) => unit <= 0x7F ? unit : 0x3F).toList();
}

String _formatHistoryTime(DateTime value) {
  if (value.millisecondsSinceEpoch <= 0) return 'Unknown time';
  final local = value.toLocal();
  return '${local.day}/${local.month}/${local.year} ${_formatClock(local)}';
}

String _formatClock(DateTime value) {
  final local = value.toLocal();
  final hour = local.hour % 12 == 0 ? 12 : local.hour % 12;
  final minute = local.minute.toString().padLeft(2, '0');
  final suffix = local.hour >= 12 ? 'PM' : 'AM';
  return '$hour:$minute $suffix';
}
