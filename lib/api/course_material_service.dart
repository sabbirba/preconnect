import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:preconnect/api/api_client.dart';
import 'package:preconnect/api/api_config.dart';

class CourseMaterialItem {
  const CourseMaterialItem({
    required this.materialId,
    required this.courseCode,
    required this.courseTitle,
    required this.semester,
    required this.title,
    required this.description,
    required this.fileName,
    required this.contentType,
    required this.fileSize,
    required this.isApproved,
    required this.canDelete,
    required this.filePath,
    required this.uploaderName,
    required this.externalUrl,
    this.createdAt,
    this.updatedAt,
  });

  final int materialId;
  final String courseCode;
  final String courseTitle;
  final String semester;
  final String title;
  final String description;
  final String fileName;
  final String contentType;
  final int fileSize;
  final bool isApproved;
  final bool? canDelete;
  final String filePath;
  final String uploaderName;
  final String externalUrl;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  factory CourseMaterialItem.fromJson(Map<String, dynamic> json) {
    return CourseMaterialItem(
      materialId: (json['materialId'] as num?)?.toInt() ?? 0,
      courseCode: '${json['courseCode'] ?? ''}'.trim(),
      courseTitle: '${json['courseTitle'] ?? ''}'.trim(),
      semester: '${json['semester'] ?? ''}'.trim(),
      title: '${json['title'] ?? ''}'.trim(),
      description: '${json['description'] ?? ''}'.trim(),
      fileName: '${json['fileName'] ?? ''}'.trim(),
      contentType: '${json['contentType'] ?? ''}'.trim(),
      fileSize: (json['fileSize'] as num?)?.toInt() ?? 0,
      isApproved: json['isApproved'] == true,
      canDelete:
          (json['canDelete'] as bool?) ??
          (json['can_delete'] as bool?) ??
          (json['isOwner'] as bool?) ??
          (json['is_owner'] as bool?) ??
          (json['isMine'] as bool?) ??
          (json['is_mine'] as bool?),
      filePath: '${json['filePath'] ?? ''}'.trim(),
      uploaderName: _firstNonEmpty(<dynamic>[
        json['uploaderName'],
        json['uploadedByName'],
        json['uploadedBy'],
        json['ownerName'],
        json['studentName'],
        json['fullName'],
        json['createdByName'],
      ]),
      externalUrl: _firstNonEmpty(<dynamic>[
        json['externalUrl'],
        json['linkUrl'],
        json['url'],
        json['materialUrl'],
      ]),
      createdAt: DateTime.tryParse('${json['createdAt'] ?? ''}'),
      updatedAt: DateTime.tryParse('${json['updatedAt'] ?? ''}'),
    );
  }

  static String _firstNonEmpty(List<dynamic> values) {
    for (final value in values) {
      final normalized = '${value ?? ''}'.trim();
      if (normalized.isNotEmpty) return normalized;
    }
    return '';
  }
}

class CourseMaterialDetail {
  const CourseMaterialDetail({
    required this.item,
    required this.downloadUrl,
    required this.downloadUrlExpiresIn,
  });

  final CourseMaterialItem item;
  final String downloadUrl;
  final int downloadUrlExpiresIn;

  factory CourseMaterialDetail.fromJson(Map<String, dynamic> json) {
    return CourseMaterialDetail(
      item: CourseMaterialItem.fromJson(json),
      downloadUrl: '${json['downloadUrl'] ?? ''}'.trim(),
      downloadUrlExpiresIn:
          (json['downloadUrlExpiresIn'] as num?)?.toInt() ?? 0,
    );
  }
}

class CourseMaterialUploadUrlResponse {
  const CourseMaterialUploadUrlResponse({
    required this.key,
    required this.uploadUrl,
    required this.expiresIn,
  });

  final String key;
  final String uploadUrl;
  final int expiresIn;

  factory CourseMaterialUploadUrlResponse.fromJson(Map<String, dynamic> json) {
    return CourseMaterialUploadUrlResponse(
      key: '${json['key'] ?? ''}'.trim(),
      uploadUrl: '${json['uploadUrl'] ?? ''}'.trim(),
      expiresIn: (json['expiresIn'] as num?)?.toInt() ?? 0,
    );
  }
}

class CourseMaterialUploadUrlInput {
  const CourseMaterialUploadUrlInput({
    required this.fileName,
    required this.contentType,
    required this.courseCode,
    required this.semester,
  });

  final String fileName;
  final String contentType;
  final String courseCode;
  final String semester;

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'fileName': fileName,
      'contentType': contentType,
      'courseCode': courseCode,
      'semester': semester,
    };
  }
}

class CourseMaterialFinalizeInput {
  const CourseMaterialFinalizeInput({
    required this.key,
    required this.courseCode,
    required this.courseTitle,
    required this.semester,
    required this.title,
    required this.description,
    required this.fileName,
    required this.contentType,
    required this.fileSize,
  });

  final String key;
  final String courseCode;
  final String courseTitle;
  final String semester;
  final String title;
  final String description;
  final String fileName;
  final String contentType;
  final int fileSize;

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'key': key,
      'courseCode': courseCode,
      'courseTitle': courseTitle,
      'semester': semester,
      'title': title,
      'description': description,
      'fileName': fileName,
      'contentType': contentType,
      'fileSize': fileSize,
    };
  }
}

class CourseMaterialService {
  CourseMaterialService._internal();
  static final CourseMaterialService _instance =
      CourseMaterialService._internal();
  factory CourseMaterialService() => _instance;

  final ApiClient _client = ApiClient();
  static const Duration _uploadTimeout = Duration(seconds: 40);
  static final Uri _filesBaseUri = Uri.parse(ApiConfig.filesBase);

  String get _base => ApiConfig.seatStatusProxyBase;

  Future<List<CourseMaterialItem>> list({
    required String courseCode,
    String semester = '',
    int limit = 20,
    int offset = 0,
    String search = '',
  }) async {
    final code = Uri.encodeQueryComponent(courseCode.trim().toUpperCase());
    final query = StringBuffer('courseCode=$code&limit=$limit&offset=$offset');
    final semesterValue = semester.trim();
    if (semesterValue.isNotEmpty) {
      query.write('&semester=${Uri.encodeQueryComponent(semesterValue)}');
    }
    final searchValue = search.trim();
    if (searchValue.isNotEmpty) {
      query.write('&search=${Uri.encodeQueryComponent(searchValue)}');
    }
    final response = await _client.publicGet(
      '$_base/v1/course-materials?$query',
    );
    final map = _decodeMap(response.body);
    final items =
        (map['items'] as List?)
            ?.whereType<Map>()
            .map((e) => CourseMaterialItem.fromJson(e.cast<String, dynamic>()))
            .toList() ??
        const <CourseMaterialItem>[];
    return items;
  }

  Future<CourseMaterialDetail> get({
    required String semester,
    required String courseCode,
    required String fileName,
  }) async {
    final path =
        '/v1/course-materials/'
        '${Uri.encodeComponent(semester.trim())}/'
        '${Uri.encodeComponent(courseCode.trim().toUpperCase())}/'
        '${Uri.encodeComponent(fileName.trim())}';
    final response = await _client.publicGet('$_base$path');
    return CourseMaterialDetail.fromJson(_decodeMap(response.body));
  }

  String resolvePublicDownloadUrl({
    required CourseMaterialItem item,
    required String signedDownloadUrl,
  }) {
    final fromFilePath = _storageKeySegmentsFromRaw(item.filePath);
    if (fromFilePath.isNotEmpty) {
      return _filesBaseUri.replace(pathSegments: fromFilePath).toString();
    }

    final signedUri = Uri.tryParse(signedDownloadUrl.trim());
    if (signedUri != null && signedUri.pathSegments.isNotEmpty) {
      final cleanedSegments = _storageKeySegmentsFromSignedUrl(signedUri);
      if (cleanedSegments.isNotEmpty) {
        return _filesBaseUri.replace(pathSegments: cleanedSegments).toString();
      }
    }

    return signedDownloadUrl.trim();
  }

  Future<CourseMaterialUploadUrlResponse> createUploadUrl(
    CourseMaterialUploadUrlInput input,
  ) async {
    final response = await _client.authenticatedRequest(
      'POST',
      '$_base/v1/course-materials/upload-url',
      body: jsonEncode(input.toJson()),
      additionalHeaders: const <String, String>{
        'Content-Type': 'application/json',
      },
    );
    return CourseMaterialUploadUrlResponse.fromJson(_decodeMap(response.body));
  }

  Future<void> uploadToSignedUrl({
    required String uploadUrl,
    required String contentType,
    required Uint8List bytes,
  }) async {
    final response = await http
        .put(
          Uri.parse(uploadUrl),
          headers: <String, String>{'Content-Type': contentType},
          body: bytes,
        )
        .timeout(_uploadTimeout);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ApiException(
        response.statusCode,
        'Signed upload failed: ${response.body}',
      );
    }
  }

  Future<CourseMaterialItem> finalize(CourseMaterialFinalizeInput input) async {
    final response = await _client.authenticatedRequest(
      'POST',
      '$_base/v1/course-materials',
      body: jsonEncode(input.toJson()),
      additionalHeaders: const <String, String>{
        'Content-Type': 'application/json',
      },
    );
    final map = _decodeMap(response.body);
    final item =
        (map['item'] as Map?)?.cast<String, dynamic>() ??
        const <String, dynamic>{};
    return CourseMaterialItem.fromJson(item);
  }

  Future<void> delete({
    required String semester,
    required String courseCode,
    required String fileName,
  }) async {
    final path =
        '/v1/course-materials/'
        '${Uri.encodeComponent(semester.trim())}/'
        '${Uri.encodeComponent(courseCode.trim().toUpperCase())}/'
        '${Uri.encodeComponent(fileName.trim())}';
    await _client.authenticatedRequest('DELETE', '$_base$path');
  }

  Future<bool> report({
    required String semester,
    required String courseCode,
    required String fileName,
    required String reason,
  }) async {
    final path =
        '/v1/course-materials/'
        '${Uri.encodeComponent(semester.trim())}/'
        '${Uri.encodeComponent(courseCode.trim().toUpperCase())}/'
        '${Uri.encodeComponent(fileName.trim())}/report';
    final response = await _client.authenticatedRequest(
      'POST',
      '$_base$path',
      body: jsonEncode(<String, dynamic>{'reason': reason}),
      additionalHeaders: const <String, String>{
        'Content-Type': 'application/json',
      },
    );
    final map = _decodeMap(response.body);
    return map['reported'] == true;
  }

  Map<String, dynamic> _decodeMap(String raw) {
    final decoded = jsonDecode(raw);
    if (decoded is Map<String, dynamic>) return decoded;
    if (decoded is Map) return decoded.cast<String, dynamic>();
    return const <String, dynamic>{};
  }

  List<String> _storageKeySegmentsFromRaw(String rawPath) {
    final normalized = rawPath.trim().replaceAll('\\', '/');
    if (normalized.isEmpty) return const <String>[];
    final segments = normalized
        .split('/')
        .where((segment) => segment.trim().isNotEmpty)
        .toList();
    if (segments.isEmpty) return const <String>[];
    if (segments.length >= 2 &&
        segments[0].toLowerCase() == 'v1' &&
        segments[1].toLowerCase() == 'course-materials') {
      return const <String>[];
    }
    return segments;
  }

  List<String> _storageKeySegmentsFromSignedUrl(Uri uri) {
    final host = uri.host.toLowerCase();
    final filesHost = _filesBaseUri.host.toLowerCase();
    final fromFilesHost = host == filesHost || host.endsWith('.$filesHost');
    if (!fromFilesHost) return const <String>[];
    final segments = uri.pathSegments
        .where((segment) => segment.trim().isNotEmpty)
        .toList();
    if (segments.length >= 2 &&
        segments[0].toLowerCase() == 'v1' &&
        segments[1].toLowerCase() == 'course-materials') {
      return const <String>[];
    }
    return segments;
  }
}
