import 'dart:convert';
import 'dart:typed_data';

import 'package:preconnect/tools/print_layout.dart';

class JpegPage {
  const JpegPage(this.jpeg, this.width, this.height, {this.fill = true});

  final Uint8List jpeg;
  final int width;
  final int height;

  final bool fill;
}

Uint8List jpegPagesPdf(List<JpegPage> pages) {
  final out = BytesBuilder(copy: false);
  final offsets = <int>[];
  var length = 0;

  void raw(List<int> bytes) {
    out.add(bytes);
    length += bytes.length;
  }

  void text(String value) => raw(latin1.encode(value));

  void object(int number, String dictionary, {Uint8List? stream}) {
    offsets.add(length);
    text('$number 0 obj\n$dictionary\n');
    if (stream != null) {
      text('stream\n');
      raw(stream);
      text('\nendstream\n');
    }
    text('endobj\n');
  }

  String number(double value) => value.toStringAsFixed(3);

  text('%PDF-1.4\n');
  raw(const [0x25, 0xE2, 0xE3, 0xCF, 0xD3, 0x0A]);
  object(1, '<< /Type /Catalog /Pages 2 0 R >>');
  final kids = [for (var i = 0; i < pages.length; i++) '${3 + i * 3} 0 R'];
  object(
    2,
    '<< /Type /Pages /Kids [${kids.join(' ')}] /Count ${pages.length} >>',
  );

  for (var i = 0; i < pages.length; i++) {
    final page = pages[i];
    final pageObject = 3 + i * 3;
    final width = PrintLayout.a4Width;
    final height = PrintLayout.a4Height;
    var drawWidth = width;
    var drawHeight = height;
    if (!page.fill) {
      final scale = [
        width / page.width,
        height / page.height,
      ].reduce((a, b) => a < b ? a : b);
      drawWidth = page.width * scale;
      drawHeight = page.height * scale;
    }
    final x = (width - drawWidth) / 2;
    final y = (height - drawHeight) / 2;
    final content = latin1.encode(
      'q ${number(drawWidth)} 0 0 ${number(drawHeight)} '
      '${number(x)} ${number(y)} cm /Im0 Do Q',
    );
    object(
      pageObject,
      '<< /Type /Page /Parent 2 0 R '
      '/MediaBox [0 0 ${number(width)} ${number(height)}] '
      '/Resources << /XObject << /Im0 ${pageObject + 2} 0 R >> >> '
      '/Contents ${pageObject + 1} 0 R >>',
    );
    object(
      pageObject + 1,
      '<< /Length ${content.length} >>',
      stream: Uint8List.fromList(content),
    );
    object(
      pageObject + 2,
      '<< /Type /XObject /Subtype /Image /Width ${page.width} '
      '/Height ${page.height} /ColorSpace /DeviceRGB '
      '/BitsPerComponent 8 /Filter /DCTDecode /Length ${page.jpeg.length} >>',
      stream: page.jpeg,
    );
  }

  final xref = length;
  final count = offsets.length + 1;
  text('xref\n0 $count\n0000000000 65535 f \n');
  for (final offset in offsets) {
    text('${offset.toString().padLeft(10, '0')} 00000 n \n');
  }
  text('trailer\n<< /Size $count /Root 1 0 R >>\nstartxref\n$xref\n%%EOF\n');
  return out.takeBytes();
}
