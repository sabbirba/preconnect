import 'dart:async';
import 'dart:convert';
import 'package:intl/intl.dart';
import 'package:flutter/material.dart';
import 'package:preconnect/api/bracu_auth_manager.dart';
import 'package:preconnect/model/payment_info.dart';
import 'package:preconnect/model/attendance_info.dart';
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

      if (!mounted) return;
      setState(() {
        _profile = profile;
        _photoUrl = photoUrl;
        _payments = payments;
        _attendances = attendances;
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

      if (!mounted) return;
      setState(() {
        _profile = profile ?? _profile;
        _photoUrl = photoUrl ?? _photoUrl;
        _payments = payments.isNotEmpty ? payments : _payments;
        _attendances = attendances.isNotEmpty ? attendances : _attendances;
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
            _ProfileHeader(profile: _profile, photoUrl: _photoUrl),
            const SizedBox(height: 12),
            _ProfileGrid(profile: _profile),
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
            BracuCard(
              child: _payments.isEmpty
                  ? const BracuEmptyState(message: 'No payments found')
                  : Column(
                      children: _payments.map((payment) {
                        final textSecondary = BracuPalette.textSecondary(
                          context,
                        );
                        final textPrimary = BracuPalette.textPrimary(context);
                        final dueDate = formatDate(
                          payment.dueDate.toIso8601String(),
                        );
                        final status = payment.paymentStatus;
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                width: 36,
                                height: 36,
                                decoration: BoxDecoration(
                                  color: status == 'PAID'
                                      ? BracuPalette.accent.withValues(
                                          alpha: 0.12,
                                        )
                                      : const Color(
                                          0xFFFF8A34,
                                        ).withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                alignment: Alignment.center,
                                child: Icon(
                                  Icons.payment,
                                  size: 18,
                                  color: status == 'PAID'
                                      ? BracuPalette.accent
                                      : const Color(0xFFFF8A34),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Payslip: ${payment.payslipNumber}',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w600,
                                        color: textPrimary,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      '${payment.paymentType} • ${formatSemester(payment.semesterSessionId)}',
                                      style: TextStyle(color: textSecondary),
                                    ),
                                    Text(
                                      'Status: $status${status != 'PAID' ? ' • Due: $dueDate' : ''}',
                                      style: TextStyle(color: textSecondary),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      'Requested: ${formatDate(payment.requestDate.toIso8601String())} '
                                      '• Amount: ${_formatAmount(payment.totalAmount)}',
                                      style: TextStyle(color: textSecondary),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      'Due date: ${formatDate(payment.dueDate.toIso8601String())}',
                                      style: TextStyle(color: textSecondary),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        );
                      }).toList(),
                    ),
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }
}

class _ProfileHeader extends StatelessWidget {
  const _ProfileHeader({required this.profile, required this.photoUrl});

  final Map<String, String?>? profile;
  final String? photoUrl;

  @override
  Widget build(BuildContext context) {
    final name = profile?['fullName'] ?? 'BRACU Student';
    final email = profile?['email'] ?? 'N/A';
    final mobile = profile?['mobileNo'] ?? 'N/A';
    final textPrimary = BracuPalette.textPrimary(context);
    final textSecondary = BracuPalette.textSecondary(context);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: BracuPalette.card(context),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: BracuPalette.primary.withValues(alpha: 0.08)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              color: BracuPalette.primary.withValues(alpha: 0.12),
            ),
            child: photoUrl == null
                ? const Icon(
                    Icons.person,
                    size: 36,
                    color: BracuPalette.primary,
                  )
                : ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: Image.network(
                      photoUrl!,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) {
                        return const Icon(
                          Icons.person,
                          size: 36,
                          color: BracuPalette.primary,
                        );
                      },
                    ),
                  ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: TextStyle(
                    color: textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  email,
                  style: TextStyle(color: textSecondary, fontSize: 12),
                ),
                const SizedBox(height: 4),
                Text(
                  mobile,
                  style: TextStyle(color: textSecondary, fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ProfileGrid extends StatelessWidget {
  const _ProfileGrid({required this.profile});

  final Map<String, String?>? profile;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardColor = isDark
        ? const Color(0xFF0F3B6D)
        : BracuPalette.card(context);
    final labelColor = BracuPalette.textSecondary(context);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: BracuPalette.primary.withValues(alpha: 0.08)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              _ProfilePill(
                label: 'Credits',
                value: profile?['earnedCredit']?.toString() ?? 'N/A',
                labelColor: labelColor,
              ),
              const SizedBox(width: 12),
              _ProfilePill(
                label: 'CGPA',
                value: profile?['cgpa']?.toString() ?? 'N/A',
                labelColor: labelColor,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ProfilePill extends StatelessWidget {
  const _ProfilePill({
    required this.label,
    required this.value,
    required this.labelColor,
  });

  final String label;
  final String value;
  final Color labelColor;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
        decoration: BoxDecoration(
          color: Theme.of(context).brightness == Brightness.dark
              ? const Color(0xFF0A2A4A)
              : Colors.white.withValues(alpha: 0.9),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: BracuPalette.primary.withValues(alpha: 0.08),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: TextStyle(color: labelColor, fontSize: 11)),
            const SizedBox(height: 4),
            Text(
              value,
              style: TextStyle(
                color: BracuPalette.textPrimary(context),
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
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
