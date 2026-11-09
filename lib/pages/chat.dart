import 'dart:async';

import 'package:flutter/material.dart';
import 'package:gap/gap.dart';
import 'package:preconnect/api/chat.dart';
import 'package:preconnect/model/chat.dart';
import 'package:preconnect/pages/chat_room.dart';
import 'package:preconnect/pages/ui_kit.dart';
import 'package:preconnect/tools/app_storage.dart';

const String _rulesAcceptedKey = 'chat_rules_accepted_v1';

class ChatPage extends StatefulWidget {
  const ChatPage({super.key, this.openRoomId});

  final String? openRoomId;

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  final ChatService _chat = ChatService.instance;
  bool? _rulesAccepted;
  bool _loading = false;
  String? _error;

  Future<ChatWatch>? _watch;

  @override
  void initState() {
    super.initState();
    unawaited(_init());
  }

  @override
  void dispose() {
    unawaited(_watch?.then((watch) => watch.cancel()));
    super.dispose();
  }

  Future<void> _init() async {
    final accepted = await AppStorage.instance.getBool(_rulesAcceptedKey);
    if (!mounted) return;
    setState(() => _rulesAccepted = accepted == true);
    if (accepted == true) await _load();
  }

  Future<void> _acceptRules() async {
    await AppStorage.instance.setBool(_rulesAcceptedKey, true);
    if (!mounted) return;
    setState(() => _rulesAccepted = true);
    await _load();
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
      await (_watch ??= _chat.watchRooms()).catchError((Object error) {
        _watch = null;
        throw error;
      });
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
    return AppPageScaffold(
      title: 'Chat',
      subtitle: 'Lounge',
      icon: Icons.chat_bubble_outline_rounded,
      body: switch (_rulesAccepted) {
        null => const AppLoading(),
        false => _ChatRules(onAccept: _acceptRules),
        true => _buildRooms(),
      },
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

class _ChatRules extends StatelessWidget {
  const _ChatRules({required this.onAccept});

  final Future<void> Function() onAccept;

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
              for (final rule in _rules) ...[
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Icon(
                        Icons.circle,
                        size: 6,
                        color: AppPalette.primary,
                      ),
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
