import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:preconnect/api/http_service.dart';

import 'package:preconnect/api/api_client.dart';
import 'package:preconnect/api/api_config.dart';
import 'package:preconnect/api/app_preferences_store.dart';

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
      materialId:
          (json['materialId'] as num?)?.toInt() ??
          (json['material_id'] as num?)?.toInt() ??
          0,
      courseCode: _firstNonEmpty(<dynamic>[
        json['courseCode'],
        json['course_code'],
      ]),
      courseTitle: _firstNonEmpty(<dynamic>[
        json['courseTitle'],
        json['course_title'],
      ]),
      semester: _firstNonEmpty(<dynamic>[json['semester']]),
      title: _firstNonEmpty(<dynamic>[json['title']]),
      description: _firstNonEmpty(<dynamic>[json['description']]),
      fileName: _firstNonEmpty(<dynamic>[json['fileName'], json['file_name']]),
      contentType: _firstNonEmpty(<dynamic>[
        json['contentType'],
        json['content_type'],
      ]),
      fileSize:
          (json['fileSize'] as num?)?.toInt() ??
          (json['file_size'] as num?)?.toInt() ??
          0,
      isApproved: json['isApproved'] == true || json['is_approved'] == true,
      canDelete: (json['canDelete'] as bool?) ?? (json['can_delete'] as bool?),
      filePath: _firstNonEmpty(<dynamic>[json['filePath'], json['file_path']]),
      uploaderName: _firstNonEmpty(<dynamic>[
        json['uploaderName'],
        json['uploader_name'],
        json['uploadedByName'],
        json['uploadedBy'],
        json['ownerName'],
        json['studentName'],
        json['fullName'],
        json['createdByName'],
      ]),
      externalUrl: _firstNonEmpty(<dynamic>[
        json['externalUrl'],
        json['external_url'],
        json['linkUrl'],
        json['link_url'],
        json['url'],
        json['materialUrl'],
        json['material_url'],
      ]),
      createdAt: DateTime.tryParse(
        _firstNonEmpty(<dynamic>[json['createdAt'], json['created_at']]),
      ),
      updatedAt: DateTime.tryParse(
        _firstNonEmpty(<dynamic>[json['updatedAt'], json['updated_at']]),
      ),
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'materialId': materialId,
      'courseCode': courseCode,
      'courseTitle': courseTitle,
      'semester': semester,
      'title': title,
      'description': description,
      'fileName': fileName,
      'contentType': contentType,
      'fileSize': fileSize,
      'isApproved': isApproved,
      'canDelete': canDelete,
      'filePath': filePath,
      'uploaderName': uploaderName,
      'externalUrl': externalUrl,
      'createdAt': createdAt?.toIso8601String(),
      'updatedAt': updatedAt?.toIso8601String(),
    };
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
    final itemJson =
        (json['item'] as Map?)?.cast<String, dynamic>() ??
        (json['material'] as Map?)?.cast<String, dynamic>() ??
        json;
    return CourseMaterialDetail(
      item: CourseMaterialItem.fromJson(itemJson),
      downloadUrl: CourseMaterialItem._firstNonEmpty(<dynamic>[
        json['downloadUrl'],
        json['download_url'],
      ]),
      downloadUrlExpiresIn:
          (json['downloadUrlExpiresIn'] as num?)?.toInt() ??
          (json['download_url_expires_in'] as num?)?.toInt() ??
          0,
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
      key: CourseMaterialItem._firstNonEmpty(<dynamic>[
        json['key'],
        json['storageKey'],
        json['storage_key'],
      ]),
      uploadUrl: CourseMaterialItem._firstNonEmpty(<dynamic>[
        json['uploadUrl'],
        json['upload_url'],
      ]),
      expiresIn:
          (json['expiresIn'] as num?)?.toInt() ??
          (json['expires_in'] as num?)?.toInt() ??
          0,
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
      'file_name': fileName,
      'contentType': contentType,
      'content_type': contentType,
      'courseCode': courseCode,
      'course_code': courseCode,
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
    this.externalUrl = '',
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
  final String externalUrl;

  Map<String, dynamic> toJson() {
    final normalizedExternalUrl = externalUrl.trim();
    return <String, dynamic>{
      'key': key,
      'storageKey': key,
      'storage_key': key,
      'courseCode': courseCode,
      'course_code': courseCode,
      'courseTitle': courseTitle,
      'course_title': courseTitle,
      'semester': semester,
      'title': title,
      'description': description,
      'fileName': fileName,
      'file_name': fileName,
      'contentType': contentType,
      'content_type': contentType,
      'fileSize': fileSize,
      'file_size': fileSize,
      if (normalizedExternalUrl.isNotEmpty) ...<String, dynamic>{
        'externalUrl': normalizedExternalUrl,
        'linkUrl': normalizedExternalUrl,
        'external_url': normalizedExternalUrl,
        'link_url': normalizedExternalUrl,
      },
    };
  }
}

class CourseMaterialService {
  CourseMaterialService._internal();
  static final CourseMaterialService _instance =
      CourseMaterialService._internal();
  factory CourseMaterialService() => _instance;

  final ApiClient _client = ApiClient();
  final AppPreferencesStore _store = AppPreferencesStore();
  static const Duration _uploadTimeout = Duration(seconds: 40);
  static final Uri _filesBaseUri = Uri.parse(ApiConfig.filesBase);
  static final Map<String, List<CourseMaterialItem>> _cachedLists =
      <String, List<CourseMaterialItem>>{};

  String get _realtimeBase => ApiConfig.realtimeApiBase;
  String get _publicBase => ApiConfig.publicJsonBase;

  Future<List<CourseMaterialItem>> list({
    required String courseCode,
    String semester = '',
    int limit = 20,
    int offset = 0,
    String search = '',
  }) async {
    final cacheKey = _cacheKey(
      courseCode: courseCode,
      semester: semester,
      limit: limit,
      offset: offset,
      search: search,
    );
    final cached = await _readCachedList(cacheKey);
    if (cached != null) {
      return cached;
    }
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
    final response = await _publicJsonGet(
      publicUrl: '$_publicBase/v1/course-materials?$query',
      realtimeUrl: '$_realtimeBase/v1/course-materials?$query',
    );
    final map = _decodeMap(response.body);
    final items = parseCourseMaterialItemsFromResponse(map);
    _cachedLists[cacheKey] = items;
    unawaited(_writeCachedList(cacheKey, items));
    return items;
  }

  String _cacheKey({
    required String courseCode,
    required String semester,
    required int limit,
    required int offset,
    required String search,
  }) {
    final code = courseCode.trim().toUpperCase();
    final sem = semester.trim();
    final q = search.trim();
    return 'course_materials_v1|$code|$sem|$limit|$offset|$q';
  }

  Future<List<CourseMaterialItem>?> _readCachedList(String cacheKey) async {
    final inMemory = _cachedLists[cacheKey];
    if (inMemory != null) return inMemory;
    final raw = await _store.getJsonMap(cacheKey);
    if (raw == null) return null;
    final itemsRaw = raw['items'];
    if (itemsRaw is! List) return null;
    final items = itemsRaw
        .whereType<Map>()
        .map((e) => CourseMaterialItem.fromJson(e.cast<String, dynamic>()))
        .toList();
    _cachedLists[cacheKey] = items;
    return items;
  }

  Future<void> _writeCachedList(
    String cacheKey,
    List<CourseMaterialItem> items,
  ) async {
    try {
      await _store.setJson(cacheKey, <String, dynamic>{
        'items': items.map((item) => item.toJson()).toList(),
      });
    } catch (_) {}
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
    final response = await _publicJsonGet(
      publicUrl: '$_publicBase$path',
      realtimeUrl: '$_realtimeBase$path',
    );
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
      '$_realtimeBase/v1/course-materials/upload-url',
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
    final response = await HttpService.client
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
      '$_realtimeBase/v1/course-materials',
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
    await _client.authenticatedRequest('DELETE', '$_realtimeBase$path');
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
      '$_realtimeBase$path',
      body: jsonEncode(<String, dynamic>{'reason': reason}),
      additionalHeaders: const <String, String>{
        'Content-Type': 'application/json',
      },
    );
    final map = _decodeMap(response.body);
    return map['reported'] == true;
  }

  Map<String, dynamic> _decodeMap(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) return decoded;
      if (decoded is Map) return decoded.cast<String, dynamic>();
    } catch (_) {}
    return const <String, dynamic>{};
  }

  List<String> _storageKeySegmentsFromRaw(String rawPath) {
    final normalized = rawPath.trim().replaceAll('\\', '/');
    if (normalized.isEmpty) return const <String>[];
    final uri = Uri.tryParse(normalized);
    if (uri != null && uri.hasScheme && uri.pathSegments.isNotEmpty) {
      return _storageKeySegmentsFromUri(uri);
    }
    final segments = normalized
        .split('/')
        .where((segment) => segment.trim().isNotEmpty)
        .toList();
    return _cleanStorageKeySegments(segments);
  }

  List<String> _storageKeySegmentsFromSignedUrl(Uri uri) {
    final host = uri.host.toLowerCase();
    final filesHost = _filesBaseUri.host.toLowerCase();
    final fromFilesHost = host == filesHost || host.endsWith('.$filesHost');
    final fromR2Host =
        host.endsWith('.r2.cloudflarestorage.com') ||
        host.endsWith('.r2.dev') ||
        host.contains('.r2.');
    if (!fromFilesHost && !fromR2Host) return const <String>[];
    return _storageKeySegmentsFromUri(uri);
  }

  List<String> _storageKeySegmentsFromUri(Uri uri) {
    final segments = uri.pathSegments
        .where((segment) => segment.trim().isNotEmpty)
        .toList();
    return _cleanStorageKeySegments(segments);
  }

  List<String> _cleanStorageKeySegments(List<String> segments) {
    if (segments.isEmpty) return const <String>[];
    if (segments.length >= 2 &&
        segments[0].toLowerCase() == 'v1' &&
        segments[1].toLowerCase() == 'course-materials') {
      return const <String>[];
    }
    if (segments.length >= 2 && segments[0].toLowerCase() == 'preconnect') {
      return segments.sublist(1);
    }
    return segments;
  }

  Future<http.Response> _publicJsonGet({
    required String publicUrl,
    required String realtimeUrl,
  }) async {
    try {
      return await _client.publicGet(publicUrl);
    } catch (_) {
      return _client.publicGet(realtimeUrl);
    }
  }
}

List<CourseMaterialItem> parseCourseMaterialItemsFromResponse(
  Map<String, dynamic> map,
) {
  final candidates = <dynamic>[
    map['items'],
    map['materials'],
    map['courseMaterials'],
    map['rows'],
    map['data'],
  ];
  for (final candidate in candidates) {
    final items = _courseMaterialItemsFromValue(candidate);
    if (items.isNotEmpty) return items;
  }
  return const <CourseMaterialItem>[];
}

List<CourseMaterialItem> _courseMaterialItemsFromValue(dynamic value) {
  final parsed = value is Map ? value.cast<String, dynamic>() : value;
  if (parsed is List) {
    return parsed
        .whereType<Map>()
        .map((e) => CourseMaterialItem.fromJson(e.cast<String, dynamic>()))
        .toList();
  }
  if (parsed is Map) {
    return parseCourseMaterialItemsFromResponse(parsed.cast<String, dynamic>());
  }
  return const <CourseMaterialItem>[];
}
