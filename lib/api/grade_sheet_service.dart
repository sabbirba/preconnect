import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:path_provider/path_provider.dart';
import 'package:preconnect/api/api_client.dart';
import 'package:preconnect/api/api_config.dart';
import 'package:preconnect/api/profile_service.dart';
import 'package:preconnect/api/app_preferences_store.dart';
import 'package:preconnect/tools/app_storage.dart';

class GradeSheetFile {
  const GradeSheetFile({required this.file, required this.fromCache});

  final File file;
  final bool fromCache;
}

class GradeSheetService {
  GradeSheetService._internal();
  static final GradeSheetService _instance = GradeSheetService._internal();
  factory GradeSheetService() => _instance;

  final ApiClient _client = ApiClient();
  final Map<String, Future<GradeSheetFile?>> _inFlight =
      <String, Future<GradeSheetFile?>>{};
  final StreamController<GradeSheetFile?> _streamController =
      StreamController<GradeSheetFile?>.broadcast();

  Stream<GradeSheetFile?> watchGradeSheet() async* {
    yield await getGradeSheet();
    yield* _streamController.stream;
  }

  Future<Uint8List?> fetchGradeSheetBytes({bool fromGet = false}) async {
    final profileId = await resolvePortfolioId(
      prefs: AppPreferencesStore(),
      refreshProfile: () => ProfileService().fetchProfile(fromGet: true),
    );

    if (profileId == null || profileId.isEmpty) return null;

    try {
      final response = await _client.authenticatedGet(
        '${ApiConfig.connectApiBase}${ApiConfig.gradeSheetPath(profileId)}',
        additionalHeaders: const <String, String>{
          'Accept': 'application/pdf, text/plain, */*',
        },
      );
      final bytes = _extractPdfBytes(response.bodyBytes, response.body);
      if (bytes != null && bytes.isNotEmpty) return bytes;
    } catch (e) {
      debugPrint('[GRADE_SHEET] ERROR in fetchGradeSheetBytes: $e');
    }

    if (fromGet) return null;
    return fetchGradeSheetBytes(fromGet: true);
  }

  Future<GradeSheetFile?> fetchGradeSheet({bool fromGet = false}) async {
    final key = 'gradesheet|$fromGet';
    final inFlight = _inFlight[key];
    if (inFlight != null) {
      return inFlight;
    }

    final request = _fetchGradeSheetInternal(fromGet: fromGet);
    _inFlight[key] = request;
    try {
      return await request;
    } finally {
      _inFlight.remove(key);
    }
  }

  Future<GradeSheetFile?> _fetchGradeSheetInternal({
    required bool fromGet,
  }) async {
    final profileId = await resolvePortfolioId(
      prefs: AppPreferencesStore(),
      refreshProfile: () => ProfileService().fetchProfile(fromGet: true),
    );

    if (profileId == null || profileId.isEmpty) {
      return fromGet ? null : getGradeSheet(fromFetch: true);
    }

    try {
      final response = await _client.authenticatedGet(
        '${ApiConfig.connectApiBase}${ApiConfig.gradeSheetPath(profileId)}',
        additionalHeaders: const <String, String>{
          'Accept': 'application/pdf, text/plain, */*',
        },
      );
      final bytes = _extractPdfBytes(response.bodyBytes, response.body);
      if (bytes == null || bytes.isEmpty) {
        final fallback = fromGet ? null : await getGradeSheet(fromFetch: true);
        _publish(fallback);
        return fallback;
      }

      final file = await _writePdfFile(profileId, bytes);
      final result = GradeSheetFile(file: file, fromCache: false);
      _publish(result);
      return result;
    } catch (_) {
      final fallback = fromGet ? null : await getGradeSheet(fromFetch: true);
      _publish(fallback);
      return fallback;
    }
  }

  Future<GradeSheetFile?> getGradeSheet({bool fromFetch = false}) async {
    final profileId = await resolvePortfolioId(
      prefs: AppPreferencesStore(),
      refreshProfile: () => ProfileService().fetchProfile(fromGet: true),
    );
    if (profileId == null || profileId.isEmpty) return null;

    final file = await _gradeSheetFile(profileId);
    if (await file.exists()) {
      final result = GradeSheetFile(file: file, fromCache: true);
      _publish(result);
      return result;
    }

    if (fromFetch) return null;
    return fetchGradeSheet(fromGet: true);
  }

  Future<File> _writePdfFile(String profileId, Uint8List bytes) async {
    final file = await _gradeSheetFile(profileId);
    await file.parent.create(recursive: true);
    await file.writeAsBytes(bytes, flush: true);
    return file;
  }

  Future<File> _gradeSheetFile(String profileId) async {
    final dir = await getApplicationSupportDirectory();
    final fileName = await gradeSheetFileName(profileId: profileId);
    return File('${dir.path}/$fileName.pdf');
  }

  Future<String> gradeSheetFileName({String? profileId}) async {
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
    final fallbackId = (profileId ?? '').trim();
    return fallbackId.isEmpty
        ? 'Grade Sheet_PreConnect'
        : '${fallbackId}_Grade Sheet_PreConnect';
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
      debugPrint('[GRADE_SHEET] Extracted bytes don\'t look like PDF');
    } catch (e) {
      debugPrint('[GRADE_SHEET] PDF extraction error: $e');
    }

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

  void _publish(GradeSheetFile? value) {
    if (_streamController.isClosed) return;
    _streamController.add(value);
  }
}
