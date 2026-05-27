// ignore_for_file: use_build_context_synchronously

import 'dart:async';

import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_alarmkit/flutter_alarmkit.dart';
import 'package:intl/intl.dart';
import 'package:preconnect/api/schedule_service.dart';
import 'package:preconnect/api/custom_schedules_service.dart';
import 'package:preconnect/model/custom_schedule.dart';
import 'package:preconnect/pages/ui_kit.dart';
import 'package:preconnect/pages/custom_schedules_sections/custom_schedules_editor_sheet.dart'
    show showCustomSchedulesEditorSheet;
import 'package:preconnect/pages/custom_schedules_sections/custom_schedules_shared.dart';
import 'package:preconnect/pages/shared_widgets/current_session_helper.dart';
import 'package:preconnect/tools/preload_cache.dart';
import 'package:preconnect/tools/refresh_bus.dart';

class CustomSchedulesPage extends StatefulWidget {
  const CustomSchedulesPage({super.key});

  static Future<void> preload() async {
    await _CustomSchedulesPageState.preloadData();
  }

  @override
  State<CustomSchedulesPage> createState() => _CustomSchedulesPageState();
}

class _CustomSchedulesPageState extends State<CustomSchedulesPage>
    with RefreshBusState, WidgetsBindingObserver {
  static const MethodChannel _androidAlarmChannel = MethodChannel(
    'preconnect/android_alarm',
  );
  static const Duration _autoRefreshInterval = Duration(seconds: 20);
  static final CachedPageController<List<CustomSchedule>> itemsCache =
      CachedPageController<List<CustomSchedule>>(({
        bool forceRefresh = false,
      }) async {
        final service = CustomSchedulesService();
        try {
          final items = await service.getItems(forceRefresh: forceRefresh);
          return await service.autoCompleteOverdueItems(items);
        } catch (_) {
          return await service.getCachedItems() ?? const <CustomSchedule>[];
        }
      });
  static List<CustomSchedulesCourseOption>? _cachedCourseOptions;
  static Future<void>? _preloadFuture;

  late Future<List<CustomSchedule>> _future;
  List<CustomSchedule>? _latestItems;
  List<CustomSchedulesCourseOption> _latestCourseOptions =
      const <CustomSchedulesCourseOption>[];
  Future<List<CustomSchedulesCourseOption>>? _courseOptionsLoadInFlight;
  bool _isBusy = false;
  Timer? _autoRefreshTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _latestItems = itemsCache.value;
    if (_cachedCourseOptions != null) {
      _latestCourseOptions = _cachedCourseOptions!;
    }
    _future = itemsCache.value == null
        ? _loadItems()
        : Future<List<CustomSchedule>>.value(itemsCache.value!);
    unawaited(_warmAndBind());
    unawaited(_primeCachedItems());
    _autoRefreshTimer = Timer.periodic(_autoRefreshInterval, (_) {
      if (!mounted || _isBusy) return;
      unawaited(_refresh(forceRefresh: true, notify: false));
    });
    bindRefreshBus(_onRefreshSignal);
  }

  Future<void> _warmAndBind() async {
    await preloadData();
    if (!mounted) return;
    setState(() {
      _future = Future<List<CustomSchedule>>.value(
        itemsCache.value ?? const <CustomSchedule>[],
      );
      _latestItems = itemsCache.value;
      if (_cachedCourseOptions != null) {
        _latestCourseOptions = _cachedCourseOptions!;
      }
    });
  }

  static Future<void> preloadData({bool forceRefresh = false}) async {
    if (!forceRefresh &&
        itemsCache.value != null &&
        _cachedCourseOptions != null &&
        _cachedCourseOptions!.isNotEmpty) {
      return;
    }
    if (!forceRefresh) {
      final inFlight = _preloadFuture;
      if (inFlight != null) {
        await inFlight;
        return;
      }
    }

    final future = _loadPreloadData(forceRefresh: forceRefresh);
    _preloadFuture = future;
    try {
      await future;
    } finally {
      if (identical(_preloadFuture, future)) {
        _preloadFuture = null;
      }
    }
  }

  static Future<void> _loadPreloadData({bool forceRefresh = false}) async {
    itemsCache.value = await itemsCache.load(forceRefresh: forceRefresh);

    try {
      final currentSessionSemesterId = await resolveCurrentSessionSemesterId();
      final scheduleService = ScheduleService();
      if (currentSessionSemesterId == null) {
        _cachedCourseOptions = const <CustomSchedulesCourseOption>[];
        return;
      }
      final jsonString = await scheduleService.fetchStudentScheduleForSemester(
        semesterSessionId: currentSessionSemesterId,
      );
      final sections = scheduleService.parseStudentSections(
        jsonString,
        semesterSessionId: currentSessionSemesterId,
      );
      final courseOptions = <CustomSchedulesCourseOption>[];
      final seen = <String>{};
      for (final sectionItem in sections) {
        final code = sectionItem.courseCode.trim().toUpperCase();
        if (code.isEmpty) continue;
        final option = (
          courseCode: code,
          sectionName: sectionItem.sectionName.trim(),
          classSchedules: sectionItem.sectionSchedule.classSchedules
              .map(
                (schedule) => (
                  day: schedule.day,
                  startTime: schedule.startTime,
                  endTime: schedule.endTime,
                ),
              )
              .toList(),
        );
        final identity = '${option.courseCode}|${option.sectionName}';
        if (seen.add(identity)) {
          courseOptions.add(option);
        }
      }
      courseOptions.sort((a, b) {
        final codeCmp = a.courseCode.compareTo(b.courseCode);
        if (codeCmp != 0) return codeCmp;
        return a.sectionName.compareTo(b.sectionName);
      });
      _cachedCourseOptions = courseOptions;
    } catch (_) {
      _cachedCourseOptions ??= const <CustomSchedulesCourseOption>[];
    }
  }

  @override
  void dispose() {
    _autoRefreshTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    unbindRefreshBus(_onRefreshSignal);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted) {
      unawaited(_refresh(forceRefresh: true, notify: false));
    }
  }

  void _onRefreshSignal() {
    if (!mounted) return;
    if (isRefreshingFrom('schedule')) return;
    if (isRefreshingFrom('cache_cleared')) {
      if (mounted) {
        setState(() {
          _future = CustomSchedulesService().getItems(forceRefresh: true);
        });
      }
      return;
    }
    unawaited(_refresh(forceRefresh: false, notify: false));
  }

  Future<List<CustomSchedule>> _loadItems({bool forceRefresh = false}) async {
    return itemsCache.load(forceRefresh: forceRefresh);
  }

  Future<void> _primeCachedItems() async {
    if (itemsCache.value != null) {
      if (!mounted) return;
      setState(() {
        _latestItems = itemsCache.value;
      });
      return;
    }
    final cached = await CustomSchedulesService().getCachedItems();
    if (!mounted || cached == null) return;
    setState(() {
      _latestItems = cached;
    });
    itemsCache.value = cached;
  }

  Future<List<CustomSchedulesCourseOption>> _loadCourseOptions({
    bool forceRefresh = false,
  }) async {
    if (!forceRefresh &&
        _cachedCourseOptions != null &&
        _cachedCourseOptions!.isNotEmpty) {
      if (_latestCourseOptions.isEmpty && mounted) {
        setState(() {
          _latestCourseOptions = _cachedCourseOptions!;
        });
      }
      return _cachedCourseOptions!;
    }
    if (!forceRefresh && _latestCourseOptions.isNotEmpty) {
      return _latestCourseOptions;
    }
    if (_courseOptionsLoadInFlight != null) {
      return _courseOptionsLoadInFlight!;
    }

    final loadFuture = () async {
      try {
        final currentSessionSemesterId =
            await resolveCurrentSessionSemesterId();
        final scheduleService = ScheduleService();
        if (currentSessionSemesterId == null) {
          return const <CustomSchedulesCourseOption>[];
        }
        final jsonString = await scheduleService
            .fetchStudentScheduleForSemester(
              semesterSessionId: currentSessionSemesterId,
            );
        final sections = scheduleService.parseStudentSections(
          jsonString,
          semesterSessionId: currentSessionSemesterId,
        );
        final courseOptions = <CustomSchedulesCourseOption>[];
        final seen = <String>{};
        for (final sectionItem in sections) {
          final code = sectionItem.courseCode.trim().toUpperCase();
          if (code.isNotEmpty) {
            final option = (
              courseCode: code,
              sectionName: sectionItem.sectionName.trim(),
              classSchedules: sectionItem.sectionSchedule.classSchedules
                  .map(
                    (schedule) => (
                      day: schedule.day,
                      startTime: schedule.startTime,
                      endTime: schedule.endTime,
                    ),
                  )
                  .toList(),
            );
            if (seen.add(_courseOptionIdentity(option))) {
              courseOptions.add(option);
            }
          }
        }
        courseOptions.sort((a, b) {
          final codeCmp = a.courseCode.compareTo(b.courseCode);
          if (codeCmp != 0) return codeCmp;
          return a.sectionName.compareTo(b.sectionName);
        });
        final options = courseOptions;
        if (mounted) {
          setState(() {
            _latestCourseOptions = options;
          });
        }
        _cachedCourseOptions = options;
        return options;
      } catch (_) {
        return const <CustomSchedulesCourseOption>[];
      } finally {
        _courseOptionsLoadInFlight = null;
      }
    }();

    _courseOptionsLoadInFlight = loadFuture;
    return loadFuture;
  }

  String _courseOptionIdentity(CustomSchedulesCourseOption option) {
    return '${option.courseCode}|${option.sectionName}';
  }

  Future<void> _refresh({bool forceRefresh = true, bool notify = true}) async {
    if (_isBusy) return;
    if (notify && !mounted) return;
    setState(() {
      _isBusy = true;
      _future = _loadItems(forceRefresh: forceRefresh);
    });
    unawaited(_loadCourseOptions(forceRefresh: forceRefresh));
    try {
      final items = await _future;
      if (!mounted) return;
      setState(() {
        _latestItems = items;
      });
    } finally {
      if (mounted) {
        setState(() {
          _isBusy = false;
        });
      }
    }
  }

  Future<void> _openEditor({CustomSchedule? item}) async {
    final currentContext = context;
    final courseOptions = _latestCourseOptions;
    final draft = await showCustomSchedulesEditorSheet(
      currentContext,
      item: item,
      courseOptions: courseOptions,
      onDelete: item == null ? null : () => _deleteItem(item),
      onToggleDone: item == null
          ? null
          : (isDone) => _setDoneStatus(item, isDone),
      onSetAlarm:
          ({
            required String courseCode,
            required String title,
            required DateTime reminderAt,
          }) {
            return _setMyAlarm(
              context: currentContext,
              courseCode: courseCode,
              title: title,
              reminderAt: reminderAt,
            );
          },
    );
    if (draft == null || !mounted) return;

    final kindLabel = personalSchedulesFormatKind(draft.kind);
    try {
      final normalizedTitle = _normalizeMyTitleForSave(draft.title);
      if (item == null) {
        await CustomSchedulesService().createItem(
          kind: draft.kind,
          title: normalizedTitle,
          startTime: draft.startTime,
          endTime: draft.endTime,
          reminderAt: draft.reminderAt,
          courseCode: draft.courseCode,
          sectionName: draft.sectionName,
          notes: draft.notes,
          isDone: draft.isDone,
        );
        showAppSnackBar(currentContext, '$kindLabel added');
      } else {
        await CustomSchedulesService().updateItem(
          itemId: item.itemId,
          kind: draft.kind,
          title: normalizedTitle,
          startTime: draft.startTime,
          endTime: draft.endTime,
          clearEndTime: draft.endTime == null,
          reminderAt: draft.reminderAt,
          clearReminderAt: false,
          courseCode: draft.courseCode,
          sectionName: draft.sectionName,
          notes: draft.notes,
          isDone: draft.isDone,
        );
        showAppSnackBar(currentContext, '$kindLabel updated');
      }
      RefreshBus.instance.notify(reason: 'schedule');
      await _refresh(forceRefresh: true, notify: false);
    } catch (_) {
      if (!mounted) return;
      showAppSnackBar(
        currentContext,
        'Unable to save ${kindLabel.toLowerCase()}',
      );
    }
  }

  Future<void> _setDoneStatus(CustomSchedule item, bool done) async {
    if (item.isDone == done) return;
    final currentContext = context;
    if (_isBusy) return;
    final previousItems = _latestItems;
    if (previousItems != null) {
      final optimistic = previousItems
          .map(
            (entry) => entry.itemId == item.itemId
                ? entry.copyWith(isDone: done)
                : entry,
          )
          .toList();
      optimistic.sort((a, b) {
        final doneCompare = a.isDone == b.isDone
            ? 0
            : a.isDone
            ? 1
            : -1;
        if (doneCompare != 0) return doneCompare;
        final dueCompare = a.startTime.compareTo(b.startTime);
        if (dueCompare != 0) return dueCompare;
        return b.createdAt.compareTo(a.createdAt);
      });
      setState(() {
        _latestItems = optimistic;
      });
    }
    setState(() {
      _isBusy = true;
    });
    try {
      final updated = await CustomSchedulesService().updateItem(
        itemId: item.itemId,
        isDone: done,
      );
      if (mounted && _latestItems != null) {
        final merged = _latestItems!
            .map((entry) => entry.itemId == updated.itemId ? updated : entry)
            .toList();
        merged.sort((a, b) {
          final doneCompare = a.isDone == b.isDone
              ? 0
              : a.isDone
              ? 1
              : -1;
          if (doneCompare != 0) return doneCompare;
          final dueCompare = a.startTime.compareTo(b.startTime);
          if (dueCompare != 0) return dueCompare;
          return b.createdAt.compareTo(a.createdAt);
        });
        setState(() {
          _latestItems = merged;
        });
      }
      if (!mounted) return;
      showAppSnackBar(
        currentContext,
        done ? 'Marked as done' : 'Marked as pending',
      );
      RefreshBus.instance.notify(reason: 'schedule');
      await _refresh(forceRefresh: false, notify: false);
    } catch (_) {
      if (mounted && previousItems != null) {
        setState(() {
          _latestItems = previousItems;
        });
      }
      if (!mounted) return;
      showAppSnackBar(
        currentContext,
        'Unable to update ${personalSchedulesFormatKind(item.kind).toLowerCase()}',
      );
    } finally {
      if (mounted) {
        setState(() {
          _isBusy = false;
        });
      }
    }
  }

  Future<void> _deleteItem(CustomSchedule item) async {
    final currentContext = context;
    final kindLabel = personalSchedulesFormatKind(item.kind).toLowerCase();

    final deleted = await showBracuConfirmationWithActionDialog(
      currentContext,
      icon: Icons.delete_outline_rounded,
      title: 'Delete $kindLabel?',
      message: 'This will remove this $kindLabel from your schedule.',
      confirmLabel: 'Delete',
      confirmColor: BracuPalette.danger,
      onConfirm: () async {
        await CustomSchedulesService().deleteItem(item.itemId);
      },
    );

    if (!deleted || !mounted) return;

    try {
      showAppSnackBar(
        currentContext,
        '${personalSchedulesFormatKind(item.kind)} deleted',
      );
      RefreshBus.instance.notify(reason: 'schedule');
      await _refresh(forceRefresh: true, notify: false);
    } catch (_) {
      if (!mounted) return;
      showAppSnackBar(currentContext, 'Unable to refresh after delete');
    }
  }

  Future<void> _setMyAlarm({
    required BuildContext context,
    required String courseCode,
    required String title,
    required DateTime reminderAt,
  }) async {
    if (kIsWeb) {
      if (!context.mounted) return;
      showAppSnackBar(context, 'Alarm setup is not available on web.');
      return;
    }
    if (reminderAt.isBefore(DateTime.now())) return;

    final labelCode = courseCode.trim().isNotEmpty
        ? courseCode.trim().toUpperCase()
        : 'My';
    final trimmedTitle = title.trim();
    final message = trimmedTitle.isEmpty
        ? labelCode
        : '$labelCode $trimmedTitle';

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
          timestamp: reminderAt.millisecondsSinceEpoch.toDouble(),
          label: message,
          tintColor: '#1E6BE3',
        );
        if (!context.mounted) return;
        showAppSnackBar(context, 'Alarm scheduled on iOS.');
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

    try {
      final opened = await _androidAlarmChannel.invokeMethod<bool>('setAlarm', {
        'hour': reminderAt.hour,
        'minute': reminderAt.minute,
        'message': message,
      });
      if (opened != true) {
        throw Exception('Unable to open alarm on Android.');
      }
      if (!context.mounted) return;
      showAppSnackBar(context, 'Alarm opened in Clock app.');
    } catch (_) {
      if (!context.mounted) return;
      showAppSnackBar(context, 'Unable to open alarm on Android.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return BracuPageScaffold(
      title: 'Personal',
      subtitle: 'Schedules',
      icon: Icons.event_note_outlined,
      actions: [
        IconButton(
          tooltip: 'Add custom schedule',
          onPressed: _openEditor,
          icon: const Icon(Icons.add_rounded),
        ),
      ],
      body: FutureBuilder<List<CustomSchedule>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.hasError && _latestItems == null) {
            return buildRefreshErrorState(
              onRefresh: () => _refresh(forceRefresh: true),
              topSpacing: 180,
              error: snapshot.error,
            );
          }

          final items =
              _latestItems ?? snapshot.data ?? const <CustomSchedule>[];
          final dayGroups = _groupItemsByDay(items);

          if (items.isEmpty) {
            return BracuRefreshList(
              onRefresh: () => _refresh(forceRefresh: true),
              children: [
                const SizedBox(height: 160),
                _MyContentWrap(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Text(
                        'No custom schedules yet.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: BracuPalette.textPrimary(context),
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Tap plus to add your first one.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: BracuPalette.textSecondary(context),
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 14),
                      BracuActionButton(
                        onPressed: _openEditor,
                        icon: Icons.add_rounded,
                        label: 'Add Schedule',
                      ),
                    ],
                  ),
                ),
              ],
            );
          }

          return BracuRefreshScroll(
            onRefresh: () => _refresh(forceRefresh: true),
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
            child: _MyContentWrap(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (
                    var groupIndex = 0;
                    groupIndex < dayGroups.length;
                    groupIndex++
                  ) ...[
                    if (groupIndex > 0) const SizedBox(height: 10),
                    _DayDateHeader(date: dayGroups[groupIndex].date),
                    const SizedBox(height: 8),
                    ...dayGroups[groupIndex].items.map(
                      (item) => Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: _UpcomingScheduleItemCard(
                          item: item,
                          sectionBadgeLabel:
                              _personalSchedulesSectionBadgeLabel(
                                item,
                                _latestCourseOptions,
                              ),
                          onTap: () => _openEditor(item: item),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  List<_MyDayGroup> _groupItemsByDay(List<CustomSchedule> items) {
    final grouped = <DateTime, List<CustomSchedule>>{};
    for (final item in items) {
      final localDueAt = item.startTime.toLocal();
      final date = DateTime(localDueAt.year, localDueAt.month, localDueAt.day);
      grouped.putIfAbsent(date, () => <CustomSchedule>[]).add(item);
    }

    final groups =
        grouped.entries
            .map(
              (entry) => _MyDayGroup(
                date: entry.key,
                items: List<CustomSchedule>.from(entry.value)
                  ..sort(_compareMyItems),
              ),
            )
            .toList()
          ..sort((a, b) => a.date.compareTo(b.date));

    return groups;
  }

  int _compareMyItems(CustomSchedule a, CustomSchedule b) {
    final doneCompare = a.isDone == b.isDone
        ? 0
        : a.isDone
        ? 1
        : -1;
    if (doneCompare != 0) return doneCompare;
    final dueCompare = a.startTime.compareTo(b.startTime);
    if (dueCompare != 0) return dueCompare;
    return b.createdAt.compareTo(a.createdAt);
  }
}

class _MyContentWrap extends StatelessWidget {
  const _MyContentWrap({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760),
        child: child,
      ),
    );
  }
}

class _MyDayGroup {
  const _MyDayGroup({required this.date, required this.items});

  final DateTime date;
  final List<CustomSchedule> items;
}

class _DayDateHeader extends StatelessWidget {
  const _DayDateHeader({required this.date});

  final DateTime date;

  @override
  Widget build(BuildContext context) {
    final weekdayLabel = formatWeekdayTitle(DateFormat('EEEE').format(date));
    return Row(
      children: [
        Expanded(child: BracuSectionTitle(title: weekdayLabel)),
        Text(
          formatLongDate(date),
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: BracuPalette.textPrimary(context),
          ),
        ),
      ],
    );
  }
}

class _UpcomingScheduleItemCard extends StatelessWidget {
  const _UpcomingScheduleItemCard({
    required this.item,
    required this.sectionBadgeLabel,
    required this.onTap,
  });

  final CustomSchedule item;
  final String sectionBadgeLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final title = _personalSchedulesCardTitle(item.title);
    final startTime = item.startTime.toLocal();
    final endTime = item.endTime?.toLocal();
    final isComplete = item.isDone || !startTime.isAfter(DateTime.now());
    final titleStyle = TextStyle(
      fontWeight: FontWeight.w600,
      decoration: isComplete ? TextDecoration.lineThrough : null,
      color: isComplete
          ? BracuPalette.textSecondary(context)
          : BracuPalette.textPrimary(context),
    );
    final timeColor = isComplete
        ? BracuPalette.textSecondary(context)
        : BracuPalette.textPrimary(context);

    return InkWell(
      borderRadius: BorderRadius.circular(18),
      splashFactory: NoSplash.splashFactory,
      overlayColor: const WidgetStatePropertyAll(Colors.transparent),
      onTap: onTap,
      child: BracuCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Align(
                  alignment: Alignment.center,
                  child: SectionBadge(
                    label: sectionBadgeLabel,
                    color: BracuPalette.primary,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 7,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text.rich(
                        TextSpan(
                          children: [TextSpan(text: title, style: titleStyle)],
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        endTime == null
                            ? DateFormat('hh:mm a').format(startTime)
                            : '${DateFormat('hh:mm a').format(startTime)} - ${DateFormat('hh:mm a').format(endTime)}',
                        style: TextStyle(
                          color: timeColor,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
              ],
            ),
            if (item.notes.trim().isNotEmpty) ...[
              const SizedBox(height: 10),
              Divider(
                height: 1,
                thickness: 1,
                color: BracuPalette.textSecondary(
                  context,
                ).withValues(alpha: 0.14),
              ),
              const SizedBox(height: 8),
              Text(
                item.notes.trim(),
                softWrap: true,
                style: TextStyle(
                  fontSize: 12,
                  height: 1.35,
                  color: BracuPalette.textSecondary(context),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

String _personalSchedulesCardTitle(String rawTitle) {
  return personalSchedulesCardTitle(rawTitle);
}

String _normalizeMyTitleForSave(String rawTitle) {
  return personalSchedulesNormalizeTitleForSave(rawTitle);
}

String _personalSchedulesSectionBadgeLabel(
  CustomSchedule item,
  List<CustomSchedulesCourseOption> courseOptions,
) {
  return personalSchedulesSectionBadgeLabel(item, courseOptions);
}
