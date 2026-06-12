import 'package:flutter/material.dart';
import 'package:preconnect/pages/ui_kit.dart';

const kGradeSheetTitle = 'Grade Sheet';

class GradeSheetCard extends StatefulWidget {
  const GradeSheetCard({super.key, this.title = kGradeSheetTitle});

  final String title;

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
    return BracuActionBannerCard(
      icon: Icons.picture_as_pdf_rounded,
      title: widget.title,
      subtitle: 'Download your latest transcript',
      onTap: _isOpening ? () {} : _openGradeSheet,
      trailing: _isOpening
          ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : null,
    );
  }
}
