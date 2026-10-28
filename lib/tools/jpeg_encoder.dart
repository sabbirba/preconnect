import 'dart:math' as math;
import 'dart:typed_data';

/// Baseline JPEG encoder (4:4:4, Huffman tables from ITU-T T.81 Annex K).
///
/// Takes straight RGBA pixels (alpha is ignored, so flatten first) and returns
/// a JFIF file. It exists so the app does not have to ship a general purpose
/// image library just to write print sheets.
Uint8List encodeJpeg(
  Uint8List rgba,
  int width,
  int height, {
  int quality = 85,
}) {
  assert(rgba.length >= width * height * 4);
  return _JpegWriter(width, height, quality).write(rgba);
}

// dart format off
const List<int> _zigzag = [
  0, 1, 8, 16, 9, 2, 3, 10, 17, 24, 32, 25, 18, 11, 4, 5,
  12, 19, 26, 33, 40, 48, 41, 34, 27, 20, 13, 6, 7, 14, 21, 28,
  35, 42, 49, 56, 57, 50, 43, 36, 29, 22, 15, 23, 30, 37, 44, 51,
  58, 59, 52, 45, 38, 31, 39, 46, 53, 60, 61, 54, 47, 55, 62, 63,
];

const List<int> _lumaQuant = [
  16, 11, 10, 16, 24, 40, 51, 61,
  12, 12, 14, 19, 26, 58, 60, 55,
  14, 13, 16, 24, 40, 57, 69, 56,
  14, 17, 22, 29, 51, 87, 80, 62,
  18, 22, 37, 56, 68, 109, 103, 77,
  24, 35, 55, 64, 81, 104, 113, 92,
  49, 64, 78, 87, 103, 121, 120, 101,
  72, 92, 95, 98, 112, 100, 103, 99,
];

const List<int> _chromaQuant = [
  17, 18, 24, 47, 99, 99, 99, 99,
  18, 21, 26, 66, 99, 99, 99, 99,
  24, 26, 56, 99, 99, 99, 99, 99,
  47, 66, 99, 99, 99, 99, 99, 99,
  99, 99, 99, 99, 99, 99, 99, 99,
  99, 99, 99, 99, 99, 99, 99, 99,
  99, 99, 99, 99, 99, 99, 99, 99,
  99, 99, 99, 99, 99, 99, 99, 99,
];

const List<int> _dcCounts = [
  0, 1, 5, 1, 1, 1, 1, 1, 1, 0, 0, 0, 0, 0, 0, 0,
];

const List<int> _dcValues = [
  0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11,
];

const List<int> _acCounts = [
  0, 2, 1, 3, 3, 2, 4, 3, 5, 5, 4, 4, 0, 0, 1, 125,
];

const List<int> _acValues = [
  1, 2, 3, 0, 4, 17, 5, 18, 33, 49, 65, 6,
  19, 81, 97, 7, 34, 113, 20, 50, 129, 145, 161, 8,
  35, 66, 177, 193, 21, 82, 209, 240, 36, 51, 98, 114,
  130, 9, 10, 22, 23, 24, 25, 26, 37, 38, 39, 40,
  41, 42, 52, 53, 54, 55, 56, 57, 58, 67, 68, 69,
  70, 71, 72, 73, 74, 83, 84, 85, 86, 87, 88, 89,
  90, 99, 100, 101, 102, 103, 104, 105, 106, 115, 116, 117,
  118, 119, 120, 121, 122, 131, 132, 133, 134, 135, 136, 137,
  138, 146, 147, 148, 149, 150, 151, 152, 153, 154, 162, 163,
  164, 165, 166, 167, 168, 169, 170, 178, 179, 180, 181, 182,
  183, 184, 185, 186, 194, 195, 196, 197, 198, 199, 200, 201,
  202, 210, 211, 212, 213, 214, 215, 216, 217, 218, 225, 226,
  227, 228, 229, 230, 231, 232, 233, 234, 241, 242, 243, 244,
  245, 246, 247, 248, 249, 250,
];

// dart format on

class _HuffmanTable {
  _HuffmanTable(List<int> counts, List<int> values)
    : codes = Uint16List(256),
      lengths = Uint8List(256) {
    var code = 0;
    var index = 0;
    for (var length = 1; length <= 16; length++) {
      for (var i = 0; i < counts[length - 1]; i++) {
        final symbol = values[index++];
        codes[symbol] = code;
        lengths[symbol] = length;
        code++;
      }
      code <<= 1;
    }
  }

  final Uint16List codes;
  final Uint8List lengths;
}

class _JpegWriter {
  _JpegWriter(this.width, this.height, int quality)
    : _lumaTable = _scaledQuant(_lumaQuant, quality),
      _chromaTable = _scaledQuant(_chromaQuant, quality);

  final int width;
  final int height;
  final Int32List _lumaTable;
  final Int32List _chromaTable;
  final _HuffmanTable _dc = _HuffmanTable(_dcCounts, _dcValues);
  final _HuffmanTable _ac = _HuffmanTable(_acCounts, _acValues);
  final BytesBuilder _out = BytesBuilder(copy: false);

  int _bitBuffer = 0;
  int _bitCount = 0;

  static final Float64List _cosine = _buildCosine();

  static Float64List _buildCosine() {
    final table = Float64List(64);
    for (var u = 0; u < 8; u++) {
      for (var x = 0; x < 8; x++) {
        final scale = u == 0 ? 0.35355339059327373 : 0.5;
        table[u * 8 + x] = scale * math.cos((2 * x + 1) * u * math.pi / 16);
      }
    }
    return table;
  }

  static Int32List _scaledQuant(List<int> base, int quality) {
    final q = quality.clamp(1, 100);
    final scale = q < 50 ? 5000 ~/ q : 200 - q * 2;
    final table = Int32List(64);
    for (var i = 0; i < 64; i++) {
      table[i] = ((base[i] * scale + 50) ~/ 100).clamp(1, 255);
    }
    return table;
  }

  Uint8List write(Uint8List rgba) {
    _header();
    final block = Float64List(64);
    final temp = Float64List(64);
    final coefficients = Int32List(64);
    var lastY = 0;
    var lastCb = 0;
    var lastCr = 0;
    final blocksX = (width + 7) >> 3;
    final blocksY = (height + 7) >> 3;
    final yPlane = Float64List(64);
    final cbPlane = Float64List(64);
    final crPlane = Float64List(64);

    for (var by = 0; by < blocksY; by++) {
      for (var bx = 0; bx < blocksX; bx++) {
        for (var y = 0; y < 8; y++) {
          final py = (by * 8 + y).clamp(0, height - 1);
          for (var x = 0; x < 8; x++) {
            final px = (bx * 8 + x).clamp(0, width - 1);
            final i = (py * width + px) * 4;
            final r = rgba[i].toDouble();
            final g = rgba[i + 1].toDouble();
            final b = rgba[i + 2].toDouble();
            final k = y * 8 + x;
            yPlane[k] = 0.299 * r + 0.587 * g + 0.114 * b - 128;
            cbPlane[k] = -0.168736 * r - 0.331264 * g + 0.5 * b;
            crPlane[k] = 0.5 * r - 0.418688 * g - 0.081312 * b;
          }
        }
        lastY = _encodeBlock(
          yPlane,
          block,
          temp,
          coefficients,
          _lumaTable,
          lastY,
        );
        lastCb = _encodeBlock(
          cbPlane,
          block,
          temp,
          coefficients,
          _chromaTable,
          lastCb,
        );
        lastCr = _encodeBlock(
          crPlane,
          block,
          temp,
          coefficients,
          _chromaTable,
          lastCr,
        );
      }
    }
    _flushBits();
    _out.add(const [0xFF, 0xD9]);
    return _out.takeBytes();
  }

  int _encodeBlock(
    Float64List plane,
    Float64List block,
    Float64List temp,
    Int32List coefficients,
    Int32List table,
    int previousDc,
  ) {
    for (var y = 0; y < 8; y++) {
      for (var u = 0; u < 8; u++) {
        var sum = 0.0;
        for (var x = 0; x < 8; x++) {
          sum += plane[y * 8 + x] * _cosine[u * 8 + x];
        }
        temp[y * 8 + u] = sum;
      }
    }
    for (var v = 0; v < 8; v++) {
      for (var u = 0; u < 8; u++) {
        var sum = 0.0;
        for (var y = 0; y < 8; y++) {
          sum += temp[y * 8 + u] * _cosine[v * 8 + y];
        }
        block[v * 8 + u] = sum;
      }
    }
    for (var k = 0; k < 64; k++) {
      final natural = _zigzag[k];
      coefficients[k] = (block[natural] / table[natural]).round();
    }

    final diff = coefficients[0] - previousDc;
    _writeValue(_dc, diff, 0);
    var zeros = 0;
    for (var k = 1; k < 64; k++) {
      final value = coefficients[k];
      if (value == 0) {
        zeros++;
        continue;
      }
      while (zeros > 15) {
        _writeBits(_ac.codes[0xF0], _ac.lengths[0xF0]);
        zeros -= 16;
      }
      _writeValue(_ac, value, zeros << 4);
      zeros = 0;
    }
    if (zeros > 0) _writeBits(_ac.codes[0x00], _ac.lengths[0x00]);
    return coefficients[0];
  }

  void _writeValue(_HuffmanTable table, int value, int runBits) {
    var magnitude = value < 0 ? -value : value;
    var size = 0;
    while (magnitude != 0) {
      size++;
      magnitude >>= 1;
    }
    final symbol = runBits | size;
    _writeBits(table.codes[symbol], table.lengths[symbol]);
    if (size > 0) {
      final bits = value < 0 ? value - 1 : value;
      _writeBits(bits & ((1 << size) - 1), size);
    }
  }

  void _writeBits(int bits, int count) {
    _bitBuffer = (_bitBuffer << count) | (bits & ((1 << count) - 1));
    _bitCount += count;
    while (_bitCount >= 8) {
      final byte = (_bitBuffer >> (_bitCount - 8)) & 0xFF;
      _out.addByte(byte);
      if (byte == 0xFF) _out.addByte(0);
      _bitCount -= 8;
    }
    _bitBuffer &= (1 << _bitCount) - 1;
  }

  void _flushBits() {
    if (_bitCount > 0) _writeBits(0x7F, 8 - _bitCount);
  }

  void _marker(int marker, List<int> payload) {
    final length = payload.length + 2;
    _out
      ..add([0xFF, marker, length >> 8, length & 0xFF])
      ..add(payload);
  }

  void _header() {
    _out.add(const [0xFF, 0xD8]);
    _marker(0xE0, const [0x4A, 0x46, 0x49, 0x46, 0, 1, 1, 0, 0, 1, 0, 1, 0, 0]);
    _marker(0xDB, [0, for (var k = 0; k < 64; k++) _lumaTable[_zigzag[k]]]);
    _marker(0xDB, [1, for (var k = 0; k < 64; k++) _chromaTable[_zigzag[k]]]);
    _marker(0xC0, [
      8,
      height >> 8,
      height & 0xFF,
      width >> 8,
      width & 0xFF,
      3,
      1,
      0x11,
      0,
      2,
      0x11,
      1,
      3,
      0x11,
      1,
    ]);
    _marker(0xC4, [0x00, ..._dcCounts, ..._dcValues]);
    _marker(0xC4, [0x10, ..._acCounts, ..._acValues]);
    _marker(0xDA, [3, 1, 0x00, 2, 0x00, 3, 0x00, 0, 63, 0]);
  }
}

/// Pixels handed to an isolate so a sheet can be encoded off the main thread.
class JpegPixels {
  const JpegPixels(this.width, this.height, this.rgba, this.quality);

  final int width;
  final int height;
  final Uint8List rgba;
  final int quality;
}

Uint8List encodeJpegPixels(JpegPixels pixels) => encodeJpeg(
  pixels.rgba,
  pixels.width,
  pixels.height,
  quality: pixels.quality,
);
