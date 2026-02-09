import 'dart:async';
import 'dart:convert';
import 'package:intl/intl.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:preconnect/api/bracu_auth_manager.dart';
import 'package:preconnect/model/payment_info.dart';
import 'package:preconnect/model/attendance_info.dart';
import 'package:preconnect/pages/card_section.dart';
import 'package:preconnect/pages/ui_kit.dart';

class StudentProfile extends StatefulWidget {
  const StudentProfile({super.key});

  @override
  State<StudentProfile> createState() => _StudentProfileState();
}

class _StudentProfileState extends State<StudentProfile>
    with SingleTickerProviderStateMixin {
  Map<String, String?>? _profile = {};
  String? _photoUrl;
  List<PaymentInfo> _payments = [];
  List<AttendanceInfo> _attendances = [];
  Map<String, String?> _advising = {};
  bool _isRefreshing = false;
  late final AnimationController _refreshController;

  @override
  void initState() {
    super.initState();
    _refreshController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    unawaited(BracuAuthManager().fetchProfile());
    unawaited(BracuAuthManager().fetchPaymentInfo());
    unawaited(BracuAuthManager().fetchAttendanceInfo());
    unawaited(BracuAuthManager().fetchAdvisingInfo());
    _loadProfile();
  }

  @override
  void dispose() {
    _refreshController.dispose();
    super.dispose();
  }

  List<dynamic> _decodeList(String? raw) {
    if (raw == null || raw.trim().isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List<dynamic>) return decoded;
      if (decoded is Map<String, dynamic>) {
        final data = decoded['data'];
        if (data is List<dynamic>) return data;
        final content = decoded['content'];
        if (content is List<dynamic>) return content;
      }
      return const [];
    } catch (_) {
      return const [];
    }
  }

  int _payslipSortValue(PaymentInfo p) {
    return int.tryParse(p.payslipNumber) ?? 0;
  }

  Future<void> _loadProfile() async {
    try {
      final profile = await BracuAuthManager().getProfile();
      final photoUrl = _buildPhotoUrl(profile?['photoFilePath']);
      final List<dynamic> paymentsJson = _decodeList(
        await BracuAuthManager().getPaymentInfo(),
      );
      final List<PaymentInfo> payments =
          paymentsJson
              .map<PaymentInfo?>((item) {
                try {
                  return PaymentInfo.fromJson(item as Map<String, dynamic>);
                } catch (_) {
                  return null;
                }
              })
              .whereType<PaymentInfo>()
              .toList()
            ..sort(
              (a, b) => _payslipSortValue(b).compareTo(_payslipSortValue(a)),
            );

      final List<dynamic> attendanceJson = _decodeList(
        await BracuAuthManager().getAttendanceInfo(),
      );
      final attendances = attendanceJson
          .map<AttendanceInfo?>((e) {
            try {
              return AttendanceInfo.fromJson(e as Map<String, dynamic>);
            } catch (_) {
              return null;
            }
          })
          .whereType<AttendanceInfo>()
          .toList();
      final advising = await BracuAuthManager().getAdvisingInfo();

      if (!mounted) return;
      setState(() {
        _profile = profile;
        _photoUrl = photoUrl;
        _payments = payments;
        _attendances = attendances;
        _advising = advising ?? _advising;
      });
    } catch (_) {}
  }

  Future<void> _refreshProfile() async {
    if (!_isRefreshing) {
      setState(() {
        _isRefreshing = true;
      });
      _refreshController.repeat();
    }
    try {
      final profile = await BracuAuthManager().fetchProfile();
      final photoUrl = _buildPhotoUrl(profile?['photoFilePath']);
      final List<dynamic> paymentsJson = _decodeList(
        await BracuAuthManager().fetchPaymentInfo(),
      );
      final List<PaymentInfo> payments =
          paymentsJson
              .map<PaymentInfo?>((item) {
                try {
                  return PaymentInfo.fromJson(item as Map<String, dynamic>);
                } catch (_) {
                  return null;
                }
              })
              .whereType<PaymentInfo>()
              .toList()
            ..sort(
              (a, b) => _payslipSortValue(b).compareTo(_payslipSortValue(a)),
            );

      final List<dynamic> attendanceJson = _decodeList(
        await BracuAuthManager().fetchAttendanceInfo(),
      );
      final attendances = attendanceJson
          .map<AttendanceInfo?>((e) {
            try {
              return AttendanceInfo.fromJson(e as Map<String, dynamic>);
            } catch (_) {
              return null;
            }
          })
          .whereType<AttendanceInfo>()
          .toList();
      final advising = await BracuAuthManager().fetchAdvisingInfo();

      if (!mounted) return;
      setState(() {
        _profile = profile ?? _profile;
        _photoUrl = photoUrl ?? _photoUrl;
        _payments = payments.isNotEmpty ? payments : _payments;
        _attendances = attendances.isNotEmpty ? attendances : _attendances;
        _advising = advising ?? _advising;
      });
    } catch (_) {}
    if (mounted) {
      setState(() {
        _isRefreshing = false;
      });
      _refreshController
        ..stop()
        ..reset();
    }
  }

  String formatSemester(int semesterSessionId) {
    final year = semesterSessionId ~/ 10;
    final semesterCode = semesterSessionId % 10;

    String semester;
    switch (semesterCode) {
      case 1:
        semester = 'Fall';
        break;
      case 2:
        semester = 'Summer';
        break;
      case 3:
        semester = 'Spring';
        break;
      default:
        semester = 'Unknown';
    }

    return '$semester $year';
  }

  String? _buildPhotoUrl(String? photoFilePath) {
    if (photoFilePath == null || photoFilePath.isEmpty) return null;
    final encoded = base64Url
        .encode(utf8.encode(photoFilePath))
        .replaceAll('=', '');
    return 'https://connect.bracu.ac.bd/cdn/img/thumb/$encoded.jpg';
  }

  String _formatAmount(double amount) {
    final formatter = NumberFormat.decimalPattern('en_IN');
    final rounded = amount.round();
    return '${formatter.format(rounded)} Taka';
  }

  @override
  Widget build(BuildContext context) {
    return BracuPageScaffold(
      title: 'Student Profile',
      subtitle: 'Academic & Finance',
      icon: Icons.person_outline,
      body: RefreshIndicator(
        onRefresh: _refreshProfile,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            const SizedBox(height: 6),
            CardSection(profile: _profile, photoUrl: _photoUrl),
            const SizedBox(height: 18),
            const BracuSectionTitle(title: 'Attendance'),
            const SizedBox(height: 10),
            _attendances.isEmpty
                ? const SizedBox.shrink()
                : _AttendanceGraph(attendances: _attendances),
            if (_attendances.isNotEmpty) const SizedBox(height: 12),
            const SizedBox(height: 18),
            const BracuSectionTitle(title: 'Advising'),
            const SizedBox(height: 10),
            BracuCard(
              child: _AdvisingSummary(
                data: _advising,
                cgpa: (_profile?['cgpa'] ?? 'N/A').trim(),
              ),
            ),
            const SizedBox(height: 18),
            const BracuSectionTitle(title: 'Payments'),
            const SizedBox(height: 10),
            _payments.isEmpty
                ? const SizedBox.shrink()
                : _PaymentGraph(payments: _payments),
            if (_payments.isNotEmpty) const SizedBox(height: 12),
            if (_payments.isEmpty)
              const BracuEmptyState(message: 'No payments found')
            else
              Column(
                children: _payments.map((payment) {
                        final textSecondary = BracuPalette.textSecondary(
                          context,
                        );
                        final textPrimary = BracuPalette.textPrimary(context);
                        final dueDate = formatDate(
                          payment.dueDate.toIso8601String(),
                        );
                        final status = payment.paymentStatus;
                        final isPaid = status == 'PAID';
                        final amount = _formatAmount(payment.totalAmount);
                        final statusColor =
                            isPaid ? BracuPalette.accent : const Color(0xFFFF8A34);
                        final statusBg = statusColor.withValues(alpha: 0.14);
                        final semester = formatSemester(payment.semesterSessionId);
                        final paymentType = payment.paymentType;
                        final cardTint = isPaid
                            ? Colors.transparent
                            : statusBg.withValues(alpha: 0.08);
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
                              Row(
                                children: [
                                  Text(
                                    'Payslip: ${payment.payslipNumber}',
                                    style: TextStyle(
                                      color: textSecondary,
                                      fontWeight: FontWeight.w700,
                                      fontSize: 14,
                                    ),
                                  ),
                                  IconButton(
                                    icon: const Icon(
                                      Icons.copy_rounded,
                                      size: 16,
                                    ),
                                    visualDensity: VisualDensity.compact,
                                    padding: EdgeInsets.zero,
                                    constraints: const BoxConstraints(
                                      minWidth: 28,
                                      minHeight: 28,
                                    ),
                                    tooltip: 'Copy payslip number',
                                    onPressed: () {
                                      Clipboard.setData(
                                        ClipboardData(
                                          text: payment.payslipNumber,
                                        ),
                                      );
                                      ScaffoldMessenger.of(
                                        context,
                                      ).showSnackBar(
                                        const SnackBar(
                                          content: Text(
                                            'Payslip number copied',
                                          ),
                                        ),
                                      );
                                    },
                                  ),
                                  const Spacer(),
                                  Text(
                                    amount,
                                    style: TextStyle(
                                      color: textPrimary,
                                      fontWeight: FontWeight.w700,
                                      fontSize: 14,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              _InfoLine(
                                label: paymentType,
                                value: semester,
                                isLabelBold: true,
                                isValueBold: true,
                              ),
                              const SizedBox(height: 8),
                              _InfoLine(
                                label: 'Requested',
                                value: formatDate(
                                  payment.requestDate.toIso8601String(),
                                ),
                                isLabelBold: true,
                                isValueBold: true,
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
                    ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }
}

class _AttendanceGraph extends StatelessWidget {
  const _AttendanceGraph({required this.attendances});

  final List<AttendanceInfo> attendances;

  @override
  Widget build(BuildContext context) {
    final textSecondary = BracuPalette.textSecondary(context);
    final textPrimary = BracuPalette.textPrimary(context);
    return BracuCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: attendances.map((att) {
          final percent = att.totalClasses == 0
              ? 0.0
              : (att.attend / att.totalClasses) * 100;
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${att.courseCode} • ${att.courseName}',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: textPrimary,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '${percent.toStringAsFixed(0)}%',
                      style: TextStyle(
                        color: textSecondary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                _SimpleBar(value: percent / 100, color: BracuPalette.primary),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }
}

class _PaymentGraph extends StatelessWidget {
  const _PaymentGraph({required this.payments});

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

class _AdvisingSummary extends StatelessWidget {
  const _AdvisingSummary({required this.data, required this.cgpa});

  final Map<String, String?> data;
  final String cgpa;

  bool get _hasData {
    return data.values.any((value) => value != null && value.trim().isNotEmpty);
  }

  @override
  Widget build(BuildContext context) {
    if (!_hasData) {
      return const BracuEmptyState(message: 'No advising info found');
    }

    final textSecondary = BracuPalette.textSecondary(context);
    final textPrimary = BracuPalette.textPrimary(context);
    final pillBg = BracuPalette.primary.withValues(alpha: 0.12);

    final start = formatDate(data['advisingStartDate']);
    final end = formatDate(data['advisingEndDate']);
    final phase = (data['advisingPhase'] ?? 'N/A').trim();
    final totalCredit = (data['totalCredit'] ?? 'N/A').trim();
    final earnedCredit = (data['earnedCredit'] ?? 'N/A').trim();
    final semesterCount = (data['noOfSemester'] ?? 'N/A').trim();
    final activeSessionRaw =
        (data['activeSemesterSessionId'] ?? 'N/A').trim();
    final activeSession = _formatSession(activeSessionRaw);
    final displayCgpa = cgpa.isNotEmpty ? cgpa : 'N/A';
    final totalNum = double.tryParse(totalCredit) ?? 0;
    final earnedNum = double.tryParse(earnedCredit) ?? 0;
    final completion = totalNum == 0 ? 0 : (earnedNum / totalNum * 100);
    final completionLabel = '${completion.toStringAsFixed(0)}%';
    final earnedDisplay = earnedCredit;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: pillBg,
                borderRadius: BorderRadius.circular(10),
              ),
              alignment: Alignment.center,
              child: Icon(
                Icons.school_outlined,
                size: 18,
                color: BracuPalette.primary,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                phase,
                style: TextStyle(
                  color: textPrimary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            Text(
              start == end ? start : start,
              style: TextStyle(
                color: textPrimary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Divider(color: textSecondary.withValues(alpha: 0.25), height: 16),
        _InfoLine(
          label: 'Active Session',
          value: activeSession,
          isLabelBold: true,
          isValueBold: true,
        ),
        _InfoLine(
          label: 'Total Credit',
          value: totalCredit,
          isLabelBold: true,
          isValueBold: true,
        ),
        _InfoLine(
          label: 'Earned Credit',
          value: earnedDisplay,
          isLabelBold: true,
          isValueBold: true,
        ),
        _InfoLine(
          label: 'Completion',
          value: completionLabel,
          isLabelBold: true,
          isValueBold: true,
        ),
        _InfoLine(
          label: 'CGPA',
          value: displayCgpa,
          isLabelBold: true,
          isValueBold: true,
        ),
        _InfoLine(
          label: 'Semesters',
          value: semesterCount,
          isLabelBold: true,
          isValueBold: true,
        ),
      ],
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
        children: [
          Expanded(
            flex: 4,
            child: Text(
              label,
              style: TextStyle(
                color: textSecondary,
                fontWeight: isLabelBold ? FontWeight.w700 : FontWeight.w500,
                fontSize: 14,
              ),
            ),
          ),
          Expanded(
            flex: 6,
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

String _formatSession(String raw) {
  if (raw.trim().isEmpty || raw.trim() == 'N/A') return 'N/A';
  final value = int.tryParse(raw.trim());
  if (value == null) return raw;
  final year = value ~/ 10;
  final code = value % 10;
  final label = switch (code) {
    1 => 'Spring',
    2 => 'Fall',
    3 => 'Summer',
    _ => 'Session',
  };
  return '$label $year';
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
                  color: textPrimary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            Text(
              _PaymentGraph._formatAmountStatic(amount),
              style: TextStyle(color: textSecondary),
            ),
          ],
        ),
        const SizedBox(height: 6),
        _SimpleBar(value: value, color: color),
      ],
    );
  }
}

class _SimpleBar extends StatelessWidget {
  const _SimpleBar({required this.value, required this.color});

  final double value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final trackColor = BracuPalette.primary.withValues(alpha: 0.08);
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth * value.clamp(0.0, 1.0).toDouble();
        return Container(
          height: 8,
          decoration: BoxDecoration(
            color: trackColor,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Container(
              width: width,
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(999),
              ),
            ),
          ),
        );
      },
    );
  }
}
