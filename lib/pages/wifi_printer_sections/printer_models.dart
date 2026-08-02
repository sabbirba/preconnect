part of '../wifi_printer.dart';

class _SelectedFile {
  _SelectedFile({required this.name, required this.bytes, this.pageCount});

  final String name;
  final Uint8List bytes;
  int? pageCount;
}

class _CampusPrinterConfig {
  const _CampusPrinterConfig({
    required this.hosts,
    required this.port,
    required this.queue,
  });

  final List<String> hosts;
  final int port;
  final String queue;

  static const _CampusPrinterConfig current = _CampusPrinterConfig(
    hosts: <String>['172.16.0.111'],
    port: 515,
    queue: 'secure',
  );
}

class _CampusPrinterBootstrap {
  const _CampusPrinterBootstrap({
    required this.copies,
    required this.history,
    required this.studentId,
    required this.studentName,
    required this.studentShortCode,
    required this.currentSemester,
    required this.pagesPerSheet,
    required this.fittingMode,
    required this.staple,
    required this.punch,
    required this.jobOffset,
    required this.slipSheet,
    required this.booklet,
    this.profile,
    this.photoUrl,
  });

  final int copies;
  final List<_PrintHistoryEntry> history;
  final String studentId;
  final String studentName;
  final String studentShortCode;
  final String currentSemester;
  final String pagesPerSheet;
  final String fittingMode;
  final String staple;
  final String punch;
  final String jobOffset;
  final String slipSheet;
  final String booklet;
  final Map<String, String?>? profile;
  final String? photoUrl;
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
