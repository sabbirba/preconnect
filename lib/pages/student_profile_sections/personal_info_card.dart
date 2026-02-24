import 'package:flutter/material.dart';
import 'package:preconnect/pages/ui_kit.dart';

class PersonalInfoCard extends StatelessWidget {
  const PersonalInfoCard({super.key, required this.profile});

  final Map<String, String?> profile;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final borderColor = BracuPalette.textSecondary(
      context,
    ).withValues(alpha: isDark ? 0.35 : 0.18);
    final rows = <({String label, String value})>[
      (
        label: 'Permanent Address',
        value: (profile['permanentAddress'] ?? '').trim(),
      ),
      (label: 'Father Name', value: (profile['fatherName'] ?? '').trim()),
      (label: 'Father Mobile', value: (profile['fatherMobileNo'] ?? '').trim()),
      (label: 'Father Email', value: (profile['fatherEmail'] ?? '').trim()),
      (label: 'Mother Name', value: (profile['motherName'] ?? '').trim()),
      (label: 'Mother Mobile', value: (profile['motherMobileNo'] ?? '').trim()),
      (label: 'Mother Email', value: (profile['motherEmail'] ?? '').trim()),
      (
        label: 'Local Guardian Name',
        value: (profile['localGuardianName'] ?? '').trim(),
      ),
      (
        label: 'Local Guardian Mobile',
        value: (profile['localGuardianMobileNo'] ?? '').trim(),
      ),
      (
        label: 'Local Guardian Email',
        value: (profile['localGuardianEmail'] ?? '').trim(),
      ),
      (label: 'Sponsored By', value: (profile['sponsoredBy'] ?? '').trim()),
      (label: 'Country Name', value: (profile['countryName'] ?? '').trim()),
      (label: 'Hobbies', value: (profile['hobbies'] ?? '').trim()),
      (label: 'Awards', value: (profile['awards'] ?? '').trim()),
      (label: 'Has Disability', value: (profile['hasDisability'] ?? '').trim()),
      (
        label: 'Disability Details',
        value: (profile['disabilityDetails'] ?? '').trim(),
      ),
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
              enableCopy:
                  rows[i].label == 'Father Mobile' ||
                  rows[i].label == 'Mother Mobile' ||
                  rows[i].label == 'Local Guardian Mobile',
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
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          flex: 4,
          child: Text(
            label,
            style: TextStyle(
              color: BracuPalette.textSecondary(context),
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          flex: 6,
          child: GestureDetector(
            onTap: enableCopy ? () => copyToClipboard(context, value) : null,
            child: Text(
              value,
              textAlign: TextAlign.right,
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
  }
}
