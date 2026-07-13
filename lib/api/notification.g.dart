// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'notification.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

RecentConnectNotification _$RecentConnectNotificationFromJson(
  Map<String, dynamic> json,
) => RecentConnectNotification(
  id: (json['id'] as num?)?.toInt() ?? 0,
  title: json['title'] == null ? '' : _trimString(json['title'] as String?),
  module: json['module'] == null ? '' : _trimString(json['module'] as String?),
  link: _trimNullableString(json['link'] as String?),
  createdOn: _dateTimeFromJson(json['createdOn'] as String?),
  expireAt: _dateTimeFromJson(json['expireAt'] as String?),
  seen: json['seen'] as bool? ?? false,
);

Map<String, dynamic> _$RecentConnectNotificationToJson(
  RecentConnectNotification instance,
) => <String, dynamic>{
  'id': instance.id,
  'title': instance.title,
  'module': instance.module,
  'link': instance.link,
  'createdOn': _dateTimeToJson(instance.createdOn),
  'expireAt': _dateTimeToJson(instance.expireAt),
  'seen': instance.seen,
};

NotificationsFeed _$NotificationsFeedFromJson(Map<String, dynamic> json) =>
    NotificationsFeed(
      newCount: (json['new'] as num?)?.toInt() ?? 0,
      items:
          (json['items'] as List<dynamic>?)
              ?.map(
                (e) => RecentConnectNotification.fromJson(
                  e as Map<String, dynamic>,
                ),
              )
              .toList() ??
          [],
    );

Map<String, dynamic> _$NotificationsFeedToJson(NotificationsFeed instance) =>
    <String, dynamic>{'new': instance.newCount, 'items': instance.items};

ConnectNotificationDetail _$ConnectNotificationDetailFromJson(
  Map<String, dynamic> json,
) => ConnectNotificationDetail(
  id: (json['id'] as num?)?.toInt() ?? 0,
  title: json['title'] == null ? '' : _trimString(json['title'] as String?),
  module: json['module'] == null ? '' : _trimString(json['module'] as String?),
  link: _trimNullableString(json['link'] as String?),
  expireAt: _dateTimeFromJson(json['expireAt'] as String?),
  createdOn: _dateTimeFromJson(json['createdOn'] as String?),
  details: json['details'] == null
      ? ''
      : _trimString(json['details'] as String?),
);

Map<String, dynamic> _$ConnectNotificationDetailToJson(
  ConnectNotificationDetail instance,
) => <String, dynamic>{
  'id': instance.id,
  'title': instance.title,
  'module': instance.module,
  'link': instance.link,
  'expireAt': _dateTimeToJson(instance.expireAt),
  'createdOn': _dateTimeToJson(instance.createdOn),
  'details': instance.details,
};

ScraperContentItem _$ScraperContentItemFromJson(
  Map<String, dynamic> json,
) => ScraperContentItem(
  id: json['id'] == null ? '' : _trimString(json['id'] as String?),
  source: json['source'] == null ? '' : _trimString(json['source'] as String?),
  title: json['title'] == null ? '' : _trimString(json['title'] as String?),
  message: json['message'] == null
      ? ''
      : _trimString(json['message'] as String?),
  url: json['url'] == null ? '' : _trimString(json['url'] as String?),
  publishedAt: _dateTimeFromJson(json['publishedAt'] as String?),
  imageUrl: _trimNullableString(json['imageUrl'] as String?),
  imageUrls:
      (json['imageUrls'] as List<dynamic>?)?.map((e) => e as String).toList() ??
      [],
);

Map<String, dynamic> _$ScraperContentItemToJson(ScraperContentItem instance) =>
    <String, dynamic>{
      'id': instance.id,
      'source': instance.source,
      'title': instance.title,
      'message': instance.message,
      'url': instance.url,
      'publishedAt': _dateTimeToJson(instance.publishedAt),
      'imageUrl': instance.imageUrl,
      'imageUrls': instance.imageUrls,
    };
