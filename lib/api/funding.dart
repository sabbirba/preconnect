import 'dart:async';
import 'dart:convert';
import 'package:preconnect/api/api_client.dart';
import 'package:preconnect/tools/app_storage.dart';

class ContributionItem {
  final String name;
  final String? picture;
  final int amount;
  final int ts;

  const ContributionItem({
    required this.name,
    this.picture,
    required this.amount,
    required this.ts,
  });

  factory ContributionItem.fromJson(Map<String, dynamic> json) {
    return ContributionItem(
      name: json['name'] as String? ?? 'Anonymous',
      picture: json['picture'] as String?,
      amount: json['amount'] as int? ?? 0,
      ts: json['ts'] as int? ?? 0,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'name': name,
      'picture': picture,
      'amount': amount,
      'ts': ts,
    };
  }
}

class FundingStatus {
  final int totalRaised;
  final int goal;
  final int contributorsCount;
  final List<ContributionItem> contributions;

  const FundingStatus({
    required this.totalRaised,
    required this.goal,
    required this.contributorsCount,
    required this.contributions,
  });

  factory FundingStatus.fromJson(Map<String, dynamic> json) {
    final list = json['contributions'] as List?;
    final contributionsList = list != null
        ? list.map((e) => ContributionItem.fromJson(e as Map<String, dynamic>)).toList()
        : <ContributionItem>[];

    return FundingStatus(
      totalRaised: json['totalRaised'] as int? ?? 0,
      goal: json['goal'] as int? ?? 0,
      contributorsCount: json['contributorsCount'] as int? ?? 0,
      contributions: contributionsList,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'totalRaised': totalRaised,
      'goal': goal,
      'contributorsCount': contributorsCount,
      'contributions': contributions.map((e) => e.toJson()).toList(),
    };
  }
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
