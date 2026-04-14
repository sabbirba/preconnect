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
import 'package:preconnect/pages/schedule_planner_sections/schedule_planner_editor_sheet.dart';
import 'package:preconnect/tools/refresh_bus.dart';

class SchedulePlannerPage extends StatefulWidget {
  const SchedulePlannerPage({super.key});

  @override
  State<SchedulePlannerPage> createState() => _SchedulePlannerPageState();
}

class _SchedulePlannerPageState extends State<SchedulePlannerPage>
    with RefreshBusState {
  static const MethodChannel _androidAlarmChannel = MethodChannel(
    'preconnect/android_alarm',
  );
  late Future<List<SchedulePlannerItem>> _future;
  late Future<List<SchedulePlannerCourseOption>> _courseOptionsFuture;
  List<SchedulePlannerItem>? _latestItems;
  bool _isBusy = false;

  @override
  void initState() {
    super.initState();
    _future = _loadItems();
    _courseOptionsFuture = _loadCourseOptions();
    bindRefreshBus(_onRefreshSignal);
  }

  @override
  void dispose() {
    unbindRefreshBus(_onRefreshSignal);
    super.dispose();
  }

  void _onRefreshSignal() {
    if (!mounted) return;
    if (isRefreshingFrom('schedule')) return;
    unawaited(_refresh(forceRefresh: false, notify: false));
  }

  Future<List<SchedulePlannerItem>> _loadItems({
    bool forceRefresh = false,
  }) async {
    final items = await SchedulePlannerService().getItems(
      forceRefresh: forceRefresh,
    );
    return items;
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

    try {
      final normalizedTitle = _normalizePlannerTitleForSave(draft.title);
      if (item == null) {
        await SchedulePlannerService().createItem(
          kind: draft.kind,
          title: normalizedTitle,
          dueAt: draft.dueAt,
          reminderAt: draft.reminderAt,
          courseCode: draft.courseCode,
          sectionName: draft.sectionName,
          notes: draft.notes,
          isDone: draft.isDone,
        );
        showAppSnackBar(currentContext, 'Item added');
      } else {
        await SchedulePlannerService().updateItem(
          itemId: item.itemId,
          kind: draft.kind,
          title: normalizedTitle,
          dueAt: draft.dueAt,
          reminderAt: draft.reminderAt,
          clearReminderAt: false,
          courseCode: draft.courseCode,
          sectionName: draft.sectionName,
          notes: draft.notes,
          isDone: draft.isDone,
        );
        showAppSnackBar(currentContext, 'Item updated');
      }
      RefreshBus.instance.notify(reason: 'schedule');
      await _refresh(forceRefresh: true, notify: false);
    } catch (_) {
      if (!mounted) return;
      showAppSnackBar(currentContext, 'Unable to save item');
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
        final dueCompare = a.dueAt.compareTo(b.dueAt);
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
          final dueCompare = a.dueAt.compareTo(b.dueAt);
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
      showAppSnackBar(currentContext, 'Unable to update item');
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
    final shouldDelete = await showBracuConfirmationDialog(
      currentContext,
      icon: Icons.delete_outline_rounded,
      title: 'Delete item?',
      message: 'This will remove the item from your schedule.',
      confirmLabel: 'Delete',
    );
    if (!shouldDelete || !mounted) return;

    try {
      await SchedulePlannerService().deleteItem(item.itemId);
      if (!mounted) return;
      showAppSnackBar(currentContext, 'Item deleted');
      RefreshBus.instance.notify(reason: 'schedule');
      await _refresh(forceRefresh: true, notify: false);
    } catch (_) {
      if (!mounted) return;
      showAppSnackBar(currentContext, 'Unable to delete item');
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
          tooltip: 'Add item',
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
          final pendingItems = items.where((item) => !item.isDone).toList();
          final doneItems = items.where((item) => item.isDone).toList();

          if (items.isEmpty) {
            return BracuRefreshScroll(
              onRefresh: () => _refresh(forceRefresh: true),
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
              child: _PlannerContentWrap(
                child: const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    BracuEmptyState(
                      message: 'No items yet. Tap + to add task.',
                    ),
                  ],
                ),
              ),
            );
          }

          return BracuRefreshScroll(
            onRefresh: () => _refresh(forceRefresh: true),
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
            child: _PlannerContentWrap(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (pendingItems.isNotEmpty) ...[
                    _DayDateHeader(date: _pendingHeaderDate(pendingItems)),
                    const SizedBox(height: 10),
                    ...pendingItems.map(
                      (item) => Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: _UpcomingScheduleItemCard(
                          item: item,
                          onTap: () => _openEditor(item: item),
                          onSetDone: () => _setDoneStatus(item, true),
                          onSetPending: () => _setDoneStatus(item, false),
                          onDelete: () => _deleteItem(item),
                        ),
                      ),
                    ),
                  ],
                  if (doneItems.isNotEmpty) ...[
                    if (pendingItems.isNotEmpty) const SizedBox(height: 16),
                    const _SectionLabel(title: 'Completed', subtitle: ''),
                    const SizedBox(height: 10),
                    ...doneItems.map(
                      (item) => Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: _UpcomingScheduleItemCard(
                          item: item,
                          onTap: () => _openEditor(item: item),
                          onSetDone: () => _setDoneStatus(item, true),
                          onSetPending: () => _setDoneStatus(item, false),
                          onDelete: () => _deleteItem(item),
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

  DateTime _pendingHeaderDate(List<SchedulePlannerItem> items) {
    if (items.isEmpty) return DateTime.now();
    return items
        .map((item) => item.dueAt)
        .reduce((a, b) => a.isBefore(b) ? a : b);
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

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(child: BracuSectionTitle(title: title)),
        if (subtitle.trim().isNotEmpty)
          Text(
            subtitle,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: BracuPalette.textSecondary(context),
            ),
          ),
      ],
    );
  }
}

class _DayDateHeader extends StatelessWidget {
  const _DayDateHeader({required this.date});

  final DateTime date;

  String _weekdayLabel(DateTime value) {
    const days = <String>[
      'Monday',
      'Tuesday',
      'Wednesday',
      'Thursday',
      'Friday',
      'Saturday',
      'Sunday',
    ];
    final index = value.weekday - 1;
    if (index < 0 || index >= days.length) return '';
    return days[index];
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(child: BracuSectionTitle(title: _weekdayLabel(date))),
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
    required this.onTap,
    required this.onSetDone,
    required this.onSetPending,
    required this.onDelete,
  });

  final SchedulePlannerItem item;
  final VoidCallback onTap;
  final VoidCallback onSetDone;
  final VoidCallback onSetPending;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final title = _plannerCardTitle(item.title);

    return InkWell(
      borderRadius: BorderRadius.circular(18),
      splashFactory: NoSplash.splashFactory,
      overlayColor: const WidgetStatePropertyAll(Colors.transparent),
      onTap: onTap,
      child: BracuCard(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Align(
              alignment: Alignment.center,
              child: SectionBadge(
                label: '${item.dueAt.day}',
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
                      children: [
                        TextSpan(
                          text: title,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    DateFormat('hh:mm a').format(item.dueAt),
                    style: TextStyle(
                      color: BracuPalette.textPrimary(context),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              flex: 4,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    item.isDone ? 'Done' : 'Pending',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: BracuPalette.textSecondary(context),
                    ),
                  ),
                  const SizedBox(height: 2),
                  _PlannerItemActionsMenu(
                    isDone: item.isDone,
                    onSetDone: onSetDone,
                    onSetPending: onSetPending,
                    onDelete: onDelete,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String _plannerCardTitle(String rawTitle) {
  final parts = rawTitle
      .split('•')
      .map((part) => part.trim())
      .where((part) => part.isNotEmpty)
      .toList();
  if (parts.length < 2) return rawTitle.trim();
  final kind = parts.last.toLowerCase();
  if (kind != 'quiz' && kind != 'assignment' && kind != 'reminder') {
    return rawTitle.trim();
  }
  return '${parts.first} • ${parts.last}';
}

String _normalizePlannerTitleForSave(String rawTitle) {
  final parts = rawTitle
      .split('•')
      .map((part) => part.trim())
      .where((part) => part.isNotEmpty)
      .toList();
  if (parts.length < 2) return rawTitle.trim();
  final kind = parts.last.toLowerCase();
  if (kind != 'quiz' && kind != 'assignment' && kind != 'reminder') {
    return rawTitle.trim();
  }
  return '${parts.first} • ${parts.last}';
}

class _PlannerItemActionsMenu extends StatelessWidget {
  const _PlannerItemActionsMenu({
    required this.isDone,
    required this.onSetDone,
    required this.onSetPending,
    required this.onDelete,
  });

  final bool isDone;
  final VoidCallback onSetDone;
  final VoidCallback onSetPending;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Builder(
      builder: (anchorContext) => InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () async {
          final action = await showBracuSelectDropdown<String>(
            anchorContext,
            optionFontSize: 16,
            optionPadding: const EdgeInsets.symmetric(
              horizontal: 14,
              vertical: 8,
            ),
            options: [
              if (!isDone)
                const BracuSelectOption<String>(
                  value: 'done',
                  label: 'Done',
                  icon: Icons.check_circle_outline_rounded,
                ),
              if (isDone)
                const BracuSelectOption<String>(
                  value: 'pending',
                  label: 'Pending',
                  icon: Icons.radio_button_unchecked_rounded,
                ),
              const BracuSelectOption<String>(
                value: 'delete',
                label: 'Delete',
                icon: Icons.delete_outline_rounded,
              ),
            ],
          );
          if (action == null) return;
          if (action == 'done') {
            onSetDone();
          } else if (action == 'pending') {
            onSetPending();
          } else if (action == 'delete') {
            onDelete();
          }
        },
        child: SizedBox(
          width: 24,
          height: 24,
          child: Center(
            child: Icon(
              Icons.more_horiz_rounded,
              size: 18,
              color: BracuPalette.textPrimary(context),
            ),
          ),
        ),
      ),
    );
  }
}
