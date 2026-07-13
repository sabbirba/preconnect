// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'progress_info.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

ProgressSummary _$ProgressSummaryFromJson(Map<String, dynamic> json) =>
    ProgressSummary(
      programName: json['programName'] as String? ?? '',
      totalCredit: (json['totalCredit'] as num?)?.toDouble() ?? 0.0,
      completedCredit: (json['completedCredit'] as num?)?.toDouble() ?? 0.0,
      completionPercent: (json['completionPercent'] as num?)?.toDouble() ?? 0.0,
      remainingCourses: (json['remainingCourses'] as num?)?.toInt() ?? 0,
    );

Map<String, dynamic> _$ProgressSummaryToJson(ProgressSummary instance) =>
    <String, dynamic>{
      'programName': instance.programName,
      'totalCredit': instance.totalCredit,
      'completedCredit': instance.completedCredit,
      'completionPercent': instance.completionPercent,
      'remainingCourses': instance.remainingCourses,
    };
