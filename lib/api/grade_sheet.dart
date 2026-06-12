import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:preconnect/api/api_client.dart';
import 'package:preconnect/api/api_config.dart';
import 'package:preconnect/api/profile.dart';
import 'package:preconnect/api/preferences_store.dart';
import 'package:preconnect/tools/app_paths.dart';
import 'package:preconnect/tools/app_storage.dart';

class GradeSheetFile {
  const GradeSheetFile({required this.file});

  final File file;
}

class GradeSheetService {
  GradeSheetService._internal();
  static final GradeSheetService _instance = GradeSheetService._internal();
  factory GradeSheetService() => _instance;

  final ApiClient _client = ApiClient();

  Stream<GradeSheetFile?> watchGradeSheet() async* {
    yield await getGradeSheet();
  }

  Future<Uint8List?> fetchGradeSheetBytes() async {
    final profileId = await resolvePortfolioId(
      prefs: AppPreferencesStore(),
      refreshProfile: () async {
        await ProfileService().fetchProfile(fromGet: true);
      },
    );

    if (profileId == null || profileId.isEmpty) return null;

    try {
      final response = await _client.authenticatedGet(
        '${ApiConfig.connectApiBase}${ApiConfig.gradeSheetPath(profileId)}',
        additionalHeaders: const <String, String>{
          'Accept': 'application/pdf, text/plain, */*',
        },
        cacheDuration: const Duration(seconds: 15),
      );
      final bytes = _extractPdfBytes(response.bodyBytes, response.body);
      if (bytes != null && bytes.isNotEmpty) return bytes;
    } catch (_) {}

    return null;
  }

  Future<GradeSheetFile?> fetchGradeSheet() async {
    final profileId = await resolvePortfolioId(
      prefs: AppPreferencesStore(),
      refreshProfile: () async {
        await ProfileService().fetchProfile(fromGet: true);
      },
    );

    if (profileId == null || profileId.isEmpty) {
      return null;
    }

    try {
      final response = await _client.authenticatedGet(
        '${ApiConfig.connectApiBase}${ApiConfig.gradeSheetPath(profileId)}',
        additionalHeaders: const <String, String>{
          'Accept': 'application/pdf, text/plain, */*',
        },
        cacheDuration: const Duration(seconds: 15),
      );
      final bytes = _extractPdfBytes(response.bodyBytes, response.body);
      if (bytes == null || bytes.isEmpty) {
        return null;
      }

      return GradeSheetFile(file: await _writeTempPdfFile(bytes));
    } catch (_) {
      return null;
    }
  }

  Future<GradeSheetFile?> getGradeSheet() async {
    return fetchGradeSheet();
  }

  Future<File> _writeTempPdfFile(Uint8List bytes) async {
    final file = await _gradeSheetTempFile();
    await file.parent.create(recursive: true);
    await file.writeAsBytes(bytes, flush: true);
    return file;
  }

  Future<File> _gradeSheetTempFile() async {
    final dir = await AppPaths.temporaryDirectory();
    final fileName = await gradeSheetFileName();
    return File('${dir.path}/$fileName.pdf');
  }

  Future<String> gradeSheetFileName() async {
    final fullName = (await AppStorage.instance.getString('fullName') ?? '')
        .trim();
    final studentId = (await AppStorage.instance.getString('studentId') ?? '')
        .trim();
    final safeName = fullName
        .replaceAll(RegExp(r'[\\/:*?"<>|]+'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim()
        .replaceAll(' ', '_');
    final safeStudentId = studentId
        .replaceAll(RegExp(r'[\\/:*?"<>|]+'), '')
        .trim();

    if (safeName.isNotEmpty && safeStudentId.isNotEmpty) {
      return '${safeName}_${safeStudentId}_Grade Sheet_PreConnect';
    }
    if (safeName.isNotEmpty) {
      return '${safeName}_Grade Sheet_PreConnect';
    }
    if (safeStudentId.isNotEmpty) {
      return '${safeStudentId}_Grade Sheet_PreConnect';
    }
    return 'Grade Sheet_PreConnect';
  }

  Uint8List? _extractPdfBytes(Uint8List rawBytes, String rawBody) {
    if (_looksLikePdf(rawBytes)) {
      return rawBytes;
    }

    final trimmed = rawBody.trim();
    if (trimmed.isEmpty) return null;

    final normalized = _normalizeBase64Payload(trimmed);
    if (normalized.isEmpty) return null;

    try {
      final decoded = base64Decode(normalized);
      if (_looksLikePdf(decoded)) {
        return Uint8List.fromList(decoded);
      }
    } catch (_) {}

    return null;
  }

  bool _looksLikePdf(List<int> bytes) {
    return bytes.length >= 4 &&
        bytes[0] == 0x25 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x44 &&
        bytes[3] == 0x46;
  }

  String _normalizeBase64Payload(String value) {
    var output = value;
    if (output.startsWith('"') && output.endsWith('"') && output.length >= 2) {
      try {
        output = jsonDecode(output) as String;
      } catch (_) {
        output = output.substring(1, output.length - 1);
      }
    }
    if (output.startsWith('data:')) {
      final commaIndex = output.indexOf(',');
      if (commaIndex >= 0) {
        output = output.substring(commaIndex + 1);
      }
    }
    return output.replaceAll(RegExp(r'\s+'), '');
  }
}
