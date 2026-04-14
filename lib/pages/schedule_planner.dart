// ignore_for_file: use_build_context_synchronously

import 'dart:async';

import 'package:flutter/material.dart';
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
    );
    if (draft == null || !mounted) return;

    try {
      if (item == null) {
        await SchedulePlannerService().createItem(
          kind: draft.kind,
          title: draft.title,
          dueAt: draft.dueAt,
          reminderAt: draft.useReminder ? draft.reminderAt : null,
          courseCode: draft.courseCode,
          notes: draft.notes,
          isDone: draft.isDone,
        );
        showAppSnackBar(currentContext, 'Item added');
      } else {
        await SchedulePlannerService().updateItem(
          itemId: item.itemId,
          kind: draft.kind,
          title: draft.title,
          dueAt: draft.dueAt,
          reminderAt: draft.useReminder ? draft.reminderAt : null,
          clearReminderAt: !draft.useReminder,
          courseCode: draft.courseCode,
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

  Future<void> _toggleDone(SchedulePlannerItem item) async {
    final currentContext = context;
    if (_isBusy) return;
    setState(() {
      _isBusy = true;
    });
    try {
      await SchedulePlannerService().updateItem(
        itemId: item.itemId,
        isDone: !item.isDone,
      );
      if (!mounted) return;
      showAppSnackBar(
        currentContext,
        item.isDone ? 'Marked as pending' : 'Marked as done',
      );
      RefreshBus.instance.notify(reason: 'schedule');
      await _refresh(forceRefresh: true, notify: false);
    } catch (_) {
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
          final pendingItems = items.where((item) => !item.isDone).toList();
          final doneItems = items.where((item) => item.isDone).toList();
          final overdueCount = pendingItems
              .where((item) => item.isOverdue)
              .length;
          final dueSoonCount = pendingItems
              .where((item) => item.isDueSoon)
              .length;

          if (items.isEmpty) {
            return BracuRefreshScroll(
              onRefresh: () => _refresh(forceRefresh: true),
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _SummaryCard(
                    totalCount: 0,
                    pendingCount: 0,
                    overdueCount: 0,
                    dueSoonCount: 0,
                  ),
                  const SizedBox(height: 16),
                  BracuCard(
                    child: Padding(
                      padding: const EdgeInsets.all(18),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'No items yet',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: BracuPalette.textPrimary(context),
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Add items and keep them synced.',
                            style: TextStyle(
                              fontSize: 13,
                              height: 1.4,
                              color: BracuPalette.textSecondary(context),
                            ),
                          ),
                          const SizedBox(height: 14),
                          ElevatedButton.icon(
                            onPressed: () => _openEditor(),
                            icon: const Icon(Icons.add_rounded),
                            label: const Text('Add'),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            );
          }

          return BracuRefreshScroll(
            onRefresh: () => _refresh(forceRefresh: true),
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _SummaryCard(
                  totalCount: items.length,
                  pendingCount: pendingItems.length,
                  overdueCount: overdueCount,
                  dueSoonCount: dueSoonCount,
                ),
                const SizedBox(height: 16),
                if (pendingItems.isNotEmpty) ...[
                  _SectionLabel(
                    title: 'Upcoming',
                    subtitle: '$overdueCount overdue, $dueSoonCount due soon',
                  ),
                  const SizedBox(height: 10),
                  ...pendingItems.map(
                    (item) => Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: _ScheduleItemCard(
                        item: item,
                        onTap: () => _openEditor(item: item),
                        onToggleDone: () => _toggleDone(item),
                        onDelete: () => _deleteItem(item),
                      ),
                    ),
                  ),
                ],
                if (doneItems.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  _SectionLabel(
                    title: 'Completed',
                    subtitle: '${doneItems.length} items',
                  ),
                  const SizedBox(height: 10),
                  ...doneItems.map(
                    (item) => Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: _ScheduleItemCard(
                        item: item,
                        onTap: () => _openEditor(item: item),
                        onToggleDone: () => _toggleDone(item),
                        onDelete: () => _deleteItem(item),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.totalCount,
    required this.pendingCount,
    required this.overdueCount,
    required this.dueSoonCount,
  });

  final int totalCount;
  final int pendingCount;
  final int overdueCount;
  final int dueSoonCount;

  @override
  Widget build(BuildContext context) {
    return BracuCard(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Schedule',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: BracuPalette.textPrimary(context),
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: _MetricPill(
                    label: 'Total',
                    value: totalCount.toString(),
                    color: const Color(0xFF1E6BE3),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _MetricPill(
                    label: 'Pending',
                    value: pendingCount.toString(),
                    color: const Color(0xFF22B573),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _MetricPill(
                    label: 'Urgent',
                    value: overdueCount.toString(),
                    color: const Color(0xFFE05252),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              '$dueSoonCount items are due in the next 48 hours.',
              style: TextStyle(
                fontSize: 13,
                color: BracuPalette.textSecondary(context),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MetricPill extends StatelessWidget {
  const _MetricPill({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: color,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: BracuPalette.textSecondary(context),
            ),
          ),
        ],
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
        Expanded(
          child: Text(
            title,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: BracuPalette.textPrimary(context),
            ),
          ),
        ),
        Text(
          subtitle,
          style: TextStyle(
            fontSize: 12,
            color: BracuPalette.textSecondary(context),
          ),
        ),
      ],
    );
  }
}

class _ScheduleItemCard extends StatelessWidget {
  const _ScheduleItemCard({
    required this.item,
    required this.onTap,
    required this.onToggleDone,
    required this.onDelete,
  });

  final SchedulePlannerItem item;
  final VoidCallback onTap;
  final VoidCallback onToggleDone;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final color = schedulePlannerKindColor(item.kind);
    final statusLabel = item.isDone
        ? 'Done'
        : item.isOverdue
        ? 'Overdue'
        : item.isDueSoon
        ? 'Due soon'
        : 'Open';

    return BracuCard(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(
                      schedulePlannerKindIcon(item.kind),
                      color: color,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: BracuPalette.textPrimary(context),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          schedulePlannerFormatKind(item.kind),
                          style: TextStyle(
                            fontSize: 12,
                            color: BracuPalette.textSecondary(context),
                          ),
                        ),
                      ],
                    ),
                  ),
                  PopupMenuButton<String>(
                    onSelected: (value) {
                      switch (value) {
                        case 'toggle':
                          onToggleDone();
                          break;
                        case 'delete':
                          onDelete();
                          break;
                      }
                    },
                    itemBuilder: (context) => [
                      PopupMenuItem(
                        value: 'toggle',
                        child: Text(
                          item.isDone ? 'Mark as pending' : 'Mark as done',
                        ),
                      ),
                      const PopupMenuItem(
                        value: 'delete',
                        child: Text('Delete'),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _StatusChip(label: statusLabel, color: color),
                  if (item.courseCode.isNotEmpty)
                    _StatusChip(
                      label: item.courseCode,
                      color: const Color(0xFF5B8DEF),
                    ),
                  _StatusChip(
                    label: schedulePlannerFormatDueDate(item.dueAt),
                    color: const Color(0xFF7C56FF),
                  ),
                ],
              ),
              if (item.notes.isNotEmpty) ...[
                const SizedBox(height: 10),
                Text(
                  item.notes,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.4,
                    color: BracuPalette.textSecondary(context),
                  ),
                ),
              ],
              if (item.reminderAt != null) ...[
                const SizedBox(height: 8),
                Text(
                  'Reminder ${schedulePlannerFormatReminder(item.reminderAt!)}',
                  style: TextStyle(
                    fontSize: 12,
                    color: BracuPalette.textSecondary(context),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }
}
