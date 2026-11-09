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

class ChatPage extends StatefulWidget {
  const ChatPage({super.key, this.openRoomId});

  final String? openRoomId;

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  final ChatService _chat = ChatService.instance;
  late bool _rulesAccepted = _chat.rulesAccepted;
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (_rulesAccepted) {
      unawaited(_load());
    } else {
      unawaited(_chat.preload());
    }
  }

  Future<void> _acceptRules() async {
    setState(() => _rulesAccepted = true);
    final saved = AppStorage.instance.setBool(
      ChatService.rulesAcceptedKey,
      true,
    );
    await _load();
    try {
      await saved;
    } catch (_) {
      if (mounted) {
        showAppSnackBar(context, 'Chat rules could not be saved.');
      }
    }
  }

  Future<void> _load() async {
    setState(() {
      _loading = _chat.rooms.value.isEmpty;
      _error = null;
    });
    try {
      final rooms = await _chat.loadRooms();
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

  Future<void> _openRoom(ChatRoom room) async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => ChatRoomPage(room: room)));
    if (mounted) unawaited(_chat.refreshUnread());
  }

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
        if (_rulesAccepted)
          ValueListenableBuilder<Map<String, int>>(
            valueListenable: _chat.unread,
            builder: (context, unread, _) => _HeaderButton(
              tooltip: 'Mark All Read',
              icon: Icons.done_all_rounded,
              onPressed: unread.values.any((count) => count > 0)
                  ? _markAllRead
                  : null,
            ),
          ),
        if (_rulesAccepted)
          _HeaderButton(
            tooltip: 'Chat Rules',
            icon: Icons.info_outline_rounded,
            onPressed: _showRules,
          ),
      ],
      body: _rulesAccepted ? _buildRooms() : _ChatRules(onAccept: _acceptRules),
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
        onRetry: _load,
      );
    }
    return ValueListenableBuilder<List<ChatRoom>>(
      valueListenable: _chat.rooms,
      builder: (context, rooms, _) {
        return ListenableBuilder(
          listenable: Listenable.merge([_chat.unread, _chat.muted]),
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
              onRefresh: _load,
              children: [
                for (final (label, list) in groups)
                  if (list.isNotEmpty) ...[
                    if (label.isNotEmpty) _GroupLabel(label: label),
                    for (final room in list) ...[
                      ActionBannerCard(
                        icon: _roomIcon(room.kind),
                        title: room.title,
                        subtitle: _roomSubtitle(room, muted.contains(room.id)),
                        trailing: (unread[room.id] ?? 0) > 0
                            ? UnreadCountPill(count: unread[room.id]!)
                            : null,
                        onTap: () => _openRoom(room),
                      ),
                      const Gap(10),
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

IconData _roomIcon(ChatRoomKind kind) => switch (kind) {
  ChatRoomKind.lounge => Icons.chat_bubble_outline_rounded,
  ChatRoomKind.course => Icons.book_outlined,
  ChatRoomKind.section => Icons.people_outline_rounded,
};

String _roomSubtitle(ChatRoom room, bool muted) {
  if (!room.active) return 'Read only';
  return switch (room.kind) {
    ChatRoomKind.lounge => 'Everyone · Mentions only',
    ChatRoomKind.course => muted ? 'All sections · Muted' : 'All sections',
    ChatRoomKind.section => muted ? 'Your section · Muted' : 'Your section',
  };
}

class _GroupLabel extends StatelessWidget {
  const _GroupLabel({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 6, 4, 8),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w700,
          color: AppPalette.textSecondary(context),
        ),
      ),
    );
  }
}

class _HeaderButton extends StatelessWidget {
  const _HeaderButton({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
      visualDensity: VisualDensity.compact,
      icon: Icon(
        icon,
        color: onPressed == null
            ? AppPalette.textSecondary(context)
            : AppPalette.primary,
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

class _ChatRules extends StatelessWidget {
  const _ChatRules({required this.onAccept});

  final Future<void> Function() onAccept;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: kPageListPadding,
      children: [
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Chat Rules',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: AppPalette.textPrimary(context),
                ),
              ),
              const Gap(12),
              const _RuleList(),
              const Gap(6),
              SizedBox(
                width: double.infinity,
                child: AppActionButton(
                  label: 'Agree and Continue',
                  outlined: false,
                  backgroundColor: AppPalette.primary,
                  foregroundColor: Colors.white,
                  onPressed: onAccept,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
