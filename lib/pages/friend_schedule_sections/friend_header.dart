import 'package:flutter/material.dart';
import 'package:preconnect/model/friend_schedule.dart';
import 'package:preconnect/pages/ui_kit.dart';

class FriendHeaderCard extends StatelessWidget {
  const FriendHeaderCard({
    super.key,
    required this.friend,
    required this.onDelete,
  });

  final FriendSchedule friend;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final textPrimary = BracuPalette.textPrimary(context);
    final textSecondary = BracuPalette.textSecondary(context);
    return BracuCard(
      child: Row(
        children: [
          FriendAvatar(name: friend.name, photoUrl: friend.photoUrl),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  friend.name.trim().isEmpty ? 'Friend' : friend.name,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: textPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  friend.id.trim().isEmpty ? 'ID: N/A' : 'ID: ${friend.id}',
                  style: TextStyle(fontSize: 12, color: textSecondary),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Remove schedule',
            onPressed: onDelete,
            icon: const Icon(Icons.delete_outline_rounded),
          ),
        ],
      ),
    );
  }
}

class FriendAvatar extends StatelessWidget {
  const FriendAvatar({super.key, required this.name, required this.photoUrl});

  final String name;
  final String? photoUrl;

  String _initials() {
    final parts = name
        .trim()
        .split(RegExp(r'\s+'))
        .where((p) => p.isNotEmpty)
        .toList();
    if (parts.isEmpty) return 'F';
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    return (parts.first.substring(0, 1) + parts[1].substring(0, 1))
        .toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: BracuPalette.primary.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(14),
      ),
      child: photoUrl == null || photoUrl!.trim().isEmpty
          ? Center(
              child: Text(
                _initials(),
                style: const TextStyle(
                  color: BracuPalette.primary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            )
          : ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: Image.network(
                photoUrl!,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) {
                  return Center(
                    child: Text(
                      _initials(),
                      style: const TextStyle(
                        color: BracuPalette.primary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  );
                },
              ),
            ),
    );
  }
}
