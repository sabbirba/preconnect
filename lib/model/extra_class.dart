import 'package:preconnect/model/section_info.dart';
import 'package:preconnect/tools/string_utils.dart';

class ExtraClass {
  ExtraClass({required this.section, required Set<String> days})
    : days = Set.unmodifiable(days.map((day) => day.toUpperCase()));

  final Section section;
  final Set<String> days;

  String get key => '${section.semesterSessionId}|${section.sectionId}';

  Section get selectedSection => Section.fromJson(
    _sectionJson(
      section.sectionSchedule.classSchedules.where(
        (meeting) => days.contains(meeting.day.toUpperCase()),
      ),
    ),
  );

  List<Section> get meetingSections => selectedSection
      .sectionSchedule
      .classSchedules
      .map(
        (meeting) => Section.fromJson({
          ..._sectionJson([meeting]),
          'roomNumber': roomForDay(section.roomNumber, meeting.day),
        }),
      )
      .toList();

  Map<String, dynamic> _sectionJson(Iterable<ClassSchedule> meetings) => {
    ...section.toJson(),
    'studentPortfolioId': 0,
    'sectionSchedule': {
      'classStartDate': section.sectionSchedule.classStartDate,
      'classEndDate': section.sectionSchedule.classEndDate,
      'classSchedules': meetings
          .map(
            (meeting) => {
              ...meeting.toJson(),
              'day': meeting.day.toUpperCase(),
            },
          )
          .toList(),
    },
  };

  factory ExtraClass.fromJson(Map<String, dynamic> json) => ExtraClass(
    section: Section.fromJson(
      Map<String, dynamic>.from(json['section'] as Map),
    ),
    days: (json['days'] as List).cast<String>().toSet(),
  );

  Map<String, dynamic> toJson() => {
    'section': _sectionJson(section.sectionSchedule.classSchedules),
    'days': days.toList()..sort(),
  };
}
