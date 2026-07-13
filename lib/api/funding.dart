import 'dart:async';
import 'dart:convert';
import 'package:json_annotation/json_annotation.dart';
import 'package:preconnect/api/api_client.dart';
import 'package:preconnect/tools/app_storage.dart';

part 'funding.g.dart';

@JsonSerializable()
class ContributionItem {
  @JsonKey(defaultValue: 'Anonymous')
  final String name;
  final String? picture;
  @JsonKey(defaultValue: 0)
  final int amount;
  @JsonKey(defaultValue: 0)
  final int ts;

  const ContributionItem({
    required this.name,
    this.picture,
    required this.amount,
    required this.ts,
  });

  factory ContributionItem.fromJson(Map<String, dynamic> json) =>
      _$ContributionItemFromJson(json);

  Map<String, dynamic> toJson() => _$ContributionItemToJson(this);
}

@JsonSerializable()
class FundingStatus {
  @JsonKey(defaultValue: 0)
  final int totalRaised;
  @JsonKey(defaultValue: 0)
  final int goal;
  @JsonKey(defaultValue: 0)
  final int contributorsCount;
  @JsonKey(defaultValue: <ContributionItem>[])
  final List<ContributionItem> contributions;

  const FundingStatus({
    required this.totalRaised,
    required this.goal,
    required this.contributorsCount,
    required this.contributions,
  });

  factory FundingStatus.fromJson(Map<String, dynamic> json) =>
      _$FundingStatusFromJson(json);

  Map<String, dynamic> toJson() => _$FundingStatusToJson(this);
}

class FundingService {
  static const String _url = 'https://preconnect.app/api/funding-status';
  static const String _cacheKey = 'funding_status_json';
  static const String _etagKey = 'funding_status_etag';

  static FundingStatus? _cached;

  static FundingStatus? get cached {
    if (_cached != null) return _cached;
    final cachedRaw = AppStorage.instance.getStringSync(_cacheKey);
    if (cachedRaw != null && cachedRaw.trim().isNotEmpty) {
      try {
        _cached = FundingStatus.fromJson(jsonDecode(cachedRaw));
      } catch (_) {}
    }
    return _cached;
  }

  static Future<FundingStatus?> fetchStatus() async {
    try {
      final cachedEtag = AppStorage.instance.getStringSync(_etagKey);
      final headers = <String, String>{};
      if (cachedEtag != null && cachedEtag.trim().isNotEmpty) {
        headers['If-None-Match'] = cachedEtag;
      }

      final response = await ApiClient().publicGet(
        _url,
        headers: headers,
        acceptedStatusCodes: const {200, 304},
        cacheDuration: Duration.zero,
      );

      if (response.statusCode == 304) {
        return cached;
      }

      if (response.statusCode == 200) {
        final body = response.body;
        if (body.trim().isNotEmpty) {
          final decoded = jsonDecode(body);
          if (decoded is Map<String, dynamic>) {
            final status = FundingStatus.fromJson(decoded);
            _cached = status;
            await AppStorage.instance.setString(_cacheKey, body);

            final etag = response.headers['etag'] ?? response.headers['ETag'];
            if (etag != null && etag.trim().isNotEmpty) {
              await AppStorage.instance.setString(_etagKey, etag);
            }
            return status;
          }
        }
      }
    } catch (_) {}
    return cached;
  }
}
