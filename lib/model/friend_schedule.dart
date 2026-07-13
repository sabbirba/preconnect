import 'dart:convert';
import 'package:json_annotation/json_annotation.dart';
import 'package:equatable/equatable.dart';
import 'package:preconnect/api/api_config.dart';
import 'package:preconnect/tools/time_utils.dart';

part 'friend_schedule.g.dart';

@JsonSerializable()
class FriendSchedule extends Equatable {
  @JsonKey(defaultValue: '')
  final String name;
  @JsonKey(defaultValue: '')
  final String id;
  final String? photoFilePath;
  final String? photoUrl;
  @JsonKey(defaultValue: <Course>[])
  final List<Course> courses;
  final String? shortCode;
  final String? semester;

  const FriendSchedule({
    required this.name,
    required this.id,
    required this.photoFilePath,
    required this.photoUrl,
    required this.courses,
    this.shortCode,
    this.semester,
  });

  @override
  List<Object?> get props => [
    name,
    id,
    photoFilePath,
    photoUrl,
    courses,
    shortCode,
    semester,
  ];

  factory FriendSchedule.fromJson(Map<String, dynamic> json) {
    final temp = _$FriendScheduleFromJson(json);
    return FriendSchedule(
      name: temp.name,
      id: temp.id,
      photoFilePath: temp.photoFilePath,
      photoUrl: temp.photoUrl ?? _buildPhotoUrl(temp.photoFilePath),
      courses: temp.courses,
      shortCode: temp.shortCode,
      semester: temp.semester,
    );
  }

  Map<String, dynamic> toJson() => _$FriendScheduleToJson(this);
}

String? _buildPhotoUrl(String? photoFilePath) {
  if (photoFilePath == null || photoFilePath.isEmpty) return null;
  final encoded = base64Url
      .encode(utf8.encode(photoFilePath))
      .replaceAll('=', '');
  return '${ApiConfig.connectCdnBase}/img/thumb/$encoded.jpg';
}

class Course extends Equatable {
  @JsonKey(defaultValue: '')
  final String courseCode;
  final String? sectionName;
  final String? roomNumber;
  final String? faculties;
  @JsonKey(defaultValue: <CourseSchedule>[])
  final List<CourseSchedule> schedule;

  const Course({
    required this.courseCode,
    required this.schedule,
    required this.sectionName,
    required this.roomNumber,
    required this.faculties,
  });

  @override
  List<Object?> get props => [
    courseCode,
    sectionName,
    roomNumber,
    faculties,
    schedule,
  ];

  factory Course.fromJson(Map<String, dynamic> json) {
    final roomNumber =
        json['roomNumber']?.toString() ?? json['roomName']?.toString();

    List<CourseSchedule> schedules = [];

    String convertTime(String time24) {
      return BracuTime.format(time24);
    }

    String convertDay(String day) {
      if (day.isEmpty) return '';
      return day[0].toUpperCase() + day.substring(1).toLowerCase();
    }

    if (json['sectionSchedule'] != null) {
      var sectionSchedule = json['sectionSchedule'];

      if (sectionSchedule is String) {
        try {
          sectionSchedule = jsonDecode(sectionSchedule);
        } catch (_) {
          sectionSchedule = null;
        }
      }

      if (sectionSchedule is Map) {
        final classSchedules =
            sectionSchedule['classSchedules'] as List<dynamic>? ?? [];
        schedules = classSchedules.map((e) {
          final schedule = e as Map<String, dynamic>;
          return CourseSchedule(
            day: convertDay(schedule['day']?.toString() ?? ''),
            startTime: convertTime(schedule['startTime']?.toString() ?? ''),
            endTime: convertTime(schedule['endTime']?.toString() ?? ''),
          );
        }).toList();
      }
    } else if (json['schedule'] != null) {
      schedules = (json['schedule'] as List<dynamic>? ?? [])
          .map((e) => CourseSchedule.fromJson(e as Map<String, dynamic>))
          .toList();
    }

    return Course(
      courseCode: json['courseCode'] ?? '',
      sectionName: json['sectionName']?.toString(),
      roomNumber: roomNumber?.isEmpty == true ? null : roomNumber,
      faculties: _facultyLabel(json['faculties']),
      schedule: schedules,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'courseCode': courseCode,
      'sectionName': sectionName,
      'roomNumber': roomNumber,
      'faculties': faculties,
      'schedule': schedule.map((e) => e.toJson()).toList(),
    };
  }
}

@JsonSerializable()
class CourseSchedule extends Equatable {
  @JsonKey(defaultValue: '')
  final String day;
  @JsonKey(defaultValue: '')
  final String startTime;
  @JsonKey(defaultValue: '')
  final String endTime;

  const CourseSchedule({
    required this.day,
    required this.startTime,
    required this.endTime,
  });

  @override
  List<Object?> get props => [day, startTime, endTime];

  factory CourseSchedule.fromJson(Map<String, dynamic> json) =>
      _$CourseScheduleFromJson(json);

  Map<String, dynamic> toJson() => _$CourseScheduleToJson(this);
}

@JsonSerializable()
class FriendMetadata extends Equatable {
  @JsonKey(defaultValue: '')
  final String friendId;
  final String? nickname;
  @JsonKey(defaultValue: false)
  final bool isFavorite;

  const FriendMetadata({
    required this.friendId,
    this.nickname,
    this.isFavorite = false,
  });

  @override
  List<Object?> get props => [friendId, nickname, isFavorite];

  factory FriendMetadata.fromJson(Map<String, dynamic> json) =>
      _$FriendMetadataFromJson(json);

  Map<String, dynamic> toJson() => _$FriendMetadataToJson(this);

  static const Object _unsetNickname = Object();

  FriendMetadata copyWith({
    Object? nickname = _unsetNickname,
    bool? isFavorite,
  }) {
    return FriendMetadata(
      friendId: friendId,
      nickname: identical(nickname, _unsetNickname)
          ? this.nickname
          : nickname as String?,
      isFavorite: isFavorite ?? this.isFavorite,
    );
  }
}

String? _facultyLabel(dynamic value) {
  if (value == null) return null;
  if (value is Map) {
    final map = value.cast<String, dynamic>();
    final staffName = '${map['staffName'] ?? ''}'.trim();
    if (staffName.isNotEmpty) return staffName;
    final shortName = '${map['shortName'] ?? ''}'.trim();
    if (shortName.isNotEmpty) return shortName;
    return null;
  }
  final label = value.toString().trim();
  return label.isEmpty ? null : label;
}
