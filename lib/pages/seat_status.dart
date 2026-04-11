import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:preconnect/api/seat_status_service.dart';
import 'package:preconnect/pages/home_tab.dart';
import 'package:preconnect/model/section_info.dart' as section;
import 'package:preconnect/model/seat_status_info.dart';
import 'package:preconnect/pages/notifications.dart';
import 'package:preconnect/pages/shared_widgets/course_community_sheet.dart';
import 'package:preconnect/pages/ui_kit.dart';
import 'package:preconnect/tools/push_notifications_service.dart';
import 'package:preconnect/tools/refresh_bus.dart';
import 'package:preconnect/tools/ramadan_timing.dart';
import 'package:preconnect/tools/time_utils.dart';
part 'shared_widgets/seat_status_methods_part.dart';

class SeatStatusPage extends StatefulWidget {
  const SeatStatusPage({super.key});
  @override
  State<SeatStatusPage> createState() => _SeatStatusPageState();
}

class _SeatStatusPageState extends State<SeatStatusPage>
    with WidgetsBindingObserver, RefreshBusState {
  static const List<String> _weekdayOrder = <String>[
    'SUNDAY',
    'MONDAY',
    'TUESDAY',
    'WEDNESDAY',
    'THURSDAY',
    'FRIDAY',
    'SATURDAY',
  ];

  final SeatStatusService _service = SeatStatusService();
  final SeatAlertSyncService _pushService = SeatAlertSyncService();
  final List<_SeatStatusCardData> _cards = <_SeatStatusCardData>[];
  final List<_SeatStatusCardData> _visibleCards = <_SeatStatusCardData>[];
  final Map<int, SeatStatusDetailsResponse> _detailsCache =
      <int, SeatStatusDetailsResponse>{};
  final Map<String, SeatStatusStaffInfo> _staffInfoByInitial =
      <String, SeatStatusStaffInfo>{};
  final Map<int, SeatAlertConfig> _seatAlerts = <int, SeatAlertConfig>{};
  final TextEditingController _searchController = TextEditingController();
  Timer? _searchDebounce;
  bool _isInitialLoading = true;
  String _searchQuery = '';
  bool _cacheLoaded = false;
  bool _isAppForeground = true;
  bool _isDetailsRefreshing = false;
  bool _isResolvingStaffInfo = false;
  bool _isStreamConnecting = false;
  bool _isSavingCache = false;
  bool _availableOnly = false;
  bool _alertsOnly = false;
  String _selectedDayFilter = '';
  final Set<String> _pendingInitials = <String>{};
  http.Client? _streamClient;
  StreamSubscription<String>? _streamSubscription;
  Timer? _streamReconnectTimer;
  Timer? _streamRefreshDebounce;
  @override
  void initState() {
    super.initState();
    _searchController.addListener(() {
      _searchDebounce?.cancel();
      _searchDebounce = Timer(const Duration(milliseconds: 150), () {
        if (!mounted) return;
        final next = _searchController.text.trim().toLowerCase();
        _updateSearchQuery(next);
      });
    });
    unawaited(_reloadAll());
    unawaited(_loadSeatAlerts());
    _isSavingCache = _service.isSavingDetailsCache.value;
    _service.isSavingDetailsCache.addListener(_onCacheSaveStateChanged);
    WidgetsBinding.instance.addObserver(this);
    HomeTabRegistry.activeTab.addListener(_onActiveTabChanged);
    _updatePollingStrategy();
    bindRefreshBus(_onRefreshSignal);
  }
  @override
  void dispose() {
    _stopSeatStatusStream();
    _service.isSavingDetailsCache.removeListener(_onCacheSaveStateChanged);
    WidgetsBinding.instance.removeObserver(this);
    HomeTabRegistry.activeTab.removeListener(_onActiveTabChanged);
    _searchDebounce?.cancel();
    _searchController.dispose();
    unbindRefreshBus(_onRefreshSignal);
    super.dispose();
  }
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _isAppForeground = true;
      _updatePollingStrategy();
      return;
    }
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      _isAppForeground = false;
      _updatePollingStrategy();
    }
  }
  void _onActiveTabChanged() {
    if (!mounted) return;
    _updatePollingStrategy();
  }

  void _onRefreshSignal() {
    if (!mounted) return;
    if (isRefreshingFrom('seat_status')) {
      return;
    }
    unawaited(_handleRefresh(notify: false));
  }
  void _onCacheSaveStateChanged() {
    if (!mounted) return;
    final next = _service.isSavingDetailsCache.value;
    if (next == _isSavingCache) return;
    setState(() {
      _isSavingCache = next;
    });
  }
  Future<void> _handleRefresh({bool notify = true}) async {
    if (!await ensureOnline(context, notify: notify)) {
      return;
    }
    await _refreshDetailsFromApi();
    if (notify) {
      RefreshBus.instance.notify(reason: 'seat_status');
    }
  }
  Future<void> _reloadAll() async {
    if (mounted) {
      setState(() {
        _isInitialLoading = true;
      });
    }
    if (!_cacheLoaded) {
      final cached = await _service.loadCachedDetails(
        maxAge: const Duration(hours: 1),
      );
      if (cached.isNotEmpty) {
        _detailsCache
          ..clear()
          ..addAll(cached);
        final cachedCards = _buildCardsFromDetailsMap(cached);
        _sortCardsByCourseAndSection(cachedCards);
        _applyCardsSnapshot(cachedCards, isInitialLoading: false);
        unawaited(_loadCachedStaffInfoForDetails(cached.values));
        _queueStaffInfoResolve(cached.values);
      }
      _cacheLoaded = true;
    }

    await _refreshDetailsFromApi();
    if (!mounted) return;
    if (_isInitialLoading) {
      setState(() {
        _isInitialLoading = false;
      });
    }
  }
  Future<void> _loadSeatAlerts() async {
    final loaded = await _service.loadSeatAlertConfigs();
    try {
      await _pushService.syncAllSeatAlertConfigs(loaded);
    } catch (_) {}
    if (!mounted) return;
    _seatAlerts
      ..clear()
      ..addAll(loaded);
    _refreshVisibleCards();
  }
  List<_SeatStatusCardData> _buildCardsFromDetailsMap(
    Map<int, SeatStatusDetailsResponse> detailsMap,
  ) {
    final sectionIds = _visibleSectionIdsFromDetails(detailsMap).toList()
      ..sort((a, b) => _compareSectionIdsByNaming(a, b));
    return sectionIds.map((sectionId) {
      final cached = detailsMap[sectionId];
      if (cached == null) {
        return _buildFallbackCard(sectionId: sectionId, remaining: 0);
      }
      return _buildCardFromDetails(sectionId: sectionId, details: cached);
    }).toList();
  }
  Future<void> _applyDetailsUpdate(
    Map<int, SeatStatusDetailsResponse> detailsMap,
  ) async {
    if (!mounted || detailsMap.isEmpty) return;
    final previousCards = List<_SeatStatusCardData>.from(_cards);
    _detailsCache
      ..clear()
      ..addAll(detailsMap);
    final updated = _buildCardsFromDetailsMap(detailsMap);
    _sortCardsByCourseAndSection(updated);
    if (_areCardListsDifferent(_cards, updated)) {
      _applyCardsSnapshot(updated, isInitialLoading: false);
    } else if (_isInitialLoading) {
      setState(() {
        _isInitialLoading = false;
      });
    }
    await _processSeatAlerts(previousCards, updated);
    unawaited(_loadCachedStaffInfoForDetails(detailsMap.values));
    _queueStaffInfoResolve(detailsMap.values);
  }
  Future<void> _processSeatAlerts(
    List<_SeatStatusCardData> previous,
    List<_SeatStatusCardData> next,
  ) async {
    if (_seatAlerts.isEmpty) return;
    final previousById = {for (final item in previous) item.sectionId: item};
    final nextById = {for (final item in next) item.sectionId: item};
    final triggeredMessages = <String>[];
    var changedConfig = false;
    final now = DateTime.now();

    for (final entry in _seatAlerts.entries.toList()) {
      final sectionId = entry.key;
      var config = entry.value;
      final oldItem = previousById[sectionId];
      final newItem = nextById[sectionId];
      if (newItem == null) continue;
      final oldRemaining = oldItem?.remaining;
      final newRemaining = newItem.remaining;

      if (config.notifyOnAvailable &&
          (oldRemaining == null || oldRemaining <= 0) &&
          newRemaining > 0) {
        triggeredMessages.add(
          '${newItem.courseCode}-${newItem.sectionName} now has $newRemaining seat${newRemaining == 1 ? '' : 's'} available',
        );
        if (config.availableOneTime) {
          config = config.copyWith(notifyOnAvailable: false);
          changedConfig = true;
        }
      }

      final threshold = config.thresholdSeats;
      if (threshold != null &&
          (oldRemaining == null || oldRemaining < threshold) &&
          newRemaining >= threshold) {
        triggeredMessages.add(
          '${newItem.courseCode}-${newItem.sectionName} reached $newRemaining available seat${newRemaining == 1 ? '' : 's'}',
        );
        if (config.thresholdOneTime) {
          config = config.copyWith(thresholdSeats: null);
          changedConfig = true;
        }
      }

      if (config.notifyOnAnyChange &&
          oldRemaining != null &&
          oldRemaining != newRemaining) {
        final diff = newRemaining - oldRemaining;
        final direction = diff > 0 ? 'up' : 'down';
        triggeredMessages.add(
          '${newItem.courseCode}-${newItem.sectionName} changed $direction to $newRemaining seats',
        );
        config = config.copyWith(
          lastChangeNotifiedAtMs: now.millisecondsSinceEpoch,
        );
        changedConfig = true;
      }

      if (!config.hasAnyRule) {
        _seatAlerts.remove(sectionId);
        await _service.removeSeatAlertConfig(sectionId);
        try {
          await _pushService.removeSeatAlertConfig(sectionId);
        } catch (_) {}
        changedConfig = true;
        continue;
      }
      if (config != entry.value) {
        _seatAlerts[sectionId] = config;
        await _service.saveSeatAlertConfig(config);
        try {
          await _pushService.syncSeatAlertConfig(config);
        } catch (_) {}
      }
    }

    if (changedConfig && mounted) {
      _refreshVisibleCards();
    }
    if (triggeredMessages.isEmpty || !mounted) return;
    final first = triggeredMessages.first;
    final suffix = triggeredMessages.length > 1
        ? ' • +${triggeredMessages.length - 1} more'
        : '';
    showAppSnackBar(context, '$first$suffix');
  }

  Future<void> _openSeatAlertSheet(_SeatStatusCardData item) async {
    final existing =
        _seatAlerts[item.sectionId] ??
        SeatAlertConfig(sectionId: item.sectionId);
    var temp = existing;
    const thresholdOptions = <int>[1, 2, 3, 5, 10];
    final updated = await showBracuBottomSheet<SeatAlertConfig?>(
      context,
      title: '${item.courseCode} - ${item.sectionName}',
      subtitle:
          '${item.remaining} seat${item.remaining == 1 ? '' : 's'} remaining',
      builder: (sheetContext, textPrimary, textSecondary) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return ListView(
              shrinkWrap: true,
              children: [
                _buildSeatAlertRuleCard(
                  context,
                  label: 'When seats become available',
                  subtitle: 'Alert when a seat becomes available',
                  value: temp.notifyOnAvailable,
                  onChanged: (value) {
                    setSheetState(() {
                      temp = temp.copyWith(notifyOnAvailable: value);
                    });
                  },
                ),
                const SizedBox(height: 10),
                _buildSeatAlertRuleCard(
                  context,
                  label: 'When seats reach your limit',
                  subtitle: 'Alert when seats reach your selected',
                  value: temp.thresholdSeats != null,
                  onChanged: (value) {
                    setSheetState(() {
                      temp = temp.copyWith(
                        thresholdSeats: value
                            ? (temp.thresholdSeats ?? 1)
                            : null,
                      );
                    });
                  },
                ),
                if (temp.thresholdSeats != null) ...[
                  const SizedBox(height: 10),
                  Wrap(
                    alignment: WrapAlignment.center,
                    spacing: 8,
                    runSpacing: 8,
                    children: thresholdOptions.map((threshold) {
                      final selected = temp.thresholdSeats == threshold;
                      return ChoiceChip(
                        label: Text('$threshold+'),
                        selected: selected,
                        onSelected: (_) {
                          setSheetState(() {
                            temp = temp.copyWith(thresholdSeats: threshold);
                          });
                        },
                      );
                    }).toList(),
                  ),
                ],
                const SizedBox(height: 10),
                _buildSeatAlertRuleCard(
                  context,
                  label: 'When seat count changes',
                  subtitle: 'Alert when the seat count changes',
                  value: temp.notifyOnAnyChange,
                  onChanged: (value) {
                    setSheetState(() {
                      temp = temp.copyWith(
                        notifyOnAnyChange: value,
                        changeCooldownMinutes: value
                            ? 0
                            : temp.changeCooldownMinutes,
                      );
                    });
                  },
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.of(sheetContext).pop(),
                        child: const Text('Cancel'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: FilledButton(
                        onPressed: () => Navigator.of(sheetContext).pop(temp),
                        child: const Text('Save'),
                      ),
                    ),
                  ],
                ),
              ],
            );
          },
        );
      },
    );
    if (!mounted || updated == null) return;
    final normalizedUpdated = updated.notifyOnAnyChange
        ? updated.copyWith(changeCooldownMinutes: 0)
        : updated;
    if (!normalizedUpdated.hasAnyRule) {
      await _service.removeSeatAlertConfig(item.sectionId);
      try {
        await _pushService.removeSeatAlertConfig(item.sectionId);
      } catch (_) {}
      if (!mounted) return;
      _seatAlerts.remove(item.sectionId);
      _refreshVisibleCards();
      showAppSnackBar(context, 'Seat alert removed');
      return;
    }
    await PushNotificationsService().ensureNotificationPermission();
    await _service.saveSeatAlertConfig(normalizedUpdated);
    try {
      await _pushService.syncSeatAlertConfig(normalizedUpdated);
    } catch (_) {}
    if (!mounted) return;
    _seatAlerts[item.sectionId] = normalizedUpdated;
    _refreshVisibleCards();
    showAppSnackBar(context, 'Seat alert saved');
  }

  Future<void> _handleSeatAlertTap(_SeatStatusCardData item) async {
    await _openSeatAlertSheet(item);
  }

  Future<void> _openCourseCommunitySheet(_SeatStatusCardData item) async {
    final primarySchedule = item.classSchedule.isNotEmpty
        ? item.classSchedule.first
        : (item.labSchedule.isNotEmpty ? item.labSchedule.first : null);
    if (primarySchedule == null) {
      showAppSnackBar(context, 'Not available');
      return;
    }
    final schedule = section.ClassSchedule(
      startTime: primarySchedule.startTime,
      endTime: primarySchedule.endTime,
      day: primarySchedule.day,
    );
    final isRamadan = await RamadanTiming.isRamadan();
    if (!mounted) return;
    await showBracuBottomSheet<void>(
      context,
      title: item.courseCode,
      initialChildSize: 0.88,
      builder: (sheetContext, textPrimary, textSecondary) {
        return CourseCommunitySheet.forClass(
          courseCode: item.courseCode,
          sectionName: item.sectionName,
          semesterLabel: 'Current',
          roomNumber: item.room.isNotEmpty ? item.room : item.labRoom,
          faculties: item.facultyInitial,
          consumedSeat: item.consumed,
          courseType: null,
          classSchedule: schedule,
          isRamadan: isRamadan,
          showActions: false,
        );
      },
    );
  }

  void _showSeatAlertPermissionSnackBar() {
    showAppSnackBar(
      context,
      'Seat alerts sync through the VPS backend.',
      actionLabel: 'Refresh',
      onAction: () {
        unawaited(PushNotificationsService().pollPendingAlerts());
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return _buildPageContent(context);
  }
}
class _SeatStatusCard extends StatelessWidget {
  const _SeatStatusCard({
    required this.item,
    required this.hasAlert,
    required this.onAlertTap,
    this.onTap,
  });

  final _SeatStatusCardData item;
  final bool hasAlert;
  final VoidCallback onAlertTap;
  final VoidCallback? onTap;

  Future<void> _openFacultyEmail(BuildContext context) async {
    await openMailComposer(context, item.facultyEmail);
  }

  @override
  Widget build(BuildContext context) {
    final textPrimary = BracuPalette.textPrimary(context);
    final textSecondary = BracuPalette.textSecondary(context);

    final card = BracuCard(
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
                      '${item.courseCode} - ${item.sectionName}',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        color: textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      item.courseName,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                        color: textSecondary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    RichText(
                      text: TextSpan(
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: textSecondary,
                        ),
                        children: [
                          TextSpan(text: item.facultyInitial),
                          const TextSpan(text: '  •  '),
                          TextSpan(text: '${item.credits} credits'),
                        ],
                      ),
                    ),
                    if (item.facultyName.isNotEmpty ||
                        item.facultyEmail.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (item.facultyName.isNotEmpty)
                              Text(
                                item.facultyName,
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: textSecondary,
                                ),
                              ),
                            if (item.facultyEmail.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(top: 1),
                                child: GestureDetector(
                                  onTap: () => _openFacultyEmail(context),
                                  child: Text(
                                    item.facultyEmail,
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w500,
                                      color: textSecondary,
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Row(
                children: [
                  Material(
                    color: Colors.transparent,
                    child: InkWell(
                      customBorder: const CircleBorder(),
                      onTap: onAlertTap,
                      child: Container(
                        width: 38,
                        height: 38,
                        alignment: Alignment.center,
                        child: Icon(
                          hasAlert
                              ? Icons.notifications_active_rounded
                              : Icons.notifications_outlined,
                          color: hasAlert
                              ? BracuPalette.primary
                              : BracuPalette.textPrimary(context),
                          size: 20,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 14),
          _SeatScheduleBlock(
            title: 'Class',
            lines: _scheduleLines(item.classSchedule),
          ),
          const SizedBox(height: 10),
          RichText(
            text: TextSpan(
              style: TextStyle(color: textSecondary, fontSize: 11),
              children: [
                const TextSpan(text: 'Room: '),
                TextSpan(
                  text: item.room.isEmpty ? '--' : item.room,
                  style: TextStyle(
                    color: textSecondary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          _SeatScheduleBlock(
            title: 'Lab',
            lines: _scheduleLines(
              item.labSchedule,
              fallback: const <String>['-'],
            ),
          ),
          const SizedBox(height: 10),
          RichText(
            text: TextSpan(
              style: TextStyle(color: textSecondary, fontSize: 11),
              children: [
                const TextSpan(text: 'Room: '),
                TextSpan(
                  text: item.labRoom.isEmpty ? '--' : item.labRoom,
                  style: TextStyle(
                    color: textSecondary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _ExamInfo(
                  label: 'Mid',
                  date: item.midExamDate,
                  start: item.midExamStartTime,
                  end: item.midExamEndTime,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _ExamInfo(
                  label: 'Final',
                  date: item.finalExamDate,
                  start: item.finalExamStartTime,
                  end: item.finalExamEndTime,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Divider(color: textSecondary.withValues(alpha: 0.2), height: 1),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _SeatMetric(
                  value: item.remaining,
                  label: 'Remaining',
                  color: item.remaining <= 0
                      ? BracuPalette.danger
                      : textPrimary,
                ),
              ),
              Expanded(
                child: _SeatMetric(
                  value: item.consumed,
                  label: 'Consumed',
                  color: textPrimary,
                ),
              ),
              Expanded(
                child: _SeatMetric(
                  value: item.total,
                  label: 'Total Seats',
                  color: textPrimary,
                ),
              ),
            ],
          ),
        ],
      ),
    );
    if (onTap == null) return card;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: card,
      ),
    );
  }

  List<String> _scheduleLines(
    List<SeatStatusClassSchedule> schedules, {
    List<String> fallback = const <String>['-'],
  }) {
    if (schedules.isEmpty) return fallback;
    final lines = schedules.map((entry) {
      final day = formatWeekdayTitle(entry.day);
      final time = formatTimeRange(entry.startTime, entry.endTime);
      return '$day $time';
    }).toList();
    return lines;
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.icon,
    required this.label,
    this.selected = false,
    this.onTap,
    this.showArrow = true,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback? onTap;
  final bool showArrow;

  @override
  Widget build(BuildContext context) {
    return BracuSelectChip(
      icon: icon,
      label: label,
      selected: selected,
      onTap: onTap,
      showArrow: showArrow,
      compact: true,
      borderRadius: 16,
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
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 3),
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

class _ExamInfo extends StatelessWidget {
  const _ExamInfo({
    required this.label,
    required this.date,
    required this.start,
    required this.end,
  });

  final String label;
  final String? date;
  final String? start;
  final String? end;

  @override
  Widget build(BuildContext context) {
    final dateValue = _formatExamDate(date);
    final timeValue = _formatExamTime(start, end);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '$label:',
          style: TextStyle(
            color: BracuPalette.textSecondary(context),
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          dateValue,
          style: TextStyle(
            color: BracuPalette.textPrimary(context),
            fontSize: 12.5,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 1),
        Text(
          timeValue,
          style: TextStyle(
            color: BracuPalette.textSecondary(context),
            fontSize: 11.5,
          ),
        ),
      ],
    );
  }

  String _formatExamDate(String? raw) {
    if (raw == null || raw.trim().isEmpty) return '--';
    final parsed = BracuTime.parseDate(raw);
    if (parsed == null) return raw;
    return DateFormat('MMM d, y').format(parsed);
  }

  String _formatExamTime(String? start, String? end) {
    final range = formatTimeRange(start, end);
    if (range.isEmpty) return '--';
    return range;
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
        const SizedBox(height: 3),
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

class _SeatStatusCardData {
  const _SeatStatusCardData({
    required this.sectionId,
    required this.courseCode,
    required this.sectionName,
    required this.courseName,
    required this.facultyInitial,
    required this.facultyName,
    required this.facultyEmail,
    required this.facultyMeta,
    required this.credits,
    required this.room,
    required this.classSchedule,
    required this.labSchedule,
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
    required this.searchToken,
  });

  final int sectionId;
  final String courseCode;
  final String sectionName;
  final String courseName;
  final String facultyInitial;
  final String facultyName;
  final String facultyEmail;
  final String facultyMeta;
  final int credits;
  final String room;
  final List<SeatStatusClassSchedule> classSchedule;
  final List<SeatStatusClassSchedule> labSchedule;
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
  final String searchToken;

  _SeatStatusCardData copyWith({int? remaining, int? consumed, int? total}) {
    return _SeatStatusCardData(
      sectionId: sectionId,
      courseCode: courseCode,
      sectionName: sectionName,
      courseName: courseName,
      facultyInitial: facultyInitial,
      facultyName: facultyName,
      facultyEmail: facultyEmail,
      facultyMeta: facultyMeta,
      credits: credits,
      room: room,
      classSchedule: classSchedule,
      labSchedule: labSchedule,
      labRoom: labRoom,
      midExamDate: midExamDate,
      midExamStartTime: midExamStartTime,
      midExamEndTime: midExamEndTime,
      finalExamDate: finalExamDate,
      finalExamStartTime: finalExamStartTime,
      finalExamEndTime: finalExamEndTime,
      remaining: remaining ?? this.remaining,
      consumed: consumed ?? this.consumed,
      total: total ?? this.total,
      searchToken: searchToken,
    );
  }
}

int _sectionOrder(String sectionName) {
  final number = RegExp(r'\d+').firstMatch(sectionName)?.group(0);
  if (number == null) return 9999;
  return int.tryParse(number) ?? 9999;
}

String _pickNonEmpty(String? primary, String fallback) {
  final value = (primary ?? '').trim();
  if (value.isNotEmpty) return value;
  return fallback.trim();
}
