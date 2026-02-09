import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:preconnect/model/payment_info.dart';
import 'package:preconnect/pages/shared_widgets/progress_bar.dart';
import 'package:preconnect/pages/ui_kit.dart';

class PaymentGraph extends StatelessWidget {
  const PaymentGraph({super.key, required this.payments});

  final List<PaymentInfo> payments;

  @override
  Widget build(BuildContext context) {
    double paidTotal = 0;
    double dueTotal = 0;
    for (final p in payments) {
      if (p.paymentStatus == 'PAID') {
        paidTotal += p.totalAmount;
      } else {
        dueTotal += p.totalAmount;
      }
    }
    final overall = paidTotal + dueTotal;
    final paidRatio = overall == 0 ? 0.0 : paidTotal / overall;
    final dueRatio = overall == 0 ? 0.0 : dueTotal / overall;

    final textSecondary = BracuPalette.textSecondary(context);
    final textPrimary = BracuPalette.textPrimary(context);

    return BracuCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Paid vs Due',
            style: TextStyle(fontWeight: FontWeight.w600, color: textPrimary),
          ),
          const SizedBox(height: 10),
          _BarRow(
            label: 'Paid',
            value: paidRatio,
            amount: paidTotal,
            color: BracuPalette.accent,
          ),
          const SizedBox(height: 8),
          _BarRow(
            label: 'Due',
            value: dueRatio,
            amount: dueTotal,
            color: const Color(0xFFFF8A34),
          ),
          const SizedBox(height: 6),
          Text(
            'Total: ${_formatAmountStatic(overall)}',
            style: TextStyle(color: textSecondary),
          ),
        ],
      ),
    );
  }

  static String _formatAmountStatic(double amount) {
    final formatter = NumberFormat.decimalPattern('en_IN');
    final rounded = amount.round();
    return '${formatter.format(rounded)} Taka';
  }
}

class _BarRow extends StatelessWidget {
  const _BarRow({
    required this.label,
    required this.value,
    required this.amount,
    required this.color,
  });

  final String label;
  final double value;
  final double amount;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final textSecondary = BracuPalette.textSecondary(context);
    final textPrimary = BracuPalette.textPrimary(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  color: textSecondary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            Text(
              PaymentGraph._formatAmountStatic(amount),
              style: TextStyle(color: textPrimary, fontWeight: FontWeight.w600),
            ),
          ],
        ),
        const SizedBox(height: 6),
        SimpleProgressBar(value: value, color: color),
      ],
    );
  }
}
