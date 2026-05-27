import 'package:flutter/material.dart';
import 'package:preconnect/pages/ui_kit.dart';

class PersonalInfoCard extends StatelessWidget {
  const PersonalInfoCard({super.key, required this.profile});

  final Map<String, String?> profile;

  String _valueOf(String key) => (profile[key] ?? '').trim();

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final borderColor = BracuPalette.textSecondary(
      context,
    ).withValues(alpha: isDark ? 0.35 : 0.18);
    final rows = <({String label, String value})>[
      (label: 'Student ID', value: _valueOf('studentId')),
      (label: 'Phone Number', value: _valueOf('mobileNo')),
      (label: 'Email', value: _valueOf('email')),
      (label: 'Academic Type', value: _valueOf('academicType')),
      (label: 'Current Semester', value: _valueOf('currentSemester')),
      (label: 'Enrolled Semester', value: _valueOf('enrolledSemester')),
      (label: 'Gender', value: _valueOf('gender')),
      (label: 'Date of Birth', value: _valueOf('dateOfBirth')),
      (label: 'Blood Group', value: _valueOf('bloodGroup')),
      (label: 'Religion', value: _valueOf('religion')),
      (label: 'Nationality', value: _valueOf('nationality')),
      (label: 'Marital Status', value: _valueOf('maritalStatus')),
      (label: 'Admission Session', value: _valueOf('admissionSession')),
      (label: 'Program', value: _valueOf('program')),
      (label: 'Department', value: _valueOf('departmentName')),
      (label: 'Batch', value: _valueOf('batch')),
      (label: 'Section', value: _valueOf('section')),
      (label: 'Campus', value: _valueOf('campus')),
      (label: 'Room / Hall', value: _valueOf('roomNo')),
      (label: 'Present Address', value: _valueOf('presentAddress')),
      (label: 'Permanent Address', value: _valueOf('permanentAddress')),
      (label: 'Father Name', value: _valueOf('fatherName')),
      (label: 'Father Mobile', value: _valueOf('fatherMobileNo')),
      (label: 'Father Email', value: _valueOf('fatherEmail')),
      (label: 'Father Occupation', value: _valueOf('fatherOccupation')),
      (label: 'Mother Name', value: _valueOf('motherName')),
      (label: 'Mother Mobile', value: _valueOf('motherMobileNo')),
      (label: 'Mother Email', value: _valueOf('motherEmail')),
      (label: 'Mother Occupation', value: _valueOf('motherOccupation')),
      (label: 'Local Guardian Name', value: _valueOf('localGuardianName')),
      (
        label: 'Local Guardian Mobile',
        value: _valueOf('localGuardianMobileNo'),
      ),
      (label: 'Local Guardian Email', value: _valueOf('localGuardianEmail')),
      (
        label: 'Local Guardian Address',
        value: _valueOf('localGuardianAddress'),
      ),
      (label: 'Sponsored By', value: _valueOf('sponsoredBy')),
      (label: 'Country Name', value: _valueOf('countryName')),
      (label: 'Hobbies', value: _valueOf('hobbies')),
      (label: 'Awards', value: _valueOf('awards')),
      (label: 'Has Disability', value: _valueOf('hasDisability')),
      (label: 'Disability Details', value: _valueOf('disabilityDetails')),
      (label: 'Student Type', value: _valueOf('studentType')),
      (label: 'Emergency Contact', value: _valueOf('emergencyContact')),
      (label: 'Emergency Relation', value: _valueOf('emergencyRelation')),
    ].where((row) => row.value.isNotEmpty).toList();

    if (rows.isEmpty) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: BracuPalette.card(context),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: borderColor),
        boxShadow: isDark
            ? const []
            : [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.06),
                  blurRadius: 16,
                  offset: const Offset(0, 8),
                ),
              ],
      ),
      child: Column(
        children: [
          for (var i = 0; i < rows.length; i++) ...[
            _InfoRow(
              label: rows[i].label,
              value: rows[i].value,
              enableCopy: _copyableLabels.contains(rows[i].label),
            ),
            if (i != rows.length - 1)
              Divider(
                height: 18,
                thickness: 1,
                color: BracuPalette.textSecondary(
                  context,
                ).withValues(alpha: isDark ? 0.22 : 0.14),
              ),
          ],
        ],
      ),
    );
  }
}

const _copyableLabels = <String>{
  'Student ID',
  'Phone Number',
  'Email',
  'CGPA',
  'Earned Credit',
  'Father Mobile',
  'Father Email',
  'Mother Mobile',
  'Mother Email',
  'Local Guardian Mobile',
  'Local Guardian Email',
  'Emergency Contact',
};

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.label,
    required this.value,
    this.enableCopy = false,
  });

  final String label;
  final String value;
  final bool enableCopy;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final labelWidth = (label.length * 7.8).clamp(
          92.0,
          constraints.maxWidth * 0.42,
        );
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: labelWidth,
              child: Text(
                label,
                maxLines: 1,
                softWrap: false,
                overflow: TextOverflow.clip,
                style: TextStyle(
                  color: BracuPalette.textSecondary(context),
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: GestureDetector(
                onTap: enableCopy
                    ? () => copyToClipboard(context, value)
                    : null,
                child: Text(
                  value,
                  textAlign: TextAlign.right,
                  softWrap: true,
                  textWidthBasis: TextWidthBasis.parent,
                  style: TextStyle(
                    color: BracuPalette.textPrimary(context),
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
