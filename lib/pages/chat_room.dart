import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:gap/gap.dart';
import 'package:image_picker/image_picker.dart';
import 'package:preconnect/api/chat.dart';
import 'package:preconnect/model/chat.dart';
import 'package:preconnect/pages/friend_sections/friend_header.dart';
import 'package:preconnect/pages/ui_kit.dart';
import 'package:preconnect/tools/string_utils.dart';
import 'package:share_plus/share_plus.dart';
import 'package:preconnect/tools/cached_image.dart';
import 'package:preconnect/tools/image_cache.dart';
import 'package:preconnect/tools/time_utils.dart';

class ChatRoomPage extends StatefulWidget {
  const ChatRoomPage({super.key, required this.room});

  final ChatRoom room;

  @override
  State<ChatRoomPage> createState() => _ChatRoomPageState();
}

class _ChatRoomPageState extends State<ChatRoomPage> {
  final ChatService _chat = ChatService.instance;
  final TextEditingController _input = TextEditingController();
  final ScrollController _scroll = ScrollController();
  final Map<String, ChatAuthor> _mentionPicks = <String, ChatAuthor>{};

  late List<ChatMessage> _messages = _chat.recent(_room.id).messages;
  late List<ChatReaction> _reactions = _chat.recent(_room.id).reactions;
  Future<ChatWatch>? _watch;
  ChatMessage? _replyTo;
  List<Uint8List> _images = const <Uint8List>[];
  late bool _loading = !_chat.hasRecent(_room.id);
  bool _loadingOlder = false;
  bool _hasMore = true;
  bool _sending = false;
  String? _error;
  Timer? _readTimer;
  Timer? _cooldownTimer;
  bool _coolingDown = false;

  ChatRoom get _room => widget.room;

  String _headerSubtitle() {
    final current = _chat.rooms.value.where((room) => room.id == _room.id);
    final count = current.isEmpty
        ? _room.memberCount
        : current.first.memberCount;
    if (count > 0) {
      return '${formatAmount(count)} ${count == 1 ? 'student' : 'students'}';
    }
    return switch (_room.kind) {
      ChatRoomKind.lounge => 'Everyone',
      ChatRoomKind.course => 'Course',
      ChatRoomKind.section => 'Section',
    };
  }

  @override
  void initState() {
    super.initState();
    _chat.activeRoomId = _room.id;
    _scroll.addListener(_onScroll);
    unawaited(_load());
  }

  @override
  void dispose() {
    if (_chat.activeRoomId == _room.id) _chat.activeRoomId = null;
    _chat.remember(_room.id, _messages, _reactions);
    _readTimer?.cancel();
    _cooldownTimer?.cancel();
    unawaited(_watch?.then((watch) => watch.cancel()));
    _scroll.dispose();
    _input.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final watch = _watch ??= _chat.watchRoom(
        _room.id,
        onMessage: _onIncoming,
        onReaction: _onReaction,
      );
      await watch.catchError((Object error) {
        _watch = null;
        throw error;
      });
      final messages = await _chat.loadMessages(_room.id);
      if (!mounted) return;
      final loaded = messages.map((m) => m.id).toSet();
      setState(() {
        _messages = _merged(messages, _messages);
        _hasMore = messages.length >= ChatService.pageSize;
        _loading = false;
        _error = null;
      });
      _markLatestRead();
      _loadOlderIfAllHidden();
      final reactions = await _chat.loadReactions(loaded.toList());
      if (!mounted) return;
      setState(() {
        _reactions = <ChatReaction>[
          ...reactions,
          ..._reactions.where((r) => !loaded.contains(r.messageId)),
        ];
      });
    } on ChatException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Messages could not be loaded.');
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<ChatMessage> _merged(
    List<ChatMessage> fresh,
    List<ChatMessage> current,
  ) {
    final byId = <String, ChatMessage>{
      for (final message in current) message.id: message,
      for (final message in fresh) message.id: message,
    };
    return byId.values.toList()..sort((a, b) {
      final order = a.created.compareTo(b.created);
      return order != 0 ? order : a.id.compareTo(b.id);
    });
  }

  void _onIncoming(ChatMessage message) {
    if (!mounted || _messages.any((m) => m.id == message.id)) return;
    setState(() => _messages = <ChatMessage>[..._messages, message]);
    _readTimer?.cancel();
    _readTimer = Timer(const Duration(seconds: 2), _markLatestRead);
  }

  void _markLatestRead() {
    if (_messages.isEmpty) return;
    unawaited(_chat.markRead(_room.id, _messages.last.created));
  }

  void _loadOlderIfAllHidden() {
    final blocked = _chat.blocked.value;
    if (_hasMore && _messages.every((m) => blocked.contains(m.author.id))) {
      unawaited(_loadOlder());
    }
  }

  void _onReaction(ChatReaction reaction, bool added) {
    if (!mounted) return;
    setState(() {
      _reactions = <ChatReaction>[
        ..._reactions.where((r) => r.id != reaction.id),
        if (added) reaction,
      ];
    });
  }

  void _onScroll() {
    if (!_scroll.hasClients || _loadingOlder || !_hasMore) return;
    if (_scroll.position.pixels >= _scroll.position.maxScrollExtent - 200) {
      unawaited(_loadOlder());
    }
  }

  Future<void> _loadOlder() async {
    if (_messages.isEmpty || _loadingOlder) return;
    setState(() => _loadingOlder = true);
    try {
      final older = await _chat.loadMessages(_room.id, before: _messages.first);
      final reactions = await _chat.loadReactions(
        older.map((m) => m.id).toList(),
      );
      if (!mounted) return;
      setState(() {
        _messages = <ChatMessage>[...older, ..._messages];
        _reactions = <ChatReaction>[...reactions, ..._reactions];
        _hasMore = older.length >= ChatService.pageSize;
        _loadingOlder = false;
      });
      _loadOlderIfAllHidden();
    } catch (_) {
      if (mounted) showAppSnackBar(context, 'Older messages could not load.');
    } finally {
      if (mounted) setState(() => _loadingOlder = false);
    }
  }

  Future<void> _pickImages() async {
    final files = await ImagePicker().pickMultiImage(
      limit: ChatService.maxPhotos,
    );
    final room = ChatService.maxPhotos - _images.length;
    final picked = await Future.wait(
      files.take(room).map((file) => file.readAsBytes()),
    );
    if (picked.isNotEmpty && mounted) {
      setState(() => _images = <Uint8List>[..._images, ...picked]);
    }
  }

  List<String> _mentionIds(String text) => _mentionPicks.entries
      .where((entry) => text.contains('@${entry.value.name}'))
      .map((entry) => entry.key)
      .toList();

  bool _canSend(TextEditingValue value) =>
      !_sending &&
      !_coolingDown &&
      _room.active &&
      (value.text.trim().isNotEmpty || _images.isNotEmpty);

  void _startCooldown() {
    if (_room.slowSeconds <= 0 || !mounted) return;
    _cooldownTimer?.cancel();
    setState(() => _coolingDown = true);
    _cooldownTimer = Timer(Duration(seconds: _room.slowSeconds), () {
      if (mounted) setState(() => _coolingDown = false);
    });
  }

  Future<void> _send() async {
    final text = _input.text.trim();
    if (!_canSend(_input.value)) return;
    setState(() => _sending = true);
    try {
      final sent = await _chat.send(
        _room,
        text: text,
        images: _images,
        replyTo: _replyTo,
        mentions: _mentionIds(text),
      );
      if (!mounted) return;
      _input.clear();
      _mentionPicks.clear();
      setState(() {
        _images = const <Uint8List>[];
        _replyTo = null;
      });
      _onIncoming(sent);
      if (_scroll.hasClients) _scroll.jumpTo(0);
      _startCooldown();
    } on ChatCooldownException {
      _startCooldown();
    } on ChatException catch (error) {
      if (mounted) showAppSnackBar(context, error.message);
    } on FormatException catch (error) {
      if (mounted) showAppSnackBar(context, error.message);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  void _mention(ChatAuthor author) {
    _mentionPicks[author.id] = author;
    final text = _input.text;
    final prefix = text.isEmpty || text.endsWith(' ') ? '' : ' ';
    _input.text = '$text$prefix@${author.name} ';
    _input.selection = TextSelection.collapsed(offset: _input.text.length);
  }

  Future<void> _showActions(ChatMessage message) async {
    final me = _chat.me?.id;
    final isMine = message.author.id == me;
    await showAppBottomSheet<void>(
      context,
      title: 'Message',
      draggable: false,
      isScrollControlled: false,
      builder: (sheetContext, textPrimary, textSecondary) {
        Widget action(IconData icon, String label, VoidCallback onTap) {
          return Expanded(
            child: InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: () {
                Navigator.of(sheetContext).pop();
                onTap();
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(icon, size: 22, color: AppPalette.primary),
                    const Gap(6),
                    Text(
                      label,
                      style: TextStyle(fontSize: 12, color: textPrimary),
                    ),
                  ],
                ),
              ),
            ),
          );
        }

        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  for (final emoji in ChatService.reactionEmojis)
                    InkWell(
                      borderRadius: BorderRadius.circular(20),
                      onTap: () {
                        Navigator.of(sheetContext).pop();
                        unawaited(_toggleReaction(message, emoji));
                      },
                      child: Padding(
                        padding: const EdgeInsets.all(6),
                        child: Text(
                          emoji,
                          style: const TextStyle(fontSize: 26),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Row(
              children: [
                if (_room.active)
                  action(Icons.reply_rounded, 'Reply', () {
                    setState(() => _replyTo = message);
                  }),
                if (_room.active && !isMine)
                  action(Icons.alternate_email_rounded, 'Mention', () {
                    _mention(message.author);
                  }),
                if (message.text.isNotEmpty)
                  action(Icons.copy_rounded, 'Copy', () {
                    unawaited(
                      Clipboard.setData(ClipboardData(text: message.text)),
                    );
                    showAppSnackBar(context, 'Copied.');
                  }),
                if (!isMine)
                  action(Icons.flag_outlined, 'Report', () {
                    unawaited(_report(message));
                  }),
                if (!isMine)
                  action(Icons.block_rounded, 'Block', () {
                    unawaited(_block(message.author));
                  }),
              ],
            ),
          ],
        );
      },
    );
  }

  Future<void> _toggleReaction(ChatMessage message, String emoji) async {
    try {
      await _chat.toggleReaction(message.id, emoji, _reactions);
    } catch (_) {
      if (mounted) showAppSnackBar(context, 'Reaction could not be saved.');
    }
  }

  Future<void> _report(ChatMessage message) async {
    await showAppConfirmationWithActionDialog(
      context,
      icon: Icons.flag_outlined,
      title: 'Report Message',
      message: 'Send this message to the moderators for review?',
      confirmLabel: 'Report',
      confirmColor: AppPalette.danger,
      onConfirm: () async {
        await _chat.report(message.id);
        if (mounted) showAppSnackBar(context, 'Message reported.');
      },
    );
  }

  Future<void> _block(ChatAuthor author) async {
    await showAppConfirmationWithActionDialog(
      context,
      icon: Icons.block_rounded,
      title: 'Block Student',
      message: 'You will no longer see messages from ${author.name}.',
      confirmLabel: 'Block',
      confirmColor: AppPalette.danger,
      onConfirm: () async {
        await _chat.block(author.id);
        if (mounted) setState(() {});
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return AppPageScaffold(
      title: _room.title,
      subtitle: _headerSubtitle(),
      icon: Icons.chat_bubble_outline_rounded,
      actions: [
        if (_room.kind != ChatRoomKind.lounge && _room.active)
          ValueListenableBuilder<Set<String>>(
            valueListenable: _chat.muted,
            builder: (context, muted, _) {
              final isMuted = muted.contains(_room.id);
              return IconButton(
                tooltip: isMuted ? 'Unmute' : 'Mute',
                onPressed: () => _toggleMute(!isMuted),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                visualDensity: VisualDensity.compact,
                icon: Icon(
                  isMuted
                      ? Icons.notifications_off_outlined
                      : Icons.notifications_none_rounded,
                  color: AppPalette.primary,
                ),
              );
            },
          ),
      ],
      body: Column(
        children: [
          Expanded(child: _buildMessages()),
          if (_room.active) _buildComposer() else const _ReadOnlyNotice(),
        ],
      ),
    );
  }

  Future<void> _toggleMute(bool value) async {
    try {
      await _chat.setMuted(_room.id, value);
    } catch (_) {
      if (mounted) showAppSnackBar(context, 'Could not update notifications.');
    }
  }

  Widget _buildMessages() {
    if (_loading) return const AppLoading();
    if (_error != null) {
      return AppErrorState(
        title: 'Chat Unavailable',
        message: _error!,
        onRetry: () {
          setState(() => _loading = true);
          unawaited(_load());
        },
      );
    }
    return ValueListenableBuilder<Set<String>>(
      valueListenable: _chat.blocked,
      builder: (context, blocked, _) {
        final visible = _messages
            .where((m) => !blocked.contains(m.author.id))
            .toList();
        if (visible.isEmpty) {
          return const AppEmptyState(
            message: 'No messages yet.',
            icon: Icons.chat_bubble_outline_rounded,
          );
        }
        final me = _chat.me?.id;
        return ListView.builder(
          controller: _scroll,
          reverse: true,
          padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
          itemCount: visible.length + (_loadingOlder ? 1 : 0),
          itemBuilder: (context, index) {
            if (index == visible.length) return const AppLoading();
            final message = visible[visible.length - 1 - index];
            final previous = index + 1 < visible.length
                ? visible[visible.length - 2 - index]
                : null;
            final newDay =
                previous == null ||
                !DateUtils.isSameDay(previous.created, message.created);
            final next = index > 0 ? visible[visible.length - index] : null;
            final grouped = previous != null && _sameGroup(previous, message);
            final bubble = _MessageBubble(
              message: message,
              isMine: message.author.id == me,
              showAuthor: !grouped,
              showTime: next == null || !_sameGroup(message, next),
              reactions: _reactions
                  .where((r) => r.messageId == message.id)
                  .toList(),
              myId: me ?? '',
              onLongPress: () => _showActions(message),
              onReact: (emoji) => _toggleReaction(message, emoji),
            );
            if (!newDay) return bubble;
            return Column(
              children: [
                _DayLabel(day: message.created),
                bubble,
              ],
            );
          },
        );
      },
    );
  }

  bool _sameGroup(ChatMessage earlier, ChatMessage later) =>
      earlier.author.id == later.author.id &&
      DateUtils.isSameDay(earlier.created, later.created) &&
      later.created.difference(earlier.created).inMinutes < 5;

  Widget _buildComposer() {
    final textSecondary = AppPalette.textSecondary(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 10),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_replyTo != null)
            _ComposerBanner(
              icon: Icons.reply_rounded,
              label:
                  'Replying to ${_replyTo!.author.name}: ${_replyTo!.text.isEmpty ? 'Photo' : _replyTo!.text}',
              onClear: () => setState(() => _replyTo = null),
            ),
          if (_images.isNotEmpty)
            _AttachedPhotos(
              images: _images,
              onRemove: (index) => setState(
                () => _images = <Uint8List>[..._images]..removeAt(index),
              ),
            ),
          Row(
            children: [
              IconButton(
                tooltip: 'Add Photos',
                onPressed:
                    _sending ||
                        !_room.active ||
                        _images.length >= ChatService.maxPhotos
                    ? null
                    : _pickImages,
                icon: Icon(Icons.image_outlined, color: textSecondary),
              ),
              Expanded(
                child: CallbackShortcuts(
                  bindings: <ShortcutActivator, VoidCallback>{
                    const SingleActivator(LogicalKeyboardKey.enter): () =>
                        unawaited(_send()),
                  },
                  child: TextField(
                    controller: _input,
                    minLines: 1,
                    maxLines: 5,
                    maxLength: 2000,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: appInputDecoration(
                      context,
                      hintText: 'Message',
                      counterText: '',
                      borderRadius: 22,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 10,
                      ),
                    ),
                  ),
                ),
              ),
              ValueListenableBuilder<TextEditingValue>(
                valueListenable: _input,
                builder: (context, value, _) {
                  final canSend = _canSend(value);
                  return IconButton(
                    tooltip: 'Send',
                    onPressed: canSend ? _send : null,
                    icon: _sending
                        ? const AppSpinner(size: 20)
                        : Icon(
                            Icons.send_rounded,
                            color: canSend ? AppPalette.primary : textSecondary,
                          ),
                  );
                },
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _DayLabel extends StatelessWidget {
  const _DayLabel({required this.day});

  final DateTime day;

  @override
  Widget build(BuildContext context) {
    final today = DateUtils.dateOnly(DateTime.now());
    final date = DateUtils.dateOnly(day);
    final label = date == today
        ? 'Today'
        : date == today.subtract(const Duration(days: 1))
        ? 'Yesterday'
        : AppTime.formatLongDate(date);
    return Padding(
      padding: const EdgeInsets.only(top: 10, bottom: 2),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: AppPalette.textSecondary(context),
        ),
      ),
    );
  }
}

class _ComposerBanner extends StatelessWidget {
  const _ComposerBanner({
    required this.icon,
    required this.label,
    required this.onClear,
  });

  final IconData icon;
  final String label;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final textSecondary = AppPalette.textSecondary(context);
    return Row(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Icon(icon, size: 16, color: AppPalette.primary),
        ),
        Expanded(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 12, color: textSecondary),
          ),
        ),
        IconButton(
          tooltip: 'Remove',
          visualDensity: VisualDensity.compact,
          onPressed: onClear,
          icon: Icon(Icons.close_rounded, size: 18, color: textSecondary),
        ),
      ],
    );
  }
}

class _PhotoViewer extends StatefulWidget {
  const _PhotoViewer({
    required this.urls,
    required this.thumbs,
    required this.page,
  });

  final List<String> urls;
  final List<String> thumbs;
  final ValueNotifier<int> page;

  @override
  State<_PhotoViewer> createState() => _PhotoViewerState();
}

class _PhotoViewerState extends State<_PhotoViewer> {
  late final PageController _pages = PageController(
    initialPage: widget.page.value,
  );

  static const double _thumbSize = 52;

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: PageView.builder(
            controller: _pages,
            itemCount: widget.urls.length,
            onPageChanged: (index) => widget.page.value = index,
            itemBuilder: (context, index) => InteractiveViewer(
              child: Center(
                child: CachedImage(
                  url: widget.urls[index],
                  fit: BoxFit.contain,
                ),
              ),
            ),
          ),
        ),
        if (widget.urls.length > 1)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: SizedBox(
              height: _thumbSize,
              child: ValueListenableBuilder<int>(
                valueListenable: widget.page,
                builder: (context, current, _) => Center(
                  child: ListView.separated(
                    shrinkWrap: true,
                    scrollDirection: Axis.horizontal,
                    itemCount: widget.thumbs.length,
                    separatorBuilder: (_, _) => const Gap(8),
                    itemBuilder: (context, index) => GestureDetector(
                      onTap: () => _pages.animateToPage(
                        index,
                        duration: const Duration(milliseconds: 250),
                        curve: Curves.easeOutCubic,
                      ),
                      child: Container(
                        width: _thumbSize,
                        height: _thumbSize,
                        foregroundDecoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: index == current
                                ? AppPalette.primary
                                : Colors.transparent,
                            width: 2,
                          ),
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: Opacity(
                            opacity: index == current ? 1 : 0.55,
                            child: CachedImage(
                              url: widget.thumbs[index],
                              fit: BoxFit.cover,
                              width: _thumbSize,
                              height: _thumbSize,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _AttachedPhotos extends StatelessWidget {
  const _AttachedPhotos({required this.images, required this.onRemove});

  final List<Uint8List> images;
  final ValueChanged<int> onRemove;

  static const double _size = 56;

  @override
  Widget build(BuildContext context) {
    final textPrimary = AppPalette.textPrimary(context);
    final card = AppPalette.card(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            for (var index = 0; index < images.length; index++)
              Stack(
                clipBehavior: Clip.none,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: Image.memory(
                      images[index],
                      width: _size,
                      height: _size,
                      fit: BoxFit.cover,
                      cacheWidth: (_size * 3).round(),
                    ),
                  ),
                  Positioned(
                    top: -6,
                    right: -6,
                    child: Semantics(
                      button: true,
                      label: 'Remove Photo',
                      child: GestureDetector(
                        onTap: () => onRemove(index),
                        child: Container(
                          width: 20,
                          height: 20,
                          decoration: BoxDecoration(
                            color: textPrimary,
                            shape: BoxShape.circle,
                            border: Border.all(color: card, width: 1.5),
                          ),
                          child: Icon(
                            Icons.close_rounded,
                            size: 13,
                            color: card,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

class _ReadOnlyNotice extends StatelessWidget {
  const _ReadOnlyNotice();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 6, 14, 14),
      child: Text(
        'This room is from a past semester and is read-only.',
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: 12,
          color: AppPalette.textSecondary(context),
        ),
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({
    required this.message,
    required this.isMine,
    required this.showAuthor,
    required this.showTime,
    required this.reactions,
    required this.myId,
    required this.onLongPress,
    required this.onReact,
  });

  final ChatMessage message;
  final bool isMine;
  final bool showAuthor;
  final bool showTime;
  final List<ChatReaction> reactions;
  final String myId;
  final VoidCallback onLongPress;
  final void Function(String emoji) onReact;

  static const double _avatarSize = 32;

  @override
  Widget build(BuildContext context) {
    final textPrimary = AppPalette.textPrimary(context);
    final textSecondary = AppPalette.textSecondary(context);
    final borderColor = isMine
        ? AppPalette.primary.withValues(alpha: 0.5)
        : textSecondary.withValues(alpha: 0.3);
    final counts = <String, int>{};
    for (final reaction in reactions) {
      counts[reaction.emoji] = (counts[reaction.emoji] ?? 0) + 1;
    }
    final mine = reactions
        .where((r) => r.studentId == myId)
        .map((r) => r.emoji)
        .toSet();
    final time = Text(
      AppTime.formatDateTime(message.created),
      style: TextStyle(fontSize: 10, color: textSecondary),
    );
    final hasReply =
        message.replyToId.isNotEmpty && message.replyText.isNotEmpty;
    final hasText = hasReply || message.text.isNotEmpty;
    final bubble = GestureDetector(
      onLongPress: onLongPress,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: isMine
            ? CrossAxisAlignment.end
            : CrossAxisAlignment.start,
        children: [
          if (message.hasImage) _ChatPhotos(message: message),
          if (message.hasImage && hasText) const Gap(4),
          if (hasText)
            Container(
              constraints: BoxConstraints(
                maxWidth: MediaQuery.sizeOf(context).width * 0.72,
              ),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: borderColor),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (hasReply)
                    Container(
                      margin: const EdgeInsets.only(bottom: 6),
                      padding: const EdgeInsets.only(left: 8),
                      decoration: const BoxDecoration(
                        border: Border(
                          left: BorderSide(color: AppPalette.primary, width: 2),
                        ),
                      ),
                      child: Text(
                        '${message.replyAuthorName}: ${message.replyText}',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 12, color: textSecondary),
                      ),
                    ),
                  if (message.text.isNotEmpty)
                    Text(
                      message.text,
                      style: TextStyle(
                        fontSize: 14,
                        height: 1.35,
                        color: textPrimary,
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
    return Padding(
      padding: EdgeInsets.only(top: showAuthor ? 8 : 2),
      child: Row(
        mainAxisAlignment: isMine
            ? MainAxisAlignment.end
            : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!isMine)
            SizedBox(
              width: _avatarSize + 8,
              child: showAuthor
                  ? Align(
                      alignment: Alignment.topLeft,
                      child: Stack(
                        children: [
                          CircleAvatar(
                            radius: _avatarSize / 2,
                            backgroundColor: AppPalette.primary.withValues(
                              alpha: 0.16,
                            ),
                            child: Text(
                              message.author.name.characters.firstOrNull
                                      ?.toUpperCase() ??
                                  '',
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: AppPalette.primary,
                              ),
                            ),
                          ),
                          FriendAvatar(
                            name: message.author.name,
                            photoUrl: message.author.photo,
                            size: _avatarSize,
                            radius: _avatarSize / 2,
                          ),
                        ],
                      ),
                    )
                  : null,
            ),
          Flexible(
            child: Column(
              crossAxisAlignment: isMine
                  ? CrossAxisAlignment.end
                  : CrossAxisAlignment.start,
              children: [
                if (showAuthor && !isMine)
                  Padding(
                    padding: const EdgeInsets.only(left: 4, bottom: 2),
                    child: Text(
                      message.author.name,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: textSecondary,
                      ),
                    ),
                  ),
                bubble,
                if (counts.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 3),
                    child: Wrap(
                      spacing: 4,
                      runSpacing: 4,
                      children: [
                        for (final entry in counts.entries)
                          InkWell(
                            borderRadius: BorderRadius.circular(12),
                            onTap: () => onReact(entry.key),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 3,
                              ),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(12),
                                color: mine.contains(entry.key)
                                    ? AppPalette.primary.withValues(alpha: 0.18)
                                    : AppPalette.card(context),
                                border: Border.all(
                                  color: mine.contains(entry.key)
                                      ? AppPalette.primary
                                      : textSecondary.withValues(alpha: 0.2),
                                ),
                              ),
                              child: Text(
                                '${entry.key} ${entry.value}',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: textPrimary,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                if (showTime)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(4, 3, 4, 0),
                    child: time,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ChatPhotos extends StatelessWidget {
  const _ChatPhotos({required this.message});

  final ChatMessage message;

  static const double _width = 220;
  static const double _gap = 4;

  @override
  Widget build(BuildContext context) {
    final single = message.images.length == 1;
    final size = single ? _width : (_width - _gap) / 2;
    return SizedBox(
      width: _width,
      child: Wrap(
        spacing: _gap,
        runSpacing: _gap,
        children: [
          for (final name in message.images)
            _ChatImage(message: message, name: name, size: size),
        ],
      ),
    );
  }
}

class _ChatImage extends StatefulWidget {
  const _ChatImage({
    required this.message,
    required this.name,
    required this.size,
  });

  final ChatMessage message;
  final String name;
  final double size;

  @override
  State<_ChatImage> createState() => _ChatImageState();
}

class _ChatImageState extends State<_ChatImage> {
  late final Future<String> _thumb = ChatService.instance.imageUrl(
    widget.message,
    widget.name,
  );

  Future<void> _openFull() async {
    final message = widget.message;
    final chat = ChatService.instance;
    final (urls, thumbs) = await (
      Future.wait(
        message.images.map(
          (name) => chat.imageUrl(message, name, thumb: false),
        ),
      ),
      Future.wait(message.images.map((name) => chat.imageUrl(message, name))),
    ).wait;
    if (!mounted) return;
    final page = ValueNotifier<int>(message.images.indexOf(widget.name));
    final title = ValueNotifier<String>('');
    void updateTitle() => title.value = urls.length == 1
        ? 'Photo'
        : 'Photo ${page.value + 1} of ${urls.length}';
    updateTitle();
    page.addListener(updateTitle);
    await showAppBottomSheet<void>(
      context,
      title: 'Photo',
      liveTitle: title,
      initialChildSize: 0.9,
      draggable: false,
      actions: [
        Builder(
          builder: (buttonContext) => IconButton(
            tooltip: 'Save',
            icon: Icon(
              Icons.adaptive.share,
              color: AppPalette.textSecondary(buttonContext),
            ),
            onPressed: () => _save(
              buttonContext,
              urls[page.value],
              message.images[page.value],
            ),
          ),
        ),
      ],
      builder: (sheetContext, textPrimary, textSecondary) =>
          _PhotoViewer(urls: urls, thumbs: thumbs, page: page),
    );
    page.dispose();
    title.dispose();
  }

  Future<void> _save(
    BuildContext buttonContext,
    String url,
    String name,
  ) async {
    final box = buttonContext.findRenderObject() as RenderBox?;
    final origin = box == null
        ? null
        : box.localToGlobal(Offset.zero) & box.size;
    try {
      final file = await AppImageCache.instance.getSingleFile(url);
      final bytes = await file.readAsBytes();
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile.fromData(bytes, mimeType: 'image/jpeg', name: name)],
          sharePositionOrigin: origin,
        ),
      );
    } catch (_) {
      if (buttonContext.mounted) {
        showAppSnackBar(buttonContext, 'Photo could not be saved.');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String>(
      future: _thumb,
      builder: (context, snapshot) {
        final url = snapshot.data;
        return GestureDetector(
          onTap: url == null ? null : _openFull,
          child: Container(
            foregroundDecoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: AppPalette.textSecondary(context).withValues(alpha: 0.3),
              ),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: SizedBox(
                width: widget.size,
                height: widget.size,
                child: url == null
                    ? const Center(child: AppSpinner(size: 20))
                    : CachedImage(url: url, fit: BoxFit.cover),
              ),
            ),
          ),
        );
      },
    );
  }
}
