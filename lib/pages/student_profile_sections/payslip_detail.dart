import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:gap/gap.dart';
import 'package:preconnect/api/profile.dart';
import 'package:preconnect/pages/ui_kit.dart';
import 'package:preconnect/tools/file_open.dart';

class PayslipDetailSheet extends StatefulWidget {
  const PayslipDetailSheet({
    super.key,
    required this.payslipNumber,
    this.fallbackItem,
  });

  final String payslipNumber;
  final PayslipItem? fallbackItem;

  static Future<void> show(
    BuildContext context, {
    required String payslipNumber,
    PayslipItem? fallbackItem,
  }) {
    return showBracuBottomSheet<void>(
      context,
      title: 'Payslip Details',
      subtitle: 'Payslip #$payslipNumber',
      initialChildSize: 0.85,
      builder: (sheetContext, textPrimary, textSecondary) {
        return PayslipDetailSheet(
          payslipNumber: payslipNumber,
          fallbackItem: fallbackItem,
        );
      },
    );
  }

  @override
  State<PayslipDetailSheet> createState() => _PayslipDetailSheetState();
}

class _PayslipDetailSheetState extends State<PayslipDetailSheet> {
  bool _isLoading = true;
  bool _isDownloadingPdf = false;
  PayslipDetail? _detail;
  List<BankConfig> _banks = const [];

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final detailFuture = PaymentService().fetchPayslipDetail(
      widget.payslipNumber,
      cacheDuration: Duration.zero,
    );
    final banksFuture = PaymentService().fetchBankConfigurations();

    final results = await Future.wait([detailFuture, banksFuture]);
    if (!mounted) return;

    setState(() {
      _detail = results[0] as PayslipDetail?;
      _banks = results[1] as List<BankConfig>;
      _isLoading = false;
    });
  }

  Future<void> _downloadPdf() async {
    final detail = _detail;
    if (detail == null || _isDownloadingPdf) return;

    setState(() {
      _isDownloadingPdf = true;
    });

    try {
      final bytes = await PaymentService().generatePayslipPdfBytes(
        detail: detail,
        banks: _banks,
      );

      if (!mounted) return;

      if (bytes == null || bytes.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not generate PDF payslip')),
        );
        return;
      }

      if (kIsWeb) {
        await openPdfInBrowser(
          bytes: Uint8List.fromList(bytes),
          fileName: 'Payslip_${detail.payslipNumber}.pdf',
        );
      } else {
        final tempDir = Directory.systemTemp;
        final file = File(
          '${tempDir.path}/Payslip_${detail.payslipNumber}.pdf',
        );
        await file.writeAsBytes(bytes);
        final opened = await NativeFile.open(file.path);
        if (!opened && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Saved payslip PDF to ${file.path}')),
          );
        }
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Error downloading payslip PDF')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isDownloadingPdf = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final textSecondary = BracuPalette.textSecondary(context);

    if (_isLoading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 40),
        child: Center(child: BracuLoading()),
      );
    }

    if (_detail == null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 40),
        child: Center(
          child: Text(
            'Could not load payslip details',
            style: TextStyle(color: textSecondary),
          ),
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(0, 8, 0, 28),
      children: [
        _buildHeaderSection(context),
        const Gap(14),
        _buildParticularsSection(context),
        if (_detail!.courseList.isNotEmpty) ...[
          const Gap(14),
          _buildCoursesSection(context),
        ],
        if (_banks.isNotEmpty) ...[const Gap(14), _buildBanksSection(context)],
        const Gap(16),
      ],
    );
  }

  Widget _buildHeaderSection(BuildContext context) {
    final detail = _detail!;
    final textPrimary = BracuPalette.textPrimary(context);
    final textSecondary = BracuPalette.textSecondary(context);
    final isPaid = detail.isPaid;
    final statusColor = isPaid ? BracuPalette.accent : const Color(0xFFFF8A34);

    return BracuCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      detail.paySlipTitle.isNotEmpty
                          ? detail.paySlipTitle
                          : 'Payslip',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: textPrimary,
                      ),
                    ),
                    const Gap(2),
                    Text(
                      detail.semesterSession,
                      style: TextStyle(
                        fontSize: 12,
                        color: textSecondary,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  isPaid ? 'Paid' : 'Due',
                  style: TextStyle(
                    color: statusColor,
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
          const Gap(10),
          const Divider(height: 1),
          const Gap(10),
          _DetailRow(
            label: 'Payslip No.',
            value: detail.payslipNumber,
            enableCopy: true,
          ),
          const Gap(6),
          _DetailRow(label: 'Program', value: detail.programOrCourseName),
          if (detail.deadlineFormatted.isNotEmpty) ...[
            const Gap(6),
            _DetailRow(
              label: 'Due Date',
              value: detail.deadlineFormatted,
              isBold: true,
            ),
          ],
          const Gap(14),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: _isDownloadingPdf ? null : _downloadPdf,
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                side: BorderSide(
                  color: BracuPalette.primary.withValues(alpha: 0.3),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (_isDownloadingPdf)
                    const BracuSpinner(size: 16)
                  else
                    Icon(
                      Icons.picture_as_pdf_rounded,
                      size: 16,
                      color: textPrimary,
                    ),
                  const Gap(8),
                  Text(
                    _isDownloadingPdf ? 'Downloading' : 'Download Payslip',
                    style: TextStyle(
                      color: textPrimary,
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildParticularsSection(BuildContext context) {
    final detail = _detail!;
    final textPrimary = BracuPalette.textPrimary(context);
    final textSecondary = BracuPalette.textSecondary(context);

    return BracuCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Payment Breakdown',
            style: TextStyle(
              fontSize: 14.5,
              fontWeight: FontWeight.w700,
              color: textPrimary,
            ),
          ),
          const Gap(10),
          ...() {
            final activeParticulars = detail.particulars.where((p) {
              if (p.type == 'AGGREGATION' || p.type == 'WORDS') return true;
              final amt = p.amount ?? 0;
              if (amt > 0) return true;
              return p.particular.toLowerCase().contains('fee') ||
                  p.particular.toLowerCase().contains('due');
            }).toList();

            return activeParticulars.map((p) {
              final isBold = p.type == 'AGGREGATION' || p.type == 'WORDS';
              final amountStr = p.amount != null
                  ? '৳${_formatAmount(p.amount!)}'
                  : '';

              if (p.type == 'WORDS') {
                return Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    p.particular,
                    style: TextStyle(
                      fontSize: 11.5,
                      fontStyle: FontStyle.italic,
                      color: textSecondary,
                    ),
                  ),
                );
              }

              final isLessHeader = p.particular.trim().toLowerCase() == 'less:';
              if (isLessHeader) {
                return Padding(
                  padding: const EdgeInsets.only(top: 4, bottom: 2),
                  child: Text(
                    p.particular,
                    style: TextStyle(
                      fontSize: 11.5,
                      fontStyle: FontStyle.italic,
                      color: textSecondary,
                    ),
                  ),
                );
              }

              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 3.5),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        p.particular,
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: isBold
                              ? FontWeight.w700
                              : FontWeight.w500,
                          color: textPrimary,
                        ),
                      ),
                    ),
                    if (amountStr.isNotEmpty)
                      Text(
                        amountStr,
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: isBold
                              ? FontWeight.w700
                              : FontWeight.w600,
                          color: isBold ? BracuPalette.primary : textPrimary,
                        ),
                      ),
                  ],
                ),
              );
            });
          }(),
        ],
      ),
    );
  }

  Widget _buildCoursesSection(BuildContext context) {
    final detail = _detail!;
    final textPrimary = BracuPalette.textPrimary(context);
    final textSecondary = BracuPalette.textSecondary(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Registered Courses (${detail.courseList.length})',
          style: TextStyle(
            fontSize: 14.5,
            fontWeight: FontWeight.w700,
            color: textPrimary,
          ),
        ),
        const Gap(8),
        ...detail.courseList.map((c) {
          final isLab = c.courseCode.endsWith('L');
          return Container(
            margin: const EdgeInsets.only(bottom: 6),
            child: BracuCard(
              padding: const EdgeInsets.all(12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Container(
                    width: 26,
                    height: 26,
                    decoration: const BoxDecoration(color: Colors.transparent),
                    alignment: Alignment.center,
                    child: Icon(
                      isLab ? Icons.science_rounded : Icons.book_rounded,
                      size: 14,
                      color: isLab
                          ? const Color(0xFFFF8A34)
                          : BracuPalette.accent,
                    ),
                  ),
                  const Gap(10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          c.courseCode,
                          style: TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w700,
                            color: textPrimary,
                          ),
                        ),
                        const Gap(1),
                        Text(
                          c.courseTitle,
                          style: TextStyle(fontSize: 11, color: textSecondary),
                        ),
                      ],
                    ),
                  ),
                  const Gap(8),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        '৳${_formatAmount(c.amount)}',
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          color: textPrimary,
                        ),
                      ),
                      const Gap(1),
                      Text(
                        '${c.academicCredit} Credits',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: textSecondary,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        }),
      ],
    );
  }

  Widget _buildBanksSection(BuildContext context) {
    final textPrimary = BracuPalette.textPrimary(context);
    final textSecondary = BracuPalette.textSecondary(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'BRACU Deposit Bank Accounts',
          style: TextStyle(
            fontSize: 14.5,
            fontWeight: FontWeight.w700,
            color: textPrimary,
          ),
        ),
        const Gap(2),
        Text(
          'Deposit the payable amount to any of the following accounts',
          style: TextStyle(fontSize: 11, color: textSecondary),
        ),
        const Gap(8),
        ..._banks.map((b) {
          return Container(
            margin: const EdgeInsets.only(bottom: 6),
            child: BracuCard(
              padding: const EdgeInsets.all(12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Container(
                    width: 26,
                    height: 26,
                    decoration: const BoxDecoration(color: Colors.transparent),
                    alignment: Alignment.center,
                    child: const Icon(
                      Icons.account_balance_rounded,
                      size: 14,
                      color: BracuPalette.accent,
                    ),
                  ),
                  const Gap(10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          b.branch.isNotEmpty
                              ? '${b.bankName} • ${b.branch}'
                              : b.bankName,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: textPrimary,
                          ),
                        ),
                        const Gap(3),
                        GestureDetector(
                          onTap: () =>
                              copyToClipboard(context, b.accountNumber),
                          child: Row(
                            children: [
                              Text(
                                'Acc: ${b.accountNumber}',
                                style: TextStyle(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w600,
                                  color: BracuPalette.primary,
                                ),
                              ),
                              const Gap(4),
                              Icon(
                                Icons.copy_rounded,
                                size: 11.5,
                                color: textSecondary,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        }),
      ],
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({
    required this.label,
    required this.value,
    this.isBold = false,
    this.enableCopy = false,
  });

  final String label;
  final String value;
  final bool isBold;
  final bool enableCopy;

  @override
  Widget build(BuildContext context) {
    final textPrimary = BracuPalette.textPrimary(context);
    final textSecondary = BracuPalette.textSecondary(context);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: TextStyle(fontSize: 12, color: textSecondary)),
        const Gap(8),
        Expanded(
          child: Align(
            alignment: Alignment.centerRight,
            child: enableCopy
                ? GestureDetector(
                    onTap: () => copyToClipboard(context, value),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Flexible(
                          child: Text(
                            value,
                            textAlign: TextAlign.right,
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: isBold
                                  ? FontWeight.w700
                                  : FontWeight.w600,
                              color: textPrimary,
                            ),
                          ),
                        ),
                        const Gap(4),
                        Icon(
                          Icons.copy_rounded,
                          size: 12.5,
                          color: textSecondary,
                        ),
                      ],
                    ),
                  )
                : Text(
                    value,
                    textAlign: TextAlign.right,
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: isBold ? FontWeight.w700 : FontWeight.w600,
                      color: textPrimary,
                    ),
                  ),
          ),
        ),
      ],
    );
  }
}

String _formatAmount(double amount) {
  final s = amount.toStringAsFixed(0);
  final buf = StringBuffer();
  final len = s.length;
  for (int i = 0; i < len; i++) {
    if (i > 0 && (len - i) % 3 == 0) {
      buf.write(',');
    }
    buf.write(s[i]);
  }
  return buf.toString();
}
