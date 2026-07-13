// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'profile.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

AttendanceInfo _$AttendanceInfoFromJson(Map<String, dynamic> json) =>
    AttendanceInfo(
      courseSectionId: (json['courseSectionId'] as num?)?.toInt() ?? 0,
      studentPortfolioId: (json['studentPortfolioId'] as num?)?.toInt() ?? 0,
      courseName: json['courseName'] as String? ?? '',
      courseCode: json['courseCode'] as String? ?? '',
      attend: (json['attend'] as num?)?.toInt() ?? 0,
      missed: (json['missed'] as num?)?.toInt() ?? 0,
      remaining: (json['remaining'] as num?)?.toInt() ?? 0,
      totalClasses: (json['totalClasses'] as num?)?.toInt() ?? 0,
    );

Map<String, dynamic> _$AttendanceInfoToJson(AttendanceInfo instance) =>
    <String, dynamic>{
      'courseSectionId': instance.courseSectionId,
      'studentPortfolioId': instance.studentPortfolioId,
      'courseName': instance.courseName,
      'courseCode': instance.courseCode,
      'attend': instance.attend,
      'missed': instance.missed,
      'remaining': instance.remaining,
      'totalClasses': instance.totalClasses,
    };

PaymentInfo _$PaymentInfoFromJson(Map<String, dynamic> json) => PaymentInfo(
  paymentStatus: json['paymentStatus'] as String? ?? '',
  payslipNumber: json['payslipNumber'] as String? ?? '',
  paymentType: json['paymentType'] as String? ?? '',
  requestDate: DateTime.parse(json['requestDate'] as String),
  dueDate: DateTime.parse(json['dueDate'] as String),
  totalAmount: (json['totalAmount'] as num?)?.toDouble() ?? 0.0,
  semesterSessionId: (json['semesterSessionId'] as num?)?.toInt() ?? 0,
);

Map<String, dynamic> _$PaymentInfoToJson(PaymentInfo instance) =>
    <String, dynamic>{
      'paymentStatus': instance.paymentStatus,
      'payslipNumber': instance.payslipNumber,
      'paymentType': instance.paymentType,
      'requestDate': instance.requestDate.toIso8601String(),
      'dueDate': instance.dueDate.toIso8601String(),
      'totalAmount': instance.totalAmount,
      'semesterSessionId': instance.semesterSessionId,
    };
