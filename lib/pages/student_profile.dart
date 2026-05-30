import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:preconnect/api/api_config.dart';
import 'package:preconnect/api/profile.dart';
import 'package:preconnect/api/progress.dart';
import 'package:preconnect/model/progress_info.dart';
import 'package:preconnect/pages/card_section.dart';
import 'package:preconnect/pages/shared_widgets/grade_sheet_card.dart';
import 'package:preconnect/pages/student_profile_sections/academic_summary.dart';
import 'package:preconnect/pages/student_profile_sections/attendance_summary.dart';
import 'package:preconnect/pages/student_profile_sections/payment_graph.dart';
import 'package:preconnect/pages/student_profile_sections/payment_list.dart';
import 'package:preconnect/pages/student_profile_sections/personal_info_card.dart';
import 'package:preconnect/pages/ui_kit.dart';
import 'package:preconnect/tools/token_storage.dart';
import 'package:preconnect/tools/refresh_bus.dart';

class StudentProfile extends StatefulWidget {
  const StudentProfile({super.key});

  static Future<void> preload() async {
    await _StudentProfileState.preloadData();
  }

  @override
  State<StudentProfile> createState() => _StudentProfileState();
}

class _StudentProfileState extends State<StudentProfile>
    with SingleTickerProviderStateMixin, RefreshBusState {
  static _StudentProfileSnapshot? _cachedSnapshot;
  static Future<_StudentProfileSnapshot>? _preloadFuture;
  static const Duration _emptyRetryInterval = Duration(seconds: 5);
  Map<String, String?>? _profile;
  String? _photoUrl;
  List<PaymentInfo> _payments = [];
  List<AttendanceInfo> _attendances = [];
  Map<String, String?> _advising = {};
  ProgressSummary? _progressSummary;
  bool _isRefreshing = false;
  late final AnimationController _refreshController;
  Timer? _emptyRetryTimer;

  @override
  void initState() {
    super.initState();
    _refreshController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    final forceRefresh = isRefreshingFrom('auth');
    if (!forceRefresh) {
      _seedCachedSnapshot();
    }
    unawaited(_warmAndBind());
    _scheduleEmptyRetry();
    bindRefreshBus(_onRefreshSignal);
  }

  void _seedCachedSnapshot() {
    final snapshot = _cachedSnapshot;
    if (snapshot == null) return;
    _profile = snapshot.profile;
    _photoUrl = snapshot.photoUrl;
    _payments = snapshot.payments;
    _attendances = snapshot.attendances;
    _advising = snapshot.advising;
    _progressSummary = snapshot.progressSummary;
  }

  static Future<_StudentProfileSnapshot> preloadData({
    bool forceRefresh = false,
  }) async {
    if (!forceRefresh && _cachedSnapshot != null) {
      return _cachedSnapshot!;
    }
    if (!forceRefresh) {
      final inFlight = _preloadFuture;
      if (inFlight != null) {
        return inFlight;
      }
    }

    final future = _loadProfileSnapshot(forceRefresh: forceRefresh);
    _preloadFuture = future;
    try {
      final snapshot = await future;
      _cachedSnapshot = snapshot;
      return snapshot;
    } finally {
      if (identical(_preloadFuture, future)) {
        _preloadFuture = null;
      }
    }
  }

  @override
  void dispose() {
    _emptyRetryTimer?.cancel();
    _refreshController.dispose();
    unbindRefreshBus(_onRefreshSignal);
    super.dispose();
  }

  void _scheduleEmptyRetry() {
    _emptyRetryTimer?.cancel();
    if (_profile != null) return;
    _emptyRetryTimer = Timer(_emptyRetryInterval, () {
      if (!mounted || _isRefreshing) return;
      if (_profile != null) return;
      unawaited(_refreshProfile(notify: false));
      _scheduleEmptyRetry();
    });
  }

  void _onRefreshSignal() {
    if (!mounted) return;
    final reason = refreshBusReason;
    if (reason == 'student_profile') {
      return;
    }
    if (reason == 'auth') {
      _cachedSnapshot = null;
      _preloadFuture = null;
      setState(() {
        _profile = null;
        _photoUrl = null;
        _payments = [];
        _attendances = [];
        _advising = {};
        _progressSummary = null;
      });
      unawaited(_refreshProfile(notify: false));
    }
  }

  static List<dynamic> _decodeListStatic(String? raw) {
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

  static int _payslipSortValue(PaymentInfo p) {
    return int.tryParse(p.payslipNumber) ?? 0;
  }

  static int _comparePayments(PaymentInfo a, PaymentInfo b) {
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

  Future<void> _warmAndBind() async {
    final snapshot = await preloadData(forceRefresh: isRefreshingFrom('auth'));
    if (!mounted) return;
    setState(() {
      _profile = snapshot.profile;
      _photoUrl = snapshot.photoUrl;
      _payments = snapshot.payments;
      _attendances = snapshot.attendances;
      _advising = snapshot.advising;
      _progressSummary = snapshot.progressSummary;
    });
  }

  static Future<_StudentProfileSnapshot> _loadProfileSnapshot({
    bool forceRefresh = false,
  }) async {
    final profileFuture = () async {
      try {
        return forceRefresh
            ? await ProfileService().fetchProfile()
            : await ProfileService().getProfile();
      } catch (_) {
        return null;
      }
    }();
    final paymentsFuture = () async {
      try {
        final List<dynamic> paymentsJson = _decodeListStatic(
          forceRefresh
              ? await PaymentService().fetchPaymentInfo()
              : await PaymentService().getPaymentInfo(),
        );
        return paymentsJson
            .map<PaymentInfo?>((item) {
              try {
                return PaymentInfo.fromJson(item as Map<String, dynamic>);
              } catch (e) {
                return null;
              }
            })
            .whereType<PaymentInfo>()
            .toList()
          ..sort(_comparePayments);
      } catch (_) {
        return const <PaymentInfo>[];
      }
    }();
    final attendanceFuture = () async {
      try {
        final List<dynamic> attendanceJson = _decodeListStatic(
          forceRefresh
              ? await AttendanceService().fetchAttendanceInfo()
              : await AttendanceService().getAttendanceInfo(),
        );
        return attendanceJson
            .map<AttendanceInfo?>((e) {
              try {
                return AttendanceInfo.fromJson(e as Map<String, dynamic>);
              } catch (e) {
                return null;
              }
            })
            .whereType<AttendanceInfo>()
            .toList();
      } catch (_) {
        return const <AttendanceInfo>[];
      }
    }();
    final advisingFuture = () async {
      try {
        return forceRefresh
            ? await AdvisingService().fetchAdvisingInfo()
            : await AdvisingService().getAdvisingInfo();
      } catch (_) {
        return null;
      }
    }();
    final progressFuture = () async {
      try {
        final progress = forceRefresh
            ? await ProgressService().fetchProgress()
            : await ProgressService().getProgress();
        return progress == null
            ? null
            : ProgressSummary.fromProgressInfo(progress);
      } catch (_) {
        return null;
      }
    }();

    final results = await Future.wait<dynamic>(<Future<dynamic>>[
      profileFuture,
      paymentsFuture,
      attendanceFuture,
      advisingFuture,
      progressFuture,
    ]);

    final profile = results[0] as Map<String, String?>?;
    final payments = results[1] as List<PaymentInfo>;
    final attendances = results[2] as List<AttendanceInfo>;
    final advising = results[3] as Map<String, String?>? ?? <String, String?>{};
    final progressSummary = results[4] as ProgressSummary?;
    final photoUrl = ApiConfig.photoUrl(profile?['photoFilePath']);
    if ((photoUrl ?? '').trim().isNotEmpty) {
      unawaited(ProfileImageCache.instance.getProfileImage(photoUrl));
    }

    return _StudentProfileSnapshot(
      profile: profile,
      photoUrl: photoUrl,
      payments: payments,
      attendances: attendances,
      advising: advising,
      progressSummary: progressSummary,
    );
  }

  Future<void> _refreshProfile({bool notify = true}) async {
    if (_isRefreshing) return;
    if (!await ensureOnline(context, notify: notify)) {
      return;
    }
    setState(() {
      _isRefreshing = true;
    });
    _refreshController.repeat();
    try {
      final snapshot = await preloadData(forceRefresh: true);
      if (!mounted) return;
      setState(() {
        _profile = snapshot.profile;
        _photoUrl = snapshot.photoUrl;
        _payments = snapshot.payments;
        _attendances = snapshot.attendances;
        _advising = snapshot.advising;
        _progressSummary = snapshot.progressSummary;
      });
      _scheduleEmptyRetry();
      _cachedSnapshot = snapshot;
      RefreshBus.instance.notify(reason: 'student_profile');
    } finally {
      if (mounted) {
        setState(() {
          _isRefreshing = false;
        });
        _refreshController
          ..stop()
          ..reset();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isLoading = _profile == null;
    return BracuPageScaffold(
      title: 'Student Profile',
      subtitle: 'Academic & Finance',
      icon: Icons.person_outline,
      body: BracuRefreshList(
        onRefresh: _refreshProfile,
        children: [
          if (isLoading)
            const BracuLoading()
          else
            CardSection(profile: _profile, photoUrl: _photoUrl),
          const SizedBox(height: 18),
          if (!isLoading)
            AcademicSummaryCard(
              profile: _profile ?? const {},
              advising: _advising,
              progressSummary: _progressSummary,
            ),
          const SizedBox(height: 18),
          if (!isLoading) ...[
            const BracuSectionTitle(title: 'Documents'),
            const SizedBox(height: 10),
            const GradeSheetCard(),
            const SizedBox(height: 18),
            const BracuSectionTitle(title: 'Personal Info'),
            const SizedBox(height: 10),
            PersonalInfoCard(profile: _profile ?? const {}),
            const SizedBox(height: 18),
            const BracuSectionTitle(title: 'Attendance'),
            const SizedBox(height: 10),
            if (_attendances.isNotEmpty) ...[
              AttendanceSummary(attendances: _attendances),
              const SizedBox(height: 12),
            ],
            const SizedBox(height: 18),
            const BracuSectionTitle(title: 'Payments'),
            const SizedBox(height: 10),
            _payments.isEmpty
                ? const BracuEmptyState(message: 'No payments found')
                : PaymentGraph(payments: _payments),
            if (_payments.isNotEmpty) const SizedBox(height: 12),
            if (_payments.isNotEmpty) PaymentList(payments: _payments),
            const SizedBox(height: 12),
          ],
        ],
      ),
    );
  }
}

class _StudentProfileSnapshot {
  const _StudentProfileSnapshot({
    required this.profile,
    required this.photoUrl,
    required this.payments,
    required this.attendances,
    required this.advising,
    required this.progressSummary,
  });

  final Map<String, String?>? profile;
  final String? photoUrl;
  final List<PaymentInfo> payments;
  final List<AttendanceInfo> attendances;
  final Map<String, String?> advising;
  final ProgressSummary? progressSummary;
}
