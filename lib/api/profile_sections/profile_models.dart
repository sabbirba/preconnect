part of '../profile.dart';

class AttendanceInfo {
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

  final int courseSectionId;
  final int studentPortfolioId;
  final String courseName;
  final String courseCode;
  final int attend;
  final int missed;
  final int remaining;
  final int totalClasses;

  factory AttendanceInfo.fromJson(Map<String, dynamic> json) {
    return AttendanceInfo(
      courseSectionId: json['courseSectionId'] as int? ?? 0,
      studentPortfolioId: json['studentPortfolioId'] as int? ?? 0,
      courseName: json['courseName'] as String? ?? '',
      courseCode: json['courseCode'] as String? ?? '',
      attend: json['attend'] as int? ?? 0,
      missed: json['missed'] as int? ?? 0,
      remaining: json['remaining'] as int? ?? 0,
      totalClasses: json['totalClasses'] as int? ?? 0,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'courseSectionId': courseSectionId,
    'studentPortfolioId': studentPortfolioId,
    'courseName': courseName,
    'courseCode': courseCode,
    'attend': attend,
    'missed': missed,
    'remaining': remaining,
    'totalClasses': totalClasses,
  };
}

class PaymentInfo {
  PaymentInfo({
    required this.paymentStatus,
    required this.payslipNumber,
    required this.paymentType,
    required this.requestDate,
    required this.dueDate,
    required this.totalAmount,
    required this.semesterSessionId,
  });

  final String paymentStatus;
  final String payslipNumber;
  final String paymentType;
  final DateTime requestDate;
  final DateTime dueDate;
  final double totalAmount;
  final int semesterSessionId;

  factory PaymentInfo.fromJson(Map<String, dynamic> json) {
    return PaymentInfo(
      paymentStatus: json['paymentStatus'] as String? ?? '',
      payslipNumber: json['payslipNumber'] as String? ?? '',
      paymentType: json['paymentType'] as String? ?? '',
      requestDate: DateTime.parse(json['requestDate'] as String),
      dueDate: DateTime.parse(json['dueDate'] as String),
      totalAmount: (json['totalAmount'] as num?)?.toDouble() ?? 0,
      semesterSessionId: json['semesterSessionId'] as int? ?? 0,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'paymentStatus': paymentStatus,
    'payslipNumber': payslipNumber,
    'paymentType': paymentType,
    'requestDate': requestDate.toIso8601String(),
    'dueDate': dueDate.toIso8601String(),
    'totalAmount': totalAmount,
    'semesterSessionId': semesterSessionId,
  };
}
