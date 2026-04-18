// ignore_for_file: use_build_context_synchronously

import 'dart:async';

import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_alarmkit/flutter_alarmkit.dart';
import 'package:intl/intl.dart';
import 'package:preconnect/api/schedule_service.dart';
import 'package:preconnect/api/schedule_planner_service.dart';
import 'package:preconnect/model/schedule_planner_item.dart';
import 'package:preconnect/pages/ui_kit.dart';
import 'package:preconnect/pages/schedule_planner_sections/schedule_planner_editor_sheet.dart'
    show showSchedulePlannerEditorSheet;
import 'package:preconnect/pages/schedule_planner_sections/schedule_planner_shared.dart';
import 'package:preconnect/tools/refresh_bus.dart';

class SchedulePlannerPage extends StatefulWidget {
  const SchedulePlannerPage({super.key});

  @override
  State<SchedulePlannerPage> createState() => _SchedulePlannerPageState();
}

class _SchedulePlannerPageState extends State<SchedulePlannerPage>
    with RefreshBusState, WidgetsBindingObserver {
  static const MethodChannel _androidAlarmChannel = MethodChannel(
    'preconnect/android_alarm',
  );
  static const Duration _autoRefreshInterval = Duration(seconds: 20);
  late Future<List<SchedulePlannerItem>> _future;
  late Future<List<SchedulePlannerCourseOption>> _courseOptionsFuture;
  List<SchedulePlannerItem>? _latestItems;
  List<SchedulePlannerCourseOption> _latestCourseOptions =
      const <SchedulePlannerCourseOption>[];
  bool _isBusy = false;
  Timer? _autoRefreshTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _future = _loadItems();
    _courseOptionsFuture = _loadCourseOptions();
    unawaited(_primeCachedItems());
    _autoRefreshTimer = Timer.periodic(_autoRefreshInterval, (_) {
      if (!mounted || _isBusy) return;
      unawaited(_refresh(forceRefresh: true, notify: false));
    });
    bindRefreshBus(_onRefreshSignal);
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
    unawaited(_refresh(forceRefresh: false, notify: false));
  }

  Future<List<SchedulePlannerItem>> _loadItems({
    bool forceRefresh = false,
  }) async {
    try {
      final service = SchedulePlannerService();
      final items = await service.getItems(forceRefresh: forceRefresh);
      return service.autoCompleteOverdueItems(items);
    } catch (e) {
      final cached = await SchedulePlannerService().getCachedItems();
      return cached ?? const <SchedulePlannerItem>[];
    }
  }

  Future<void> _primeCachedItems() async {
    final cached = await SchedulePlannerService().getCachedItems();
    if (!mounted || cached == null || cached.isEmpty) return;
    setState(() {
      _latestItems = cached;
    });
  }

  Future<List<SchedulePlannerCourseOption>> _loadCourseOptions({
    bool forceRefresh = false,
  }) async {
    try {
      final sections = await ScheduleService().getStudentSections(
        forceRefresh: forceRefresh,
      );
      final courseOptions = <SchedulePlannerCourseOption>[];
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
      return options;
    } catch (_) {
      return const <SchedulePlannerCourseOption>[];
    }
  }

  String _courseOptionIdentity(SchedulePlannerCourseOption option) {
    return '${option.courseCode}|${option.sectionName}';
  }

  Future<void> _refresh({bool forceRefresh = true, bool notify = true}) async {
    if (_isBusy) return;
    if (notify && !mounted) return;
    setState(() {
      _isBusy = true;
      _future = _loadItems(forceRefresh: forceRefresh);
      _courseOptionsFuture = _loadCourseOptions(forceRefresh: forceRefresh);
    });
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

  Future<void> _openEditor({SchedulePlannerItem? item}) async {
    final currentContext = context;
    final courseOptions = await _courseOptionsFuture;
    final draft = await showSchedulePlannerEditorSheet(
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
            return _setPlannerAlarm(
              context: currentContext,
              courseCode: courseCode,
              title: title,
              reminderAt: reminderAt,
            );
          },
    );
    if (draft == null || !mounted) return;

    final kindLabel = schedulePlannerFormatKind(draft.kind);
    try {
      final normalizedTitle = _normalizePlannerTitleForSave(draft.title);
      if (item == null) {
        await SchedulePlannerService().createItem(
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
        await SchedulePlannerService().updateItem(
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

  Future<void> _setDoneStatus(SchedulePlannerItem item, bool done) async {
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
      final updated = await SchedulePlannerService().updateItem(
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
        'Unable to update ${schedulePlannerFormatKind(item.kind).toLowerCase()}',
      );
    } finally {
      if (mounted) {
        setState(() {
          _isBusy = false;
        });
      }
    }
  }

  Future<void> _deleteItem(SchedulePlannerItem item) async {
    final currentContext = context;
    final kindLabel = schedulePlannerFormatKind(item.kind).toLowerCase();
    final shouldDelete = await showBracuConfirmationDialog(
      currentContext,
      icon: Icons.delete_outline_rounded,
      title: 'Delete $kindLabel?',
      message: 'This will remove this $kindLabel from your schedule.',
      confirmLabel: 'Delete',
    );
    if (!shouldDelete || !mounted) return;

    try {
      await SchedulePlannerService().deleteItem(item.itemId);
      if (!mounted) return;
      showAppSnackBar(
        currentContext,
        '${schedulePlannerFormatKind(item.kind)} deleted',
      );
      RefreshBus.instance.notify(reason: 'schedule');
      await _refresh(forceRefresh: true, notify: false);
    } catch (_) {
      if (!mounted) return;
      showAppSnackBar(
        currentContext,
        'Unable to delete ${schedulePlannerFormatKind(item.kind).toLowerCase()}',
      );
    }
  }

  Future<void> _setPlannerAlarm({
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
        : 'Planner';
    final messageTitle = title.trim().isNotEmpty ? title.trim() : labelCode;
    final message = messageTitle;

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
      title: 'Planner',
      subtitle: 'Schedules',
      icon: Icons.event_note_outlined,
      actions: [
        IconButton(
          tooltip: 'Add planner schedule',
          onPressed: _openEditor,
          icon: const Icon(Icons.add_rounded),
        ),
      ],
      body: FutureBuilder<List<SchedulePlannerItem>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting &&
              _latestItems == null) {
            return buildRefreshLoadingState(
              onRefresh: () => _refresh(forceRefresh: true),
              topSpacing: 180,
            );
          }

          if (snapshot.hasError && _latestItems == null) {
            return buildRefreshErrorState(
              onRefresh: () => _refresh(forceRefresh: true),
              topSpacing: 180,
              error: snapshot.error,
            );
          }

          final items =
              _latestItems ?? snapshot.data ?? const <SchedulePlannerItem>[];
          if (_latestItems == null &&
              snapshot.hasData &&
              snapshot.data != null) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted || _latestItems != null) return;
              setState(() {
                _latestItems = List<SchedulePlannerItem>.from(snapshot.data!);
              });
            });
          }
          final dayGroups = _groupItemsByDay(items);

          if (items.isEmpty) {
            return BracuRefreshScroll(
              onRefresh: () => _refresh(forceRefresh: true),
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
              child: _PlannerContentWrap(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: const [
                    BracuEmptyState(
                      message: 'No planner schedules yet. Tap + to add one.',
                    ),
                  ],
                ),
              ),
            );
          }

          return BracuRefreshScroll(
            onRefresh: () => _refresh(forceRefresh: true),
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
            child: _PlannerContentWrap(
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
                          sectionBadgeLabel: _plannerSectionBadgeLabel(
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

  List<_PlannerDayGroup> _groupItemsByDay(List<SchedulePlannerItem> items) {
    final grouped = <DateTime, List<SchedulePlannerItem>>{};
    for (final item in items) {
      final localDueAt = item.startTime.toLocal();
      final date = DateTime(localDueAt.year, localDueAt.month, localDueAt.day);
      grouped.putIfAbsent(date, () => <SchedulePlannerItem>[]).add(item);
    }

    final groups =
        grouped.entries
            .map(
              (entry) => _PlannerDayGroup(
                date: entry.key,
                items: List<SchedulePlannerItem>.from(entry.value)
                  ..sort(_comparePlannerItems),
              ),
            )
            .toList()
          ..sort((a, b) => a.date.compareTo(b.date));

    return groups;
  }

  int _comparePlannerItems(SchedulePlannerItem a, SchedulePlannerItem b) {
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

class _PlannerContentWrap extends StatelessWidget {
  const _PlannerContentWrap({required this.child});

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

class _PlannerDayGroup {
  const _PlannerDayGroup({required this.date, required this.items});

  final DateTime date;
  final List<SchedulePlannerItem> items;
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

  final SchedulePlannerItem item;
  final String sectionBadgeLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final title = _plannerCardTitle(item.title);
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

String _plannerCardTitle(String rawTitle) {
  return schedulePlannerCardTitle(rawTitle);
}

String _normalizePlannerTitleForSave(String rawTitle) {
  return schedulePlannerNormalizeTitleForSave(rawTitle);
}

String _plannerSectionBadgeLabel(
  SchedulePlannerItem item,
  List<SchedulePlannerCourseOption> courseOptions,
) {
  return schedulePlannerSectionBadgeLabel(item, courseOptions);
}
