// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'funding.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

ContributionItem _$ContributionItemFromJson(Map<String, dynamic> json) =>
    ContributionItem(
      name: json['name'] as String? ?? 'Anonymous',
      picture: json['picture'] as String?,
      amount: (json['amount'] as num?)?.toInt() ?? 0,
      ts: (json['ts'] as num?)?.toInt() ?? 0,
    );

Map<String, dynamic> _$ContributionItemToJson(ContributionItem instance) =>
    <String, dynamic>{
      'name': instance.name,
      'picture': instance.picture,
      'amount': instance.amount,
      'ts': instance.ts,
    };

FundingStatus _$FundingStatusFromJson(Map<String, dynamic> json) =>
    FundingStatus(
      totalRaised: (json['totalRaised'] as num?)?.toInt() ?? 0,
      goal: (json['goal'] as num?)?.toInt() ?? 0,
      contributorsCount: (json['contributorsCount'] as num?)?.toInt() ?? 0,
      contributions:
          (json['contributions'] as List<dynamic>?)
              ?.map((e) => ContributionItem.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
    );

Map<String, dynamic> _$FundingStatusToJson(FundingStatus instance) =>
    <String, dynamic>{
      'totalRaised': instance.totalRaised,
      'goal': instance.goal,
      'contributorsCount': instance.contributorsCount,
      'contributions': instance.contributions,
    };
