import 'package:flutter/material.dart';
import 'package:barcode_widget/barcode_widget.dart';
import 'package:preconnect/pages/ui_kit.dart';

class BracuQrCard extends StatelessWidget {
  const BracuQrCard({required this.data, super.key});

  final String data;

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 1.0,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Container(
          decoration: const BoxDecoration(color: Colors.white),
          padding: const EdgeInsets.all(12),
          child: BarcodeWidget(
            barcode: Barcode.qrCode(),
            data: data,
            color: Colors.black,
            backgroundColor: Colors.white,
            padding: EdgeInsets.zero,
            errorBuilder: (context, error) => Center(
              child: Text(
                'QR generation failed',
                style: TextStyle(color: BracuPalette.textSecondary(context)),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
