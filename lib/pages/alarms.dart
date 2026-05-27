import 'dart:async';
import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_alarmkit/flutter_alarmkit.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:preconnect/api/exam_map_service.dart';
import 'package:preconnect/api/schedule_service.dart';
import 'package:preconnect/model/section_info.dart';
import 'package:preconnect/pages/shared_widgets/current_session_helper.dart';
import 'package:preconnect/pages/shared_widgets/highlight_scroll_helper.dart';
import 'package:preconnect/pages/shared_widgets/schedule_entry_card.dart';
import 'package:preconnect/pages/ui_kit.dart';
import 'package:preconnect/tools/json_snapshot_store.dart';
import 'package:preconnect/tools/preload_cache.dart';
import 'package:preconnect/tools/storage_keys.dart';
import 'package:preconnect/tools/refresh_bus.dart';
import 'package:preconnect/tools/exam_sorting.dart';
import 'package:preconnect/tools/exam_visibility.dart';
import 'package:preconnect/tools/ramadan_timing.dart';
import 'package:preconnect/tools/time_utils.dart';

class AlarmPage extends StatefulWidget {
  const AlarmPage({super.key});

  static Future<void> preload() async {
    await _AlarmPageState.preloadData();
  }

  @override
  State<AlarmPage> createState() => _AlarmPageState();
}

class _AlarmPageState extends State<AlarmPage> with RefreshBusState {
  static const MethodChannel _androidAlarmChannel = MethodChannel(
    'preconnect/android_alarm',
  );
  static final PreloadCache<_AlarmData> cache = PreloadCache<_AlarmData>();

  late Future<_AlarmData> _futureData;
  _AlarmData? _latestData;
  final ScrollController _scrollController = ScrollController();
  late final HighlightScrollCoordinator _highlightScroll =
      HighlightScrollCoordinator(scrollController: _scrollController);
  final Map<String, int> _minutesBefore = {};

  @override
  void initState() {
    super.initState();
    _latestData = cache.value;
    _futureData = cache.value == null
        ? _fetchSchedule()
        : Future<_AlarmData>.value(cache.value!);
    bindRefreshBus(_onRefreshSignal);
    unawaited(_warmAndBind());
  }

  @override
  void dispose() {
    unbindRefreshBus(_onRefreshSignal);
    _scrollController.dispose();
    super.dispose();
  }

  void _onRefreshSignal() {
    if (!mounted) return;
    if (isRefreshingFrom('alarms')) {
      return;
    }
    if (isRefreshingFrom('cache_cleared')) {
      unawaited(_handleRefresh(notify: false));
      return;
    }
    unawaited(_handleRefresh(notify: false));
  }

  Future<void> _warmAndBind() async {
    final data = await preloadData();
    if (!mounted) return;
    setState(() {
      _latestData = data;
      _futureData = Future<_AlarmData>.value(data);
    });
  }

  static Future<_AlarmData> preloadData({bool forceRefresh = false}) async {
    return cache.load(
      forceRefresh: forceRefresh,
      fetch: () => _loadAlarmData(forceRefresh: forceRefresh),
    );
  }

  Future<_AlarmData> _fetchSchedule({bool forceRefresh = false}) async {
    return preloadData(forceRefresh: forceRefresh);
  }

  static Future<_AlarmData> _loadAlarmData({bool forceRefresh = false}) async {
    final now = DateTime.now();
    if (!forceRefresh) {
      final cached = await JsonSnapshotStore.read<_AlarmData>(
        key: StorageKeys.alarmsSnapshot,
        decode: (decoded) {
          final sectionsRaw = decoded['sections'];
          final examsRaw = decoded['examEntries'];
          final isRamadan = decoded['isRamadan'] == true;
          if (sectionsRaw is! List || examsRaw is! List) return null;
          final sections = sectionsRaw
              .whereType<Map>()
              .map((entry) => Section.fromJson(entry.cast<String, dynamic>()))
              .toList(growable: false);
          final examEntries = examsRaw
              .whereType<Map>()
              .map(
                (entry) =>
                    _ExamAlarmEntry.fromJson(entry.cast<String, dynamic>()),
              )
              .toList(growable: false);
          return _AlarmData(
            sections: sections,
            examEntries: _pruneExpiredExamEntries(examEntries, now: now),
            isRamadan: isRamadan,
          );
        },
      );
      if (cached != null) {
        return cached;
      }
    }
    final ramadanFuture = RamadanTiming.isRamadan(forceRefresh: forceRefresh);
    final semesterSessionId = await resolveCurrentSessionSemesterIdWithRetry();
    if (semesterSessionId == null) {
      final isRamadan = await ramadanFuture;
      return _AlarmData(
        sections: const [],
        examEntries: const <_ExamAlarmEntry>[],
        isRamadan: isRamadan,
      );
    }
    final scheduleService = ScheduleService();
    final cachedJson = await scheduleService
        .getCachedStudentScheduleForSemester(
          semesterSessionId: semesterSessionId,
        );
    final jsonString =
        cachedJson ??
        (forceRefresh
            ? await scheduleService.fetchStudentScheduleForSemester(
                semesterSessionId: semesterSessionId,
                fromGet: true,
              )
            : await scheduleService.getStudentScheduleForSemester(
                semesterSessionId: semesterSessionId,
              ));
    final sections = scheduleService.parseStudentSections(
      jsonString,
      semesterSessionId: semesterSessionId,
    );
    final overrides = await ExamScheduleService().getOverridesForSections(
      sections,
      forceRefresh: forceRefresh,
    );
    final examEntries = _buildExamEntries(sections, overrides);
    if (sections.isEmpty) {
      final isRamadan = await ramadanFuture;
      return _AlarmData(
        sections: const [],
        examEntries: _pruneExpiredExamEntries(examEntries, now: now),
        isRamadan: isRamadan,
      );
    }

    final isRamadan = await ramadanFuture;
    final data = _AlarmData(
      sections: sections,
      examEntries: _pruneExpiredExamEntries(examEntries, now: now),
      isRamadan: isRamadan,
    );
    cache.value = data;
    await _writeSnapshot(data);
    return data;
  }

  static List<_ExamAlarmEntry> _pruneExpiredExamEntries(
    List<_ExamAlarmEntry> entries, {
    required DateTime now,
  }) {
    return entries
        .where(
          (entry) => ExamVisibility.isUpcomingOrOngoingDateTime(
            entry.dateTime,
            now: now,
          ),
        )
        .toList(growable: false);
  }

  static Future<void> _writeSnapshot(_AlarmData data) {
    return JsonSnapshotStore.write(
      key: StorageKeys.alarmsSnapshot,
      value: _alarmSnapshotPayload(data),
    );
  }

  static Map<String, dynamic> _alarmSnapshotPayload(_AlarmData data) {
    return <String, dynamic>{
      'sections': data.sections.map((section) => section.toJson()).toList(),
      'examEntries': data.examEntries.map((entry) => entry.toJson()).toList(),
      'isRamadan': data.isRamadan,
    };
  }

  static List<_ExamAlarmEntry> _buildExamEntries(
    List<Section> sections,
    Map<String, ExamScheduleOverride> overrides,
  ) {
    final service = ExamScheduleService();
    final now = DateTime.now();
    final items = <_ExamAlarmEntry>[];
    for (final section in sections) {
      final resolved = service.resolveSection(
        section: section,
        overrides: overrides,
      );
      final midAt = BracuTime.parseDateTime(
        resolved.midDate,
        resolved.midStartTime,
      );
      if (midAt != null &&
          ExamVisibility.isUpcomingOrOngoingDateTime(midAt, now: now)) {
        items.add(
          _ExamAlarmEntry(
            id: '${section.sectionId}-mid',
            type: 'Midterm',
            courseCode: section.courseCode,
            sectionName: section.sectionName,
            roomNumber: resolved.midRoomNumber ?? '',
            faculties: section.faculties,
            consumedSeat: section.consumedSeat,
            startTime: resolved.midStartTime,
            endTime: resolved.midEndTime,
            dateTime: midAt,
          ),
        );
      }
      final finalAt = BracuTime.parseDateTime(
        resolved.finalDate,
        resolved.finalStartTime,
      );
      if (finalAt != null &&
          ExamVisibility.isUpcomingOrOngoingDateTime(finalAt, now: now)) {
        items.add(
          _ExamAlarmEntry(
            id: '${section.sectionId}-final',
            type: 'Final',
            courseCode: section.courseCode,
            sectionName: section.sectionName,
            roomNumber: resolved.finalRoomNumber ?? '',
            faculties: section.faculties,
            consumedSeat: section.consumedSeat,
            startTime: resolved.finalStartTime,
            endTime: resolved.finalEndTime,
            dateTime: finalAt,
          ),
        );
      }
    }
    items.sort((a, b) {
      return ExamSorting.compareExamEntries(
        typeA: a.type,
        typeB: b.type,
        dateTimeA: a.dateTime,
        dateTimeB: b.dateTime,
        courseCodeA: a.courseCode,
        courseCodeB: b.courseCode,
        sectionNameA: a.sectionName,
        sectionNameB: b.sectionName,
      );
    });
    return items;
  }

  String? _resolveHighlightedExamKey(List<_ExamAlarmEntry> exams) {
    final now = DateTime.now();
    DateTime? nextExamTime;
    String? nextExamKey;

    for (final exam in exams) {
      final startTime = exam.dateTime;
      if (startTime.isAfter(now)) {
        if (nextExamTime == null || startTime.isBefore(nextExamTime)) {
          nextExamTime = startTime;
          nextExamKey = exam.id;
        }
      }
    }

    return nextExamKey;
  }

  Future<void> _handleRefresh({bool notify = true}) async {
    if (!await ensureOnline(context, notify: notify)) {
      return;
    }
    setState(() {
      _latestData = _latestData ?? cache.value;
      _futureData = preloadData(forceRefresh: true);
    });
    final data = await _futureData;
    if (mounted) {
      setState(() {
        _latestData = data;
      });
    }
  }

  Future<void> _setAlarm(
    BuildContext context,
    List<String> days,
    String startTime,
    String courseCode,
    int minutesBefore,
  ) async {
    if (kIsWeb) {
      if (!context.mounted) return;
      showAppSnackBar(context, 'Alarm setup is not available on web.');
      return;
    }
    final parsed = BracuTime.parseHourMinute(startTime);
    if (parsed == null) {
      if (!context.mounted) return;
      showAppSnackBar(context, 'Unable to parse class time.');
      return;
    }
    var (hour, minute) = parsed;

    final classTime = DateTime(2025, 1, 2, hour, minute);
    final adjusted = classTime.subtract(Duration(minutes: minutesBefore));
    hour = adjusted.hour;
    minute = adjusted.minute;
    final dayShift = adjusted.day.compareTo(classTime.day);

    if (defaultTargetPlatform == TargetPlatform.iOS) {
      final weekdays = _mapWeekdays(days, shift: dayShift);
      if (weekdays.isEmpty) return;
      try {
        final alarmkit = FlutterAlarmkit();
        await alarmkit.getPlatformVersion();
        final authorized = await alarmkit.requestAuthorization();
        if (!authorized) {
          if (!context.mounted) return;
          showAppSnackBar(context, 'Alarm permission denied.');
          return;
        }
        await alarmkit.scheduleRecurrentAlarm(
          weekdays: weekdays,
          hour: hour,
          minute: minute,
          label: '$courseCode Class Reminder ($minutesBefore min before)',
          tintColor: '#1E6BE3',
        );
        if (!context.mounted) return;
        showAppSnackBar(context, 'Alarm scheduled on iOS.');
        RefreshBus.instance.notify(reason: 'alarms');
      } on PlatformException catch (e) {
        if (!context.mounted) return;
        showAppSnackBar(
          context,
          e.code == 'UNSUPPORTED'
              ? 'AlarmKit requires iOS 26+.'
              : 'Unable to schedule alarm on this iOS.',
        );
      } catch (_) {
        if (!context.mounted) return;
        showAppSnackBar(context, 'Unable to schedule alarm on this iOS.');
      }
      return;
    }

    final dayMapping = {
      'SUNDAY': 1,
      'MONDAY': 2,
      'TUESDAY': 3,
      'WEDNESDAY': 4,
      'THURSDAY': 5,
      'FRIDAY': 6,
      'SATURDAY': 7,
    };

    final alarmDays = days
        .map((day) => dayMapping[day])
        .whereType<int>()
        .toList();

    try {
      final opened = await _androidAlarmChannel.invokeMethod<bool>('setAlarm', {
        'hour': hour,
        'minute': minute,
        'message': '$courseCode Class Reminder ($minutesBefore min before)',
        'days': alarmDays,
      });
      if (opened != true) {
        throw Exception('Unable to open alarm on Android.');
      }
      if (!context.mounted) return;
      showAppSnackBar(context, 'Alarm opened in Clock app.');
      RefreshBus.instance.notify(reason: 'alarms');
    } catch (_) {
      if (!context.mounted) return;
      showAppSnackBar(context, 'Unable to open alarm on Android.');
    }
  }

  Set<Weekday> _mapWeekdays(List<String> days, {int shift = 0}) {
    Weekday? toWeekday(String day) {
      switch (day.toUpperCase()) {
        case 'MONDAY':
          return Weekday.monday;
        case 'TUESDAY':
          return Weekday.tuesday;
        case 'WEDNESDAY':
          return Weekday.wednesday;
        case 'THURSDAY':
          return Weekday.thursday;
        case 'FRIDAY':
          return Weekday.friday;
        case 'SATURDAY':
          return Weekday.saturday;
        case 'SUNDAY':
          return Weekday.sunday;
        default:
          return null;
      }
    }

    Weekday shiftWeekday(Weekday day, int shiftBy) {
      final order = [
        Weekday.monday,
        Weekday.tuesday,
        Weekday.wednesday,
        Weekday.thursday,
        Weekday.friday,
        Weekday.saturday,
        Weekday.sunday,
      ];
      final index = order.indexOf(day);
      if (index < 0) return day;
      final next = (index + shiftBy) % order.length;
      return order[(next + order.length) % order.length];
    }

    final mapped = days.map(toWeekday).whereType<Weekday>().toSet();
    if (shift == 0) return mapped;
    return mapped.map((d) => shiftWeekday(d, shift)).toSet();
  }

  Future<void> _setExamAlarm(
    BuildContext context,
    _ExamAlarmEntry entry,
    int minutesBefore,
  ) async {
    if (kIsWeb) {
      if (!context.mounted) return;
      showAppSnackBar(context, 'Alarm setup is not available on web.');
      return;
    }

    final fireAt = entry.dateTime.subtract(Duration(minutes: minutesBefore));
    if (fireAt.isBefore(DateTime.now())) {
      if (!context.mounted) return;
      showAppSnackBar(context, 'This exam is already over.');
      return;
    }

    if (defaultTargetPlatform == TargetPlatform.iOS) {
      try {
        final alarmkit = FlutterAlarmkit();
        await alarmkit.getPlatformVersion();
        final authorized = await alarmkit.requestAuthorization();
        if (!authorized) {
          if (!context.mounted) return;
          showAppSnackBar(context, 'Alarm permission denied.');
          return;
        }
        await alarmkit.scheduleOneShotAlarm(
          timestamp: fireAt.millisecondsSinceEpoch.toDouble(),
          label:
              '${entry.courseCode} ${entry.type} Reminder ($minutesBefore min before)',
          tintColor: '#1E6BE3',
        );
        if (!context.mounted) return;
        showAppSnackBar(context, 'Exam alarm scheduled on iOS.');
        RefreshBus.instance.notify(reason: 'alarms');
      } on PlatformException catch (e) {
        if (!context.mounted) return;
        showAppSnackBar(
          context,
          e.code == 'UNSUPPORTED'
              ? 'AlarmKit requires iOS 26+.'
              : 'Unable to schedule exam alarm on this iOS.',
        );
      } catch (_) {
        if (!context.mounted) return;
        showAppSnackBar(context, 'Unable to schedule exam alarm on this iOS.');
      }
      return;
    }

    try {
      final opened = await _androidAlarmChannel.invokeMethod<bool>('setAlarm', {
        'hour': fireAt.hour,
        'minute': fireAt.minute,
        'message':
            '${entry.courseCode} ${entry.type} Reminder ($minutesBefore min before)',
      });
      if (opened != true) {
        throw Exception('Unable to open alarm on Android.');
      }
      if (!context.mounted) return;
      showAppSnackBar(
        context,
        'Alarm opened in Clock app. Please verify the date and time.',
      );
      RefreshBus.instance.notify(reason: 'alarms');
    } catch (_) {
      if (!context.mounted) return;
      showAppSnackBar(context, 'Unable to open alarm on Android.');
    }
  }

  String _formatExamDateOnly(DateTime dt) {
    return DateFormat('d MMMM, yyyy').format(dt);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final chipBg = isDark
        ? const Color(0xFF0F3B6D)
        : BracuPalette.primary.withValues(alpha: 0.10);
    final controlBg = isDark ? const Color(0xFF0B0B0B) : Colors.white;

    return BracuPageScaffold(
      title: 'Set Alarms',
      subtitle: 'Class & Exam',
      icon: Icons.alarm_outlined,
      body: FutureBuilder<_AlarmData>(
        future: _futureData,
        builder: (context, snapshot) {
          if (snapshot.hasError && _latestData == null) {
            return buildRefreshErrorState(
              onRefresh: _handleRefresh,
              error: snapshot.error,
            );
          }

          final data = _latestData ?? snapshot.data;
          if (snapshot.connectionState == ConnectionState.waiting &&
              data == null) {
            return buildRefreshLoadingState(onRefresh: _handleRefresh);
          }
          final sections = data?.sections ?? const <Section>[];
          final exams = data?.examEntries ?? const <_ExamAlarmEntry>[];
          final isRamadan = data?.isRamadan ?? false;
          final highlightedExamKey = _resolveHighlightedExamKey(exams);
          _highlightScroll.clearHighlightKey();
          if (sections.isEmpty && exams.isEmpty) {
            return buildRefreshEmptyState(
              onRefresh: _handleRefresh,
              message: 'No class or exam found',
            );
          }

          final highlightedIndex = highlightedExamKey == null
              ? -1
              : exams.indexWhere((exam) => exam.id == highlightedExamKey);
          unawaited(
            _highlightScroll.scrollToTarget(
              targetToken: highlightedExamKey,
              targetIndex: highlightedIndex >= 0
                  ? sections.length + highlightedIndex
                  : null,
              itemCount: sections.length + exams.length + 1,
              onRetryBuild: () {
                if (mounted) {
                  setState(() {});
                }
              },
            ),
          );

          return BracuRefreshListBuilder(
            onRefresh: _handleRefresh,
            controller: _scrollController,
            itemCount: sections.length + exams.length + 1,
            itemBuilder: (context, index) {
              if (index == sections.length + exams.length) {
                return const Padding(padding: EdgeInsets.only(top: 12));
              }

              if (index >= sections.length && exams.isNotEmpty) {
                final examIndex = index - sections.length;
                final exam = exams[examIndex];
                final alarmKey = 'exam_${exam.id}';
                _minutesBefore.putIfAbsent(alarmKey, () => 15);
                final isHighlighted = highlightedExamKey == exam.id;
                if (isHighlighted) {
                  _highlightScroll.markHighlighted(true);
                }
                return Padding(
                  key: isHighlighted ? _highlightScroll.highlightKey : null,
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      BracuCard(
                        isHighlighted: isHighlighted,
                        highlightColor: BracuPalette.primary,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                SectionBadge(
                                  label: formatSectionBadge(exam.sectionName),
                                  color: exam.type == 'Final'
                                      ? BracuPalette.accent
                                      : BracuPalette.primary,
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text.rich(
                                        TextSpan(
                                          children: [
                                            TextSpan(
                                              text: exam.courseCode.trim(),
                                              style: const TextStyle(
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                            TextSpan(
                                              text: ' ${exam.type}',
                                              style: TextStyle(
                                                fontWeight: FontWeight.w600,
                                                color:
                                                    BracuPalette.textSecondary(
                                                      context,
                                                    ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(height: 6),
                                      Text(
                                        formatTimeRange(
                                          exam.startTime,
                                          exam.endTime,
                                        ),
                                        style: TextStyle(
                                          color: BracuPalette.textPrimary(
                                            context,
                                          ),
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    Text(
                                      exam.roomNumber.trim().isEmpty
                                          ? 'TBA'
                                          : exam.roomNumber,
                                      style: TextStyle(
                                        color: BracuPalette.textPrimary(
                                          context,
                                        ),
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    if (exam.faculties.trim().isNotEmpty ||
                                        exam.consumedSeat > 0) ...[
                                      const SizedBox(height: 2),
                                      Text.rich(
                                        TextSpan(
                                          children: [
                                            if (exam.faculties
                                                .trim()
                                                .isNotEmpty)
                                              TextSpan(
                                                text: exam.faculties.trim(),
                                                style: TextStyle(
                                                  fontSize: 12,
                                                  fontWeight: FontWeight.w700,
                                                  color:
                                                      BracuPalette.textPrimary(
                                                        context,
                                                      ),
                                                ),
                                              ),
                                            if (exam.consumedSeat > 0)
                                              TextSpan(
                                                text:
                                                    '${exam.faculties.trim().isEmpty ? '' : ' '}(${exam.consumedSeat})',
                                                style: TextStyle(
                                                  fontSize: 12,
                                                  color:
                                                      BracuPalette.textSecondary(
                                                        context,
                                                      ),
                                                ),
                                              ),
                                          ],
                                        ),
                                        textAlign: TextAlign.right,
                                      ),
                                    ],
                                  ],
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            SizedBox(
                              width: double.infinity,
                              child: Wrap(
                                alignment: WrapAlignment.center,
                                spacing: 8,
                                runSpacing: 8,
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 6,
                                    ),
                                    decoration: BoxDecoration(
                                      color: chipBg,
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Text(
                                      _formatExamDateOnly(exam.dateTime),
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: BracuPalette.textPrimary(
                                          context,
                                        ),
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 6,
                                    ),
                                    decoration: BoxDecoration(
                                      color: chipBg,
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Text(
                                      DateFormat(
                                        'EEEE',
                                      ).format(exam.dateTime).toUpperCase(),
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: BracuPalette.textPrimary(
                                          context,
                                        ),
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 14),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 8,
                              ),
                              decoration: BoxDecoration(
                                color: controlBg,
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(
                                  color: BracuPalette.primary.withValues(
                                    alpha: 0.2,
                                  ),
                                ),
                              ),
                              child: Row(
                                children: [
                                  InkWell(
                                    onTap: () {
                                      setState(() {
                                        if (_minutesBefore[alarmKey]! > 5) {
                                          _minutesBefore[alarmKey] =
                                              _minutesBefore[alarmKey]! - 5;
                                        }
                                      });
                                    },
                                    borderRadius: BorderRadius.circular(10),
                                    child: Container(
                                      padding: const EdgeInsets.all(6),
                                      decoration: BoxDecoration(
                                        color: BracuPalette.primary.withValues(
                                          alpha: 0.12,
                                        ),
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                      child: const Icon(
                                        Icons.remove,
                                        size: 18,
                                        color: BracuPalette.primary,
                                      ),
                                    ),
                                  ),
                                  Expanded(
                                    child: Center(
                                      child: Text(
                                        '${_minutesBefore[alarmKey]} min before',
                                        style: TextStyle(
                                          fontWeight: FontWeight.w600,
                                          color: BracuPalette.textPrimary(
                                            context,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                  InkWell(
                                    onTap: () {
                                      setState(() {
                                        _minutesBefore[alarmKey] =
                                            _minutesBefore[alarmKey]! + 5;
                                      });
                                    },
                                    borderRadius: BorderRadius.circular(10),
                                    child: Container(
                                      padding: const EdgeInsets.all(6),
                                      decoration: BoxDecoration(
                                        color: BracuPalette.primary.withValues(
                                          alpha: 0.12,
                                        ),
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                      child: const Icon(
                                        Icons.add,
                                        size: 18,
                                        color: BracuPalette.primary,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 12),
                            SizedBox(
                              width: double.infinity,
                              child: BracuActionButton(
                                onPressed: () async {
                                  await _setExamAlarm(
                                    context,
                                    exam,
                                    _minutesBefore[alarmKey]!,
                                  );
                                },
                                icon: Icons.notifications_active,
                                label: 'Set Alarm',
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              }

              final section = sections[index];
              final schedules = section.sectionSchedule.classSchedules;
              if (schedules.isEmpty) return const SizedBox.shrink();

              final courseCode = section.courseCode;
              _minutesBefore.putIfAbsent(courseCode, () => 5);
              final schedule = schedules.first;

              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: BracuCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ScheduleEntryCard(
                        sectionName: section.sectionName,
                        courseCode: courseCode,
                        schedule: schedule,
                        isRamadan: isRamadan,
                        roomNumber: section.roomNumber,
                        faculties: section.faculties,
                        consumedSeat: section.consumedSeat,
                        courseType: section.courseType,
                        wrapInCard: false,
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: Wrap(
                          alignment: WrapAlignment.center,
                          spacing: 8,
                          runSpacing: 8,
                          children: schedules.map((s) {
                            return Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color: chipBg,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                s.day.toUpperCase(),
                                style: TextStyle(
                                  fontSize: 12,
                                  color: BracuPalette.textPrimary(context),
                                  fontWeight: FontWeight.w600,
                                ),
                                maxLines: 1,
                                softWrap: false,
                                overflow: TextOverflow.ellipsis,
                                textAlign: TextAlign.center,
                              ),
                            );
                          }).toList(),
                        ),
                      ),
                      const SizedBox(height: 14),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: controlBg,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: BracuPalette.primary.withValues(alpha: 0.2),
                          ),
                        ),
                        child: Row(
                          children: [
                            InkWell(
                              onTap: () {
                                setState(() {
                                  if (_minutesBefore[courseCode]! > 5) {
                                    _minutesBefore[courseCode] =
                                        _minutesBefore[courseCode]! - 5;
                                  }
                                });
                              },
                              borderRadius: BorderRadius.circular(10),
                              child: Container(
                                padding: const EdgeInsets.all(6),
                                decoration: BoxDecoration(
                                  color: BracuPalette.primary.withValues(
                                    alpha: 0.12,
                                  ),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: const Icon(
                                  Icons.remove,
                                  size: 18,
                                  color: BracuPalette.primary,
                                ),
                              ),
                            ),
                            Expanded(
                              child: Center(
                                child: Text(
                                  '${_minutesBefore[courseCode]} min before',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w600,
                                    color: BracuPalette.textPrimary(context),
                                  ),
                                ),
                              ),
                            ),
                            InkWell(
                              onTap: () {
                                setState(() {
                                  _minutesBefore[courseCode] =
                                      _minutesBefore[courseCode]! + 5;
                                });
                              },
                              borderRadius: BorderRadius.circular(10),
                              child: Container(
                                padding: const EdgeInsets.all(6),
                                decoration: BoxDecoration(
                                  color: BracuPalette.primary.withValues(
                                    alpha: 0.12,
                                  ),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: const Icon(
                                  Icons.add,
                                  size: 18,
                                  color: BracuPalette.primary,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: BracuActionButton(
                              onPressed: () async {
                                final days = schedules
                                    .map((s) => s.day)
                                    .toList();
                                final startTime = schedules.isNotEmpty
                                    ? RamadanTiming.adjustRange(
                                        schedules.first.startTime,
                                        schedules.first.endTime,
                                        isRamadan: isRamadan,
                                      ).startTime
                                    : '';

                                if (startTime.isNotEmpty && days.isNotEmpty) {
                                  await _setAlarm(
                                    context,
                                    days,
                                    startTime,
                                    courseCode,
                                    _minutesBefore[courseCode]!,
                                  );
                                }
                              },
                              icon: Icons.notifications_active,
                              label: 'Set Alarm',
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class _AlarmData {
  const _AlarmData({
    required this.sections,
    required this.examEntries,
    required this.isRamadan,
  });

  final List<Section> sections;
  final List<_ExamAlarmEntry> examEntries;
  final bool isRamadan;
}

class _ExamAlarmEntry {
  const _ExamAlarmEntry({
    required this.id,
    required this.type,
    required this.courseCode,
    required this.sectionName,
    required this.roomNumber,
    required this.faculties,
    required this.consumedSeat,
    required this.startTime,
    required this.endTime,
    required this.dateTime,
  });

  final String id;
  final String type;
  final String courseCode;
  final String sectionName;
  final String roomNumber;
  final String faculties;
  final int consumedSeat;
  final String? startTime;
  final String? endTime;
  final DateTime dateTime;

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id,
      'type': type,
      'courseCode': courseCode,
      'sectionName': sectionName,
      'roomNumber': roomNumber,
      'faculties': faculties,
      'consumedSeat': consumedSeat,
      'startTime': startTime,
      'endTime': endTime,
      'dateTime': dateTime.millisecondsSinceEpoch,
    };
  }

  factory _ExamAlarmEntry.fromJson(Map<String, dynamic> json) {
    return _ExamAlarmEntry(
      id: json['id']?.toString() ?? '',
      type: json['type']?.toString() ?? '',
      courseCode: json['courseCode']?.toString() ?? '',
      sectionName: json['sectionName']?.toString() ?? '',
      roomNumber: json['roomNumber']?.toString() ?? '',
      faculties: json['faculties']?.toString() ?? '',
      consumedSeat: (json['consumedSeat'] as num?)?.toInt() ?? 0,
      startTime: json['startTime']?.toString(),
      endTime: json['endTime']?.toString(),
      dateTime: DateTime.fromMillisecondsSinceEpoch(
        (json['dateTime'] as num?)?.toInt() ?? 0,
      ),
    );
  }
}
