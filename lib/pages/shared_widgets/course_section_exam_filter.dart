import 'package:preconnect/api/exam_map.dart';
import 'package:preconnect/model/section_info.dart' as section;
import 'package:preconnect/tools/time_utils.dart';

class CourseSectionExamFilter {
  const CourseSectionExamFilter._();

  static bool isFinishedAfterFinalExam({
    required section.Section section,
    required Map<String, ExamScheduleOverride> overrides,
    DateTime? now,
  }) {
    final resolved = ExamScheduleService().resolveSection(
      section: section,
      overrides: overrides,
    );
    final finalDateTime = BracuTime.parseDateTime(
      resolved.finalDate,
      resolved.finalEndTime ?? resolved.finalStartTime,
    );
    if (finalDateTime == null) return false;
    final current = now ?? DateTime.now();
    return !current.isBefore(finalDateTime);
  }

  static Set<String> finishedSectionKeys(
    Iterable<section.Section> sections,
    Map<String, ExamScheduleOverride> overrides, {
    DateTime? now,
  }) {
    final keys = <String>{};
    for (final item in sections) {
      if (!isFinishedAfterFinalExam(
        section: item,
        overrides: overrides,
        now: now,
      )) {
        continue;
      }
      final key = ExamMapService.sectionKey(
        courseCode: item.courseCode,
        sectionName: item.sectionName,
      );
      if (key.isNotEmpty) {
        keys.add(key);
      }
    }
    return keys;
  }
}
