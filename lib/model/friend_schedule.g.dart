// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'friend_schedule.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

FriendSchedule _$FriendScheduleFromJson(Map<String, dynamic> json) =>
    FriendSchedule(
      name: json['name'] as String? ?? '',
      id: json['id'] as String? ?? '',
      photoFilePath: json['photoFilePath'] as String?,
      photoUrl: json['photoUrl'] as String?,
      courses:
          (json['courses'] as List<dynamic>?)
              ?.map((e) => Course.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      shortCode: json['shortCode'] as String?,
      semester: json['semester'] as String?,
    );

Map<String, dynamic> _$FriendScheduleToJson(FriendSchedule instance) =>
    <String, dynamic>{
      'name': instance.name,
      'id': instance.id,
      'photoFilePath': instance.photoFilePath,
      'photoUrl': instance.photoUrl,
      'courses': instance.courses,
      'shortCode': instance.shortCode,
      'semester': instance.semester,
    };

CourseSchedule _$CourseScheduleFromJson(Map<String, dynamic> json) =>
    CourseSchedule(
      day: json['day'] as String? ?? '',
      startTime: json['startTime'] as String? ?? '',
      endTime: json['endTime'] as String? ?? '',
    );

Map<String, dynamic> _$CourseScheduleToJson(CourseSchedule instance) =>
    <String, dynamic>{
      'day': instance.day,
      'startTime': instance.startTime,
      'endTime': instance.endTime,
    };

FriendMetadata _$FriendMetadataFromJson(Map<String, dynamic> json) =>
    FriendMetadata(
      friendId: json['friendId'] as String? ?? '',
      nickname: json['nickname'] as String?,
      isFavorite: json['isFavorite'] as bool? ?? false,
    );

Map<String, dynamic> _$FriendMetadataToJson(FriendMetadata instance) =>
    <String, dynamic>{
      'friendId': instance.friendId,
      'nickname': instance.nickname,
      'isFavorite': instance.isFavorite,
    };
