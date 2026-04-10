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
            ElevatedButton.icon(
              onPressed: _isOpening ? null : _openGradeSheet,
              style: ElevatedButton.styleFrom(
                backgroundColor: BracuPalette.primary,
                foregroundColor: Colors.white,
                elevation: 0,
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              icon: _isOpening
                  ? const BracuShimmer(
                      child: BracuSkeletonBox(width: 16, height: 16, radius: 8),
                    )
                  : const Icon(Icons.picture_as_pdf_outlined, size: 16),
              label: Text(_isOpening ? 'Opening' : 'Open'),
            ),
          ],
        ),
      ),
    );
  }
}
