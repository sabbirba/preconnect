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

  int _comparePayments(PaymentInfo a, PaymentInfo b) {
    final aPaid = a.paymentStatus == 'PAID';
    final bPaid = b.paymentStatus == 'PAID';
    if (aPaid != bPaid) {
      return aPaid ? 1 : -1;
    }
    if (!aPaid) {
      final dueCompare = a.dueDate.compareTo(b.dueDate);
      if (dueCompare != 0) return dueCompare;
      return _payslipSortValue(a).compareTo(_payslipSortValue(b));
    }
    return _payslipSortValue(b).compareTo(_payslipSortValue(a));
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
            ..sort(_comparePayments);

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
            ..sort(_comparePayments);

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
            BracuCard(
              child: _AcademicSummary(
                profile: _profile ?? const {},
                advising: _advising,
              ),
            ),
            const SizedBox(height: 18),
            const BracuSectionTitle(title: 'Attendance'),
            const SizedBox(height: 10),
            _attendances.isEmpty
                ? const SizedBox.shrink()
                : _AttendanceGraph(attendances: _attendances),
            if (_attendances.isNotEmpty) const SizedBox(height: 12),
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
                children: _payments.asMap().entries.map((entry) {
                        final index = entry.key;
                        final payment = entry.value;
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
                        final paymentType = _formatPaymentType(
                          payment.paymentType,
                        );
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
                              LayoutBuilder(
                                builder: (context, constraints) {
                                  return Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Text(
                                            '${index + 1}.',
                                            style: TextStyle(
                                              color: BracuPalette.primary,
                                              fontWeight: FontWeight.w700,
                                              fontSize: 14,
                                            ),
                                          ),
                                          const SizedBox(width: 4),
                                          Text(
                                            payment.payslipNumber,
                                            style: TextStyle(
                                              color: textSecondary,
                                              fontWeight: FontWeight.w700,
                                              fontSize: 14,
                                            ),
                                          ),
                                          const SizedBox(width: 0),
                                          const SizedBox(width: 4),
                                          GestureDetector(
                                            onTap: () {
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
                                            child: Icon(
                                              Icons.copy_rounded,
                                              size: 14,
                                              color: textSecondary,
                                            ),
                                          ),
                                        ],
                                      ),
                                      Text(
                                        amount,
                                        style: TextStyle(
                                          color: textPrimary,
                                          fontWeight: FontWeight.w700,
                                          fontSize: 14,
                                        ),
                                        textAlign: TextAlign.right,
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
                                value: formatDate(
                                  payment.requestDate.toIso8601String(),
                                ),
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

class _AcademicSummary extends StatelessWidget {
  const _AcademicSummary({required this.profile, required this.advising});

  final Map<String, String?> profile;
  final Map<String, String?> advising;

  String _value(String key) {
    final raw = (profile[key] ?? '').trim();
    return raw.isEmpty ? 'N/A' : raw;
  }

  String _currentSession() {
    final raw = (profile['currentSessionSemesterId'] ?? '').trim();
    if (raw.isEmpty) return 'N/A';
    return _formatSession(raw);
  }

  bool get _hasAdvisingData {
    return advising.values.any((value) => value != null && value.trim().isNotEmpty);
  }

  @override
  Widget build(BuildContext context) {
    final textSecondary = BracuPalette.textSecondary(context);
    final textPrimary = BracuPalette.textPrimary(context);
    final cgpa = (profile['cgpa'] ?? 'N/A').trim();
    final advisingPhase = _formatAdvisingPhase(advising['advisingPhase']);
    final advisingStart = formatDate(advising['advisingStartDate']);
    final advisingEnd = formatDate(advising['advisingEndDate']);
    final advisingDate = advisingStart == 'N/A' && advisingEnd == 'N/A'
        ? 'N/A'
        : (advisingStart == advisingEnd
            ? advisingStart
            : '$advisingStart - $advisingEnd');
    final totalCredit = (advising['totalCredit'] ?? 'N/A').trim();
    final earnedCredit = (advising['earnedCredit'] ?? 'N/A').trim();
    final semesterCount = (advising['noOfSemester'] ?? 'N/A').trim();
    final totalNum = double.tryParse(totalCredit) ?? 0;
    final earnedNum = double.tryParse(earnedCredit) ?? 0;
    final completionRatio =
        totalNum == 0 ? null : (earnedNum / totalNum).clamp(0.0, 1.0);
    final completion =
        completionRatio == null ? 'N/A' : '${(completionRatio * 100).toStringAsFixed(0)}%';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: BracuPalette.primary.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              alignment: Alignment.center,
              child: Icon(
                Icons.school_outlined,
                size: 20,
                color: BracuPalette.primary,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _currentSession(),
                    style: TextStyle(
                      color: textPrimary,
                      fontWeight: FontWeight.w700,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _value('departmentName'),
                    style: TextStyle(
                      color: textSecondary,
                      fontWeight: FontWeight.w600,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: BracuPalette.primary.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: BracuPalette.primary.withValues(alpha: 0.16),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Completion',
                      style: TextStyle(
                        color: textSecondary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  Text(
                    completion,
                    style: TextStyle(
                      color: textPrimary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              TweenAnimationBuilder<double>(
                tween: Tween(
                  begin: 0,
                  end: completionRatio ?? 0,
                ),
                duration: const Duration(milliseconds: 700),
                builder: (context, value, child) {
                  return ClipRRect(
                    borderRadius: BorderRadius.circular(999),
                    child: LinearProgressIndicator(
                      value: completionRatio == null ? 0 : value,
                      minHeight: 8,
                      backgroundColor:
                          BracuPalette.primary.withValues(alpha: 0.12),
                      valueColor: AlwaysStoppedAnimation<Color>(
                        BracuPalette.primary,
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(height: 10),
              LayoutBuilder(
                builder: (context, constraints) {
                  final itemWidth = (constraints.maxWidth - 12) / 3;
                  return Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      _StatTile(
                        label: 'Credits Earned',
                        value: totalNum == 0
                            ? 'N/A'
                            : '${earnedNum.toStringAsFixed(0)} of ${totalNum.toStringAsFixed(0)}',
                        width: itemWidth,
                      ),
                      _StatTile(
                        label: 'CGPA',
                        value: cgpa.isNotEmpty ? cgpa : 'N/A',
                        width: itemWidth,
                      ),
                      _StatTile(
                        label: 'Done',
                        value: semesterCount.isEmpty ? 'N/A' : semesterCount,
                        width: itemWidth,
                      ),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        LayoutBuilder(
          builder: (context, constraints) {
            final half = (constraints.maxWidth - 12) / 2;
            return Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                if (_hasAdvisingData) ...[
                  _MiniField(
                    label: 'Advising Phase',
                    value: advisingPhase,
                    width: half,
                  ),
                  _MiniField(
                    label: 'Advising Date',
                    value: advisingDate,
                    width: half,
                  ),
                ],
              ],
            );
          },
        ),
      ],
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({
    required this.label,
    required this.value,
    required this.width,
  });

  final String label;
  final String value;
  final double width;

  @override
  Widget build(BuildContext context) {
    final textSecondary = BracuPalette.textSecondary(context);
    final textPrimary = BracuPalette.textPrimary(context);
    return Container(
      width: width,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(
            label,
            style: TextStyle(
              color: textSecondary,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              color: textPrimary,
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _MiniField extends StatelessWidget {
  const _MiniField({
    required this.label,
    required this.value,
    required this.width,
  });

  final String label;
  final String value;
  final double width;

  @override
  Widget build(BuildContext context) {
    final textSecondary = BracuPalette.textSecondary(context);
    final textPrimary = BracuPalette.textPrimary(context);
    return Container(
      width: width,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: BracuPalette.card(context),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: BracuPalette.primary.withValues(alpha: 0.08),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              color: textSecondary,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              color: textPrimary,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
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

String _formatAdvisingPhase(String? raw) {
  final cleaned = (raw ?? '').trim();
  if (cleaned.isEmpty || cleaned == 'N/A') return 'N/A';
  final words = cleaned.split('_').where((w) => w.trim().isNotEmpty).toList();
  if (words.isEmpty) return cleaned;
  return words
      .map((w) {
        final lower = w.toLowerCase();
        return lower[0].toUpperCase() + lower.substring(1);
      })
      .join(' ');
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
