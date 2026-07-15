import 'package:preconnect/tools/string_utils.dart';

class ProgressInfo {
  ProgressInfo({
    required this.programName,
    required this.academicDegree,
    required this.curriculumSession,
    required this.totalCredit,
    required this.headers,
    required this.completedCourses,
    required this.majorOptions,
    required this.minorOptions,
    required this.curriculumCourses,
  });

  final String programName;
  final String academicDegree;
  final String curriculumSession;
  final double totalCredit;
  final List<ProgressHeader> headers;
  final List<CompletedCourse> completedCourses;
  final List<String> majorOptions;
  final List<String> minorOptions;
  final List<CurriculumCourse> curriculumCourses;

  factory ProgressInfo.fromPayload(Map<String, dynamic> payload) {
    final curriculumRaw = payload['curriculum'];
    final completedRaw = payload['completedCourses'];
    final majorMinorRaw = payload['majorMinors'];
    final prerequisiteRaw = payload['coursePrerequisites'];
    final prerequisiteByCode = _buildCoursePrerequisiteMap(prerequisiteRaw);

    final curriculum = curriculumRaw is Map<String, dynamic>
        ? curriculumRaw
        : curriculumRaw is List && curriculumRaw.isNotEmpty
        ? (curriculumRaw.first is Map<String, dynamic>
              ? curriculumRaw.first as Map<String, dynamic>
              : const <String, dynamic>{})
        : const <String, dynamic>{};

    final headersRaw = curriculum['headerCreditRequirements'];
    final curriculumCourses = <CurriculumCourse>[];
    final seenCourseCodes = <String>{};
    final headers = headersRaw is List
        ? headersRaw
              .whereType<Map>()
              .map((e) => e.cast<String, dynamic>())
              .map((header) {
                final subHeaders = header['subHeaderCreditRequirements'];
                final courseCodes = <String>{};
                final headerName = (header['name'] ?? '').toString().trim();
                if (subHeaders is List) {
                  for (final subHeader in subHeaders.whereType<Map>().map(
                    (e) => e.cast<String, dynamic>(),
                  )) {
                    final subHeaderName = (subHeader['name'] ?? '')
                        .toString()
                        .trim();
                    final courses = subHeader['curriculumCourses'];
                    if (courses is! List) continue;
                    for (final course in courses.whereType<Map>().map(
                      (e) => e.cast<String, dynamic>(),
                    )) {
                      final code = (course['courseCode'] ?? '')
                          .toString()
                          .trim();
                      if (code.isNotEmpty) {
                        final normalizedCode = code.toUpperCase();
                        courseCodes.add(normalizedCode);
                        if (!seenCourseCodes.contains(normalizedCode)) {
                          seenCourseCodes.add(normalizedCode);
                          curriculumCourses.add(
                            CurriculumCourse(
                              code: normalizedCode,
                              title: (course['courseName'] ?? '')
                                  .toString()
                                  .trim(),
                              credit: _toDouble(course['courseCredit']),
                              isMandatory:
                                  (course['isMandatory'] ?? false) == true,
                              headerName: headerName,
                              subHeaderName: subHeaderName,
                              prerequisiteExpression:
                                  prerequisiteByCode[normalizedCode] ?? '',
                              prerequisiteCodes: _extractPrerequisiteCodes(
                                prerequisiteByCode[normalizedCode] ?? '',
                              ),
                            ),
                          );
                        }
                      }
                    }
                  }
                }
                return ProgressHeader(
                  title: headerName,
                  requiredCredit: _toDouble(header['minimumCreditRequired']),
                  courseCodes: courseCodes,
                );
              })
              .where((h) => h.title.isNotEmpty)
              .toList()
        : const <ProgressHeader>[];

    final completedCourses = completedRaw is List
        ? completedRaw
              .whereType<Map>()
              .map((e) => e.cast<String, dynamic>())
              .map((course) {
                return CompletedCourse(
                  code: (course['courseCode'] ?? '').toString().trim(),
                  title: (course['courseTitle'] ?? '').toString().trim(),
                  semesterSession: (course['semesterSession'] ?? '')
                      .toString()
                      .trim(),
                  grade: (course['grade'] ?? '').toString().trim(),
                  credit: _toDouble(course['courseCredit']),
                  isCompleted: (course['isCompleted'] ?? true) == true,
                );
              })
              .where((c) => c.code.isNotEmpty && c.isCompleted)
              .toList()
        : const <CompletedCourse>[];

    final majorOptions = <String>[];
    final minorOptions = <String>[];

    if (majorMinorRaw is List) {
      for (final item in majorMinorRaw.whereType<Map>().map(
        (e) => e.cast<String, dynamic>(),
      )) {
        final name = (item['name'] ?? '').toString().trim();
        final type = (item['type'] ?? '').toString().trim().toUpperCase();
        if (name.isEmpty) continue;
        if (type == 'MAJOR') {
          majorOptions.add(name);
        } else if (type == 'MINOR') {
          minorOptions.add(name);
        }
      }
    }

    return ProgressInfo(
      programName: (curriculum['name'] ?? '').toString().trim(),
      academicDegree: (curriculum['academicDegree'] ?? '').toString().trim(),
      curriculumSession: (curriculum['semesterSession'] ?? '')
          .toString()
          .trim(),
      totalCredit: _toDouble(curriculum['totalCredit']),
      headers: headers,
      completedCourses: completedCourses,
      majorOptions: majorOptions.toSet().toList()..sort(),
      minorOptions: minorOptions.toSet().toList()..sort(),
      curriculumCourses: curriculumCourses,
    );
  }

  static double _toDouble(dynamic value) {
    if (value == null) return 0;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString()) ?? 0;
  }

  Map<String, double> get completedCreditByCode {
    final map = <String, double>{};
    for (final course in completedCourses) {
      final key = course.code.toUpperCase();
      final current = map[key] ?? 0;
      if (course.credit > current) {
        map[key] = course.credit;
      }
    }
    return map;
  }

  double get completedCredit {
    final creditByCode = completedCreditByCode;
    return creditByCode.values.fold(0.0, (sum, value) => sum + value);
  }

  List<HeaderProgress> get headerProgress {
    final byCode = completedCreditByCode;
    final list = headers.map((header) {
      var earned = 0.0;
      for (final code in header.courseCodes) {
        earned += byCode[code] ?? 0;
      }
      return HeaderProgress(
        title: header.title,
        requiredCredit: header.requiredCredit,
        earnedCredit: earned,
      );
    }).toList();
    list.sort((a, b) => compareNaturalText(a.title, b.title));
    return list;
  }

  List<CurriculumCourse> get remainingCourses {
    final completed = completedCreditByCode.keys.toSet();
    final list = curriculumCourses
        .where((course) => !completed.contains(course.code.toUpperCase()))
        .toList();
    list.sort((a, b) => compareNaturalText(a.code, b.code));
    return list;
  }

  List<CurriculumCourse> coursesForHeader(String headerTitle) {
    final normalized = headerTitle.trim().toLowerCase();
    if (normalized.isEmpty) return const <CurriculumCourse>[];
    final list = curriculumCourses
        .where((course) => course.headerName.trim().toLowerCase() == normalized)
        .toList();
    list.sort((a, b) => compareNaturalText(a.code, b.code));
    return list;
  }
}

class ProgressHeader {
  const ProgressHeader({
    required this.title,
    required this.requiredCredit,
    required this.courseCodes,
  });

  final String title;
  final double requiredCredit;
  final Set<String> courseCodes;
}

class CompletedCourse {
  const CompletedCourse({
    required this.code,
    required this.title,
    required this.semesterSession,
    required this.grade,
    required this.credit,
    required this.isCompleted,
  });

  final String code;
  final String title;
  final String semesterSession;
  final String grade;
  final double credit;
  final bool isCompleted;
}

class CurriculumCourse {
  const CurriculumCourse({
    required this.code,
    required this.title,
    required this.credit,
    required this.isMandatory,
    required this.headerName,
    required this.subHeaderName,
    required this.prerequisiteExpression,
    required this.prerequisiteCodes,
  });

  final String code;
  final String title;
  final double credit;
  final bool isMandatory;
  final String headerName;
  final String subHeaderName;
  final String prerequisiteExpression;
  final Set<String> prerequisiteCodes;
}

Map<String, String> _buildCoursePrerequisiteMap(dynamic raw) {
  final output = <String, String>{};
  final rows = switch (raw) {
    Map<String, dynamic> map when map['rows'] is List => map['rows'] as List,
    Map map when map['rows'] is List => map['rows'] as List,
    List list => list,
    _ => const <dynamic>[],
  };
  for (final item in rows.whereType<Map>()) {
    final map = item.cast<dynamic, dynamic>();
    final code = '${map['courseCode'] ?? ''}'.trim().toUpperCase();
    if (code.isEmpty) continue;
    final expression = '${map['prerequisiteCourses'] ?? ''}'.trim();
    output[code] = expression;
  }
  return output;
}

Set<String> _extractPrerequisiteCodes(String raw) {
  final output = <String>{};
  final matches = RegExp(
    r'\b[A-Z]{2,4}\s*-?\s*\d{3,4}[A-Z]?\b',
  ).allMatches(raw.toUpperCase());
  for (final match in matches) {
    final value = (match.group(0) ?? '').replaceAll(RegExp(r'\s+'), '');
    if (value.isNotEmpty) {
      output.add(value);
    }
  }
  return output;
}

class HeaderProgress {
  const HeaderProgress({
    required this.title,
    required this.requiredCredit,
    required this.earnedCredit,
  });

  final String title;
  final double requiredCredit;
  final double earnedCredit;

  double get percent {
    if (requiredCredit <= 0) return 0;
    final ratio = earnedCredit / requiredCredit;
    if (ratio < 0) return 0;
    if (ratio > 1) return 1;
    return ratio;
  }
}

class ProgressSummary {
  const ProgressSummary({
    required this.programName,
    required this.totalCredit,
    required this.completedCredit,
    required this.completionPercent,
    required this.remainingCourses,
  });

  final String programName;
  final double totalCredit;
  final double completedCredit;
  final double completionPercent;
  final int remainingCourses;

  factory ProgressSummary.fromProgressInfo(ProgressInfo info) {
    final total = info.totalCredit;
    final completed = info.completedCredit;
    final ratio = total <= 0 ? 0.0 : (completed / total).clamp(0.0, 1.0);
    return ProgressSummary(
      programName: info.programName,
      totalCredit: total,
      completedCredit: completed,
      completionPercent: ratio * 100,
      remainingCourses: info.remainingCourses.length,
    );
  }

  factory ProgressSummary.fromJson(Map<String, dynamic> json) {
    return ProgressSummary(
      programName: json['programName'] as String? ?? '',
      totalCredit: (json['totalCredit'] as num?)?.toDouble() ?? 0.0,
      completedCredit: (json['completedCredit'] as num?)?.toDouble() ?? 0.0,
      completionPercent: (json['completionPercent'] as num?)?.toDouble() ?? 0.0,
      remainingCourses: json['remainingCourses'] as int? ?? 0,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'programName': programName,
      'totalCredit': totalCredit,
      'completedCredit': completedCredit,
      'completionPercent': completionPercent,
      'remainingCourses': remainingCourses,
    };
  }
}
