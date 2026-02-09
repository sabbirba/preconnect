import 'package:flutter/material.dart';
import 'package:preconnect/pages/shared_widgets/leading_icon_badge.dart';
import 'package:preconnect/pages/ui_kit.dart';

class NotificationTileItem {
  const NotificationTileItem({
    required this.title,
    required this.message,
    required this.time,
    required this.icon,
    required this.color,
  });

  final String title;
  final String message;
  final String time;
  final IconData icon;
  final Color color;
}

class NotificationTile extends StatelessWidget {
  const NotificationTile({super.key, required this.item});

  final NotificationTileItem item;

  @override
  Widget build(BuildContext context) {
    final textSecondary = BracuPalette.textSecondary(context);
    final textPrimary = BracuPalette.textPrimary(context);
    return BracuCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LeadingIconBadge(icon: item.icon, color: item.color),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.title,
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: textPrimary,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  item.message,
                  style: TextStyle(color: textSecondary, height: 1.3),
                ),
                const SizedBox(height: 8),
                Text(
                  item.time,
                  style: TextStyle(fontSize: 11, color: textSecondary),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
