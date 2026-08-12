import 'package:http/http.dart' as http;

import 'http_client.dart';

class HttpUtils {
  static final http.Client client = createHttpClient();

  static String formBody(Map<String, String> fields) {
    final buffer = StringBuffer();
    var first = true;
    for (final entry in fields.entries) {
      if (!first) {
        buffer.write('&');
      }
      first = false;
      buffer.write(Uri.encodeQueryComponent(entry.key));
      buffer.write('=');
      buffer.write(Uri.encodeQueryComponent(entry.value));
    }
    return buffer.toString();
  }

  static String cookieHeader(Map<String, String> cookies) {
    return cookies.entries
        .map((entry) => '${entry.key}=${entry.value}')
        .join('; ');
  }

  static String lprJobFileName(
    String client, {
    String prefix = 'cf',
    required String suffix,
  }) {
    return '${prefix}A$suffix$client';
  }

  static String lprControlFile({
    required String client,
    required String owner,
    required String printableJobName,
    required String dataCommand,
    required String dataFileName,
    required String safeFileName,
    int copies = 1,
  }) {
    final effectiveCopies = copies < 1 ? 1 : copies;
    final dataCommands = List<String>.generate(
      effectiveCopies,
      (_) => '$dataCommand$dataFileName',
    );
    return [
      'H$client',
      'P$owner',
      'J$printableJobName',
      ...dataCommands,
      'U$dataFileName',
      'N$safeFileName',
      '',
    ].join('\n');
  }

  static String pjlPrefix({
    required String jobName,
    required int copies,
    required String duplexMode,
    required String collateMode,
    required bool isPostScript,
    required String pagesPerSheet,
    required String fittingMode,
    required String staple,
    required String punch,
    required String jobOffset,
    required String slipSheet,
    required String booklet,
  }) {
    final language = isPostScript ? 'POSTSCRIPT' : 'PDF';
    final duplex = duplexMode.trim().toUpperCase();
    final collate = collateMode.trim().toUpperCase();
    final useDuplex = duplex != 'OFF';
    return [
      '\x1B%-12345X',
      '@PJL JOB NAME = "${_escapePjlValue(jobName)}"\r\n',
      '@PJL SET COPIES = $copies\r\n',
      '@PJL SET COLLATE = ${collate == 'OFF' ? 'OFF' : 'ON'}\r\n',
      '@PJL SET PAPER = A4\r\n',
      '@PJL SET ORIENTATION = PORTRAIT\r\n',
      '@PJL SET RESOLUTION = 600\r\n',
      '@PJL SET MANUALFEED = OFF\r\n',
      '@PJL SET PERSONALITY = AUTO\r\n',
      '@PJL SET DUPLEX = ${useDuplex ? 'ON' : 'OFF'}\r\n',
      if (useDuplex) '@PJL SET BINDING = LONGEDGE\r\n',
      if (pagesPerSheet == '2-in-1') ...[
        '@PJL SET MULTIPAGE = 2\r\n',
        '@PJL SET NUP = 2\r\n',
      ] else if (pagesPerSheet == '4-in-1') ...[
        '@PJL SET MULTIPAGE = 4\r\n',
        '@PJL SET NUP = 4\r\n',
      ],
      if (fittingMode == 'Fit on Printable Area') ...[
        '@PJL SET FITOPRINTABLE = ON\r\n',
        '@PJL SET ZOOM = FIT\r\n',
        '@PJL SET FITTOPAGESIZE = ON\r\n',
      ] else if (fittingMode == 'Edge-to-Edge') ...[
        '@PJL SET EDGETOEDGE = ON\r\n',
      ] else ...[
        '@PJL SET FITOPRINTABLE = OFF\r\n',
        '@PJL SET FITTOPAGESIZE = OFF\r\n',
        '@PJL SET EDGETOEDGE = OFF\r\n',
      ],
      if (staple == 'Left Corner') ...[
        '@PJL SET STAPLE = LEFTCORNER\r\n',
      ] else if (staple == 'Right Corner') ...[
        '@PJL SET STAPLE = RIGHTCORNER\r\n',
      ] else ...[
        '@PJL SET STAPLE = OFF\r\n',
      ],
      if (punch == '2 Holes') ...[
        '@PJL SET PUNCH = 2HOLE\r\n',
      ] else if (punch == '3 Holes') ...[
        '@PJL SET PUNCH = 3HOLE\r\n',
      ] else ...[
        '@PJL SET PUNCH = OFF\r\n',
      ],
      '@PJL SET JOBOFFSET = ${jobOffset == 'On' ? 'ON' : 'OFF'}\r\n',
      '@PJL SET SLIPSHEET = ${slipSheet == 'On' ? 'ON' : 'OFF'}\r\n',
      if (booklet == 'On') ...[
        '@PJL SET MULTIPAGE = BOOKLET\r\n',
        '@PJL SET FOLD = SADDLE\r\n',
        '@PJL SET STAPLE = SADDLESTITCH\r\n',
        '@PJL SET OUTBIN = BOOKLET\r\n',
      ],
      '@PJL ENTER LANGUAGE = $language\r\n',
    ].join();
  }

  static String _escapePjlValue(String value) {
    return value.replaceAll('\\', '\\\\').replaceAll('"', '\\"');
  }
}
