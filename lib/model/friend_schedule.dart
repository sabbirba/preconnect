import 'package:preconnect/api/api_config.dart';
import 'package:preconnect/model/section_info.dart';

class FriendSchedule {
  final String name;
  final String id;
  final String? photoFilePath;
  final String? photoUrl;
  final List<Section> courses;
  final String? semester;

  const FriendSchedule({
    required this.name,
    required this.id,
    required this.photoFilePath,
    required this.photoUrl,
    required this.courses,
    this.semester,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is FriendSchedule && id == other.id;

  @override
  int get hashCode => id.hashCode;

  factory FriendSchedule.fromJson(Map<String, dynamic> json) {
    final list = json['courses'] as List?;
    final coursesList = list != null
        ? list.map((e) => Section.fromJson(e as Map<String, dynamic>)).toList()
        : <Section>[];
    final photoFilePath = json['photoFilePath'] as String?;
    final photoUrl =
        json['photoUrl'] as String? ?? ApiConfig.photoUrl(photoFilePath);

    return FriendSchedule(
      name: json['name'] as String? ?? '',
      id: json['id'] as String? ?? '',
      photoFilePath: photoFilePath,
      photoUrl: photoUrl,
      courses: coursesList,
      semester: json['semester'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'name': name,
      'id': id,
      'photoFilePath': photoFilePath,
      'photoUrl': photoUrl,
      'courses': courses.map((e) => e.toJson()).toList(),
      'semester': semester,
    };
  }
}

typedef Course = Section;

extension SectionFriendExtension on Section {
  List<ClassSchedule> get schedule => sectionSchedule.classSchedules;

  String? get midExamDate => sectionSchedule.midExamDate;
  String? get midExamStartTime => sectionSchedule.midExamStartTime;
  String? get midExamEndTime => sectionSchedule.midExamEndTime;
  String? get midExamDetail => sectionSchedule.midExamDetail;

  String? get finalExamDate => sectionSchedule.finalExamDate;
  String? get finalExamStartTime => sectionSchedule.finalExamStartTime;
  String? get finalExamEndTime => sectionSchedule.finalExamEndTime;
  String? get finalExamDetail => sectionSchedule.finalExamDetail;

  Section toSection({int semesterSessionId = 0}) => this;
}

class FriendMetadata {
  final String friendId;
  final String? nickname;
  final bool isFavorite;

  const FriendMetadata({
    required this.friendId,
    this.nickname,
    this.isFavorite = false,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FriendMetadata && friendId == other.friendId;

  @override
  int get hashCode => friendId.hashCode;

  factory FriendMetadata.fromJson(Map<String, dynamic> json) {
    return FriendMetadata(
      friendId: json['friendId'] as String? ?? '',
      nickname: json['nickname'] as String?,
      isFavorite: json['isFavorite'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'friendId': friendId,
      'nickname': nickname,
      'isFavorite': isFavorite,
    };
  }

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
