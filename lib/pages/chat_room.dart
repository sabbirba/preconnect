import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:gap/gap.dart';
import 'package:image_picker/image_picker.dart';
import 'package:preconnect/api/chat.dart';
import 'package:preconnect/model/chat.dart';
import 'package:preconnect/pages/friend_sections/friend_header.dart';
import 'package:preconnect/pages/ui_kit.dart';
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

  List<ChatMessage> _messages = <ChatMessage>[];
  List<ChatReaction> _reactions = <ChatReaction>[];
  Future<ChatWatch>? _watch;
  ChatMessage? _replyTo;
  List<Uint8List> _images = const <Uint8List>[];
  bool _loading = true;
  bool _loadingOlder = false;
  bool _hasMore = true;
  bool _sending = false;
  String? _error;
  Timer? _readTimer;

  ChatRoom get _room => widget.room;

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
    _readTimer?.cancel();
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
        _messages = <ChatMessage>[
          ...messages,
          ..._messages.where((m) => !loaded.contains(m.id)),
        ];
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

  Future<void> _send() async {
    final text = _input.text.trim();
    if (_sending || (text.isEmpty && _images.isEmpty)) return;
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
      initialChildSize: 0.42,
      draggable: false,
      builder: (sheetContext, textPrimary, textSecondary) {
        Widget action(IconData icon, String label, VoidCallback onTap) {
          return ActionBannerCard(
            icon: icon,
            title: label,
            showBorder: false,
            showTrailingIcon: false,
            onTap: () {
              Navigator.of(sheetContext).pop();
              onTap();
            },
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
                unawaited(Clipboard.setData(ClipboardData(text: message.text)));
                showAppSnackBar(context, 'Copied.');
              }),
            if (!isMine)
              action(Icons.flag_outlined, 'Report', () {
                unawaited(_report(message));
              }),
            if (!isMine)
              action(Icons.block_rounded, 'Block ${message.author.name}', () {
                unawaited(_block(message.author));
              }),
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
      subtitle: switch (_room.kind) {
        ChatRoomKind.lounge => 'Lounge',
        ChatRoomKind.course => 'Course',
        ChatRoomKind.section => 'Section',
      },
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
          padding: const EdgeInsets.fromLTRB(14, 8, 14, 8),
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
            final grouped =
                !newDay &&
                previous.author.id == message.author.id &&
                message.created.difference(previous.created).inMinutes < 5;
            final bubble = _MessageBubble(
              message: message,
              isMine: message.author.id == me,
              showAuthor: !grouped,
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
            _ComposerBanner(
              icon: Icons.image_outlined,
              label: _images.length == 1
                  ? '1 photo attached'
                  : '${_images.length} photos attached',
              onClear: () => setState(() => _images = const <Uint8List>[]),
            ),
          Row(
            children: [
              IconButton(
                tooltip: 'Add Photos',
                onPressed: _sending || _images.length >= ChatService.maxPhotos
                    ? null
                    : _pickImages,
                icon: Icon(Icons.image_outlined, color: textSecondary),
              ),
              Expanded(
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
              IconButton(
                tooltip: 'Send',
                onPressed: _sending ? null : _send,
                icon: _sending
                    ? const AppSpinner(size: 20)
                    : const Icon(Icons.send_rounded, color: AppPalette.primary),
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
      padding: const EdgeInsets.only(top: 14, bottom: 4),
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
        Icon(icon, size: 16, color: AppPalette.primary),
        const Gap(8),
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
    required this.reactions,
    required this.myId,
    required this.onLongPress,
    required this.onReact,
  });

  final ChatMessage message;
  final bool isMine;
  final bool showAuthor;
  final List<ChatReaction> reactions;
  final String myId;
  final VoidCallback onLongPress;
  final void Function(String emoji) onReact;

  static const double _avatarSize = 32;

  @override
  Widget build(BuildContext context) {
    final textPrimary = AppPalette.textPrimary(context);
    final textSecondary = AppPalette.textSecondary(context);
    final bubbleColor = isMine
        ? AppPalette.primary.withValues(alpha: 0.16)
        : AppPalette.card(context);
    final counts = <String, int>{};
    for (final reaction in reactions) {
      counts[reaction.emoji] = (counts[reaction.emoji] ?? 0) + 1;
    }
    final mine = reactions
        .where((r) => r.studentId == myId)
        .map((r) => r.emoji)
        .toSet();
    final bubble = GestureDetector(
      onLongPress: onLongPress,
      child: Container(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * 0.72,
        ),
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
        decoration: BoxDecoration(
          color: bubbleColor,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: textSecondary.withValues(alpha: 0.14)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (message.replyToId.isNotEmpty && message.replyText.isNotEmpty)
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
            if (message.hasImage) _ChatPhotos(message: message),
            if (message.hasImage && message.text.isNotEmpty) const Gap(6),
            if (message.text.isNotEmpty)
              Text(
                message.text,
                style: TextStyle(
                  fontSize: 14,
                  height: 1.35,
                  color: textPrimary,
                ),
              ),
            const Gap(4),
            Text(
              AppTime.formatDateTime(message.created),
              style: TextStyle(fontSize: 10, color: textSecondary),
            ),
          ],
        ),
      ),
    );
    return Padding(
      padding: EdgeInsets.only(top: showAuthor ? 10 : 3),
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
                      child: FriendAvatar(
                        name: message.author.name,
                        photoUrl: message.author.photo,
                        size: _avatarSize,
                        radius: _avatarSize / 2,
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
                    padding: const EdgeInsets.only(left: 4, bottom: 3),
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
                    padding: const EdgeInsets.only(top: 4),
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
    final url = await ChatService.instance.imageUrl(
      widget.message,
      widget.name,
      thumb: false,
    );
    if (!mounted) return;
    await showAppBottomSheet<void>(
      context,
      title: 'Photo',
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
            onPressed: () => _save(buttonContext, url),
          ),
        ),
      ],
      builder: (sheetContext, textPrimary, textSecondary) => InteractiveViewer(
        child: Center(
          child: CachedImage(url: url, fit: BoxFit.contain),
        ),
      ),
    );
  }

  Future<void> _save(BuildContext buttonContext, String url) async {
    final box = buttonContext.findRenderObject() as RenderBox?;
    final origin = box == null
        ? null
        : box.localToGlobal(Offset.zero) & box.size;
    try {
      final file = await AppImageCache.instance.getSingleFile(url);
      final bytes = await file.readAsBytes();
      await SharePlus.instance.share(
        ShareParams(
          files: [
            XFile.fromData(bytes, mimeType: 'image/jpeg', name: widget.name),
          ],
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
        );
      },
    );
  }
}
