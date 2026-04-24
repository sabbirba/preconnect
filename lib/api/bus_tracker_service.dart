import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:preconnect/api/api_client.dart';
import 'package:preconnect/api/api_config.dart';

class BusTrackerService {
  BusTrackerService._internal();
  static final BusTrackerService _instance = BusTrackerService._internal();
  factory BusTrackerService() => _instance;

  final ApiClient _client = ApiClient();

  Future<List<BusTrackerRouteSnapshot>> fetchFleetSnapshots(
    Iterable<String> codes,
  ) async {
    final normalizedCodes = <String>[
      for (final code in codes) code.trim().toUpperCase(),
    ].where((code) => code.isNotEmpty).toSet().toList(growable: false);

    if (normalizedCodes.isEmpty) return const <BusTrackerRouteSnapshot>[];

    await _refreshFinderSession();

    final snapshots = await Future.wait(
      normalizedCodes.map((code) async {
        return _fetchLiveSnapshot(code);
      }),
    );

    return snapshots.whereType<BusTrackerRouteSnapshot>().toList(
      growable: false,
    );
  }

  Stream<BusTrackerRouteSnapshot?> watchFleetSnapshot(
    String code,
  ) async* {
    final normalizedCode = code.trim().toUpperCase();
    if (normalizedCode.isEmpty) {
      yield null;
      return;
    }

    try {
      final snapshots = await fetchFleetSnapshots(<String>[normalizedCode]);
      yield snapshots.isEmpty ? null : snapshots.first;
    } catch (_) {
      yield null;
    }
  }

  Future<Map<String, dynamic>?> fetchLastData() async {
    try {
      final code = _defaultBusCode();
      if (code.isEmpty) return null;
      final snapshots = await fetchFleetSnapshots(<String>[code]);
      return snapshots.isEmpty ? null : snapshots.first.lastData;
    } catch (_) {}
    return null;
  }

  Future<BusTrackerRouteSnapshot?> _fetchLiveSnapshot(String code) async {
    try {
      final assetInfoUrl = ApiConfig.busTrackerAssetInfoUrl(code);
      if (assetInfoUrl.isEmpty) return null;

      final assetInfoResponse = await _client.publicGet(
        assetInfoUrl,
        acceptedStatusCodes: <int>{200},
      );
      final assetInfo = _decodeMap(assetInfoResponse.body);
      final assetId = _extractAssetId(assetInfo);
      Map<String, dynamic>? lastData;
      if (assetId.isNotEmpty) {
        final lastDataUrl = ApiConfig.busTrackerLastDataUrl(assetId);
        if (lastDataUrl.isNotEmpty) {
          final lastDataResponse = await _client.publicGet(
            lastDataUrl,
            acceptedStatusCodes: <int>{200},
          );
          lastData = _decodeMap(lastDataResponse.body);
        }
      }

      if (assetInfo == null && lastData == null) return null;
      return BusTrackerRouteSnapshot(
        code: code,
        assetInfo: assetInfo,
        lastData: lastData,
        source: 'live',
      );
    } catch (_) {
      return null;
    }
  }

  String _defaultBusCode() {
    final assetCode = ApiConfig.finderLbsAssetCode.trim().toUpperCase();
    if (assetCode.isNotEmpty) return assetCode;
    return '';
  }

  Map<String, dynamic>? _decodeMap(String raw) {
    final parsed = _decodeDynamic(raw);
    if (parsed is Map<String, dynamic>) {
      return parsed;
    }
    if (parsed is Map) return parsed.cast<String, dynamic>();
    return null;
  }

  dynamic _decodeDynamic(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return null;
    try {
      return jsonDecode(trimmed);
    } catch (_) {
      return null;
    }
  }

  Future<void> _refreshFinderSession() async {
    final accessToken = ApiConfig.finderLbsAccessToken.trim();
    final refreshToken = ApiConfig.finderLbsRefreshToken.trim();
    if (accessToken.isEmpty || refreshToken.isEmpty) return;

    try {
      await http
          .post(
            Uri.parse(ApiConfig.finderLbsRefreshEndpoint),
            headers: const {
              'Content-Type': 'application/json',
              'Accept': 'application/json',
            },
            body: jsonEncode(<String, String>{
              'access_token': accessToken,
              'refresh_token': refreshToken,
            }),
          )
          .timeout(const Duration(seconds: 10));
    } catch (_) {}
  }

  String _extractAssetId(Map<String, dynamic>? json) {
    if (json == null) return '';
    final rawId = json['_id'];
    if (rawId is String && rawId.trim().isNotEmpty) {
      return rawId.trim();
    }
    if (rawId is Map) {
      final oid = '${rawId[r'$oid'] ?? ''}'.trim();
      if (oid.isNotEmpty) return oid;
    }
    final assetId = '${json['asset_id'] ?? ''}'.trim();
    return assetId;
  }
}

class BusTrackerRouteSnapshot {
  const BusTrackerRouteSnapshot({
    required this.code,
    required this.assetInfo,
    required this.lastData,
    required this.source,
  });

  final String code;
  final Map<String, dynamic>? assetInfo;
  final Map<String, dynamic>? lastData;
  final String source;

  String get assetId => _extractAssetIdFromJson(lastData).isNotEmpty
      ? _extractAssetIdFromJson(lastData)
      : _extractAssetIdFromJson(assetInfo);
  String get assetName => _stringValue(lastData, <String>['name']).isNotEmpty
      ? _stringValue(lastData, <String>['name'])
      : _stringValue(assetInfo, <String>['name']);
  String get assetType =>
      _stringValue(lastData, <String>['asset_type']).isNotEmpty
      ? _stringValue(lastData, <String>['asset_type'])
      : _stringValue(assetInfo, <String>['asset_type']);
  String get status => _stringValue(lastData, <String>['status']);
  String get speed => _stringValue(lastData, <String>['speed']);
  String get heading => _stringValue(lastData, <String>['heading']);
  String get bearing => _stringValue(lastData, <String>['bearing']);
  String get updatedAt =>
      _stringValue(lastData, <String>['time', 'status_time']);
  String get locationDescription =>
      _stringValue(lastData, <String>['location']);
  String get latitude => _latitudeLongitudePair.$1;
  String get longitude => _latitudeLongitudePair.$2;
  bool get hasPosition => latitude.isNotEmpty && longitude.isNotEmpty;
  double? get latitudeValue => double.tryParse(latitude);
  double? get longitudeValue => double.tryParse(longitude);

  (String, String) get _latitudeLongitudePair {
    final loc = lastData?['loc'];
    final coords = loc is Map ? loc['coordinates'] : null;
    final longitude = coords is List && coords.isNotEmpty
        ? '${coords[0]}'.trim()
        : '';
    final latitude = coords is List && coords.length > 1
        ? '${coords[1]}'.trim()
        : '';
    return (latitude, longitude);
  }

  static String _stringValue(Map<String, dynamic>? json, List<String> keys) {
    if (json == null) return '';
    for (final key in keys) {
      final value = '${json[key] ?? ''}'.trim();
      if (value.isNotEmpty) return value;
    }
    return '';
  }
}

String _extractAssetIdFromJson(Map<String, dynamic>? json) {
  if (json == null) return '';
  final rawId = json['_id'];
  if (rawId is String && rawId.trim().isNotEmpty) {
    return rawId.trim();
  }
  if (rawId is Map) {
    final oid = '${rawId[r'$oid'] ?? ''}'.trim();
    if (oid.isNotEmpty) return oid;
  }
  final assetId = '${json['asset_id'] ?? ''}'.trim();
  return assetId;
}
