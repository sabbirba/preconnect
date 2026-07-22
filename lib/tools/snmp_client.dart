import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

class SnmpPrinterStatus {
  const SnmpPrinterStatus({
    this.description,
    this.deviceStatusCode,
    this.printerStatusCode,
    this.errorFlags = const <String>[],
  });

  final String? description;
  final int? deviceStatusCode;
  final int? printerStatusCode;
  final List<String> errorFlags;

  bool get hasErrors => errorFlags.isNotEmpty;

  String get printerStatusLabel {
    switch (printerStatusCode) {
      case 3:
        return 'Idle';
      case 4:
        return 'Printing';
      case 5:
        return 'Warming Up';
      case 1:
        return 'Other';
      default:
        return 'Unknown';
    }
  }
}

class SnmpClient {
  const SnmpClient._();

  static const String _oidSysDescr = '1.3.6.1.2.1.1.1.0';
  static const String _oidHrDeviceStatus = '1.3.6.1.2.1.25.3.2.1.5.1';
  static const String _oidHrPrinterStatus = '1.3.6.1.2.1.25.3.5.1.1.1';
  static const String _oidHrPrinterErrorState = '1.3.6.1.2.1.25.3.5.1.2.1';

  static const List<String> _errorBitNames = <String>[
    'Low Paper',
    'No Paper',
    'Low Toner',
    'No Toner',
    'Door Open',
    'Jammed',
    'Offline',
    'Service Requested',
    'Input Tray Missing',
    'Output Tray Missing',
    'Marker Supply Missing',
    'Output Near Full',
    'Output Full',
    'Input Tray Empty',
    'Overdue Preventive Maintenance',
  ];

  static Future<SnmpPrinterStatus?> queryPrinterStatus(
    String host, {
    Duration timeout = const Duration(seconds: 2),
    int port = 161,
    String community = 'public',
    int requestId = 1,
  }) async {
    RawDatagramSocket? socket;
    StreamSubscription<RawSocketEvent>? subscription;
    Timer? timer;
    try {
      socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
      final packet = _buildGetRequest(
        community: community,
        requestId: requestId & 0x7FFFFFFF,
        oids: const <String>[
          _oidSysDescr,
          _oidHrDeviceStatus,
          _oidHrPrinterStatus,
          _oidHrPrinterErrorState,
        ],
      );
      final address = InternetAddress(host);
      socket.send(packet, address, port);

      final completer = Completer<Uint8List?>();
      subscription = socket.listen((event) {
        if (event != RawSocketEvent.read) return;
        final datagram = socket?.receive();
        if (datagram != null && !completer.isCompleted) {
          completer.complete(datagram.data);
        }
      });
      timer = Timer(timeout, () {
        if (!completer.isCompleted) completer.complete(null);
      });

      final response = await completer.future;
      if (response == null) return null;
      return _parseResponse(response);
    } catch (_) {
      return null;
    } finally {
      timer?.cancel();
      await subscription?.cancel();
      socket?.close();
    }
  }

  static Uint8List _encodeLength(int length) {
    if (length < 0x80) return Uint8List.fromList(<int>[length]);
    final bytes = <int>[];
    var remaining = length;
    while (remaining > 0) {
      bytes.insert(0, remaining & 0xFF);
      remaining >>= 8;
    }
    return Uint8List.fromList(<int>[0x80 | bytes.length, ...bytes]);
  }

  static List<int> _tlv(int tag, List<int> content) {
    return <int>[tag, ..._encodeLength(content.length), ...content];
  }

  static List<int> _encodeUnsignedInteger(int value) {
    if (value == 0) return const <int>[0];
    final bytes = <int>[];
    var v = value;
    while (v > 0) {
      bytes.insert(0, v & 0xFF);
      v >>= 8;
    }
    if (bytes[0] & 0x80 != 0) bytes.insert(0, 0x00);
    return bytes;
  }

  static List<int> _encodeOidComponent(int value) {
    if (value == 0) return const <int>[0];
    final chunks = <int>[];
    var v = value;
    while (v > 0) {
      chunks.insert(0, v & 0x7F);
      v >>= 7;
    }
    for (var i = 0; i < chunks.length - 1; i++) {
      chunks[i] |= 0x80;
    }
    return chunks;
  }

  static List<int> _encodeOid(String oid) {
    final parts = oid.split('.').map(int.parse).toList(growable: false);
    final bytes = <int>[parts[0] * 40 + parts[1]];
    for (final part in parts.sublist(2)) {
      bytes.addAll(_encodeOidComponent(part));
    }
    return bytes;
  }

  static String _decodeOid(Uint8List bytes) {
    if (bytes.isEmpty) return '';
    final first = bytes[0];
    final parts = <int>[first ~/ 40, first % 40];
    var value = 0;
    for (var i = 1; i < bytes.length; i++) {
      final b = bytes[i];
      value = (value << 7) | (b & 0x7F);
      if (b & 0x80 == 0) {
        parts.add(value);
        value = 0;
      }
    }
    return parts.join('.');
  }

  static int _decodeInteger(Uint8List bytes) {
    if (bytes.isEmpty) return 0;
    var value = 0;
    for (final b in bytes) {
      value = (value << 8) | b;
    }
    if (bytes[0] & 0x80 != 0) {
      value -= 1 << (8 * bytes.length);
    }
    return value;
  }

  static List<String> _decodeErrorBits(Uint8List bytes) {
    final flags = <String>[];
    for (var byteIndex = 0; byteIndex < bytes.length; byteIndex++) {
      final byte = bytes[byteIndex];
      for (var bit = 0; bit < 8; bit++) {
        final flagIndex = byteIndex * 8 + bit;
        if (flagIndex >= _errorBitNames.length) continue;
        final mask = 0x80 >> bit;
        if (byte & mask != 0) flags.add(_errorBitNames[flagIndex]);
      }
    }
    return flags;
  }

  static Uint8List _buildGetRequest({
    required String community,
    required int requestId,
    required List<String> oids,
  }) {
    final varbinds = <int>[];
    for (final oid in oids) {
      final oidTlv = _tlv(0x06, _encodeOid(oid));
      final nullTlv = _tlv(0x05, const <int>[]);
      varbinds.addAll(_tlv(0x30, <int>[...oidTlv, ...nullTlv]));
    }
    final varbindList = _tlv(0x30, varbinds);

    final pdu = <int>[
      ..._tlv(0x02, _encodeUnsignedInteger(requestId)),
      ..._tlv(0x02, const <int>[0]),
      ..._tlv(0x02, const <int>[0]),
      ...varbindList,
    ];
    final pduTlv = _tlv(0xA0, pdu);

    final message = <int>[
      ..._tlv(0x02, const <int>[0]),
      ..._tlv(0x04, community.codeUnits),
      ...pduTlv,
    ];
    return Uint8List.fromList(_tlv(0x30, message));
  }

  static SnmpPrinterStatus? _parseResponse(Uint8List data) {
    final envelope = _BerReader(data).readNode();
    if (envelope.tag != 0x30) return null;
    final inner = _BerReader(envelope.content);
    inner.readNode();
    inner.readNode();
    final pduNode = inner.readNode();
    if (pduNode.tag != 0xA2) return null;

    final pduReader = _BerReader(pduNode.content);
    pduReader.readNode();
    pduReader.readNode();
    pduReader.readNode();
    final varbindListNode = pduReader.readNode();
    final varbindReader = _BerReader(varbindListNode.content);

    String? description;
    int? deviceStatus;
    int? printerStatus;
    var errorFlags = const <String>[];

    while (varbindReader.hasMore) {
      final varbindNode = varbindReader.readNode();
      final vbReader = _BerReader(varbindNode.content);
      final oidNode = vbReader.readNode();
      final valueNode = vbReader.readNode();
      final oid = _decodeOid(oidNode.content);

      switch (oid) {
        case _oidSysDescr:
          if (valueNode.tag == 0x04) {
            description = String.fromCharCodes(valueNode.content).trim();
          }
          break;
        case _oidHrDeviceStatus:
          if (valueNode.tag == 0x02) {
            deviceStatus = _decodeInteger(valueNode.content);
          }
          break;
        case _oidHrPrinterStatus:
          if (valueNode.tag == 0x02) {
            printerStatus = _decodeInteger(valueNode.content);
          }
          break;
        case _oidHrPrinterErrorState:
          if (valueNode.tag == 0x04 || valueNode.tag == 0x03) {
            errorFlags = _decodeErrorBits(valueNode.content);
          }
          break;
      }
    }

    if (description == null && deviceStatus == null && printerStatus == null) {
      return null;
    }
    return SnmpPrinterStatus(
      description: description,
      deviceStatusCode: deviceStatus,
      printerStatusCode: printerStatus,
      errorFlags: errorFlags,
    );
  }
}

class _BerNode {
  const _BerNode(this.tag, this.content);

  final int tag;
  final Uint8List content;
}

class _BerReader {
  _BerReader(this.data);

  final Uint8List data;
  int _pos = 0;

  bool get hasMore => _pos < data.length;

  _BerNode readNode() {
    final tag = data[_pos++];
    var length = data[_pos++];
    if (length & 0x80 != 0) {
      final numBytes = length & 0x7F;
      length = 0;
      for (var i = 0; i < numBytes; i++) {
        length = (length << 8) | data[_pos++];
      }
    }
    final content = Uint8List.sublistView(data, _pos, _pos + length);
    _pos += length;
    return _BerNode(tag, content);
  }
}
