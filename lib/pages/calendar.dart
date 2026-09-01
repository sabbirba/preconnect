import 'dart:async';

import 'package:flutter/material.dart';
import 'package:gap/gap.dart';
import 'package:intl/intl.dart';
import 'package:preconnect/api/calendar.dart';
import 'package:preconnect/model/calendar_info.dart';
import 'package:preconnect/pages/shared_widgets/scroll_helper.dart';
import 'package:preconnect/pages/ui_kit.dart';
import 'package:preconnect/tools/refresh_bus.dart';
import 'package:preconnect/tools/time_utils.dart';

CalendarEntry? currentOrUpcomingCalendarEntry(
  Iterable<CalendarEntry> items,
  DateTime now,
) {
  CalendarEntry? target;
  DateTime? targetTime;
  for (final item in items) {
    if (item.isCancelled) continue;
    final date = BracuTime.parseDate(item.primaryDate);
    if (date == null) continue;
    final day = DateTime(date.year, date.month, date.day);
    final today = DateTime(now.year, now.month, now.day);
    if (day.isBefore(today)) continue;

    DateTime effectiveTime;
    final start = BracuTime.parseDateTime(item.primaryDate, item.startTime);
    final end = BracuTime.parseDateTime(item.primaryDate, item.endTime);
    if (day == today) {
      if (end != null && end.isBefore(now)) continue;
      if (start == null) {
        effectiveTime = now;
      } else {
        effectiveTime = start.isAfter(now) ? start : now;
      }
    } else {
      effectiveTime = start ?? day;
    }
    if (targetTime == null || effectiveTime.isBefore(targetTime)) {
      target = item;
      targetTime = effectiveTime;
    }
  }
  return target;
}

class CalendarPage extends StatefulWidget {
  const CalendarPage({super.key});

  @override
  State<CalendarPage> createState() => _CalendarPageState();
}

class _CalendarPageState extends State<CalendarPage> with RefreshBusState {
  late Future<CalendarFeed?> _future;
  CalendarFeed? _lastFeed;
  bool _isRefreshing = false;
  final ScrollController _scrollController = ScrollController();
  late final HighlightScrollCoordinator _highlightScroll =
      HighlightScrollCoordinator(scrollController: _scrollController);

  @override
  void initState() {
    super.initState();
    final syncFeed = CalendarService().getCachedCalendarSync();
    if (syncFeed != null) {
      _lastFeed = syncFeed;
      _future = Future<CalendarFeed?>.value(syncFeed);
    } else {
      _future = CalendarService().getCalendar();
    }
    unawaited(_loadCachedFeed());
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
    if (!mounted) return;
    setState(() {
      _lastFeed = cached;
    });
  }

  Future<void> _refresh({bool notify = true}) async {
    if (_isRefreshing) return;
    setState(() {
      _isRefreshing = true;
      _highlightScroll.resetScrollState();
    });
    final next = CalendarService().fetchCalendar(fallback: _lastFeed);
    setState(() {
      _future = next;
    });
    final refreshed = await next;
    if (!mounted) return;
    setState(() {
      _lastFeed = refreshed;
      _isRefreshing = false;
    });
    if (notify) {
      RefreshBus.instance.notify(reason: 'calendar');
    }
  }

  @override
  Widget build(BuildContext context) {
    return BracuPageScaffold(
      title: 'Academic Events',
      subtitle: 'Events',
      icon: Icons.calendar_today_outlined,
      actions: [
        BracuRefreshButton(
          onPressed: () => _refresh(),
          isLoading: _isRefreshing,
        ),
      ],
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
          final sortedDates = grouped.keys.toList()..sort();
          final targetItem = currentOrUpcomingCalendarEntry(
            items,
            DateTime.now(),
          );
          final targetDateValue = targetItem == null
              ? null
              : BracuTime.parseDate(targetItem.primaryDate);
          final targetDate = targetDateValue == null
              ? null
              : DateTime(
                  targetDateValue.year,
                  targetDateValue.month,
                  targetDateValue.day,
                );
          final highlightToken = targetItem == null || targetDate == null
              ? null
              : 'focus_${targetDate.year}_${targetDate.month}_${targetDate.day}_${targetItem.id}';
          final targetIndex = targetDate == null
              ? null
              : sortedDates.indexOf(targetDate);
          _highlightScroll.clearHighlightKey();
          final sections = sortedDates
              .map((date) {
                final dateItems = grouped[date]!;
                final isTargetSection = targetDate == date;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: BracuSectionTitle(title: _dayLabel(date)),
                          ),
                          Text(
                            formatLongDate(date),
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: BracuPalette.textPrimary(context),
                            ),
                          ),
                        ],
                      ),
                      const Gap(12),
                      ...dateItems.asMap().entries.map((itemEntry) {
                        final isTargetCard =
                            isTargetSection &&
                            identical(itemEntry.value, targetItem);
                        _highlightScroll.markHighlighted(isTargetCard);
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: _CalendarCard(
                            key: isTargetCard
                                ? _highlightScroll.highlightKey
                                : null,
                            item: itemEntry.value,
                            isHighlighted: isTargetCard,
                          ),
                        );
                      }),
                    ],
                  ),
                );
              })
              .toList(growable: false);
          final content = BracuRefreshList(
            onRefresh: _refresh,
            controller: _scrollController,
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
            children: sections,
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
    for (final entries in grouped.values) {
      entries.sort((a, b) {
        final aStart = BracuTime.toMinutes(a.startTime) ?? -1;
        final bStart = BracuTime.toMinutes(b.startTime) ?? -1;
        if (aStart != bStart) return aStart.compareTo(bStart);
        return a.label.compareTo(b.label);
      });
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
      isHighlighted: isHighlighted,
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
    final label = raw.replaceAll(RegExp(r'\s*\([^)]*\)\s*'), '').trim();
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
        return '${DateFormat('d MMMM').format(start)} - ${DateFormat('d MMMM').format(end)}';
      }
    }
    return item.typeKey.replaceAll('_', ' ').trim();
  }
}
