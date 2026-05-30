import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:preconnect/api/notification.dart';
import 'package:preconnect/pages/ui_kit.dart';

class NotificationsViewData {
  const NotificationsViewData({
    required this.connect,
    required this.scraped,
    required this.seenScraperIds,
  });

  final NotificationsFeed? connect;
  final List<ScraperContentItem> scraped;
  final Set<String> seenScraperIds;
}

class NotificationListItem {
  const NotificationListItem({
    required this.id,
    required this.title,
    required this.module,
    required this.createdOn,
    required this.details,
    required this.url,
    required this.imageUrl,
    required this.imageUrls,
    required this.seen,
    this.connectItem,
  });

  final String id;
  final String title;
  final String module;
  final DateTime? createdOn;
  final String details;
  final String? url;
  final String? imageUrl;
  final List<String> imageUrls;
  final bool seen;
  final RecentConnectNotification? connectItem;
}

class HeaderActionButton extends StatelessWidget {
  const HeaderActionButton({
    super.key,
    required this.icon,
    required this.onTap,
  });

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: BracuPalette.primary.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, size: 20, color: BracuPalette.primary),
        ),
      ),
    );
  }
}

class NotificationCardItem extends StatelessWidget {
  const NotificationCardItem({
    super.key,
    required this.item,
    required this.onTap,
  });

  final NotificationListItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final createdLabel = _formatTime(item.createdOn);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: BracuCard(
          isHighlighted: false,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.title.isEmpty ? 'Untitled notification' : item.title,
                      style: TextStyle(
                        color: BracuPalette.textPrimary(context),
                        fontSize: 15,
                        fontWeight: item.seen
                            ? FontWeight.w700
                            : FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        if (!item.seen) ...[
                          Container(
                            width: 7,
                            height: 7,
                            decoration: const BoxDecoration(
                              color: BracuPalette.primary,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 8),
                        ],
                        Flexible(
                          child: Text(
                            item.module,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: BracuPalette.textSecondary(context),
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        if (createdLabel.isNotEmpty) ...[
                          const SizedBox(width: 8),
                          Text(
                            '•',
                            style: TextStyle(
                              color: BracuPalette.textSecondary(context),
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              createdLabel,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: BracuPalette.textSecondary(context),
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatTime(DateTime? value) {
    if (value == null) return '';
    final local = value.toLocal();
    return DateFormat('h:mm a').format(local);
  }
}

class NotificationDaySection extends StatelessWidget {
  const NotificationDaySection({
    super.key,
    required this.label,
    required this.dateLabel,
    required this.children,
  });

  final String label;
  final String dateLabel;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    label,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: BracuPalette.textPrimary(context),
                    ),
                  ),
                ),
                if (dateLabel.isNotEmpty)
                  Text(
                    dateLabel,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: BracuPalette.textPrimary(context),
                    ),
                  ),
              ],
            ),
          ),
          ...children,
        ],
      ),
    );
  }
}
