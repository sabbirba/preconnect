import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:preconnect/api/api_config.dart';
import 'package:preconnect/api/profile_service.dart';
import 'package:preconnect/api/progress_service.dart';
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

  @override
  State<StudentProfile> createState() => _StudentProfileState();
}

class _StudentProfileState extends State<StudentProfile>
    with SingleTickerProviderStateMixin, RefreshBusState {
  Map<String, String?>? _profile;
  String? _photoUrl;
  File? _cachedImageFile;
  List<PaymentInfo> _payments = [];
  List<AttendanceInfo> _attendances = [];
  Map<String, String?> _advising = {};
  ProgressSummary? _progressSummary;
  bool _isRefreshing = false;
  late final AnimationController _refreshController;

  @override
  void initState() {
    super.initState();
    _refreshController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    unawaited(_preloadDegreeProgress());
    unawaited(_loadProfile());
    bindRefreshBus(_onRefreshSignal);
  }

  @override
  void dispose() {
    _refreshController.dispose();
    unbindRefreshBus(_onRefreshSignal);
    super.dispose();
  }

  void _onRefreshSignal() {
    if (!mounted) return;
    final reason = refreshBusReason;
    if (reason == 'student_profile') {
      return;
    }
    if (reason == 'auth') {
      unawaited(_refreshProfile(notify: false));
    }
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
    Map<String, String?>? profile = _profile;
    String? photoUrl = _photoUrl;
    File? cachedImage = _cachedImageFile;
    List<PaymentInfo> payments = _payments;
    List<AttendanceInfo> attendances = _attendances;
    Map<String, String?> advising = _advising;
    ProgressSummary? progressSummary = _progressSummary;

    try {
      profile = await ProfileService().getProfile();
      photoUrl = ApiConfig.photoUrl(profile?['photoFilePath']);
      cachedImage = await ProfileImageCache.instance.getProfileImage(photoUrl);
    } catch (_) {}

    try {
      final List<dynamic> paymentsJson = _decodeList(
        await PaymentService().getPaymentInfo(),
      );
      payments =
          paymentsJson
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
    } catch (_) {}

    try {
      final List<dynamic> attendanceJson = _decodeList(
        await AttendanceService().getAttendanceInfo(),
      );
      attendances = attendanceJson
          .map<AttendanceInfo?>((e) {
            try {
              return AttendanceInfo.fromJson(e as Map<String, dynamic>);
            } catch (e) {
              return null;
            }
          })
          .whereType<AttendanceInfo>()
          .toList();
    } catch (_) {}

    try {
      advising = await AdvisingService().getAdvisingInfo() ?? advising;
    } catch (_) {}

    try {
      progressSummary =
          await ProgressService().getProgressSummary(fromFetch: true) ??
          progressSummary;
    } catch (_) {}

    if (!mounted) return;
    setState(() {
      _profile = profile;
      _photoUrl = photoUrl;
      _cachedImageFile = cachedImage;
      _payments = payments;
      _attendances = attendances;
      _advising = advising;
      _progressSummary = progressSummary;
    });
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
    unawaited(_preloadDegreeProgress(forceRefresh: true));
    Map<String, String?>? profile = _profile;
    String? photoUrl = _photoUrl;
    File? cachedImage = _cachedImageFile;
    List<PaymentInfo> payments = _payments;
    List<AttendanceInfo> attendances = _attendances;
    Map<String, String?> advising = _advising;
    ProgressSummary? progressSummary = _progressSummary;

    try {
      profile = await ProfileService().fetchProfile();
      photoUrl = ApiConfig.photoUrl(profile?['photoFilePath']);
      ProfileImageCache.instance.invalidate();
      cachedImage = await ProfileImageCache.instance.getProfileImage(photoUrl);
    } catch (_) {}

    try {
      final List<dynamic> paymentsJson = _decodeList(
        await PaymentService().fetchPaymentInfo(),
      );
      payments =
          paymentsJson
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
    } catch (_) {}

    try {
      final List<dynamic> attendanceJson = _decodeList(
        await AttendanceService().fetchAttendanceInfo(),
      );
      attendances = attendanceJson
          .map<AttendanceInfo?>((e) {
            try {
              return AttendanceInfo.fromJson(e as Map<String, dynamic>);
            } catch (e) {
              return null;
            }
          })
          .whereType<AttendanceInfo>()
          .toList();
    } catch (_) {}

    try {
      advising = await AdvisingService().fetchAdvisingInfo() ?? advising;
    } catch (_) {}

    try {
      progressSummary =
          await ProgressService().getProgressSummary(fromFetch: true) ??
          progressSummary;
    } catch (_) {}

    if (!mounted) return;
    setState(() {
      _profile = profile;
      _photoUrl = photoUrl;
      _cachedImageFile = cachedImage;
      _payments = payments;
      _attendances = attendances;
      _advising = advising;
      _progressSummary = progressSummary;
    });
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

  Future<void> _preloadDegreeProgress({bool forceRefresh = false}) async {
    if (forceRefresh) {
      await ProgressService().fetchProgress();
      return;
    }
    await ProgressService().getProgress();
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
          const SizedBox(height: 6),
          if (isLoading) ...[
            const _StudentProfileLoadingSection(),
          ] else ...[
            CardSection(profile: _profile, photoUrl: _photoUrl),
            const SizedBox(height: 18),
            AcademicSummaryCard(
              profile: _profile ?? const {},
              advising: _advising,
              progressSummary: _progressSummary,
            ),
            const SizedBox(height: 18),
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
                ? const SizedBox.shrink()
                : PaymentGraph(payments: _payments),
            if (_payments.isNotEmpty) const SizedBox(height: 12),
            if (_payments.isEmpty)
              const BracuEmptyState(message: 'No payments found')
            else
              PaymentList(payments: _payments),
          ],
          const SizedBox(height: 12),
        ],
      ),
    );
  }
}

class _StudentProfileLoadingSection extends StatelessWidget {
  const _StudentProfileLoadingSection();

  @override
  Widget build(BuildContext context) {
    return const Center(child: _CardSectionSkeleton());
  }
}

class _CardSectionSkeleton extends StatelessWidget {
  const _CardSectionSkeleton();

  @override
  Widget build(BuildContext context) {
    return BracuShimmer(
      child: Center(
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.black),
          ),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
                child: Row(
                  children: const [
                    BracuSkeletonBox(width: 34, height: 34, radius: 10),
                    SizedBox(width: 8),
                    Expanded(
                      child: Align(
                        alignment: Alignment.centerRight,
                        child: BracuSkeletonBox(
                          width: 140,
                          height: 16,
                          radius: 6,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(
                color: Colors.black,
                thickness: 0.9,
                height: 0,
                indent: 0,
              ),
              ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 138),
                child: Row(
                  children: [
                    Container(
                      width: 38,
                      alignment: Alignment.center,
                      child: const RotatedBox(
                        quarterTurns: 3,
                        child: BracuSkeletonBox(
                          width: 72,
                          height: 12,
                          radius: 5,
                        ),
                      ),
                    ),
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                        decoration: const BoxDecoration(
                          color: Color(0xFF7BB3D3),
                          borderRadius: BorderRadius.only(
                            bottomRight: Radius.circular(16),
                          ),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Expanded(
                              flex: 6,
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: const [
                                  BracuSkeletonBox(
                                    width: 126,
                                    height: 12,
                                    radius: 6,
                                  ),
                                  SizedBox(height: 8),
                                  BracuSkeletonBox(
                                    width: 92,
                                    height: 9,
                                    radius: 5,
                                  ),
                                  SizedBox(height: 10),
                                  BracuSkeletonBox(
                                    width: 94,
                                    height: 10,
                                    radius: 5,
                                  ),
                                  SizedBox(height: 6),
                                  BracuSkeletonBox(
                                    width: 72,
                                    height: 10,
                                    radius: 5,
                                  ),
                                  SizedBox(height: 6),
                                  BracuSkeletonBox(
                                    width: 82,
                                    height: 10,
                                    radius: 5,
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 10),
                            const SizedBox(
                              width: 90,
                              height: 106,
                              child: BracuSkeletonBox(height: 106, radius: 4),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
