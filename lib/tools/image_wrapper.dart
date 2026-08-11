import 'dart:io';
import 'dart:typed_data';

class ImageWrapper {
  static bool isImageFile(String fileName, Uint8List bytes) {
    final lower = fileName.toLowerCase();
    if (lower.endsWith('.jpg') ||
        lower.endsWith('.jpeg') ||
        lower.endsWith('.png')) {
      return true;
    }
    if (bytes.length >= 3 &&
        bytes[0] == 0xFF &&
        bytes[1] == 0xD8 &&
        bytes[2] == 0xFF) {
      return true;
    }
    if (bytes.length >= 8 &&
        bytes[0] == 0x89 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x4E &&
        bytes[3] == 0x47) {
      return true;
    }
    return false;
  }

  static Uint8List wrapImageToPdf({
    required Uint8List bytes,
    required String fileName,
  }) {
    final isPng = _isPng(fileName, bytes);
    final dims = isPng
        ? _parsePngDimensions(bytes)
        : _parseJpegDimensions(bytes);
    final imgWidth = dims.width > 0 ? dims.width.toDouble() : 595.28;
    final imgHeight = dims.height > 0 ? dims.height.toDouble() : 841.89;

    const pageWidth = 595.28;
    const pageHeight = 841.89;
    const margin = 18.0;

    final availWidth = pageWidth - (margin * 2);
    final availHeight = pageHeight - (margin * 2);

    final scaleX = availWidth / imgWidth;
    final scaleY = availHeight / imgHeight;
    final scale = scaleX < scaleY ? scaleX : scaleY;

    final renderWidth = imgWidth * scale;
    final renderHeight = imgHeight * scale;

    final xPos = (pageWidth - renderWidth) / 2;
    final yPos = (pageHeight - renderHeight) / 2;

    Uint8List imageStreamBytes;
    String filterName;
    String colorSpace;
    int bitsPerComponent = 8;
    String extraDict = '';

    if (isPng) {
      final pngData = _convertPngToPdfStream(bytes);
      imageStreamBytes = pngData.streamBytes;
      filterName = '/FlateDecode';
      colorSpace = pngData.colorSpace;
      bitsPerComponent = pngData.bitsPerComponent;
      if (pngData.decodeParms.isNotEmpty) {
        extraDict = '/DecodeParms << ${pngData.decodeParms} >>';
      }
    } else {
      imageStreamBytes = bytes;
      filterName = '/DCTDecode';
      colorSpace = '/DeviceRGB';
    }

    final contentStream =
        'q ${renderWidth.toStringAsFixed(2)} 0 0 ${renderHeight.toStringAsFixed(2)} ${xPos.toStringAsFixed(2)} ${yPos.toStringAsFixed(2)} cm /I1 Do Q';

    final body = BytesBuilder(copy: false);
    final offsets = <int>[0];

    void writeObj(int num, String strContent, [Uint8List? binaryStream]) {
      offsets.add(body.length);
      body.add(_ascii('$num 0 obj\n'));
      body.add(_ascii(strContent));
      if (binaryStream != null) {
        body.add(_ascii('\nstream\n'));
        body.add(binaryStream);
        body.add(_ascii('\nendstream'));
      }
      body.add(_ascii('\nendobj\n'));
    }

    body.add(_ascii('%PDF-1.4\n%\xFF\xFF\xFF\xFF\n'));

    writeObj(1, '<< /Type /Catalog /Pages 2 0 R >>');
    writeObj(2, '<< /Type /Pages /Kids [3 0 R] /Count 1 >>');
    writeObj(
      3,
      '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 595.28 841.89] /Resources << /XObject << /I1 4 0 R >> >> /Contents 5 0 R >>',
    );

    final imgDict = [
      '<< /Type /XObject /Subtype /Image',
      '/Width ${dims.width}',
      '/Height ${dims.height}',
      '/ColorSpace $colorSpace',
      '/BitsPerComponent $bitsPerComponent',
      '/Filter $filterName',
      if (extraDict.isNotEmpty) extraDict,
      '/Length ${imageStreamBytes.length} >>',
    ].join(' ');

    writeObj(4, imgDict, imageStreamBytes);
    writeObj(
      5,
      '<< /Length ${contentStream.length} >>',
      Uint8List.fromList(_ascii(contentStream)),
    );

    final startXref = body.length;
    body.add(_ascii('xref\n0 6\n0000000000 65535 f \n'));
    for (var i = 1; i <= 5; i++) {
      final offsetStr = offsets[i].toString().padLeft(10, '0');
      body.add(_ascii('$offsetStr 00000 n \n'));
    }
    body.add(
      _ascii(
        'trailer\n<< /Size 6 /Root 1 0 R >>\nstartxref\n$startXref\n%%EOF\n',
      ),
    );

    return body.takeBytes();
  }

  static int readPdfPageCount(Uint8List bytes) {
    if (bytes.length < 10) return 1;

    try {
      final text = String.fromCharCodes(bytes);
      final catalogCount = _resolveCatalogPageCount(text);
      if (catalogCount != null && catalogCount > 0) {
        return catalogCount;
      }

      final countFromPages = _extractMaxPagesCount(text);
      if (countFromPages != null && countFromPages > 0) {
        return countFromPages;
      }

      final directPageCount = _countDirectPageObjects(text);
      if (directPageCount > 0) {
        return directPageCount;
      }

      final decompressedText = _decompressPdfStreams(bytes);
      if (decompressedText.isNotEmpty) {
        final decompressedCatalog = _resolveCatalogPageCount(decompressedText);
        if (decompressedCatalog != null && decompressedCatalog > 0) {
          return decompressedCatalog;
        }

        final decompressedCount = _extractMaxPagesCount(decompressedText);
        if (decompressedCount != null && decompressedCount > 0) {
          return decompressedCount;
        }

        final decompressedDirect = _countDirectPageObjects(decompressedText);
        if (decompressedDirect > 0) {
          return decompressedDirect;
        }
      }
    } catch (_) {}

    return 1;
  }

  static int? _resolveCatalogPageCount(String text) {
    final rootMatch = RegExp(r'/Root\s+(\d+)\s+(\d+)\s+R').firstMatch(text);
    if (rootMatch != null) {
      final rootObjId = rootMatch.group(1);
      final catalogRegExp = RegExp(
        '$rootObjId\\s+\\d+\\s+obj\\s*<<[^>]*?/Pages\\s+(\\d+)\\s+(\\d+)\\s+R',
        dotAll: true,
      );
      final catalogMatch = catalogRegExp.firstMatch(text);
      if (catalogMatch != null) {
        final pagesObjId = catalogMatch.group(1);
        final pagesRegExp = RegExp(
          '$pagesObjId\\s+\\d+\\s+obj\\s*<<[^>]*?/Count\\s+(\\d+)',
          dotAll: true,
        );
        final pagesMatch = pagesRegExp.firstMatch(text);
        if (pagesMatch != null) {
          return int.tryParse(pagesMatch.group(1) ?? '');
        }
      }
    }
    return null;
  }

  static int? _extractMaxPagesCount(String text) {
    var maxCount = 0;

    final pagesDictRegExp = RegExp(
      r'<<[^>]*?/Type\s*/Pages\b[^>]*?>>',
      dotAll: true,
    );
    final matches = pagesDictRegExp.allMatches(text);
    for (final match in matches) {
      final dict = match.group(0) ?? '';
      final countMatch = RegExp(r'/Count\s+(\d+)').firstMatch(dict);
      if (countMatch != null) {
        final val = int.tryParse(countMatch.group(1) ?? '');
        if (val != null && val > maxCount) {
          maxCount = val;
        }
      }
    }

    if (maxCount > 0) return maxCount;

    final countFirstRegExp = RegExp(
      r'<<[^>]*?/Count\s+(\d+)[^>]*?/Type\s*/Pages\b[^>]*?>>',
      dotAll: true,
    );
    for (final match in countFirstRegExp.allMatches(text)) {
      final val = int.tryParse(match.group(1) ?? '');
      if (val != null && val > maxCount) {
        maxCount = val;
      }
    }

    if (maxCount > 0) return maxCount;

    final fallbackMatches = RegExp(
      r'/Type\s*/Pages\b[^]*?/Count\s+(\d+)',
    ).allMatches(text);
    for (final match in fallbackMatches) {
      final val = int.tryParse(match.group(1) ?? '');
      if (val != null && val > maxCount) {
        maxCount = val;
      }
    }

    return maxCount > 0 ? maxCount : null;
  }

  static int _countDirectPageObjects(String text) {
    final pageObjRegExp = RegExp(r'/Type\s*/Page\b(?![sS])');
    return pageObjRegExp.allMatches(text).length;
  }

  static String _decompressPdfStreams(Uint8List bytes) {
    final sb = StringBuffer();
    final len = bytes.length;
    var i = 0;

    while (i < len - 6) {
      if (bytes[i] == 0x73 &&
          bytes[i + 1] == 0x74 &&
          bytes[i + 2] == 0x72 &&
          bytes[i + 3] == 0x65 &&
          bytes[i + 4] == 0x61 &&
          bytes[i + 5] == 0x6D) {
        var start = i + 6;
        if (start < len && bytes[start] == 0x0D) start++;
        if (start < len && bytes[start] == 0x0A) start++;

        var end = start;
        while (end < len - 9) {
          if (bytes[end] == 0x65 &&
              bytes[end + 1] == 0x6E &&
              bytes[end + 2] == 0x64 &&
              bytes[end + 3] == 0x73 &&
              bytes[end + 4] == 0x74 &&
              bytes[end + 5] == 0x72 &&
              bytes[end + 6] == 0x65 &&
              bytes[end + 7] == 0x61 &&
              bytes[end + 8] == 0x6D) {
            break;
          }
          end++;
        }

        if (end > start && end < len) {
          final streamChunk = bytes.sublist(start, end);
          try {
            final decompressed = zlib.decode(streamChunk);
            sb.write(String.fromCharCodes(decompressed));
          } catch (_) {}
        }
        i = end + 9;
      } else {
        i++;
      }
    }
    return sb.toString();
  }

  static bool _isPng(String fileName, Uint8List bytes) {
    if (fileName.toLowerCase().endsWith('.png')) return true;
    return bytes.length >= 8 &&
        bytes[0] == 0x89 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x4E &&
        bytes[3] == 0x47;
  }

  static ({int width, int height}) _parseJpegDimensions(Uint8List bytes) {
    if (bytes.length < 4 || bytes[0] != 0xFF || bytes[1] != 0xD8) {
      return (width: 595, height: 842);
    }
    var offset = 2;
    while (offset < bytes.length - 8) {
      if (bytes[offset] != 0xFF) {
        offset++;
        continue;
      }
      final marker = bytes[offset + 1];
      if (marker == 0xD9 || marker == 0xDA) break;

      final blockLength = (bytes[offset + 2] << 8) | bytes[offset + 3];
      if (marker >= 0xC0 &&
          marker <= 0xCF &&
          marker != 0xC4 &&
          marker != 0xC8 &&
          marker != 0xCC) {
        final height = (bytes[offset + 5] << 8) | bytes[offset + 6];
        final width = (bytes[offset + 7] << 8) | bytes[offset + 8];
        return (width: width, height: height);
      }
      offset += 2 + blockLength;
    }
    return (width: 595, height: 842);
  }

  static ({int width, int height}) _parsePngDimensions(Uint8List bytes) {
    if (bytes.length >= 24 &&
        bytes[0] == 0x89 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x4E &&
        bytes[3] == 0x47) {
      final width =
          (bytes[16] << 24) | (bytes[17] << 16) | (bytes[18] << 8) | bytes[19];
      final height =
          (bytes[20] << 24) | (bytes[21] << 16) | (bytes[22] << 8) | bytes[23];
      return (width: width, height: height);
    }
    return (width: 595, height: 842);
  }

  static _PngPdfData _convertPngToPdfStream(Uint8List bytes) {
    final dims = _parsePngDimensions(bytes);
    final width = dims.width;
    final height = dims.height;

    try {
      final idatBytes = _extractPngIdat(bytes);
      final bitDepth = bytes.length > 24 ? bytes[24] : 8;
      final colorType = bytes.length > 25 ? bytes[25] : 6;

      if (colorType == 6 || colorType == 2 || colorType == 0) {
        final uncompressed = zlib.decode(idatBytes);
        final bytesPerPixel = colorType == 6 ? 4 : (colorType == 2 ? 3 : 1);
        final rawRgb = _unfilterPng(uncompressed, width, height, bytesPerPixel);
        final compressedRgb = zlib.encode(rawRgb);

        return _PngPdfData(
          streamBytes: Uint8List.fromList(compressedRgb),
          colorSpace: colorType == 0 ? '/DeviceGray' : '/DeviceRGB',
          bitsPerComponent: bitDepth > 0 ? bitDepth : 8,
          decodeParms: '',
        );
      }
    } catch (_) {}

    final fallbackRgb = Uint8List(width * height * 3);
    for (var i = 0; i < fallbackRgb.length; i += 3) {
      fallbackRgb[i] = 0xFF;
      fallbackRgb[i + 1] = 0xFF;
      fallbackRgb[i + 2] = 0xFF;
    }
    return _PngPdfData(
      streamBytes: Uint8List.fromList(zlib.encode(fallbackRgb)),
      colorSpace: '/DeviceRGB',
      bitsPerComponent: 8,
      decodeParms: '',
    );
  }

  static Uint8List _extractPngIdat(Uint8List bytes) {
    final builder = BytesBuilder(copy: false);
    var offset = 8;
    while (offset < bytes.length - 12) {
      final length =
          (bytes[offset] << 24) |
          (bytes[offset + 1] << 16) |
          (bytes[offset + 2] << 8) |
          bytes[offset + 3];
      final type = String.fromCharCodes(bytes.sublist(offset + 4, offset + 8));
      if (type == 'IDAT') {
        builder.add(bytes.sublist(offset + 8, offset + 8 + length));
      } else if (type == 'IEND') {
        break;
      }
      offset += 12 + length;
    }
    return builder.takeBytes();
  }

  static Uint8List _unfilterPng(
    List<int> input,
    int width,
    int height,
    int bytesPerPixel,
  ) {
    final isRgba = bytesPerPixel == 4;
    final outPixelComponents = isRgba ? 3 : bytesPerPixel;
    final output = Uint8List(width * height * outPixelComponents);

    final stride = 1 + (width * bytesPerPixel);
    final currRow = Uint8List(width * bytesPerPixel);
    final prevRow = Uint8List(width * bytesPerPixel);

    var outIdx = 0;

    for (var y = 0; y < height; y++) {
      final rowStart = y * stride;
      if (rowStart >= input.length) break;

      final filterType = input[rowStart];

      for (var x = 0; x < width * bytesPerPixel; x++) {
        final rawVal = input[rowStart + 1 + x];
        final left = x >= bytesPerPixel ? currRow[x - bytesPerPixel] : 0;
        final above = prevRow[x];

        var val = rawVal;
        switch (filterType) {
          case 1:
            val = (rawVal + left) & 0xFF;
            break;
          case 2:
            val = (rawVal + above) & 0xFF;
            break;
          case 3:
            val = (rawVal + ((left + above) >> 1)) & 0xFF;
            break;
          case 4:
            final upperLeft = x >= bytesPerPixel
                ? prevRow[x - bytesPerPixel]
                : 0;
            val = (rawVal + _paethPredictor(left, above, upperLeft)) & 0xFF;
            break;
        }
        currRow[x] = val;
      }

      for (var pixel = 0; pixel < width; pixel++) {
        final pIdx = pixel * bytesPerPixel;
        output[outIdx++] = currRow[pIdx];
        if (bytesPerPixel >= 2) output[outIdx++] = currRow[pIdx + 1];
        if (bytesPerPixel >= 3) output[outIdx++] = currRow[pIdx + 2];
      }

      prevRow.setAll(0, currRow);
    }

    return output;
  }

  static int _paethPredictor(int a, int b, int c) {
    final p = a + b - c;
    final pa = (p - a).abs();
    final pb = (p - b).abs();
    final pc = (p - c).abs();
    if (pa <= pb && pa <= pc) return a;
    if (pb <= pc) return b;
    return c;
  }

  static List<int> _ascii(String value) {
    return value.codeUnits.map((u) => u <= 0x7F ? u : 0x3F).toList();
  }
}

class _PngPdfData {
  const _PngPdfData({
    required this.streamBytes,
    required this.colorSpace,
    required this.bitsPerComponent,
    required this.decodeParms,
  });

  final Uint8List streamBytes;
  final String colorSpace;
  final int bitsPerComponent;
  final String decodeParms;
}
