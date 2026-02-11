import 'dart:convert';

class FriendSchedule {
  final String name;
  final String id;
  final String? photoFilePath;
  final String? photoUrl;
  final List<Course> courses;

  FriendSchedule({
    required this.name,
    required this.id,
    required this.photoFilePath,
    required this.photoUrl,
    required this.courses,
  });

  factory FriendSchedule.fromJson(Map<String, dynamic> json) {
    final photoFilePath = json['photoFilePath']?.toString();
    final providedUrl = json['photoUrl']?.toString();
    return FriendSchedule(
      name: json['name'] ?? '',
      id: json['id'] ?? '',
      photoFilePath: photoFilePath,
      photoUrl: providedUrl ?? _buildPhotoUrl(photoFilePath),
      courses: (json['courses'] as List<dynamic>? ?? [])
          .map((e) => Course.fromJson(e))
          .toList(),
    );
  }
}

String? _buildPhotoUrl(String? photoFilePath) {
  if (photoFilePath == null || photoFilePath.isEmpty) return null;
  final encoded = base64Url
      .encode(utf8.encode(photoFilePath))
      .replaceAll('=', '');
  return 'https://connect.bracu.ac.bd/cdn/img/thumb/$encoded.jpg';
}

class Course {
  final String courseCode;
  final String? sectionName;
  final String? roomNumber;
  final String? faculties;
  final List<CourseSchedule> schedule;

  Course({
    required this.courseCode,
    required this.schedule,
    required this.sectionName,
    required this.roomNumber,
    required this.faculties,
  });

  factory Course.fromJson(Map<String, dynamic> json) {
    final roomNumber =
        json['roomNumber']?.toString() ?? json['roomName']?.toString();

    List<CourseSchedule> schedules = [];

    String convertTime(String time24) {
      if (time24.isEmpty) return '';
      final parts = time24.split(':');
      int hour = int.parse(parts[0]);
      final minute = parts[1];
      final period = hour >= 12 ? 'PM' : 'AM';
      if (hour > 12) hour -= 12;
      if (hour == 0) hour = 12;
      return '$hour:$minute $period';
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
          .map((e) => CourseSchedule.fromJson(e))
          .toList();
    }

    return Course(
      courseCode: json['courseCode'] ?? '',
      sectionName: json['sectionName']?.toString(),
      roomNumber: roomNumber?.isEmpty == true ? null : roomNumber,
      faculties: json['faculties']?.toString(),
      schedule: schedules,
    );
  }
}

class CourseSchedule {
  final String day;
  final String startTime;
  final String endTime;

  CourseSchedule({
    required this.day,
    required this.startTime,
    required this.endTime,
  });

  factory CourseSchedule.fromJson(Map<String, dynamic> json) {
    return CourseSchedule(
      day: json['day'] ?? '',
      startTime: json['startTime'] ?? '',
      endTime: json['endTime'] ?? '',
    );
  }
}

class FriendMetadata {
  final String friendId;
  final String? nickname;
  final bool isFavorite;

  FriendMetadata({
    required this.friendId,
    this.nickname,
    this.isFavorite = false,
  });

  factory FriendMetadata.fromJson(Map<String, dynamic> json) {
    return FriendMetadata(
      friendId: json['friendId'] ?? '',
      nickname: json['nickname']?.toString(),
      isFavorite: json['isFavorite'] ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'friendId': friendId,
      'nickname': nickname,
      'isFavorite': isFavorite,
    };
  }

  FriendMetadata copyWith({String? nickname, bool? isFavorite}) {
    return FriendMetadata(
      friendId: friendId,
      nickname: nickname ?? this.nickname,
      isFavorite: isFavorite ?? this.isFavorite,
    );
  }
}
