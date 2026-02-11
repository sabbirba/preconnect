import 'package:flutter/material.dart';
import 'package:preconnect/model/friend_schedule.dart';
import 'package:preconnect/pages/ui_kit.dart';
import 'package:preconnect/tools/cached_image.dart';
import 'package:preconnect/tools/cached_image.dart';

class FriendHeaderCard extends StatelessWidget {
  const FriendHeaderCard({
    super.key,
    required this.friend,
    required this.onDelete,
    this.displayName,
    this.subtitle,
    this.isFavorite = false,
    this.onToggleFavorite,
    this.onEditNickname,
    this.onTap,
  });

  final FriendSchedule friend;
  final VoidCallback onDelete;
  final String? displayName;
  final String? subtitle;
  final bool isFavorite;
  final VoidCallback? onToggleFavorite;
  final VoidCallback? onEditNickname;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final textPrimary = BracuPalette.textPrimary(context);
    final textSecondary = BracuPalette.textSecondary(context);
    final nameToShow = displayName?.trim().isNotEmpty == true
        ? displayName!
        : (friend.name.trim().isEmpty ? 'Friend' : friend.name);
    
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: BracuCard(
        child: Row(
          children: [
            FriendAvatar(name: friend.name, photoUrl: friend.photoUrl),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      if (isFavorite) ...[
                        const Icon(
                          Icons.star_rounded,
                          color: Color(0xFFFFA726),
                          size: 18,
                        ),
                        const SizedBox(width: 4),
                      ],
                      Expanded(
                        child: Text(
                          nameToShow,
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: textPrimary,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    friend.id.trim().isEmpty ? 'ID: N/A' : 'ID: ${friend.id}',
                    style: TextStyle(fontSize: 12, color: textSecondary),
                  ),
                  if (subtitle != null) ...[  
                    const SizedBox(height: 2),
                    Text(
                      subtitle!,
                      style: TextStyle(fontSize: 12, color: textSecondary),
                    ),
                  ],
                ],
              ),
            ),
            if (onToggleFavorite != null)
              IconButton(
                tooltip: isFavorite ? 'Remove from favorites' : 'Add to favorites',
                onPressed: onToggleFavorite,
                icon: Icon(
                  isFavorite ? Icons.star_rounded : Icons.star_outline_rounded,
                  color: isFavorite ? const Color(0xFFFFA726) : null,
                ),
              ),
            if (onEditNickname != null)
              IconButton(
                tooltip: 'Edit nickname',
                onPressed: onEditNickname,
                icon: const Icon(Icons.edit_outlined),
              ),
            IconButton(
              tooltip: 'Remove schedule',
              onPressed: onDelete,
              icon: const Icon(Icons.delete_outline_rounded),
            ),
            const Icon(Icons.chevron_right),
          ],
        ),
      ),
    );
  }
}

class FriendAvatar extends StatelessWidget {
  const FriendAvatar({
    super.key,
    required this.name,
    required this.photoUrl,
    this.size = 44,
    this.radius = 14,
  });

  final String name;
  final String? photoUrl;
  final double size;
  final double radius;

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
    final fontSize = size > 50 ? 20.0 : 14.0;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: BracuPalette.primary.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(radius),
      ),
      child: photoUrl == null || photoUrl!.trim().isEmpty
          ? Center(
              child: Text(
                _initials(),
                style: TextStyle(
                  color: BracuPalette.primary,
                  fontWeight: FontWeight.w700,
                  fontSize: fontSize,
                ),
              ),
            )
          : ClipRRect(
              borderRadius: BorderRadius.circular(radius),
              child: CachedImage(
                url: photoUrl!,
                fit: BoxFit.cover,
                placeholder: Center(
                  child: Text(
                    _initials(),
                    style: TextStyle(
                      color: BracuPalette.primary,
                      fontWeight: FontWeight.w700,
                      fontSize: fontSize,
                    ),
                  ),
                ),
                error: Center(
                  child: Text(
                    _initials(),
                    style: TextStyle(
                      color: BracuPalette.primary,
                      fontWeight: FontWeight.w700,
                      fontSize: fontSize,
                    ),
                  ),
                ),
              ),
            ),
    );
  }
}
