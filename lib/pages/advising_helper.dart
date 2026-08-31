import 'dart:async';
import 'package:flutter/material.dart';
import 'package:gap/gap.dart';
import 'package:preconnect/api/api_client.dart';
import 'package:preconnect/api/advising_service.dart';
import 'package:preconnect/api/profile.dart';
import 'package:preconnect/api/seat_status.dart';
import 'package:preconnect/model/advising_phase.dart';
import 'package:preconnect/model/seat_timetable.dart';
import 'package:preconnect/model/section_info.dart' as section;
import 'package:preconnect/pages/friend_sections/friend_header.dart'
    show FriendAvatar;
import 'package:preconnect/pages/seat_status.dart'
    show seatStatusFacultyHasVisuals;
import 'package:preconnect/pages/shared_widgets/faculty_sheet.dart';
import 'package:preconnect/pages/shared_widgets/seat_filters.dart';
import 'package:preconnect/pages/ui_kit.dart';
import 'package:preconnect/tools/app_storage.dart';
import 'package:preconnect/tools/storage_keys.dart';

class AdvisingHelperPage extends StatefulWidget {
  const AdvisingHelperPage({super.key});

  @override
  State<AdvisingHelperPage> createState() => _AdvisingHelperPageState();
}

class _AdvisingHelperPageState extends State<AdvisingHelperPage> {
  final AdvisingHelperService _service = AdvisingHelperService();
  final AdvisingAutoEngine _engine = AdvisingAutoEngine();

  bool _isLoading = true;
  String? _errorMessage;
  String? _portfolioId;
  String? _publicKey;
  String? _sessionId;
  String? _enrolledError;

  AdvisingPhase _phase = AdvisingPhase.phaseOne;
  List<AdvisingSectionRecord> _enrolled = const [];
  Map<int, SeatStatusDetailsResponse> _seatDetails = const {};
  final TextEditingController _searchController = TextEditingController();
  Timer? _enrolledRefreshTimer;
  bool _isRefreshingEnrolled = false;
  bool _availableOnly = false;
  String _selectedModeFilter = '';
  String _selectedDayFilter = '';
  SeatTimetable _selectedTimeFilter = const SeatTimetable(
    startTime: '',
    endTime: '',
  );
  String _searchQuery = '';
  int _loadGeneration = 0;

  @override
  void initState() {
    super.initState();
    _engine.addListener(_onEngineChange);
    _searchController.addListener(() {
      if (mounted) setState(() => _searchQuery = _searchController.text.trim());
    });
    unawaited(_load());
    _enrolledRefreshTimer = Timer.periodic(
      const Duration(seconds: 2),
      (_) => unawaited(_pollEnrolled()),
    );
  }

  @override
  void dispose() {
    _engine.removeListener(_onEngineChange);
    _engine.stop();
    _engine.dispose();
    _enrolledRefreshTimer?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _onEngineChange() {
    if (mounted) setState(() {});
  }

  Future<void> _load() async {
    if (!mounted) return;
    if (_engine.isRunning) _engine.stop();
    final generation = ++_loadGeneration;
    final phase = _phase;
    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _enrolledError = null;
    });

    try {
      final resolvedPortfolioId = await resolvePortfolioId(
        prefs: AppStorage.instance,
        refreshProfile: () => ProfileService().getProfile(fromFetch: true),
      );

      if (resolvedPortfolioId == null) {
        throw Exception('Failed to resolve student portfolio profile.');
      }

      final publicKey = DateTime.now().millisecondsSinceEpoch.toString();
      final portfolioId = resolvedPortfolioId;
      final studentId = await AppStorage.instance.getString(
        StorageKeys.studentId,
      );
      if (studentId == null || studentId.trim().isEmpty) {
        throw Exception('Failed to resolve student ID.');
      }
      String? activeSessionId;
      String? activeSessionError;
      try {
        activeSessionId = await _service.fetchActiveSessionId(
          studentId,
          phase: phase,
        );
      } on ApiException catch (error) {
        if (isMissingAdvisingPhaseResponse(error)) {
          activeSessionId = null;
        } else {
          activeSessionError = advisingErrorMessage(error);
        }
      } catch (error) {
        activeSessionError = advisingErrorMessage(error);
      }
      final seatsFuture = _service.fetchRealtimeSections();
      List<AdvisingSectionRecord> enrolled = const [];
      String? enrolledError;
      try {
        enrolled = await _fetchAdvisedSections(
          portfolioId,
          phase: phase,
          publicKey: publicKey,
        );
      } catch (error) {
        enrolledError = advisingErrorMessage(error);
      }
      final seatDetails = await seatsFuture;

      if (!mounted || generation != _loadGeneration) return;
      _portfolioId = portfolioId;
      _publicKey = publicKey;
      _sessionId = activeSessionId;
      _enrolledError = enrolledError;
      if (activeSessionError != null) {
        _engine.addLog(
          '${phase.label} session response unavailable: $activeSessionError',
        );
      }
      if (enrolledError != null) {
        _engine.addLog(
          '${phase.label} enrolled sections request failed: $enrolledError',
        );
      }

      setState(() {
        _enrolled = enrolled;
        _seatDetails = seatDetails;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        _errorMessage = e.toString();
        _isLoading = false;
      });
    }
  }

  Future<void> _refreshEnrolled() async {
    final portfolioId = _portfolioId;
    final publicKey = _publicKey;
    final phase = _phase;
    if (portfolioId == null || publicKey == null) return;
    List<AdvisingSectionRecord> sections;
    try {
      sections = await _fetchAdvisedSections(
        portfolioId,
        phase: phase,
        publicKey: publicKey,
      );
    } catch (error) {
      if (mounted &&
          phase == _phase &&
          portfolioId == _portfolioId &&
          publicKey == _publicKey) {
        setState(() => _enrolledError = advisingErrorMessage(error));
      }
      rethrow;
    }
    if (mounted &&
        phase == _phase &&
        portfolioId == _portfolioId &&
        publicKey == _publicKey) {
      setState(() {
        _enrolled = sections;
        _enrolledError = null;
      });
    }
  }

  Future<void> _pollEnrolled() async {
    if (_isLoading || _isRefreshingEnrolled) return;
    _isRefreshingEnrolled = true;
    try {
      await _refreshEnrolled();
    } catch (_) {
    } finally {
      _isRefreshingEnrolled = false;
    }
  }

  Future<List<AdvisingSectionRecord>> _fetchAdvisedSections(
    String portfolioId, {
    required AdvisingPhase phase,
    required String publicKey,
  }) async {
    try {
      return await _service.fetchAdvisedSections(
        portfolioId,
        phase: phase,
        publicKey: publicKey,
      );
    } on ApiException catch (error) {
      if (isMissingAdvisingPhaseResponse(error)) {
        return const <AdvisingSectionRecord>[];
      }
      rethrow;
    }
  }

  Future<void> _refreshSeats() async {
    final portfolioId = _portfolioId;
    final publicKey = _publicKey;
    final phase = _phase;
    if (portfolioId == null || publicKey == null) return;
    final details = await _service.fetchRealtimeSections();
    if (mounted &&
        portfolioId == _portfolioId &&
        publicKey == _publicKey &&
        phase == _phase) {
      setState(() => _seatDetails = details);
    }
  }

  List<SeatStatusDetailsResponse> get _filteredSections {
    final all = _seatDetails.values.toList();
    final q = _searchQuery.toLowerCase();
    final filtered = all.where((section) {
      if (q.isNotEmpty &&
          !section.courseCode.toLowerCase().contains(q) &&
          !section.courseName.toLowerCase().contains(q) &&
          !section.sectionName.toLowerCase().contains(q) &&
          !section.faculties.toLowerCase().contains(q)) {
        return false;
      }
      return matchesSeatFilters(
        availableOnly: _availableOnly,
        remaining: section.capacity - section.consumedSeat,
        mode: _selectedModeFilter,
        hasLabSection: section.labSectionId != null,
        theorySchedules: section.sectionSchedule.classSchedules,
        labSchedules: section.labSchedules,
        day: _selectedDayFilter,
        time: _selectedTimeFilter,
      );
    }).toList();

    final queuedSet = _engine.targetSections.map((e) => e.sectionId).toSet();
    final enrolledSet = _enrolled.map((e) => e.sectionId).toSet();

    filtered.sort((a, b) {
      final aPinned =
          queuedSet.contains(a.sectionId) || enrolledSet.contains(a.sectionId);
      final bPinned =
          queuedSet.contains(b.sectionId) || enrolledSet.contains(b.sectionId);
      if (aPinned != bPinned) {
        return aPinned ? -1 : 1;
      }
      final codeCmp = a.courseCode.compareTo(b.courseCode);
      if (codeCmp != 0) return codeCmp;
      final aSec = int.tryParse(a.sectionName) ?? 9999;
      final bSec = int.tryParse(b.sectionName) ?? 9999;
      if (aSec != bSec) return aSec.compareTo(bSec);
      return a.sectionName.compareTo(b.sectionName);
    });

    return filtered;
  }

  Future<void> _confirmDrop(AdvisingSectionRecord sec) async {
    await showBracuConfirmationWithActionDialog(
      context,
      icon: Icons.remove_circle_outline_rounded,
      title: 'Drop Section?',
      message:
          'Are you sure you want to drop ${sec.courseCode} Section ${sec.sectionName}?',
      confirmLabel: 'Drop',
      cancelLabel: 'Cancel',
      confirmColor: BracuPalette.danger,
      onConfirm: () => _drop(sec),
    );
  }

  Future<void> _drop(AdvisingSectionRecord sec) async {
    if (_portfolioId == null || _publicKey == null) return;
    if (!mounted) return;
    setState(() => _isLoading = true);
    try {
      await _service.dropSection(
        portfolioId: _portfolioId!,
        sectionId: sec.sectionId,
        publicKey: _publicKey!,
        phase: _phase,
      );
      _engine.addLog('Dropped ${sec.courseCode} Sec ${sec.sectionName}');
      if (mounted) {
        showAppSnackBar(
          context,
          'Dropped ${sec.courseCode} Sec ${sec.sectionName}',
        );
      }
      await _refreshEnrolled();
    } catch (e) {
      if (mounted) showAppSnackBar(context, e.toString());
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showFacultyScheduleSheet(String facultyInitial, String? staffName) {
    if (facultyInitial.trim().isEmpty ||
        facultyInitial.toUpperCase() == 'TBA') {
      return;
    }
    final items = <FacultyScheduleItem>[];
    for (final s in _seatDetails.values) {
      final initial = s.faculties.trim();
      final hasFaculty =
          initial.toUpperCase() == facultyInitial.toUpperCase() ||
          (s.faculty != null &&
              s.faculty!.staffName.toUpperCase() ==
                  (staffName ?? '').toUpperCase());
      if (hasFaculty) {
        for (final sc in s.sectionSchedule.classSchedules) {
          items.add(
            FacultyScheduleItem(
              courseCode: s.courseCode,
              sectionName: s.sectionName,
              day: sc.day,
              startTime: sc.startTime,
              endTime: sc.endTime,
              roomNumber: s.roomNumber,
              consumedSeat: s.consumedSeat,
              courseType: s.courseType,
            ),
          );
        }
        for (final sc in s.labSchedules) {
          items.add(
            FacultyScheduleItem(
              courseCode: s.courseCode,
              sectionName: s.sectionName,
              day: sc.day,
              startTime: sc.startTime,
              endTime: sc.endTime,
              roomNumber: s.labRoomName?.isNotEmpty == true
                  ? s.labRoomName!
                  : s.roomNumber,
              consumedSeat: s.consumedSeat,
              courseType: 'Lab',
            ),
          );
        }
      }
    }
    showBracuFacultyScheduleSheet(
      context,
      facultyInitial: facultyInitial,
      staffName: staffName,
      items: items,
    );
  }

  Future<void> _confirmAdvising() async {
    if (_portfolioId == null || _sessionId == null || _publicKey == null) {
      return;
    }
    await showBracuConfirmationWithActionDialog(
      context,
      icon: Icons.check_circle_outline_rounded,
      title: 'Confirm Advising?',
      message:
          'This will finalize your advising selection for ${_phase.label}.',
      confirmLabel: 'Confirm',
      cancelLabel: 'Cancel',
      confirmColor: BracuPalette.primary,
      onConfirm: () async {
        if (!mounted) return;
        setState(() => _isLoading = true);
        try {
          await _service.confirmAdvising(
            portfolioId: _portfolioId!,
            sessionId: _sessionId!,
            publicKey: _publicKey!,
            phase: _phase,
          );
          _engine.addLog('Advising confirmed');
          if (mounted) showAppSnackBar(context, 'Advising confirmed!');
          await _refreshEnrolled();
        } catch (e) {
          if (mounted) showAppSnackBar(context, e.toString());
        } finally {
          if (mounted) setState(() => _isLoading = false);
        }
      },
    );
  }

  void _toggleQueue(SeatStatusDetailsResponse s) {
    final alreadyQueued = _engine.targetSections.any(
      (e) => e.sectionId == s.sectionId,
    );
    if (alreadyQueued) {
      _engine.removeSectionFromQueue(s.sectionId);
    } else {
      _engine.addSectionToQueue(
        TargetSectionItem(
          sectionId: s.sectionId,
          courseId: s.courseId,
          courseCode: s.courseCode,
          courseName: s.courseName,
          sectionName: s.sectionName,
          capacity: s.capacity,
          consumedSeat: s.consumedSeat,
          courseCredit: s.courseCredit,
          labSectionId: s.labSectionId,
          labSectionName: s.labName,
        ),
      );
    }
    if (mounted) setState(() {});
  }

  void _toggleEngine() {
    if (_engine.isRunning) {
      _engine.stop();
    } else {
      if (_portfolioId == null || _publicKey == null) {
        return;
      }
      _engine.start(
        portfolioId: _portfolioId!,
        publicKey: _publicKey!,
        phase: _phase,
        onSectionAdded: _refreshEnrolled,
      );
    }
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final textPrimary = BracuPalette.textPrimary(context);
    final textSecondary = BracuPalette.textSecondary(context);

    if (_isLoading) {
      return const BracuPageScaffold(
        title: 'Advising',
        subtitle: 'Helper',
        icon: Icons.bolt_rounded,
        body: Center(child: BracuLoading()),
      );
    }

    if (_errorMessage != null) {
      return BracuPageScaffold(
        title: 'Advising',
        subtitle: 'Helper',
        icon: Icons.bolt_rounded,
        body: BracuErrorState(
          title: 'Load Error',
          message: _errorMessage!,
          onRetry: _load,
        ),
      );
    }

    final queue = _engine.targetSections;

    return BracuPageScaffold(
      title: 'Advising',
      subtitle: 'Helper',
      icon: Icons.bolt_rounded,
      actions: [
        IconButton(
          tooltip: 'Open in Browser',
          icon: const Icon(Icons.open_in_new_rounded),
          onPressed: () => openExternalUrl(
            context,
            'https://connect.bracu.ac.bd/student/advising/${_phase.pathSegment}',
          ),
        ),
        if (_enrolled.isNotEmpty)
          IconButton(
            tooltip: 'Confirm Advising',
            icon: const Icon(Icons.check_circle_outline_rounded),
            onPressed: _confirmAdvising,
          ),
        BracuRefreshButton(onPressed: _load, isLoading: _isLoading),
      ],
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final phase in AdvisingPhase.values)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        label: Text(phase.label),
                        selected: _phase == phase,
                        onSelected: (selected) {
                          if (selected && _phase != phase) {
                            _engine.reset();
                            setState(() {
                              _phase = phase;
                              _enrolled = const [];
                              _portfolioId = null;
                              _sessionId = null;
                              _publicKey = null;
                              _errorMessage = null;
                              _enrolledError = null;
                            });
                            unawaited(_load());
                          }
                        },
                        selectedColor: BracuPalette.primary.withValues(
                          alpha: 0.15,
                        ),
                        labelStyle: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: _phase == phase
                              ? BracuPalette.primary
                              : textSecondary,
                        ),
                      ),
                    ),
                  if (_enrolled.isNotEmpty)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: BracuPalette.accent.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        '${_enrolled.fold<int>(0, (sum, e) => sum + e.courseCredit)} Cr Enrolled',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: BracuPalette.accent,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          if (queue.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: BracuCard(
                backgroundColor: BracuPalette.info.withValues(alpha: 0.12),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${queue.length} section(s) queued for auto-add.',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: textPrimary,
                        ),
                      ),
                    ),
                    BracuActionButton(
                      onPressed: _toggleEngine,
                      label: _engine.isRunning ? 'Stop' : 'Start',
                      outlined: false,
                      borderRadius: 10,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 10,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          Expanded(
            child: DefaultTabController(
              length: 2,
              child: Column(
                children: [
                  TabBar(
                    labelColor: BracuPalette.primary,
                    unselectedLabelColor: textSecondary,
                    indicatorColor: BracuPalette.primary,
                    tabs: [
                      Tab(
                        text: _enrolledError == null
                            ? 'Enrolled & Queue (${_enrolled.length + queue.length})'
                            : 'Enrolled & Queue (?)',
                      ),
                      const Tab(text: 'Sections'),
                    ],
                  ),
                  Expanded(
                    child: TabBarView(
                      children: [
                        _buildEnrolledAndQueueTab(textPrimary, textSecondary),
                        _buildSectionsTab(textPrimary, textSecondary),
                      ],
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

  Widget _buildEnrolledAndQueueTab(Color textPrimary, Color textSecondary) {
    return BracuRefreshList(
      onRefresh: () async {
        await _refreshEnrolled();
        await _refreshSeats();
      },
      children: [
        _buildQueueTab(textPrimary, textSecondary, embedded: true),
        if (_engine.targetSections.isNotEmpty ||
            _engine.activityLogs.isNotEmpty)
          const Divider(height: 28),
        _buildEnrolledTab(textPrimary, textSecondary, embedded: true),
      ],
    );
  }

  Widget _buildEnrolledTab(
    Color textPrimary,
    Color textSecondary, {
    bool embedded = false,
  }) {
    if (_enrolled.isEmpty) {
      final empty = BracuEmptyCard(
        message: _enrolledError == null
            ? 'No sections enrolled in this phase yet.'
            : 'Unable to load enrolled sections. Pull to retry.',
      );
      if (embedded) return empty;
      return BracuRefreshList(onRefresh: _refreshEnrolled, children: [empty]);
    }

    return ListView.builder(
      shrinkWrap: embedded,
      physics: embedded ? const NeverScrollableScrollPhysics() : null,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      itemCount: _enrolled.length + 1,
      itemBuilder: (context, index) {
        if (index == _enrolled.length) {
          return Padding(
            padding: const EdgeInsets.only(top: 4, bottom: 16),
            child: BracuActionButton(
              onPressed: _confirmAdvising,
              label: 'Confirm Advising',
              outlined: false,
              borderRadius: 12,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            ),
          );
        }
        final sec = _enrolled[index];
        final detail = _seatDetails[sec.sectionId];

        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: _AdvisingSeatStatusCard(
            courseCode: sec.courseCode,
            sectionName: sec.sectionName,
            courseName: detail?.courseName ?? '',
            courseType: detail?.courseType ?? '',
            faculty: detail?.faculty,
            facultyInitial: sec.faculty ?? detail?.faculties ?? '',
            credits: sec.courseCredit,
            classSchedule: detail?.sectionSchedule.classSchedules ?? const [],
            labSchedule: detail?.labSchedules ?? const [],
            room: sec.roomNumber ?? detail?.roomNumber ?? '',
            labRoom: detail?.labRoomName ?? '',
            midExamDate: detail?.sectionSchedule.midExamDate,
            midExamStartTime: detail?.sectionSchedule.midExamStartTime,
            midExamEndTime: detail?.sectionSchedule.midExamEndTime,
            finalExamDate: detail?.sectionSchedule.finalExamDate,
            finalExamStartTime: detail?.sectionSchedule.finalExamStartTime,
            finalExamEndTime: detail?.sectionSchedule.finalExamEndTime,
            remaining: detail != null
                ? detail.capacity - detail.consumedSeat
                : -1,
            consumed: detail?.consumedSeat ?? -1,
            total: detail?.capacity ?? -1,
            onTap: () => _showFacultyScheduleSheet(
              sec.faculty ?? detail?.faculties ?? '',
              detail?.faculty?.staffName,
            ),
            action: IconButton(
              icon: const Icon(
                Icons.remove_circle_outline_rounded,
                color: BracuPalette.danger,
                size: 26,
              ),
              onPressed: () => _confirmDrop(sec),
            ),
          ),
        );
      },
    );
  }

  Widget _buildQueueTab(
    Color textPrimary,
    Color textSecondary, {
    bool embedded = false,
  }) {
    final queue = _engine.targetSections;
    final logs = _engine.activityLogs;

    if (queue.isEmpty && logs.isEmpty) {
      const empty = BracuEmptyCard(
        message:
            'No sections queued. Add sections from the Sections tab to auto-add.',
      );
      if (embedded) return empty;
      return BracuRefreshList(
        onRefresh: _refreshSeats,
        children: const [empty],
      );
    }

    return ListView.builder(
      shrinkWrap: embedded,
      physics: embedded ? const NeverScrollableScrollPhysics() : null,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      itemCount: queue.length + (logs.isNotEmpty ? 1 : 0),
      itemBuilder: (context, index) {
        if (logs.isNotEmpty && index == 0) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Activity Log',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: textSecondary,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: _engine.clearActivityLogs,
                    child: const Text('Clear'),
                  ),
                ],
              ),
              const Gap(6),
              BracuCard(
                backgroundColor: BracuPalette.card(context),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final log in logs.take(20))
                      Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Text(
                          log,
                          style: TextStyle(fontSize: 12, color: textSecondary),
                        ),
                      ),
                  ],
                ),
              ),
              const Gap(12),
            ],
          );
        }

        final queueIndex = logs.isNotEmpty ? index - 1 : index;
        final item = queue[queueIndex];
        final isAdded = item.status == TargetSectionStatus.added;
        final isAdding = item.status == TargetSectionStatus.adding;
        final detail = _seatDetails[item.sectionId];

        final remaining = detail != null
            ? detail.capacity - detail.consumedSeat
            : item.remainingSeats;
        final consumed = detail?.consumedSeat ?? item.consumedSeat;
        final total = detail?.capacity ?? item.capacity;

        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: _AdvisingSeatStatusCard(
            courseCode: item.courseCode,
            sectionName: item.sectionName,
            courseName: item.courseName ?? '',
            courseType: detail?.courseType ?? '',
            faculty: detail?.faculty,
            facultyInitial: detail?.faculties ?? '',
            credits: item.courseCredit,
            classSchedule: detail?.sectionSchedule.classSchedules ?? const [],
            labSchedule: detail?.labSchedules ?? const [],
            room: detail?.roomNumber ?? '',
            labRoom: detail?.labRoomName ?? '',
            midExamDate: detail?.sectionSchedule.midExamDate,
            midExamStartTime: detail?.sectionSchedule.midExamStartTime,
            midExamEndTime: detail?.sectionSchedule.midExamEndTime,
            finalExamDate: detail?.sectionSchedule.finalExamDate,
            finalExamStartTime: detail?.sectionSchedule.finalExamStartTime,
            finalExamEndTime: detail?.sectionSchedule.finalExamEndTime,
            remaining: remaining,
            consumed: consumed,
            total: total,
            onTap: () => _showFacultyScheduleSheet(
              detail?.faculties ?? '',
              detail?.faculty?.staffName,
            ),
            action: isAdding
                ? const Padding(
                    padding: EdgeInsets.all(8),
                    child: SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                : isAdded
                ? const Padding(
                    padding: EdgeInsets.all(8),
                    child: Icon(
                      Icons.check_circle_rounded,
                      color: BracuPalette.accent,
                      size: 26,
                    ),
                  )
                : IconButton(
                    icon: const Icon(
                      Icons.remove_circle_outline_rounded,
                      color: BracuPalette.danger,
                      size: 26,
                    ),
                    onPressed: () =>
                        _engine.removeSectionFromQueue(item.sectionId),
                  ),
          ),
        );
      },
    );
  }

  Widget _buildSectionsTab(Color textPrimary, Color textSecondary) {
    final filtered = _filteredSections;
    final times = sortedSeatFilterTimes(
      _seatDetails.values
          .expand(
            (section) => <SeatStatusClassSchedule>[
              ...section.sectionSchedule.classSchedules,
              ...section.labSchedules,
            ],
          )
          .map((schedule) => schedule.toTimetable()),
    );

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          child: BracuSearchField(
            controller: _searchController,
            hintText: 'Search course code, section or faculty...',
            query: _searchQuery,
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
          child: SeatFilterBar(
            availableOnly: _availableOnly,
            mode: _selectedModeFilter,
            day: _selectedDayFilter,
            time: _selectedTimeFilter,
            times: times,
            onAvailableChanged: (value) =>
                setState(() => _availableOnly = value),
            onModeChanged: (value) =>
                setState(() => _selectedModeFilter = value),
            onDayChanged: (value) => setState(() => _selectedDayFilter = value),
            onTimeChanged: (value) =>
                setState(() => _selectedTimeFilter = value),
          ),
        ),
        Expanded(
          child: filtered.isEmpty
              ? BracuRefreshList(
                  onRefresh: _refreshSeats,
                  children: [
                    BracuEmptyCard(
                      message: _searchQuery.isEmpty
                          ? 'No realtime sections available.'
                          : 'No sections match your search.',
                    ),
                  ],
                )
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  itemCount: filtered.length,
                  itemBuilder: (context, index) {
                    final s = filtered[index];
                    final isQueued = _engine.targetSections.any(
                      (e) => e.sectionId == s.sectionId,
                    );
                    final isEnrolled = _enrolled.any(
                      (e) => e.sectionId == s.sectionId,
                    );
                    final remaining = s.capacity - s.consumedSeat;

                    return Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: _AdvisingSeatStatusCard(
                        courseCode: s.courseCode,
                        sectionName: s.sectionName,
                        courseName: s.courseName,
                        courseType: s.courseType,
                        faculty: s.faculty,
                        facultyInitial: s.faculties,
                        credits: s.courseCredit,
                        classSchedule: s.sectionSchedule.classSchedules,
                        labSchedule: s.labSchedules,
                        room: s.roomNumber,
                        labRoom: s.labRoomName ?? '',
                        midExamDate: s.sectionSchedule.midExamDate,
                        midExamStartTime: s.sectionSchedule.midExamStartTime,
                        midExamEndTime: s.sectionSchedule.midExamEndTime,
                        finalExamDate: s.sectionSchedule.finalExamDate,
                        finalExamStartTime:
                            s.sectionSchedule.finalExamStartTime,
                        finalExamEndTime: s.sectionSchedule.finalExamEndTime,
                        remaining: remaining,
                        consumed: s.consumedSeat,
                        total: s.capacity,
                        isPinned: isQueued,
                        onTap: () => _showFacultyScheduleSheet(
                          s.faculties,
                          s.faculty?.staffName,
                        ),
                        action: isEnrolled
                            ? const Padding(
                                padding: EdgeInsets.all(8),
                                child: Icon(
                                  Icons.check_circle_rounded,
                                  color: BracuPalette.accent,
                                  size: 28,
                                ),
                              )
                            : IconButton(
                                icon: Icon(
                                  isQueued
                                      ? Icons.check_box_rounded
                                      : Icons.check_box_outline_blank_rounded,
                                  color: isQueued
                                      ? BracuPalette.accent
                                      : textSecondary,
                                  size: 28,
                                ),
                                onPressed: () => _toggleQueue(s),
                              ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class _AdvisingSeatStatusCard extends StatelessWidget {
  const _AdvisingSeatStatusCard({
    required this.courseCode,
    required this.sectionName,
    required this.courseName,
    required this.facultyInitial,
    required this.credits,
    required this.classSchedule,
    required this.labSchedule,
    required this.room,
    required this.labRoom,
    required this.midExamDate,
    required this.midExamStartTime,
    required this.midExamEndTime,
    required this.finalExamDate,
    required this.finalExamStartTime,
    required this.finalExamEndTime,
    required this.remaining,
    required this.consumed,
    required this.total,
    required this.action,
    required this.courseType,
    this.faculty,
    this.isPinned = false,
    this.onTap,
  });

  final String courseCode;
  final String sectionName;
  final String courseName;
  final String courseType;
  final section.SectionFaculty? faculty;
  final String facultyInitial;
  final int credits;
  final List<SeatStatusClassSchedule> classSchedule;
  final List<SeatStatusClassSchedule> labSchedule;
  final String room;
  final String labRoom;
  final String? midExamDate;
  final String? midExamStartTime;
  final String? midExamEndTime;
  final String? finalExamDate;
  final String? finalExamStartTime;
  final String? finalExamEndTime;
  final int remaining;
  final int consumed;
  final int total;
  final Widget action;
  final bool isPinned;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final textPrimary = BracuPalette.textPrimary(context);
    final textSecondary = BracuPalette.textSecondary(context);
    final theoryLabel = _titleCaseText(courseType);
    final courseHeader = '$courseCode - $sectionName';
    final facultyName = faculty?.staffName.trim() ?? '';
    final facultyEmail = faculty?.email.trim() ?? '';
    final classLines = _scheduleLines(classSchedule);
    final labLines = _scheduleLines(labSchedule);
    final hasMidExam = _hasExam(midExamDate, midExamStartTime, midExamEndTime);
    final hasFinalExam = _hasExam(
      finalExamDate,
      finalExamStartTime,
      finalExamEndTime,
    );

    final card = BracuCard(
      isHighlighted: isPinned,
      highlightColor: BracuPalette.accent.withValues(alpha: 0.35),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      courseHeader,
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        color: textPrimary,
                      ),
                    ),
                    if (courseName.trim().isNotEmpty) ...[
                      const Gap(2),
                      Text(
                        courseName.trim(),
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                          color: textSecondary,
                        ),
                      ),
                    ],
                    if (facultyInitial.trim().isNotEmpty || credits > 0) ...[
                      const Gap(4),
                      RichText(
                        text: TextSpan(
                          style: TextStyle(fontSize: 13, color: textSecondary),
                          children: [
                            if (facultyInitial.trim().isNotEmpty)
                              TextSpan(
                                text: facultyInitial,
                                style: TextStyle(
                                  color: textPrimary,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            if (facultyInitial.trim().isNotEmpty && credits > 0)
                              TextSpan(
                                text: ' • ',
                                style: TextStyle(
                                  color: textSecondary,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            if (credits > 0)
                              TextSpan(
                                text: '$credits credits',
                                style: TextStyle(
                                  color: textSecondary,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                    if (seatStatusFacultyHasVisuals(faculty)) ...[
                      const Gap(8),
                      Row(
                        children: [
                          if (faculty?.imgUrl?.trim().isNotEmpty == true) ...[
                            FriendAvatar(
                              name: facultyName.isNotEmpty
                                  ? facultyName
                                  : courseHeader,
                              photoUrl: faculty!.imgUrl,
                              size: 40,
                              radius: 20,
                            ),
                            const Gap(12),
                          ],
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (facultyName.isNotEmpty)
                                  Text(
                                    facultyName,
                                    style: TextStyle(
                                      color: textPrimary,
                                      fontSize: 14,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                if (facultyEmail.isNotEmpty) ...[
                                  const Gap(2),
                                  InkWell(
                                    borderRadius: BorderRadius.circular(6),
                                    onTap: () =>
                                        openMailComposer(context, facultyEmail),
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 2,
                                      ),
                                      child: Text(
                                        facultyEmail,
                                        style: TextStyle(
                                          color: textSecondary,
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              action,
            ],
          ),
          if (classLines.isNotEmpty) ...[
            const Gap(12),
            _SeatScheduleBlock(title: 'Class', lines: classLines),
          ],
          if (labLines.isNotEmpty) ...[
            const Gap(12),
            _SeatScheduleBlock(title: 'Lab', lines: labLines),
          ],
          if (room.trim().isNotEmpty || labRoom.trim().isNotEmpty) ...[
            const Gap(12),
            _RoomBlock(
              theoryLabel: theoryLabel,
              theoryRoom: room,
              labRoom: labRoom,
            ),
          ],
          if (hasMidExam || hasFinalExam) ...[
            const Gap(12),
            Row(
              children: [
                Expanded(
                  child: _ExamBlock(
                    label: 'Mid',
                    date: midExamDate,
                    start: midExamStartTime,
                    end: midExamEndTime,
                    textPrimary: textPrimary,
                    textSecondary: textSecondary,
                  ),
                ),
                const Gap(16),
                Expanded(
                  child: _ExamBlock(
                    label: 'Final',
                    date: finalExamDate,
                    start: finalExamStartTime,
                    end: finalExamEndTime,
                    textPrimary: textPrimary,
                    textSecondary: textSecondary,
                  ),
                ),
              ],
            ),
          ],
          if (remaining >= 0 || consumed >= 0 || total >= 0) ...[
            const Gap(12),
            Divider(color: textSecondary.withValues(alpha: 0.2), height: 1),
            const Gap(12),
            Row(
              children: [
                Expanded(
                  child: _SeatMetric(
                    value: remaining,
                    label: 'Remaining',
                    color: remaining <= 0 ? BracuPalette.danger : textPrimary,
                  ),
                ),
                Expanded(
                  child: _SeatMetric(
                    value: consumed,
                    label: 'Booked',
                    color: textPrimary,
                  ),
                ),
                Expanded(
                  child: _SeatMetric(
                    value: total,
                    label: 'Total',
                    color: textPrimary,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );

    if (onTap == null) {
      return card;
    }
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: card,
      ),
    );
  }

  bool _hasExam(String? date, String? start, String? end) {
    return (date ?? '').trim().isNotEmpty ||
        (start ?? '').trim().isNotEmpty ||
        (end ?? '').trim().isNotEmpty;
  }

  String _titleCaseText(String input) {
    final trimmed = input.trim();
    if (trimmed.isEmpty) return '';
    return trimmed
        .split(RegExp(r'\s+'))
        .map(
          (word) => word.isEmpty
              ? ''
              : '${word[0].toUpperCase()}${word.substring(1).toLowerCase()}',
        )
        .join(' ');
  }

  List<String> _scheduleLines(List<SeatStatusClassSchedule> schedules) {
    if (schedules.isEmpty) return const <String>[];
    final lines = schedules.map((entry) {
      final day = formatWeekdayTitle(entry.day);
      final time = formatTimeRange(entry.startTime, entry.endTime);
      return '$day $time'.trim();
    }).toList();
    return lines.where((line) => line.trim().isNotEmpty).toList();
  }
}

class _RoomBlock extends StatelessWidget {
  const _RoomBlock({
    required this.theoryLabel,
    required this.theoryRoom,
    required this.labRoom,
  });

  final String theoryLabel;
  final String theoryRoom;
  final String labRoom;

  @override
  Widget build(BuildContext context) {
    final lines = <InlineSpan>[];
    if (theoryRoom.trim().isNotEmpty) {
      lines.add(
        TextSpan(
          text: '${theoryLabel.isEmpty ? 'Room' : theoryLabel}: ',
          style: TextStyle(
            color: BracuPalette.textSecondary(context),
            fontWeight: FontWeight.w500,
          ),
        ),
      );
      lines.add(
        TextSpan(
          text: theoryRoom.trim(),
          style: TextStyle(
            color: BracuPalette.textPrimary(context),
            fontWeight: FontWeight.w700,
          ),
        ),
      );
    }
    if (theoryRoom.trim().isNotEmpty && labRoom.trim().isNotEmpty) {
      lines.add(const TextSpan(text: '\n'));
    }
    if (labRoom.trim().isNotEmpty) {
      lines.add(
        TextSpan(
          text: 'Lab: ',
          style: TextStyle(
            color: BracuPalette.textSecondary(context),
            fontWeight: FontWeight.w500,
          ),
        ),
      );
      lines.add(
        TextSpan(
          text: labRoom.trim(),
          style: TextStyle(
            color: BracuPalette.textPrimary(context),
            fontWeight: FontWeight.w700,
          ),
        ),
      );
    }
    if (lines.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Room:',
          style: TextStyle(
            color: BracuPalette.textSecondary(context),
            fontSize: 12,
            fontWeight: FontWeight.w500,
          ),
        ),
        const Gap(3),
        RichText(
          text: TextSpan(
            style: TextStyle(
              fontSize: 14,
              height: 1.25,
              color: BracuPalette.textPrimary(context),
              fontWeight: FontWeight.w700,
            ),
            children: lines,
          ),
        ),
      ],
    );
  }
}

class _SeatScheduleBlock extends StatelessWidget {
  const _SeatScheduleBlock({required this.title, required this.lines});

  final String title;
  final List<String> lines;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '$title:',
          style: TextStyle(
            color: BracuPalette.textSecondary(context),
            fontSize: 12,
            fontWeight: FontWeight.w500,
          ),
        ),
        const Gap(3),
        for (final line in lines)
          Text(
            line,
            style: TextStyle(
              color: BracuPalette.textPrimary(context),
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
          ),
      ],
    );
  }
}

class _SeatMetric extends StatelessWidget {
  const _SeatMetric({
    required this.value,
    required this.label,
    required this.color,
  });

  final int value;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          '$value',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w700,
            color: color,
          ),
        ),
        const Gap(3),
        Text(
          label,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: BracuPalette.textSecondary(context),
            fontSize: 11.5,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

class _ExamBlock extends StatelessWidget {
  const _ExamBlock({
    required this.label,
    required this.date,
    required this.start,
    required this.end,
    required this.textPrimary,
    required this.textSecondary,
  });

  final String label;
  final String? date;
  final String? start;
  final String? end;
  final Color textPrimary;
  final Color textSecondary;

  @override
  Widget build(BuildContext context) {
    final dateLabel = formatDate(date);
    final timeLabel = formatTimeRange(start, end);
    final hasDate = dateLabel.isNotEmpty;
    final hasTime = timeLabel.isNotEmpty;
    if (!hasDate && !hasTime) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '$label:',
          style: TextStyle(
            color: textSecondary,
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
        const Gap(3),
        if (hasDate)
          Text(
            dateLabel,
            style: TextStyle(
              color: textPrimary,
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
            ),
          ),
        if (hasDate && hasTime) const Gap(1),
        if (hasTime)
          Text(
            timeLabel,
            style: TextStyle(color: textSecondary, fontSize: 11.5),
          ),
      ],
    );
  }
}
