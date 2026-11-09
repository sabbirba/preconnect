import 'package:flutter/material.dart';
import 'package:gap/gap.dart';
import 'package:preconnect/api/profile.dart';
import 'package:preconnect/pages/profile_sections/payslip_detail.dart';
import 'package:preconnect/pages/shared_widgets/info_line.dart';
import 'package:preconnect/pages/ui_kit.dart';
import 'package:preconnect/tools/string_utils.dart';
import 'package:preconnect/tools/time_utils.dart';

class PaymentList extends StatefulWidget {
  const PaymentList({super.key, required this.payments});

  final List<PaymentInfo> payments;

  @override
  State<PaymentList> createState() => _PaymentListState();
}

class _PaymentListState extends State<PaymentList> {
  int _visibleCount = 5;

  @override
  Widget build(BuildContext context) {
    final visiblePayments = widget.payments.take(_visibleCount).toList();
    final installmentTotals = <String, int>{};
    for (final payment in widget.payments) {
      if (!payment.installmentEnabled) continue;
      final key = '${payment.semesterSessionId}|${payment.paymentType}';
      installmentTotals[key] = (installmentTotals[key] ?? 0) + 1;
    }

    return Column(
      children: [
        ...visiblePayments.map((payment) {
          final textSecondary = AppPalette.textSecondary(context);
          final textPrimary = AppPalette.textPrimary(context);
          final dueDate = AppTime.formatCampusTime(
            payment.dueDate.toIso8601String(),
            'd MMMM, y',
          );
          final installmentTotal =
              installmentTotals['${payment.semesterSessionId}|${payment.paymentType}'];
          final status = payment.paymentStatus;
          final isPaid = status == 'PAID';
          final amount = _formatAmount(payment.totalAmount);
          final statusColor = isPaid
              ? AppPalette.accent
              : const Color(0xFFFF8A34);
          final statusBg = statusColor.withValues(alpha: 0.14);
          final semester = formatSemesterFromSessionIdInt(
            payment.semesterSessionId,
          );
          final paymentType = titleCaseWords(payment.paymentType);
          final cardTint = Colors.transparent;
          final cardBorder = isPaid
              ? AppPalette.primary.withValues(alpha: 0.08)
              : statusBg.withValues(alpha: 0.6);
          final iconColor = isPaid
              ? AppPalette.accent
              : const Color(0xFFFF8A34);
          final iconBg = Colors.transparent;
          return GestureDetector(
            onTap: () {
              if (payment.payslipNumber.isNotEmpty) {
                PayslipDetailSheet.show(
                  context,
                  payslipNumber: payment.payslipNumber,
                );
              }
            },
            child: Container(
              margin: const EdgeInsets.symmetric(vertical: 8),
              padding: EdgeInsets.zero,
              decoration: const BoxDecoration(),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: cardTint,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: cardBorder),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    LayoutBuilder(
                      builder: (context, constraints) {
                        return Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: Row(
                                children: [
                                  Container(
                                    width: 26,
                                    height: 26,
                                    decoration: BoxDecoration(
                                      color: iconBg,
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    alignment: Alignment.center,
                                    child: Icon(
                                      Icons.credit_card_rounded,
                                      size: 14,
                                      color: iconColor,
                                    ),
                                  ),
                                  const Gap(12),
                                  Flexible(
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        GestureDetector(
                                          onTap: () => copyToClipboard(
                                            context,
                                            payment.payslipNumber,
                                          ),
                                          child: Text(
                                            payment.payslipNumber,
                                            style: TextStyle(
                                              color: textPrimary,
                                              fontWeight: FontWeight.w800,
                                              fontSize: 15,
                                              letterSpacing: 0.2,
                                            ),
                                          ),
                                        ),
                                        const Gap(4),
                                        GestureDetector(
                                          onTap: () {
                                            copyToClipboard(
                                              context,
                                              payment.payslipNumber,
                                            );
                                          },
                                          child: Icon(
                                            Icons.copy_rounded,
                                            size: 15,
                                            color: textSecondary,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const Gap(12),
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
                    const Gap(8),
                    InfoLine(
                      label: paymentType,
                      value: semester,
                      isLabelBold: true,
                      isValueBold: true,
                      valueFlex: 7,
                      valueWeight: FontWeight.w400,
                    ),
                    if (installmentTotal != null) ...[
                      const Gap(8),
                      InfoLine(
                        label: 'Installment',
                        value:
                            '${payment.installmentNumber} of $installmentTotal',
                        isLabelBold: false,
                        isValueBold: false,
                        valueFlex: 7,
                        valueWeight: FontWeight.w400,
                      ),
                    ],
                    const Gap(8),
                    InfoLine(
                      label: 'Requested',
                      value: AppTime.formatCampusTime(
                        payment.requestDate.toIso8601String(),
                        'd MMMM, y',
                      ),
                      isLabelBold: false,
                      isValueBold: false,
                      valueFlex: 7,
                      valueWeight: FontWeight.w400,
                    ),
                    const Gap(6),
                    InfoLine(
                      label: 'Due Date',
                      value: dueDate,
                      isLabelBold: true,
                      isValueBold: true,
                      valueFlex: 7,
                      valueWeight: FontWeight.w400,
                    ),
                    const Gap(6),
                    InfoLine(
                      label: 'Status',
                      value: isPaid ? 'Paid' : 'Due',
                      isLabelBold: true,
                      isValueBold: true,
                      valueFlex: 7,
                      valueWeight: FontWeight.w400,
                    ),
                  ],
                ),
              ),
            ),
          );
        }),
        const Gap(4),
        buildStepButtons(
          shown: visiblePayments.length,
          total: widget.payments.length,
          step: 5,
          moreLabel: 'Load More',
          onChanged: (count) => setState(() => _visibleCount = count),
        ),
      ],
    );
  }
}

String _formatAmount(double amount) => '${formatAmount(amount)} Taka';
