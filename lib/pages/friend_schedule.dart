import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:preconnect/model/friend_schedule.dart';
import 'package:archive/archive.dart';
import 'package:preconnect/pages/home_tab.dart';
import 'package:preconnect/pages/friend_schedule_sections/friend_action_card.dart';
import 'package:preconnect/pages/friend_schedule_sections/schedule_list.dart';
import 'package:preconnect/pages/ui_kit.dart';
import 'package:preconnect/tools/local_notifications.dart';
import 'package:preconnect/tools/notification_store.dart';
import 'package:preconnect/model/notification_item.dart';

class FriendSchedulePage extends StatefulWidget {
  const FriendSchedulePage({super.key, required this.onNavigate});

  final void Function(HomeTab tab) onNavigate;

  @override
  State<FriendSchedulePage> createState() => _FriendSchedulePageState();
}

class _FriendSchedulePageState extends State<FriendSchedulePage> {
  List<FriendScheduleItem> decodedSchedules = [];

  @override
  void initState() {
    super.initState();
    _loadSchedules();
  }
  Future<void> _loadSchedules() async {
    final prefs = await SharedPreferences.getInstance();
    final List<String>? encodedList = prefs.getStringList("friendSchedules");

    if (encodedList == null) return;

    List<FriendScheduleItem> allSchedules = [];
    List<String> validEntries = [];
    final seenEntries = prefs.getStringList('friendSchedules_seen') ?? [];
    final List<FriendScheduleItem> newSchedules = [];

    for (final base64Json in encodedList) {
      try {
        final Uint8List decodeBase64Json = base64.decode(base64Json);
        final List<int> decodeGzipJson = GZipDecoder().decodeBytes(
          decodeBase64Json,
        );
        final String originalJson = utf8.decode(decodeGzipJson);

        final parsed = jsonDecode(originalJson);
        allSchedules.add(
          FriendScheduleItem(
            encoded: base64Json,
            friend: FriendSchedule.fromJson(parsed),
          ),
        );
        validEntries.add(base64Json);
        if (!seenEntries.contains(base64Json)) {
          newSchedules.add(
            FriendScheduleItem(
              encoded: base64Json,
              friend: FriendSchedule.fromJson(parsed),
            ),
          );
        }
      } catch (e) {
        // Sabbir
      }
    }

    await prefs.setStringList("friendSchedules", validEntries);
    await prefs.setStringList("friendSchedules_seen", validEntries);

    setState(() {
      decodedSchedules = allSchedules;
    });

    if (newSchedules.isNotEmpty) {
      final allEnabled = prefs.getBool('notif_all') ?? false;
      final friendEnabled = prefs.getBool('notif_friend') ?? false;
      if (allEnabled && friendEnabled) {
        for (final item in newSchedules) {
          final now = DateTime.now().toUtc();
          final id = now.millisecondsSinceEpoch.remainder(1000000000);
          final title = 'Friend Schedule Received';
          final name = item.friend.name.trim();
          final body =
              name.isEmpty ? 'A friend shared a schedule.' : '$name shared a schedule.';
          await LocalNotificationsService.instance.showLocalNotification(
            id: id,
            title: title,
            body: body,
          );
          await NotificationStore.add(
            NotificationItem(
              id: id,
              title: title,
              message: body,
              timeIso: now.toIso8601String(),
              category: 'friend',
            ),
          );
        }
      }
    }
  }

  Future<void> _handleRefresh() async {
    await _loadSchedules();
  }

  Future<void> _deleteFriendSchedule(FriendScheduleItem item) async {
    final shouldDelete = await showDialog<bool>(
      context: context,
      builder: (context) {
        final displayName = item.friend.name.trim().isEmpty
            ? 'this friend'
            : item.friend.name;
        return Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          insetPadding: const EdgeInsets.symmetric(horizontal: 24),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              color: BracuPalette.card(context),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.18),
                  blurRadius: 20,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(
                        Icons.delete_outline_rounded,
                        color: BracuPalette.primary,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Remove Friend Schedule?',
                        style: TextStyle(
                          color: BracuPalette.textPrimary(context),
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'This will remove $displayName\'s shared schedule.',
                    style: TextStyle(
                      color: BracuPalette.textSecondary(context),
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.pop(context, false),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: BracuPalette.primary,
                            side: BorderSide(
                              color: BracuPalette.primary.withValues(
                                alpha: 0.6,
                              ),
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          child: const Text('Cancel'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: () => Navigator.pop(context, true),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: BracuPalette.primary,
                            foregroundColor: Colors.white,
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          child: const Text('Remove'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );

    if (shouldDelete != true) return;

    final prefs = await SharedPreferences.getInstance();
    final List<String> current =
        prefs.getStringList("friendSchedules") ?? [];
    final updated = current.where((e) => e != item.encoded).toList();
    await prefs.setStringList("friendSchedules", updated);

    setState(() {
      decodedSchedules.removeWhere((e) => e.encoded == item.encoded);
    });
  }

  @override
  Widget build(BuildContext context) {
    final textPrimary = BracuPalette.textPrimary(context);
    return BracuPageScaffold(
      title: 'Friend Schedule',
      subtitle: 'Shared Schedules',
      icon: Icons.people_outline,
      body: RefreshIndicator(
        onRefresh: _handleRefresh,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            Text(
              'Scan & Share',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: textPrimary,
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                FriendActionCard(
                  icon: Icons.qr_code_scanner,
                  title: 'Scan',
                  subtitle: 'Schedule',
                  color: const Color(0xFF2AA8A8),
                  onTap: () {
                    widget.onNavigate(HomeTab.scanSchedule);
                  },
                ),
                FriendActionCard(
                  icon: Icons.qr_code_2,
                  title: 'Share',
                  subtitle: 'Schedule',
                  color: const Color(0xFF22B573),
                  onTap: () {
                    widget.onNavigate(HomeTab.shareSchedule);
                  },
                ),
              ],
            ),
            const SizedBox(height: 22),
            Text(
              'Friends',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: textPrimary,
              ),
            ),
            const SizedBox(height: 12),
            if (decodedSchedules.isEmpty)
              const BracuEmptyState(message: "No schedules found")
            else
              ...decodedSchedules.map(
                (item) => FriendScheduleSection(
                  item: item,
                  onDelete: () => _deleteFriendSchedule(item),
                ),
              ),
            if (decodedSchedules.isNotEmpty) ...[
              const SizedBox(height: 6),
              const SizedBox(height: 12),
            ],
          ],
        ),
      ),
    );
  }
}
