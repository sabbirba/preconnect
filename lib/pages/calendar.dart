import 'dart:async';

import 'package:flutter/material.dart';
import 'package:gap/gap.dart';
import 'package:intl/intl.dart';
import 'package:preconnect/api/calendar.dart';
import 'package:preconnect/model/calendar_info.dart';
import 'package:preconnect/pages/shared_widgets/scroll_helper.dart';
import 'package:preconnect/pages/ui_kit.dart';
import 'package:preconnect/tools/refresh_bus.dart';

class CalendarPage extends StatefulWidget {
  const CalendarPage({super.key});

  @override
  State<CalendarPage> createState() => _CalendarPageState();
}

class _CalendarPageState extends State<CalendarPage> with RefreshBusState {
  late Future<CalendarFeed?> _future;
  CalendarFeed? _lastFeed;
  final ScrollController _scrollController = ScrollController();
  late final HighlightScrollCoordinator _highlightScroll =
      HighlightScrollCoordinator(scrollController: _scrollController);

  @override
  void initState() {
    super.initState();
    unawaited(_loadCachedFeed());
    _future = CalendarService().getCalendar();
    bindRefreshBus(_onRefreshSignal);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    unbindRefreshBus(_onRefreshSignal);
    super.dispose();
  }

  void _onRefreshSignal() {
    if (!mounted) return;
    if (isRefreshingFrom('calendar')) return;
    _refresh(notify: false);
  }

  Future<void> _loadCachedFeed() async {
    final cached = await CalendarService().getCachedCalendar();
    if (!mounted || cached == null) return;
    setState(() {
      _lastFeed = cached;
    });
  }

  Future<void> _refresh({bool notify = true}) async {
    final next = CalendarService().fetchCalendar(fallback: _lastFeed);
    setState(() {
      _highlightScroll.resetScrollState();
      _future = next;
    });
    final refreshed = await next;
    if (!mounted) return;
    setState(() {
      _lastFeed = refreshed;
    });
    if (notify) {
      RefreshBus.instance.notify(reason: 'calendar');
    }
  }

  @override
  Widget build(BuildContext context) {
    return BracuPageScaffold(
      title: 'Calendar',
      subtitle: 'Events',
      icon: Icons.calendar_today_outlined,
      body: FutureBuilder<CalendarFeed?>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.hasError && _lastFeed == null) {
            return buildRefreshErrorState(
              onRefresh: _refresh,
              topSpacing: 180,
              error: snapshot.error,
            );
          }

          final feed = _lastFeed ?? snapshot.data;
          if (snapshot.connectionState == ConnectionState.waiting &&
              feed == null) {
            return buildRefreshLoadingState(
              onRefresh: _refresh,
              topSpacing: 180,
            );
          }
          final items = feed?.items ?? const <CalendarEntry>[];
          if (items.isEmpty) {
            return buildRefreshEmptyState(
              onRefresh: _refresh,
              topSpacing: 180,
              message: 'No calendar data available.',
            );
          }

          final grouped = _groupByDate(items);
          final today = DateTime.now();
          final todayKey = DateTime(today.year, today.month, today.day);
          final sortedDates = grouped.keys.toList()..sort();
          DateTime? targetDate;
          if (grouped.containsKey(todayKey)) {
            targetDate = todayKey;
          } else {
            for (final date in sortedDates) {
              if (!date.isBefore(todayKey)) {
                targetDate = date;
                break;
              }
            }
            targetDate ??= sortedDates.isNotEmpty ? sortedDates.last : null;
          }
          final highlightToken = targetDate == null
              ? null
              : 'focus_${targetDate.year}_${targetDate.month}_${targetDate.day}';
          final targetIndex = targetDate == null
              ? null
              : sortedDates.indexOf(targetDate);
          _highlightScroll.clearHighlightKey();
          final children = <Widget>[];
          for (final entry in grouped.entries) {
            final isTargetSection =
                targetDate != null && entry.key == targetDate;
            children.add(
              Padding(
                padding: const EdgeInsets.only(bottom: 18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: BracuSectionTitle(title: _dayLabel(entry.key)),
                        ),
                        Text(
                          formatLongDate(entry.key),
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: BracuPalette.textPrimary(context),
                          ),
                        ),
                      ],
                    ),
                    const Gap(10),
                    ...entry.value.asMap().entries.map((itemEntry) {
                      final isTargetCard =
                          isTargetSection && itemEntry.key == 0;
                      _highlightScroll.markHighlighted(isTargetCard);
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: _CalendarCard(
                          key: isTargetCard
                              ? _highlightScroll.highlightKey
                              : null,
                          item: itemEntry.value,
                          isHighlighted: false,
                        ),
                      );
                    }),
                  ],
                ),
              ),
            );
          }
          final content = BracuRefreshScroll(
            onRefresh: _refresh,
            controller: _scrollController,
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: children,
            ),
          );
          if (highlightToken != null) {
            unawaited(
              _highlightScroll.scrollToTarget(
                targetToken: highlightToken,
                targetIndex: targetIndex,
                itemCount: sortedDates.length,
                onRetryBuild: () {
                  if (mounted) {
                    setState(() {});
                  }
                },
              ),
            );
          }
          return content;
        },
      ),
    );
  }

  Map<DateTime, List<CalendarEntry>> _groupByDate(List<CalendarEntry> items) {
    final grouped = <DateTime, List<CalendarEntry>>{};
    for (final item in items) {
      final raw = item.primaryDate.trim();
      final parsed = DateTime.tryParse(raw);
      if (parsed == null) continue;
      final key = DateTime(parsed.year, parsed.month, parsed.day);
      grouped.putIfAbsent(key, () => <CalendarEntry>[]).add(item);
    }
    return grouped;
  }

  String _dayLabel(DateTime date) {
    return formatRelativeDayLabel(date, includeTomorrow: true);
  }
}

class _CalendarCard extends StatelessWidget {
  const _CalendarCard({
    super.key,
    required this.item,
    this.isHighlighted = false,
  });

  final CalendarEntry item;
  final bool isHighlighted;

  @override
  Widget build(BuildContext context) {
    final textSecondary = BracuPalette.textSecondary(context);
    final badge = _badgeLabel(item);
    final badgeColor = _badgeColor(item.typeKey);
    final timeLabel = _timeLabel(item);
    final roomLabel = item.roomNumber.isNotEmpty
        ? item.roomNumber
        : item.roomName;
    final trailing = roomLabel.isNotEmpty ? roomLabel : item.place;
    final trailingSub = item.building.isNotEmpty
        ? item.building
        : item.sessionLabel;

    return BracuCard(
      isHighlighted: false,
      highlightColor: BracuPalette.primary,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: Colors.transparent,
              borderRadius: BorderRadius.circular(14),
            ),
            alignment: Alignment.center,
            child: Text(
              badge,
              style: TextStyle(
                color: badgeColor,
                fontSize: 11,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const Gap(12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildTitle(context, item),
                const Gap(4),
                Text(
                  timeLabel,
                  style: TextStyle(
                    color: BracuPalette.textPrimary(context),
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (item.department.isNotEmpty ||
                    item.faculty.isNotEmpty ||
                    item.actor.isNotEmpty) ...[
                  const Gap(4),
                  RichText(
                    text: TextSpan(
                      style: TextStyle(color: textSecondary, fontSize: 11),
                      children: [
                        if (item.faculty.isNotEmpty)
                          TextSpan(
                            text: item.faculty,
                            style: TextStyle(
                              color: BracuPalette.textPrimary(context),
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        if (item.department.isNotEmpty)
                          TextSpan(
                            text:
                                '${item.faculty.isNotEmpty ? ' • ' : ''}${item.department}',
                          ),
                        if (item.actor.isNotEmpty)
                          TextSpan(
                            text:
                                '${item.faculty.isNotEmpty || item.department.isNotEmpty ? ' • ' : ''}${item.actor}',
                          ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
          const Gap(12),
          if (trailing.trim().isNotEmpty)
            SizedBox(
              width: 96,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    trailing,
                    textAlign: TextAlign.right,
                    style: TextStyle(
                      color: BracuPalette.textPrimary(context),
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (trailingSub.trim().isNotEmpty) ...[
                    const Gap(2),
                    Text(
                      trailingSub,
                      textAlign: TextAlign.right,
                      style: TextStyle(
                        color: textSecondary,
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }

  String _badgeLabel(CalendarEntry item) {
    final key = item.typeKey.toUpperCase();
    final courseToken = _courseToken(item);
    if (key.contains('CLASS') && courseToken != null) {
      final match = RegExp(r'-(\d+)$').firstMatch(courseToken);
      if (match != null) return match.group(1) ?? 'CLS';
    }
    if (key.contains('MID')) return 'MID';
    if (key.contains('FINAL')) return 'FIN';
    if (key.contains('CLASS')) return 'CLS';
    if (key.contains('HOLIDAY')) return 'OFF';
    if (key.contains('ACADEMIC')) return 'ACD';
    if (key.contains('EXAM')) return 'EXM';
    return key.isEmpty ? 'EVT' : key.substring(0, key.length.clamp(0, 3));
  }

  String _displayLabel(CalendarEntry item) {
    final raw = item.label.trim();
    if (raw.isEmpty) return 'Untitled Event';
    final extractedCode = _courseToken(item) ?? '';
    final typeKey = item.typeKey.toUpperCase();
    if (typeKey.contains('CLASS_SCHEDULE') && extractedCode.isNotEmpty) {
      return extractedCode.replaceFirst(RegExp(r'-(\d+)$'), '');
    }
    var label = raw.replaceAll(RegExp(r'\s*\([^)]*\)\s*'), '').trim();
    return label.isEmpty ? 'Untitled Event' : label;
  }

  String? _courseToken(CalendarEntry item) {
    final raw = item.label.trim();
    if (raw.isEmpty) return null;
    final codeMatch = RegExp(r'\(([^)]+)\)').firstMatch(raw);
    final token = codeMatch?.group(1)?.trim() ?? '';
    return token.isEmpty ? null : token;
  }

  Widget _buildTitle(BuildContext context, CalendarEntry item) {
    final title = _displayLabel(item);
    final courseToken = _courseToken(item);
    final key = item.typeKey.toUpperCase();
    final textSecondary = BracuPalette.textSecondary(context);
    if (key.contains('CLASS_SCHEDULE') &&
        courseToken != null &&
        !title.endsWith('L')) {
      return Text.rich(
        TextSpan(
          children: [
            TextSpan(
              text: title,
              style: TextStyle(
                color: BracuPalette.textPrimary(context),
                fontSize: 14,
                fontWeight: FontWeight.w700,
              ),
            ),
            TextSpan(
              text: ' Theory',
              style: TextStyle(
                color: textSecondary,
                fontSize: 14,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      );
    }
    return Text(
      title,
      style: TextStyle(
        color: BracuPalette.textPrimary(context),
        fontSize: 14,
        fontWeight: FontWeight.w700,
      ),
    );
  }

  Color _badgeColor(String key) {
    final upper = key.toUpperCase();
    if (upper.contains('HOLIDAY')) return BracuPalette.danger;
    if (upper.contains('ACADEMIC')) return BracuPalette.primary;
    if (upper.contains('MID') ||
        upper.contains('FINAL') ||
        upper.contains('EXAM')) {
      return BracuPalette.accent;
    }
    if (upper.contains('CLASS')) return BracuPalette.primary;
    return BracuPalette.info;
  }

  String _timeLabel(CalendarEntry item) {
    if (item.startTime.isNotEmpty && item.endTime.isNotEmpty) {
      return '${formatTime(item.startTime)} - ${formatTime(item.endTime)}';
    }
    if (item.startDate.isNotEmpty &&
        item.endDate.isNotEmpty &&
        item.startDate == item.endDate) {
      return 'All day';
    }
    if (item.startDate.isNotEmpty &&
        item.endDate.isNotEmpty &&
        item.startDate != item.endDate) {
      final start = DateTime.tryParse(item.startDate);
      final end = DateTime.tryParse(item.endDate);
      if (start != null && end != null) {
        return '${DateFormat('d MMM').format(start)} - ${DateFormat('d MMM').format(end)}';
      }
    }
    return item.typeKey.replaceAll('_', ' ').trim();
  }
}
