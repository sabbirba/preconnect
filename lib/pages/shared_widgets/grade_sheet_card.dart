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
  bool _isOpening = false;

  Future<void> _openGradeSheet() async {
    if (_isOpening) return;
    setState(() {
      _isOpening = true;
    });
    try {
      await openGradeSheet(context);
    } finally {
      if (mounted) {
        setState(() {
          _isOpening = false;
        });
      }
    }
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
            OutlinedButton.icon(
              onPressed: _isOpening ? null : _openGradeSheet,
              icon: _isOpening
                  ? const BracuShimmer(
                      child: BracuSkeletonBox(width: 14, height: 14, radius: 7),
                    )
                  : const Icon(Icons.picture_as_pdf_rounded, size: 16),
              label: const Text('Open'),
              style: OutlinedButton.styleFrom(
                foregroundColor: BracuPalette.primary,
                side: BorderSide(
                  color: BracuPalette.primary.withValues(alpha: 0.28),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
