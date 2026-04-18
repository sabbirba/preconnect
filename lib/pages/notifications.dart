import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:preconnect/api/notification_service.dart';
import 'package:preconnect/pages/notifications_sections/notification_detail_panels.dart';
import 'package:preconnect/pages/notifications_sections/notification_list_widgets.dart';
import 'package:preconnect/pages/ui_kit.dart';
import 'package:preconnect/tools/refresh_bus.dart';

class NotificationsPage extends StatefulWidget {
  const NotificationsPage({super.key});

  @override
  State<NotificationsPage> createState() => _NotificationsPageState();
}

class _NotificationsPageState extends State<NotificationsPage> {
  static const int _pageSize = 10;
  late Future<NotificationsViewData> _future;
  NotificationsViewData? _lastData;
  int _visibleItemCount = _pageSize;

  @override
  void initState() {
    super.initState();
    _future = _loadData(forceRefresh: true);
  }

  Future<NotificationsViewData> _loadData({bool forceRefresh = false}) async {
    final connectFuture =
        (forceRefresh
                ? NotificationService().fetchRecentNotifications()
                : NotificationService().getRecentNotifications())
            .catchError((e) {
              debugPrint(
                '[NOTIFICATIONS] Connect notifications load failed: $e',
              );
              return null;
            });
    final scraperFuture = NotificationService()
        .getScraperContentFeed(forceRefresh: forceRefresh)
        .catchError((e) {
          debugPrint('[NOTIFICATIONS] Scraper content load failed: $e');
          return const <ScraperContentItem>[];
        });
    final seenScraperIdsFuture = NotificationService()
        .getSeenScraperNotificationIds()
        .catchError((e) {
          debugPrint('[NOTIFICATIONS] Seen scraper IDs load failed: $e');
          return <String>{};
        });
    final results = await Future.wait<dynamic>(<Future<dynamic>>[
      connectFuture,
      scraperFuture,
      seenScraperIdsFuture,
    ]);
    return NotificationsViewData(
      connect: results[0] as NotificationsFeed?,
      scraped: results[1] as List<ScraperContentItem>,
      seenScraperIds: results[2] as Set<String>,
    );
  }

  Future<void> _refresh() async {
    final next = _loadData(forceRefresh: true);
    setState(() {
      _future = next;
      _visibleItemCount = _pageSize;
    });
    final refreshed = await next;
    if (!mounted) return;
    setState(() {
      _lastData = refreshed;
    });
    RefreshBus.instance.notify(reason: 'notifications');
  }

  Future<void> _markAllSeen() async {
    final currentData = _lastData ?? await _future;
    if (!mounted) return;

    final updated = await NotificationService().markAllSeen();
    final scraperIds = currentData.scraped.map((item) => item.id).toSet();
    await NotificationService().markAllScraperNotificationsSeen(scraperIds);

    final optimisticData = NotificationsViewData(
      connect: updated ?? currentData.connect,
      scraped: currentData.scraped,
      seenScraperIds: {...currentData.seenScraperIds, ...scraperIds},
    );

    final refreshedFuture = _loadData(forceRefresh: true);
    if (!mounted) return;
    setState(() {
      _lastData = optimisticData;
      _future = refreshedFuture;
    });

    unawaited(
      refreshedFuture.then((value) {
        if (!mounted) return;
        setState(() {
          _lastData = value;
        });
      }),
    );

    RefreshBus.instance.notify(reason: 'notifications');
    showAppSnackBar(
      context,
      updated == null
          ? 'No notifications available to mark as seen.'
          : 'All notifications marked as seen.',
    );
  }

  Future<void> _openConnectNotification(RecentConnectNotification item) async {
    if (!mounted) return;
    await showBracuBottomSheet<void>(
      context,
      title: item.title.trim().isEmpty ? 'Notification' : item.title.trim(),
      initialChildSize: 0.80,
      builder: (context, textPrimary, textSecondary) =>
          ConnectNotificationDetailPanel(notificationId: item.id),
    );
    if (!mounted) return;
    final currentData = _lastData ?? await _future;
    if (!mounted) return;
    final updatedConnect = currentData.connect?.copyWith(
      items: currentData.connect?.items
          .map(
            (entry) => entry.id == item.id && !entry.seen
                ? RecentConnectNotification(
                    id: entry.id,
                    title: entry.title,
                    module: entry.module,
                    link: entry.link,
                    createdOn: entry.createdOn,
                    expireAt: entry.expireAt,
                    seen: true,
                  )
                : entry,
          )
          .toList(),
    );
    setState(() {
      _lastData = NotificationsViewData(
        connect: updatedConnect ?? currentData.connect,
        scraped: currentData.scraped,
        seenScraperIds: currentData.seenScraperIds,
      );
    });
    RefreshBus.instance.notify(reason: 'notifications');
  }

  Future<void> _openScraperNotification(NotificationListItem item) async {
    if (!mounted) return;
    await showBracuBottomSheet<void>(
      context,
      title: item.title.trim().isEmpty ? 'Notification' : item.title.trim(),
      initialChildSize: 0.80,
      builder: (context, textPrimary, textSecondary) =>
          ScraperNotificationDetailPanel(item: item),
    );
    await NotificationService().markScraperNotificationSeen(item.id);
    if (!mounted) return;
    setState(() {
      final current = _lastData;
      if (current == null) return;
      _lastData = NotificationsViewData(
        connect: current.connect,
        scraped: current.scraped,
        seenScraperIds: {...current.seenScraperIds, item.id},
      );
    });
    RefreshBus.instance.notify(reason: 'notifications');
  }

  @override
  Widget build(BuildContext context) {
    return BracuPageScaffold(
      title: 'Notifications',
      subtitle: 'Recent Alerts',
      icon: Icons.notifications_outlined,
      actions: [
        HeaderActionButton(icon: Icons.done_all_rounded, onTap: _markAllSeen),
      ],
      body: FutureBuilder<NotificationsViewData>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting &&
              _lastData == null) {
            return buildRefreshLoadingState(
              onRefresh: _refresh,
              topSpacing: 180,
            );
          }

          final data = _lastData ?? snapshot.data;
          final connectItems =
              data?.connect?.items ?? const <RecentConnectNotification>[];
          final scrapedItems = data?.scraped ?? const <ScraperContentItem>[];
          final seenScraperIds = data?.seenScraperIds ?? const <String>{};
          final items = _buildCombinedItems(
            connectItems,
            scrapedItems,
            seenScraperIds,
          );
          if (items.isEmpty) {
            return buildRefreshEmptyState(
              onRefresh: _refresh,
              topSpacing: 180,
              message: 'No recent notifications found.',
            );
          }

          final visibleCount = math.min(_visibleItemCount, items.length);
          final visibleItems = items.take(visibleCount).toList(growable: false);
          final groupedItems = _groupItemsByDate(visibleItems);
          final hasMore = visibleCount < items.length;

          return BracuRefreshScroll(
            onRefresh: _refresh,
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ...groupedItems.entries.map(
                  (entry) => NotificationDaySection(
                    label: _dayLabel(entry.key),
                    dateLabel: _dateLabel(entry.key),
                    children: entry.value
                        .map(
                          (item) => NotificationCardItem(
                            item: item,
                            onTap: () {
                              if (item.connectItem != null) {
                                _openConnectNotification(item.connectItem!);
                                return;
                              }
                              _openScraperNotification(item);
                            },
                          ),
                        )
                        .toList(growable: false),
                  ),
                ),
                if (hasMore)
                  buildCenteredOutlinedActionButton(
                    label: 'Load More',
                    onPressed: () {
                      setState(() {
                        _visibleItemCount = math.min(
                          _visibleItemCount + _pageSize,
                          items.length,
                        );
                      });
                    },
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  List<NotificationListItem> _buildCombinedItems(
    List<RecentConnectNotification> connect,
    List<ScraperContentItem> scraped,
    Set<String> seenScraperIds,
  ) {
    final output = <NotificationListItem>[
      ...connect.map(
        (item) => NotificationListItem(
          id: 'connect_${item.id}',
          title: item.title,
          module: _moduleLabel(item.module),
          createdOn: item.createdOn,
          connectItem: item,
          details: '',
          url: item.link,
          imageUrl: null,
          imageUrls: const <String>[],
          seen: item.seen,
        ),
      ),
      ...scraped.map(
        (item) => NotificationListItem(
          id: item.id,
          title: item.title,
          module: item.source,
          createdOn: item.publishedAt,
          details: item.message,
          url: item.url,
          imageUrl: item.imageUrl,
          imageUrls: item.imageUrls,
          seen: seenScraperIds.contains(item.id),
        ),
      ),
    ];
    output.sort((a, b) {
      final aDate = a.createdOn;
      final bDate = b.createdOn;
      if (aDate == null && bDate == null) return a.title.compareTo(b.title);
      if (aDate == null) return 1;
      if (bDate == null) return -1;
      final dateCmp = bDate.compareTo(aDate);
      if (dateCmp != 0) return dateCmp;
      return a.title.compareTo(b.title);
    });
    return output;
  }

  Map<DateTime, List<NotificationListItem>> _groupItemsByDate(
    List<NotificationListItem> items,
  ) {
    final grouped = <DateTime, List<NotificationListItem>>{};
    for (final item in items) {
      final local = item.createdOn?.toLocal();
      final key = local == null
          ? DateTime(1970)
          : DateTime(local.year, local.month, local.day);
      grouped.putIfAbsent(key, () => <NotificationListItem>[]).add(item);
    }
    return grouped;
  }

  String _dayLabel(DateTime date) {
    return formatRelativeDayLabel(
      date,
      includeYesterday: true,
      unknownLabel: 'Unknown',
    );
  }

  String _dateLabel(DateTime date) {
    if (date.year == 1970) return '';
    return formatLongDate(date);
  }

  String _moduleLabel(String raw) {
    final cleaned = raw.trim().toLowerCase();
    switch (cleaned) {
      case 'fin':
        return 'Finance';
      case 'adv':
        return 'Advising';
      case 'reg':
        return 'Registration';
      case 'exc':
        return 'Exam & Course';
      default:
        return cleaned.isEmpty ? 'General' : cleaned.toUpperCase();
    }
  }
}
