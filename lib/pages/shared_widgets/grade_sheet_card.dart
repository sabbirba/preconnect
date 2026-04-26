import 'package:flutter/material.dart';
import 'package:preconnect/pages/ui_kit.dart';

const kGradeSheetTitle = 'Grade Sheet';
const kGradeSheetCardSubtitle = 'Open your latest grade sheet PDF';

class GradeSheetCard extends StatefulWidget {
  const GradeSheetCard({
    super.key,
    this.title = kGradeSheetTitle,
    this.subtitle = kGradeSheetCardSubtitle,
  });

  final String title;
  final String subtitle;

  @override
  State<GradeSheetCard> createState() => _GradeSheetCardState();
}

class _GradeSheetCardState extends State<GradeSheetCard> {
  Future<void> _openGradeSheet() async {
    await openGradeSheet(context);
  }

  @override
  Widget build(BuildContext context) {
    return BracuCard(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.title,
                    style: TextStyle(
                      color: BracuPalette.textPrimary(context),
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    widget.subtitle,
                    style: TextStyle(
                      color: BracuPalette.textSecondary(context),
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            ElevatedButton.icon(
              onPressed: _openGradeSheet,
              icon: const Icon(Icons.picture_as_pdf_outlined, size: 16),
              label: const Text('Open'),
            ),
          ],
        ),
      ),
    );
  }
}
