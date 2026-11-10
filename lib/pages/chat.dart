import 'dart:async';

import 'package:flutter/material.dart';
import 'package:gap/gap.dart';
import 'package:preconnect/api/chat.dart';
import 'package:preconnect/model/chat.dart';
import 'package:preconnect/pages/chat_room.dart';
import 'package:preconnect/pages/ui_kit.dart';
import 'package:preconnect/tools/app_storage.dart';
import 'package:preconnect/tools/storage_keys.dart';
import 'package:preconnect/tools/string_utils.dart';
import 'package:preconnect/tools/time_utils.dart';

class ChatPage extends StatefulWidget {
  const ChatPage({super.key, this.openRoomId});

  final String? openRoomId;

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  final ChatService _chat = ChatService.instance;
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load({bool force = false}) async {
    _chat.restoreCache();
    setState(() {
      _loading = _chat.rooms.value.isEmpty;
      _error = null;
    });
    try {
      final rooms = await _chat.loadRooms(force: force);
      if (mounted) setState(() => _loading = false);
      final target = widget.openRoomId;
      if (target != null && target.isNotEmpty && mounted) {
        final match = rooms.where((room) => room.id == target);
        if (match.isNotEmpty) unawaited(_openRoom(match.first));
      }
      await _chat.keepRoomsLive();
    } on ChatException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Chat is unavailable. Check your connection.');
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _openRoom(ChatRoom room) {
    return Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => ChatRoomPage(room: room)));
  }

  Future<void> _reload() => _load(force: true);

  @override
  Widget build(BuildContext context) {
    final semester = titleCaseWords(
      AppStorage.instance.getStringSync(StorageKeys.currentSemester) ?? '',
    );
    return AppPageScaffold(
      title: 'Chat',
      subtitle: semester.isEmpty ? 'Lounge' : semester,
      icon: Icons.chat_bubble_outline_rounded,
      actions: [
        ValueListenableBuilder<Map<String, int>>(
          valueListenable: _chat.unread,
          builder: (context, unread, _) => HeaderActionButton(
            tooltip: 'Mark All Read',
            icon: Icons.done_all_rounded,
            onTap: unread.values.any((count) => count > 0)
                ? _markAllRead
                : null,
          ),
        ),
        HeaderActionButton(
          tooltip: 'Blocked Students',
          icon: Icons.block_rounded,
          onTap: _openBlocked,
        ),
        HeaderActionButton(
          tooltip: 'Chat Rules',
          icon: Icons.info_outline_rounded,
          onTap: _showRules,
        ),
      ],
      body: _buildRooms(),
    );
  }

  Future<void> _openBlocked() {
    return Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const _BlockedStudentsPage()),
    );
  }

  Future<void> _markAllRead() async {
    try {
      await _chat.markAllRead();
    } catch (_) {
      if (mounted) showAppSnackBar(context, 'Chats could not be marked read.');
    }
  }

  Future<void> _showRules() {
    return showAppBottomSheet<void>(
      context,
      title: 'Chat Rules',
      draggable: false,
      isScrollControlled: false,
      builder: (sheetContext, textPrimary, textSecondary) => const Padding(
        padding: EdgeInsets.only(bottom: 12),
        child: _RuleList(),
      ),
    );
  }

  Widget _buildRooms() {
    if (_loading) return const AppLoading();
    if (_error != null) {
      return AppErrorState(
        title: 'Chat Unavailable',
        message: _error!,
        onRetry: _reload,
      );
    }
    return ValueListenableBuilder<List<ChatRoom>>(
      valueListenable: _chat.rooms,
      builder: (context, rooms, _) {
        return ListenableBuilder(
          listenable: Listenable.merge([
            _chat.unread,
            _chat.muted,
            _chat.blocked,
            _chat.recentVersion,
          ]),
          builder: (context, _) {
            final unread = _chat.unread.value;
            final muted = _chat.muted.value;
            final groups = <(String, List<ChatRoom>)>[
              ('', rooms.where((r) => r.kind == ChatRoomKind.lounge).toList()),
              (
                'Courses',
                rooms
                    .where((r) => r.active && r.kind == ChatRoomKind.course)
                    .toList(),
              ),
              (
                'Sections',
                rooms
                    .where((r) => r.active && r.kind == ChatRoomKind.section)
                    .toList(),
              ),
              (
                'Past Semesters',
                rooms
                    .where((r) => !r.active && r.kind != ChatRoomKind.lounge)
                    .toList(),
              ),
            ];
            return AppRefreshList(
              onRefresh: _reload,
              children: [
                for (final (label, list) in groups)
                  if (list.isNotEmpty) ...[
                    if (label.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(4, 8, 4, 8),
                        child: AppSectionTitle(title: label),
                      ),
                    for (final room in list) ...[
                      _RoomTile(
                        room: room,
                        subtitle: _roomSubtitle(room),
                        muted: muted.contains(room.id),
                        unread: unread[room.id] ?? 0,
                        onTap: () => _openRoom(room),
                      ),
                      const Gap(8),
                    ],
                  ],
              ],
            );
          },
        );
      },
    );
  }
}

String _roomSubtitle(ChatRoom room) {
  final chat = ChatService.instance;
  final blocked = chat.blocked.value;
  final visible = chat
      .recent(room.id)
      .messages
      .where((message) => !blocked.contains(message.author.id));
  if (visible.isEmpty) {
    if (!room.active) return 'Read only';
    return room.lastMessageAt > 0 ? ' ' : 'No messages yet';
  }
  final last = visible.last;
  final sender = last.author.id == chat.me?.id
      ? 'You'
      : last.author.name.split(' ').first;
  return '$sender: ${last.text.isEmpty ? 'Photo' : last.text}';
}

String _roomTime(int lastMessageAt) {
  if (lastMessageAt <= 0) return '';
  final at = DateTime.fromMillisecondsSinceEpoch(lastMessageAt);
  final now = DateTime.now();
  final days = DateUtils.dateOnly(
    now,
  ).difference(DateUtils.dateOnly(at)).inDays;
  if (days == 0) return AppTime.formatDateTime(at);
  if (days < 7) return formatRelativeDayLabel(at, includeYesterday: true);
  return AppTime.formatDayMonth(at);
}

class _RoomTile extends StatelessWidget {
  const _RoomTile({
    required this.room,
    required this.subtitle,
    required this.muted,
    required this.unread,
    required this.onTap,
  });

  static const double _leadingSize = 32;

  final ChatRoom room;
  final String subtitle;
  final bool muted;
  final int unread;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final textSecondary = AppPalette.textSecondary(context);
    final isSection = room.kind == ChatRoomKind.section;
    final dash = room.title.lastIndexOf('-');
    final title = isSection && dash > 0
        ? room.title.substring(0, dash)
        : room.title;
    final time = _roomTime(room.lastMessageAt);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: AppCard(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              if (isSection)
                SectionBadge(
                  label: dash > 0 ? room.title.substring(dash + 1) : '',
                  color: AppPalette.primary,
                  size: _leadingSize,
                  fontSize: 13,
                )
              else
                SizedBox.square(
                  dimension: _leadingSize,
                  child: Icon(
                    room.kind == ChatRoomKind.lounge
                        ? Icons.forum_outlined
                        : Icons.tag_rounded,
                    size: 20,
                    color: AppPalette.primary,
                  ),
                ),
              const Gap(10),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              color: AppPalette.textPrimary(context),
                            ),
                          ),
                        ),
                        if (muted)
                          Padding(
                            padding: const EdgeInsets.only(left: 6),
                            child: Icon(
                              Icons.notifications_off_outlined,
                              size: 14,
                              color: textSecondary,
                            ),
                          ),
                        if (time.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(left: 6),
                            child: Text(
                              time,
                              style: TextStyle(
                                fontSize: 11,
                                color: textSecondary,
                              ),
                            ),
                          ),
                      ],
                    ),
                    const Gap(2),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12, color: textSecondary),
                    ),
                  ],
                ),
              ),
              const Gap(6),
              ConstrainedBox(
                constraints: const BoxConstraints(minWidth: 24),
                child: Center(
                  widthFactor: 1,
                  child: unread > 0
                      ? UnreadCountPill(count: unread)
                      : Icon(Icons.chevron_right, color: textSecondary),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RuleList extends StatelessWidget {
  const _RuleList();

  static const List<String> _rules = <String>[
    'Only signed-in BRACU students can join. You are added to the Lounge and to your own course and section rooms automatically.',
    'Your BRACU name and profile photo are shown with your messages.',
    'Messages and photos are kept for 180 days, then deleted automatically. They cannot be edited or deleted before then.',
    'Be respectful. No harassment, hate, spam or sharing other people\'s private information.',
    'Report messages that break these rules. Reported students can be blocked from posting.',
    'PreConnect is a student-run project and is not affiliated with BRAC University.',
  ];

  @override
  Widget build(BuildContext context) {
    final textSecondary = AppPalette.textSecondary(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final rule in _rules) ...[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Icon(Icons.circle, size: 6, color: AppPalette.primary),
              ),
              const Gap(10),
              Expanded(
                child: Text(
                  rule,
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.4,
                    color: textSecondary,
                  ),
                ),
              ),
            ],
          ),
          const Gap(10),
        ],
      ],
    );
  }
}

class _BlockedStudentsPage extends StatefulWidget {
  const _BlockedStudentsPage();

  @override
  State<_BlockedStudentsPage> createState() => _BlockedStudentsPageState();
}

class _BlockedStudentsPageState extends State<_BlockedStudentsPage> {
  final ChatService _chat = ChatService.instance;
  late Future<List<ChatAuthor>> _future = _chat.loadBlockedStudents();

  void _reload() => setState(() => _future = _chat.loadBlockedStudents());

  Future<void> _unblock(ChatAuthor student) async {
    try {
      await _chat.unblock(student.id);
      if (mounted) setState(() {});
    } catch (_) {
      if (mounted) showAppSnackBar(context, 'Could not unblock. Try again.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppPageScaffold(
      title: 'Blocked Students',
      subtitle: 'People you have blocked',
      icon: Icons.block_rounded,
      body: FutureBuilder<List<ChatAuthor>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const AppLoading();
          }
          if (snapshot.hasError) {
            return AppErrorState(
              title: 'Unavailable',
              message: 'Your blocklist could not be loaded.',
              onRetry: _reload,
            );
          }
          final students = (snapshot.data ?? const <ChatAuthor>[])
              .where((student) => _chat.blocked.value.contains(student.id))
              .toList();
          if (students.isEmpty) {
            return const AppEmptyState(
              message: 'You have not blocked anyone.',
              icon: Icons.block_rounded,
            );
          }
          return AppRefreshList(
            onRefresh: () async {
              _reload();
              await _future;
            },
            children: [
              for (final student in students) ...[
                ActionBannerCard(
                  icon: Icons.person_outline_rounded,
                  title: student.name.isEmpty ? 'Student' : student.name,
                  subtitle: 'Blocked',
                  showTrailingIcon: false,
                  onTap: () {},
                  trailing: AppActionButton(
                    label: 'Unblock',
                    onPressed: () => _unblock(student),
                  ),
                ),
                const Gap(10),
              ],
            ],
          );
        },
      ),
    );
  }
}
