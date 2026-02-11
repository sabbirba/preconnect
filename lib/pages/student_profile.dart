import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:preconnect/api/bracu_auth_manager.dart';
import 'package:preconnect/model/payment_info.dart';
import 'package:preconnect/model/attendance_info.dart';
import 'package:preconnect/pages/card_section.dart';
import 'package:preconnect/pages/student_profile_sections/academic_summary.dart';
import 'package:preconnect/pages/student_profile_sections/attendance_graph.dart';
import 'package:preconnect/pages/student_profile_sections/payment_graph.dart';
import 'package:preconnect/pages/student_profile_sections/payment_list.dart';
import 'package:preconnect/pages/ui_kit.dart';
import 'package:preconnect/tools/profile_image_cache.dart';
import 'package:preconnect/tools/refresh_bus.dart';
import 'package:preconnect/tools/refresh_guard.dart';

class StudentProfile extends StatefulWidget {
  const StudentProfile({super.key});

  @override
  State<StudentProfile> createState() => _StudentProfileState();
}

class _StudentProfileState extends State<StudentProfile>
    with SingleTickerProviderStateMixin {
  Map<String, String?>? _profile = {};
  String? _photoUrl;
  File? _cachedImageFile;
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
    RefreshBus.instance.addListener(_onRefreshSignal);
  }

  @override
  void dispose() {
    _refreshController.dispose();
    RefreshBus.instance.removeListener(_onRefreshSignal);
    super.dispose();
  }

  void _onRefreshSignal() {
    if (!mounted) return;
    if (RefreshBus.instance.reason == 'student_profile') {
      return;
    }
    unawaited(_refreshProfile(notify: false));
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
      final cachedImage = await ProfileImageCache.instance.getProfileImage(photoUrl);
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
        _cachedImageFile = cachedImage;
        _payments = payments;
        _attendances = attendances;
        _advising = advising ?? _advising;
      });
    } catch (_) {}
  }

  Future<void> _refreshProfile({bool notify = true}) async {
    if (!await ensureOnline(context, notify: notify)) {
      return;
    }
    if (!_isRefreshing) {
      setState(() {
        _isRefreshing = true;
      });
      _refreshController.repeat();
    }
    try {
      final profile = await BracuAuthManager().fetchProfile();
      final photoUrl = _buildPhotoUrl(profile?['photoFilePath']);
      ProfileImageCache.instance.invalidate();
      final cachedImage = await ProfileImageCache.instance.getProfileImage(photoUrl);
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
        _cachedImageFile = cachedImage ?? _cachedImageFile;
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
    if (notify) {
      RefreshBus.instance.notify(reason: 'student_profile');
    }
  }

  String? _buildPhotoUrl(String? photoFilePath) {
    if (photoFilePath == null || photoFilePath.isEmpty) return null;
    final encoded = base64Url
        .encode(utf8.encode(photoFilePath))
        .replaceAll('=', '');
    return 'https://connect.bracu.ac.bd/cdn/img/thumb/$encoded.jpg';
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
            CardSection(profile: _profile, photoUrl: _photoUrl, cachedImageFile: _cachedImageFile),
            const SizedBox(height: 18),
            AcademicSummaryCard(
              profile: _profile ?? const {},
              advising: _advising,
            ),
            const SizedBox(height: 18),
            const BracuSectionTitle(title: 'Attendance'),
            const SizedBox(height: 10),
            _attendances.isEmpty
                ? const SizedBox.shrink()
                : AttendanceGraph(attendances: _attendances),
            if (_attendances.isNotEmpty) const SizedBox(height: 12),
            const SizedBox(height: 18),
            const BracuSectionTitle(title: 'Payments'),
            const SizedBox(height: 10),
            _payments.isEmpty
                ? const SizedBox.shrink()
                : PaymentGraph(payments: _payments),
            if (_payments.isNotEmpty) const SizedBox(height: 12),
            if (_payments.isEmpty)
              const BracuEmptyState(message: 'No payments found')
            else
              PaymentList(payments: _payments),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }
}
