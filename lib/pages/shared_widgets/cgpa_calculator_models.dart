part of 'package:preconnect/pages/cgpa_calculator.dart';

class _CurrentCourseDraft {
  _CurrentCourseDraft({
    String code = '',
    String title = '',
    String credit = '',
    required this.isRequired,
  }) : codeController = TextEditingController(text: code),
       titleController = TextEditingController(text: title),
       creditController = TextEditingController(text: credit),
       grade = 'A';

  final TextEditingController codeController;
  final TextEditingController titleController;
  final TextEditingController creditController;
  final bool isRequired;
  String grade;

  String get codeValue => codeController.text.trim().toUpperCase();
  String get titleValue => titleController.text.trim();
  String get creditValue => creditController.text.trim();

  _CourseSnapshot toSnapshot() {
    final code = codeController.text.trim().toUpperCase();
    final credit = double.tryParse(creditController.text.trim()) ?? 0.0;
    final gradeValue = _normalizeGrade(grade);
    final gradePoint = _gradePointFor(gradeValue);
    return _CourseSnapshot(
      code: code,
      credit: credit,
      grade: gradeValue,
      gradePoint: gradePoint,
    );
  }

  void dispose() {
    codeController.dispose();
    titleController.dispose();
    creditController.dispose();
  }
}

class _CompletedCourseDraft {
  _CompletedCourseDraft._({
    required String code,
    required String title,
    required String credit,
    required this.completedGrade,
    required String semester,
    required this.isRequired,
  }) : codeController = TextEditingController(text: code),
       titleController = TextEditingController(text: title),
       creditController = TextEditingController(text: credit),
       semesterController = TextEditingController(text: semester),
       selectedRetakeGrade = null;

  factory _CompletedCourseDraft.auto({
    required String code,
    required String title,
    required String credit,
    required String grade,
    required String semester,
    required bool isRequired,
  }) {
    return _CompletedCourseDraft._(
      code: code,
      title: title,
      credit: credit,
      completedGrade: grade,
      semester: semester,
      isRequired: isRequired,
    );
  }

  final TextEditingController codeController;
  final TextEditingController titleController;
  final TextEditingController creditController;
  final TextEditingController semesterController;
  final String completedGrade;
  String? selectedRetakeGrade;
  final bool isRequired;

  String get codeValue => codeController.text.trim().toUpperCase();
  String get titleValue => titleController.text.trim();
  String get creditValue => creditController.text.trim();
  String get semesterValue => semesterController.text.trim();
  bool get hasRetakeSelection =>
      selectedRetakeGrade != null && selectedRetakeGrade != completedGrade;

  _CourseSnapshot toCompletedSnapshot() {
    final code = codeController.text.trim().toUpperCase();
    final credit = double.tryParse(creditController.text.trim()) ?? 0.0;
    final gradeValue = _normalizeGrade(completedGrade);
    final gradePoint = _gradePointFor(gradeValue);
    return _CourseSnapshot(
      code: code,
      credit: credit,
      grade: gradeValue,
      gradePoint: gradePoint,
    );
  }

  _CourseSnapshot toRetakeSnapshot() {
    final code = codeController.text.trim().toUpperCase();
    final credit = double.tryParse(creditController.text.trim()) ?? 0.0;
    final gradeValue = _normalizeGrade(selectedRetakeGrade ?? completedGrade);
    final gradePoint = _gradePointFor(gradeValue);
    return _CourseSnapshot(
      code: code,
      credit: credit,
      grade: gradeValue,
      gradePoint: gradePoint,
    );
  }

  void dispose() {
    codeController.dispose();
    titleController.dispose();
    creditController.dispose();
    semesterController.dispose();
  }
}

class _CourseSnapshot {
  const _CourseSnapshot({
    required this.code,
    required this.credit,
    required this.grade,
    required this.gradePoint,
  });

  final String code;
  final double credit;
  final String grade;
  final double? gradePoint;

  bool get countsToGpa => code.isNotEmpty && credit > 0 && gradePoint != null;
  double get qualityPoints => (gradePoint ?? 0.0) * credit;
}

class _Baseline {
  const _Baseline({
    required this.cgpa,
    required this.totalCredits,
    required this.qualityPoints,
    required this.effectiveByCode,
    required this.usedOfficialCgpa,
  });

  final double cgpa;
  final double totalCredits;
  final double qualityPoints;
  final Map<String, _CourseSnapshot> effectiveByCode;
  final bool usedOfficialCgpa;
}

class _ExpectedResult {
  const _ExpectedResult({
    required this.currentCgpa,
    required this.expectedCgpa,
    required this.selectedGpa,
    required this.cgpaDelta,
    required this.selectedCredits,
    required this.usedOfficialCgpa,
  });

  final double currentCgpa;
  final double expectedCgpa;
  final double selectedGpa;
  final double cgpaDelta;
  final double selectedCredits;
  final bool usedOfficialCgpa;

  String get currentCgpaLabel => currentCgpa.toStringAsFixed(3);
  String get expectedCgpaLabel => expectedCgpa.toStringAsFixed(3);
  String get selectedGpaLabel =>
      selectedCredits <= 0 ? '--' : selectedGpa.toStringAsFixed(3);
}

class _GradeGuideRow {
  const _GradeGuideRow({
    required this.range,
    required this.grade,
    required this.point,
    required this.comment,
  });

  final String range;
  final String grade;
  final String point;
  final String comment;
}

const List<String> _gradeOptions = <String>[
  'A+',
  'A',
  'A-',
  'B+',
  'B',
  'B-',
  'C+',
  'C',
  'C-',
  'D+',
  'D',
  'D-',
  'F',
  'P',
  'S',
  'W',
  'I',
];

const List<_GradeGuideRow> _gradeGuideRows = <_GradeGuideRow>[
  _GradeGuideRow(
    range: '97 - 100',
    grade: 'A+',
    point: '4.0',
    comment: 'Exceptional',
  ),
  _GradeGuideRow(
    range: '90 - 97',
    grade: 'A',
    point: '4.0',
    comment: 'Excellent',
  ),
  _GradeGuideRow(
    range: '85 - 90',
    grade: 'A-',
    point: '3.7',
    comment: 'Very good',
  ),
  _GradeGuideRow(range: '80 - 85', grade: 'B+', point: '3.3', comment: 'Good'),
  _GradeGuideRow(range: '75 - 80', grade: 'B', point: '3.0', comment: 'Good'),
  _GradeGuideRow(range: '70 - 75', grade: 'B-', point: '2.7', comment: 'Fair'),
  _GradeGuideRow(
    range: '65 - 70',
    grade: 'C+',
    point: '2.3',
    comment: 'Average',
  ),
  _GradeGuideRow(range: '60 - 65', grade: 'C', point: '2.0', comment: 'Fair'),
  _GradeGuideRow(
    range: '57 - 60',
    grade: 'C-',
    point: '1.7',
    comment: 'Marginal',
  ),
  _GradeGuideRow(range: '55 - 57', grade: 'D+', point: '1.3', comment: 'Weak'),
  _GradeGuideRow(range: '52 - 55', grade: 'D', point: '1.0', comment: 'Poor'),
  _GradeGuideRow(range: '50 - 52', grade: 'D-', point: '0.7', comment: 'Poor'),
  _GradeGuideRow(
    range: '00 - 50',
    grade: 'F',
    point: '0.0',
    comment: 'Failure',
  ),
  _GradeGuideRow(range: '70 - 100', grade: 'P', point: '', comment: 'Pass'),
  _GradeGuideRow(
    range: '80 - 100',
    grade: 'S',
    point: '',
    comment: 'Satisfactory',
  ),
  _GradeGuideRow(range: '', grade: 'W', point: '', comment: 'Withdrawal'),
  _GradeGuideRow(range: '', grade: 'I', point: '', comment: 'Incomplete'),
];

Widget _buildGradeGuideLegend(
  BuildContext context,
  Color textPrimary,
  Color textSecondary,
) {
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        children: [
          Expanded(
            flex: 3,
            child: Text(
              'Marking',
              style: TextStyle(
                color: textSecondary,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Expanded(
            flex: 2,
            child: Center(
              child: Text(
                'Grade',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: textSecondary,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
          Expanded(
            flex: 3,
            child: Text(
              'Point • Comment',
              textAlign: TextAlign.end,
              style: TextStyle(
                color: textSecondary,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
      const SizedBox(height: 8),
      ..._gradeGuideRows.map((row) {
        final details = row.point.isEmpty && row.comment.isEmpty
            ? ''
            : row.point.isEmpty
            ? row.comment
            : row.comment.isEmpty
            ? row.point
            : '${row.point} • ${row.comment}';
        return Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
          decoration: BoxDecoration(
            color: textSecondary.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            children: [
              Expanded(
                flex: 3,
                child: Text(
                  row.range,
                  style: TextStyle(
                    color: textPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Expanded(
                flex: 2,
                child: Center(
                  child: Text(
                    row.grade,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: textPrimary,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
              Expanded(
                flex: 3,
                child: Text(
                  details,
                  textAlign: TextAlign.end,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: textSecondary,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        );
      }),
      const SizedBox(height: 4),
    ],
  );
}

String _normalizeGrade(String raw) {
  final grade = raw.trim().toUpperCase();
  if (_gradeOptions.contains(grade)) return grade;
  return 'A';
}

String _normalizeImportedGrade(String raw) {
  final grade = raw.trim().toUpperCase();
  if (_gradeOptions.contains(grade)) return grade;
  return grade;
}

double? _gradePointFor(String grade) {
  switch (grade.trim().toUpperCase()) {
    case 'A+':
      return 4.0;
    case 'A':
      return 4.0;
    case 'A-':
      return 3.7;
    case 'B+':
      return 3.3;
    case 'B':
      return 3.0;
    case 'B-':
      return 2.7;
    case 'C+':
      return 2.3;
    case 'C':
      return 2.0;
    case 'C-':
      return 1.7;
    case 'D+':
      return 1.3;
    case 'D':
      return 1.0;
    case 'D-':
      return 0.7;
    case 'F':
      return 0.0;
    default:
      return null;
  }
}

String _formatCredit(double value) {
  if (value % 1 == 0) return value.toStringAsFixed(0);
  return value.toStringAsFixed(1);
}

class _Metric extends StatelessWidget {
  const _Metric({required this.title, required this.value});

  final String title;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: BracuPalette.textSecondary(context).withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          if (title.isNotEmpty)
            Text(
              title,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: BracuPalette.textSecondary(context),
                fontSize: 10,
                fontWeight: FontWeight.w700,
              ),
            ),
          if (title.isNotEmpty) const SizedBox(height: 4),
          Text(
            value,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: BracuPalette.textPrimary(context),
              fontSize: 14,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}
