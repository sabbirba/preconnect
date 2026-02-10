import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:preconnect/model/payment_info.dart';
import 'package:preconnect/pages/ui_kit.dart';

class PaymentList extends StatelessWidget {
  const PaymentList({super.key, required this.payments});

  final List<PaymentInfo> payments;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: payments.asMap().entries.map((entry) {
        final payment = entry.value;
        final textSecondary = BracuPalette.textSecondary(context);
        final textPrimary = BracuPalette.textPrimary(context);
        final dueDate = formatDate(payment.dueDate.toIso8601String());
        final status = payment.paymentStatus;
        final isPaid = status == 'PAID';
        final amount = _formatAmount(payment.totalAmount);
        final statusColor =
            isPaid ? BracuPalette.accent : const Color(0xFFFF8A34);
        final statusBg = statusColor.withValues(alpha: 0.14);
        final semester =
            formatSemesterFromSessionIdInt(payment.semesterSessionId);
        final paymentType = _formatPaymentType(payment.paymentType);
        final cardTint =
            isPaid ? Colors.transparent : statusBg.withValues(alpha: 0.08);
        final cardBorder = isPaid
            ? BracuPalette.primary.withValues(alpha: 0.08)
            : statusBg.withValues(alpha: 0.6);
        return Container(
          margin: const EdgeInsets.symmetric(vertical: 8),
          padding: const EdgeInsets.all(2),
          decoration: BoxDecoration(
            color: BracuPalette.primary.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: cardTint,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: cardBorder,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                LayoutBuilder(
                  builder: (context, constraints) {
                    return Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.receipt_long,
                              size: 16,
                              color: BracuPalette.primary,
                            ),
                            const SizedBox(width: 6),
                            GestureDetector(
                              onTap: () => copyToClipboard(
                                context,
                                payment.payslipNumber,
                              ),
                              child: Text(
                                payment.payslipNumber,
                                style: TextStyle(
                                  color: textSecondary,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 14,
                                ),
                              ),
                            ),
                            const SizedBox(width: 4),
                            GestureDetector(
                              onTap: () {
                                copyToClipboard(
                                  context,
                                  payment.payslipNumber,
                                );
                              },
                              child: Icon(
                                Icons.copy_rounded,
                                size: 14,
                                color: textSecondary,
                              ),
                            ),
                          ],
                        ),
                        GestureDetector(
                          onTap: () => copyToClipboard(context, amount),
                          child: Text(
                            amount,
                            style: TextStyle(
                              color: textPrimary,
                              fontWeight: FontWeight.w700,
                              fontSize: 14,
                            ),
                            textAlign: TextAlign.right,
                          ),
                        ),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 8),
                _InfoLine(
                  label: paymentType,
                  value: semester,
                  isLabelBold: true,
                  isValueBold: true,
                ),
                const SizedBox(height: 8),
                _InfoLine(
                  label: 'Requested',
                  value: formatDate(payment.requestDate.toIso8601String()),
                  isLabelBold: false,
                  isValueBold: false,
                ),
                const SizedBox(height: 6),
                _InfoLine(
                  label: status,
                  value: !isPaid ? dueDate : 'Paid',
                  isLabelBold: true,
                  isValueBold: true,
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }
}

class _InfoLine extends StatelessWidget {
  const _InfoLine({
    required this.label,
    required this.value,
    this.isValueBold = false,
    this.isLabelBold = false,
  });

  final String label;
  final String value;
  final bool isValueBold;
  final bool isLabelBold;

  @override
  Widget build(BuildContext context) {
    final textSecondary = BracuPalette.textSecondary(context);
    final textPrimary = BracuPalette.textPrimary(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 5,
            child: Text(
              label,
              style: TextStyle(
                color: textSecondary,
                fontWeight: isLabelBold ? FontWeight.w700 : FontWeight.w500,
                fontSize: 14,
              ),
              textAlign: TextAlign.left,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 7,
            child: Text(
              value,
              style: TextStyle(
                color: textPrimary,
                fontWeight: isValueBold ? FontWeight.w700 : FontWeight.w400,
                fontSize: 14,
              ),
              textAlign: TextAlign.right,
            ),
          ),
        ],
      ),
    );
  }
}

String _formatPaymentType(String raw) {
  final cleaned = raw.trim();
  if (cleaned.isEmpty) return 'N/A';
  final words = cleaned.split('_').where((w) => w.trim().isNotEmpty).toList();
  if (words.isEmpty) return cleaned;
  return words
      .map((w) {
        final lower = w.toLowerCase();
        return lower[0].toUpperCase() + lower.substring(1);
      })
      .join(' ');
}

String _formatAmount(double amount) {
  final formatter = NumberFormat.decimalPattern('en_IN');
  final rounded = amount.round();
  return '${formatter.format(rounded)} Taka';
}
