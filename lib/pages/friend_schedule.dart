import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:preconnect/model/friend_schedule.dart';
import 'package:archive/archive.dart';
import 'package:preconnect/pages/home_tab.dart';
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
  List<_FriendScheduleItem> decodedSchedules = [];

  @override
  void initState() {
    super.initState();
    _loadSchedules();
  }

  Future<void> _loadSchedules() async {
    final prefs = await SharedPreferences.getInstance();
    final List<String>? encodedList = prefs.getStringList("friendSchedules");

    if (encodedList == null) return;

    List<_FriendScheduleItem> allSchedules = [];
    List<String> validEntries = [];
    final seenEntries = prefs.getStringList('friendSchedules_seen') ?? [];
    final List<_FriendScheduleItem> newSchedules = [];

    for (final base64Json in encodedList) {
      try {
        final Uint8List decodeBase64Json = base64.decode(base64Json);
        final List<int> decodeGzipJson = GZipDecoder().decodeBytes(
          decodeBase64Json,
        );
        final String originalJson = utf8.decode(decodeGzipJson);

        final parsed = jsonDecode(originalJson);
        allSchedules.add(
          _FriendScheduleItem(
            encoded: base64Json,
            friend: FriendSchedule.fromJson(parsed),
          ),
        );
        validEntries.add(base64Json);
        if (!seenEntries.contains(base64Json)) {
          newSchedules.add(
            _FriendScheduleItem(
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

  Future<void> _deleteFriendSchedule(_FriendScheduleItem item) async {
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
              gradient: const LinearGradient(
                colors: [Color(0xFF1E6BE3), Color(0xFF2C9DFF)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
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
                    children: const [
                      Icon(Icons.delete_outline, color: Colors.white),
                      SizedBox(width: 8),
                      Text(
                        'Remove Friend Schedule?',
                        style: TextStyle(
                          color: Colors.white,
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
                      color: Colors.white.withValues(alpha: 0.9),
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
                            foregroundColor: Colors.white,
                            side: BorderSide(
                              color: Colors.white.withValues(alpha: 0.7),
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
                            backgroundColor: Colors.white,
                            foregroundColor: const Color(0xFFD63B3B),
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
                _FriendActionCard(
                  icon: Icons.qr_code_scanner,
                  title: 'Scan',
                  subtitle: 'Schedule',
                  color: const Color(0xFF2AA8A8),
                  onTap: () {
                    widget.onNavigate(HomeTab.scanSchedule);
                  },
                ),
                _FriendActionCard(
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
              ...decodedSchedules.asMap().entries.map((entry) {
                final item = entry.value;
                final friend = item.friend;
                final grouped = _groupByDay(friend);
                final nextKey = _pickNextEntryKey(friend);
                final orderedDays = _orderedDays(grouped.keys.toList());
                return Padding(
                  padding: const EdgeInsets.only(bottom: 18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _FriendHeader(
                        friend: friend,
                        onDelete: () => _deleteFriendSchedule(item),
                      ),
                      const SizedBox(height: 12),
                      if (grouped.isEmpty)
                        BracuCard(
                          child: Text(
                            'No schedule shared.',
                            style: TextStyle(
                              color: BracuPalette.textSecondary(context),
                            ),
                          ),
                        )
                      else
                        ...orderedDays.map((day) {
                          final entries = grouped[day]!;
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              BracuSectionTitle(title: day),
                              const SizedBox(height: 10),
                              ...entries.map((entry) {
                                final isHighlighted =
                                    nextKey != null &&
                                    _entryKey(entry) == nextKey;
                                return Padding(
                                  padding: const EdgeInsets.only(bottom: 10),
                                  child: BracuCard(
                                    isHighlighted: isHighlighted,
                                    highlightColor: BracuPalette.accent,
                                    child: Row(
                                      children: [
                                        Container(
                                          width: 40,
                                          height: 40,
                                          decoration: BoxDecoration(
                                            color: BracuPalette.primary
                                                .withValues(alpha: 0.12),
                                            borderRadius: BorderRadius.circular(
                                              12,
                                            ),
                                          ),
                                          alignment: Alignment.center,
                                          child: Text(
                                            formatSectionBadge(
                                              entry.sectionName,
                                            ),
                                            style: const TextStyle(
                                              color: BracuPalette.primary,
                                              fontSize: 12,
                                              fontWeight: FontWeight.w700,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          flex: 7,
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                entry.courseCode,
                                                style: const TextStyle(
                                                  fontWeight: FontWeight.w600,
                                                ),
                                              ),
                                              const SizedBox(height: 4),
                                              Text(
                                                formatTimeRange(
                                                  entry.startTime,
                                                  entry.endTime,
                                                ),
                                                style: TextStyle(
                                                  color:
                                                      BracuPalette.textSecondary(
                                                        context,
                                                      ),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          flex: 4,
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.end,
                                            children: [
                                              Text(
                                                entry.roomNumber?.toString() ??
                                                    '--',
                                                textAlign: TextAlign.right,
                                                style: TextStyle(
                                                  color: BracuPalette.textPrimary(
                                                    context,
                                                  ),
                                                  fontSize: 14,
                                                  fontWeight: FontWeight.w700,
                                                ),
                                              ),
                                                if (entry.faculties != null &&
                                                    entry.faculties!
                                                        .trim()
                                                        .isNotEmpty) ...[
                                                const SizedBox(height: 2),
                                                Text(
                                                  entry.faculties!,
                                                  textAlign: TextAlign.right,
                                                  style: TextStyle(
                                                    fontSize: 12,
                                                    color:
                                                        BracuPalette.textSecondary(
                                                          context,
                                                        ),
                                                  ),
                                                ),
                                              ],
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              }),
                              const SizedBox(height: 6),
                            ],
                          );
                        }),
                    ],
                  ),
                );
              }),
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

class _FriendHeader extends StatelessWidget {
  const _FriendHeader({required this.friend, required this.onDelete});

  final FriendSchedule friend;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final textPrimary = BracuPalette.textPrimary(context);
    final textSecondary = BracuPalette.textSecondary(context);
    return BracuCard(
      child: Row(
        children: [
          _FriendAvatar(name: friend.name, photoUrl: friend.photoUrl),
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
            icon: const Icon(Icons.delete_outline),
          ),
        ],
      ),
    );
  }
}

class _FriendAvatar extends StatelessWidget {
  const _FriendAvatar({required this.name, required this.photoUrl});

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

class _FriendScheduleEntry {
  const _FriendScheduleEntry({
    required this.day,
    required this.startTime,
    required this.endTime,
    required this.courseCode,
    required this.sectionName,
    required this.roomNumber,
    required this.faculties,
  });

  final String day;
  final String startTime;
  final String endTime;
  final String courseCode;
  final String? sectionName;
  final String? roomNumber;
  final String? faculties;
}

class _FriendScheduleItem {
  const _FriendScheduleItem({required this.encoded, required this.friend});

  final String encoded;
  final FriendSchedule friend;
}

Map<String, List<_FriendScheduleEntry>> _groupByDay(FriendSchedule friend) {
  final grouped = <String, List<_FriendScheduleEntry>>{};
  for (final course in friend.courses) {
    for (final s in course.schedule) {
      grouped.putIfAbsent(s.day, () => []);
      grouped[s.day]!.add(
        _FriendScheduleEntry(
          day: s.day,
          startTime: s.startTime,
          endTime: s.endTime,
          courseCode: course.courseCode,
          sectionName: course.sectionName,
          roomNumber: course.roomNumber,
          faculties: course.faculties,
        ),
      );
    }
  }

  for (final entries in grouped.values) {
    entries.sort(
      (a, b) =>
          _timeToMinutes(a.startTime).compareTo(_timeToMinutes(b.startTime)),
    );
  }
  return grouped;
}

String _entryKey(_FriendScheduleEntry entry) {
  return [
    entry.day,
    entry.startTime,
    entry.endTime,
    entry.courseCode,
    entry.sectionName ?? '',
    entry.roomNumber ?? '',
    entry.faculties ?? '',
  ].join('|');
}

String? _pickNextEntryKey(FriendSchedule friend) {
  final now = DateTime.now();
  final nowMinutes = now.hour * 60 + now.minute;
  DateTime? nextDateTime;
  String? nextKey;

  for (final course in friend.courses) {
    for (final s in course.schedule) {
      final entry = _FriendScheduleEntry(
        day: s.day,
        startTime: s.startTime,
        endTime: s.endTime,
        courseCode: course.courseCode,
        sectionName: course.sectionName,
        roomNumber: course.roomNumber,
        faculties: course.faculties,
      );
      final candidate = _nextOccurrence(
        day: s.day,
        startTime: s.startTime,
        endTime: s.endTime,
        now: now,
        nowMinutes: nowMinutes,
      );
      if (candidate != null &&
          (nextDateTime == null || candidate.isBefore(nextDateTime))) {
        nextDateTime = candidate;
        nextKey = _entryKey(entry);
      }
    }
  }
  return nextKey;
}

DateTime? _nextOccurrence({
  required String day,
  required String startTime,
  required String endTime,
  required DateTime now,
  required int nowMinutes,
}) {
  final dayMap = {
    "MONDAY": DateTime.monday,
    "TUESDAY": DateTime.tuesday,
    "WEDNESDAY": DateTime.wednesday,
    "THURSDAY": DateTime.thursday,
    "FRIDAY": DateTime.friday,
    "SATURDAY": DateTime.saturday,
    "SUNDAY": DateTime.sunday,
  };
  final targetWeekday = dayMap[day.toUpperCase()];
  if (targetWeekday == null) return null;

  final startParts = startTime.split(':');
  if (startParts.length < 2) return null;
  final startHour = int.tryParse(startParts[0]) ?? 0;
  final startMinute = int.tryParse(startParts[1]) ?? 0;
  final startMinutes = startHour * 60 + startMinute;

  final endParts = endTime.split(':');
  final endHour = endParts.length >= 2 ? int.tryParse(endParts[0]) ?? 0 : 0;
  final endMinute = endParts.length >= 2 ? int.tryParse(endParts[1]) ?? 0 : 0;
  final endMinutes = endHour * 60 + endMinute;

  int daysAhead = (targetWeekday - now.weekday + 7) % 7;
  if (daysAhead == 0) {
    if (nowMinutes < endMinutes) {
      if (nowMinutes <= startMinutes) {
        return DateTime(now.year, now.month, now.day, startHour, startMinute);
      }
      return now;
    }
    daysAhead = 7;
  }
  final date = now.add(Duration(days: daysAhead));
  return DateTime(date.year, date.month, date.day, startHour, startMinute);
}

int _timeToMinutes(String time) {
  final parts = time.split(':');
  if (parts.length < 2) return 0;
  final hour = int.tryParse(parts[0]) ?? 0;
  final minute = int.tryParse(parts[1]) ?? 0;
  return hour * 60 + minute;
}

List<String> _orderedDays(List<String> days) {
  const order = [
    "SATURDAY",
    "SUNDAY",
    "MONDAY",
    "TUESDAY",
    "WEDNESDAY",
    "THURSDAY",
    "FRIDAY",
  ];
  final upper = days.map((d) => d.toUpperCase()).toSet();
  return order.where((d) => upper.contains(d)).toList();
}

class _FriendActionCard extends StatelessWidget {
  const _FriendActionCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textSecondary = BracuPalette.textSecondary(context);
    final textPrimary = BracuPalette.textPrimary(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        width: (MediaQuery.of(context).size.width - 52) / 2,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: BracuPalette.card(context),
          borderRadius: BorderRadius.circular(18),
          boxShadow: isDark
              ? const []
              : [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.06),
                    blurRadius: 16,
                    offset: const Offset(0, 8),
                  ),
                ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: color, size: 22),
            ),
            const SizedBox(height: 12),
            Text(
              title,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: textPrimary,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              subtitle,
              style: TextStyle(fontSize: 11, color: textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}
