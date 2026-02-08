class AttendanceInfo {
  final int courseSectionId;
  final int studentPortfolioId;
  final String courseName;
  final String courseCode;
  final int attend;
  final int missed;
  final int remaining;
  final int totalClasses;

  AttendanceInfo({
    required this.courseSectionId,
    required this.studentPortfolioId,
    required this.courseName,
    required this.courseCode,
    required this.attend,
    required this.missed,
    required this.remaining,
    required this.totalClasses,
  });

  factory AttendanceInfo.fromJson(Map<String, dynamic> json) {
    return AttendanceInfo(
      courseSectionId: json['courseSectionId'] ?? 0,
      studentPortfolioId: json['studentPortfolioId'] ?? 0,
      courseName: json['courseName'] ?? '',
      courseCode: json['courseCode'] ?? '',
      attend: json['attend'] ?? 0,
      missed: json['missed'] ?? 0,
      remaining: json['remaining'] ?? 0,
      totalClasses: json['totalClasses'] ?? 0,
    );
  }
}
