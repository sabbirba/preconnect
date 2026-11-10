import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:gap/gap.dart';
import 'package:image_picker/image_picker.dart';
import 'package:preconnect/api/chat.dart';
import 'package:preconnect/model/chat.dart';
import 'package:file_selector/file_selector.dart';
import 'package:preconnect/model/custom_schedule.dart';
import 'package:preconnect/tools/file_open.dart';
import 'package:preconnect/pages/friend_sections/friend_header.dart';
import 'package:preconnect/pages/ui_kit.dart';
import 'package:preconnect/tools/string_utils.dart';
import 'package:share_plus/share_plus.dart';
import 'package:preconnect/tools/app_paths.dart';
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
  String? _error;
  Timer? _readTimer;
  Timer? _cooldownTimer;
  bool _coolingDown = false;
  String? _timeShownFor;
  List<ChatVote> _votes = const <ChatVote>[];
  final Map<String, String> _typing = <String, String>{};
  final Map<String, Timer> _typingTimers = <String, Timer>{};
  late int _moderatedAt = _room.moderatedAt;

  ChatRoom get _room => widget.room;

  String _headerSubtitle() {
    final count =
        _chat.rooms.value
            .where((room) => room.id == _room.id)
            .firstOrNull
            ?.memberCount ??
        _room.memberCount;
    final students =
        '${formatAmount(count)} ${count == 1 ? 'student' : 'students'}';
    final section = _sectionName;
    return section.isEmpty
        ? students
        : 'Section ${formatSectionBadge(section)} · $students';
  }

  int get _sectionDash =>
      _room.kind == ChatRoomKind.section ? _room.title.lastIndexOf('-') : -1;

  String get _sectionName =>
      _sectionDash > 0 ? _room.title.substring(_sectionDash + 1) : '';

  String get _headerTitle =>
      _sectionDash > 0 ? _room.title.substring(0, _sectionDash) : _room.title;

  @override
  void initState() {
    super.initState();
    _chat.activeRoomId = _room.id;
    _scroll.addListener(_onScroll);
    _chat.rooms.addListener(_onRoomsChanged);
    _input.addListener(_onInputChanged);
    unawaited(_load());
  }

  @override
  void dispose() {
    if (_chat.activeRoomId == _room.id) _chat.activeRoomId = null;
    _chat.rooms.removeListener(_onRoomsChanged);
    _chat.remember(
      _room.id,
      _messages.where((m) => !m.isPending).toList(),
      _reactions,
    );
    if (_readTimer?.isActive ?? false) _markLatestRead();
    _readTimer?.cancel();
    _cooldownTimer?.cancel();
    for (final timer in _typingTimers.values) {
      timer.cancel();
    }
    unawaited(_watch?.then((watch) => watch.cancel()));
    _scroll.dispose();
    _input.dispose();
    super.dispose();
  }

  void _onRoomsChanged() {
    final current = _chat.rooms.value.where((room) => room.id == _room.id);
    final moderatedAt = current.firstOrNull?.moderatedAt ?? 0;
    if (moderatedAt <= _moderatedAt || !mounted) return;
    _moderatedAt = moderatedAt;
    setState(() {
      _messages = _messages.where((m) => m.isPending).toList();
      _reactions = const <ChatReaction>[];
    });
    unawaited(_load());
  }

  Future<void> _load() async {
    try {
      final watch = _watch ??= _chat.watchRoom(
        _room.id,
        onMessage: _onIncoming,
        onReaction: _onReaction,
        onVote: _onVote,
        onTyping: _onTyping,
      );
      unawaited(watch.then((_) {}, onError: (Object _) => _watch = null));
      final sent = _messages.where((m) => !m.isPending).toList();
      final after = sent.isEmpty ? null : sent.last;
      final messages = await _chat.loadMessages(_room.id, after: after);
      if (!mounted) return;
      final fullPage = messages.length >= ChatService.pageSize;
      setState(() {
        _messages = after != null && fullPage
            ? _merged(messages, _messages.where((m) => m.isPending).toList())
            : _merged(messages, _messages);
        if (after == null || fullPage) _hasMore = fullPage;
        _loading = false;
        _error = null;
      });
      _markLatestRead();
      _loadOlderIfAllHidden();
      unawaited(_chat.scheduleEvents(_messages));
      final visible = _messages
          .where((m) => !m.isPending)
          .map((m) => m.id)
          .toSet();
      final (reactions, votes) = await (
        _chat.loadReactions(visible.toList()),
        _chat.loadVotes(_pollIds(_messages)),
      ).wait;
      if (!mounted) return;
      setState(() {
        _reactions = <ChatReaction>[
          ...reactions,
          ..._reactions.where((r) => !visible.contains(r.messageId)),
        ];
        _votes = votes;
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
    final sentNonces = <String>{
      for (final message in byId.values)
        if (message.nonce.isNotEmpty && !message.isPending) message.nonce,
    };
    final result = byId.values.where((message) {
      final isTemp = message.isPending && message.nonce.isNotEmpty;
      return !(isTemp && sentNonces.contains(message.nonce));
    }).toList();
    result.sort((a, b) {
      final order = a.created.compareTo(b.created);
      return order != 0 ? order : a.id.compareTo(b.id);
    });
    return result;
  }

  void _upsert(ChatMessage message) {
    if (!mounted) return;
    final without = _messages
        .where(
          (m) =>
              m.id != message.id &&
              !(message.nonce.isNotEmpty && m.nonce == message.nonce),
        )
        .toList();
    setState(() => _messages = _merged(<ChatMessage>[message], without));
  }

  List<String> _pollIds(List<ChatMessage> messages) => [
    for (final message in messages)
      if (message.isPoll && !message.isPending) message.id,
  ];

  void _onInputChanged() {
    if (_room.active && _input.text.trim().isNotEmpty) {
      _chat.sendTyping(_room.id);
    }
  }

  void _onTyping(String studentId, String name) {
    if (!mounted || studentId.isEmpty) return;
    _typingTimers[studentId]?.cancel();
    _typingTimers[studentId] = Timer(
      ChatService.typingInterval + const Duration(seconds: 2),
      () => _stopTyping(studentId),
    );
    setState(() => _typing[studentId] = name);
  }

  void _stopTyping(String studentId) {
    _typingTimers.remove(studentId)?.cancel();
    if (mounted && _typing.containsKey(studentId)) {
      setState(() => _typing.remove(studentId));
    }
  }

  void _onVote(ChatVote vote, bool removed) {
    if (!mounted) return;
    setState(() {
      _votes = <ChatVote>[
        ..._votes.where(
          (v) =>
              v.id != vote.id &&
              !(v.messageId == vote.messageId && v.studentId == vote.studentId),
        ),
        if (!removed) vote,
      ];
    });
  }

  Future<void> _vote(ChatMessage message, int option) async {
    final me = _chat.me?.id ?? '';
    final current = _votes;
    final mine = current
        .where((v) => v.messageId == message.id && v.studentId == me)
        .firstOrNull;
    _onVote(
      ChatVote(
        id: mine?.id ?? '',
        messageId: message.id,
        studentId: me,
        option: option,
      ),
      mine?.option == option,
    );
    try {
      await _chat.vote(message.id, option, current);
    } catch (_) {
      if (!mounted) return;
      setState(() => _votes = current);
      showAppSnackBar(context, 'Your vote could not be saved.');
    }
  }

  void _onIncoming(ChatMessage message) {
    if (!mounted) return;
    _stopTyping(message.author.id);
    _upsert(message);
    unawaited(_chat.scheduleEvents(<ChatMessage>[message]));
    _scheduleRead();
  }

  void _scheduleRead() {
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
      final (reactions, votes) = await (
        _chat.loadReactions(older.map((m) => m.id).toList()),
        _chat.loadVotes(_pollIds(older)),
      ).wait;
      if (!mounted) return;
      setState(() {
        _messages = <ChatMessage>[...older, ..._messages];
        _reactions = <ChatReaction>[...reactions, ..._reactions];
        _votes = <ChatVote>[...votes, ..._votes];
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
    final maxPhotos = _chat.settings.value.maxPhotos;
    final files = await ImagePicker().pickMultiImage(limit: maxPhotos);
    final room = maxPhotos - _images.length;
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

  void _send() {
    if (!_canSend(_input.value)) return;
    final text = _input.text.trim();
    _post(text, images: _images, mentions: _mentionIds(text));
  }

  void _post(
    String text, {
    List<Uint8List> images = const <Uint8List>[],
    List<String> mentions = const <String>[],
    List<String> pollOptions = const <String>[],
    ChatEvent? event,
    String fileName = '',
    Uint8List? file,
  }) {
    final me = _chat.me;
    if (me == null) return;
    final replyTo = _replyTo;
    final nonce = '${me.id}-${DateTime.now().microsecondsSinceEpoch}';
    final optimistic = ChatMessage(
      id: nonce,
      roomId: _room.id,
      author: me,
      text: text,
      images: const <String>[],
      created: DateTime.now(),
      replyToId: replyTo?.id ?? '',
      replyAuthorName: replyTo?.author.name ?? '',
      replyText: replyTo == null
          ? ''
          : (replyTo.text.isEmpty ? 'Photo' : replyTo.text),
      mentions: mentions,
      nonce: nonce,
      status: ChatMessageStatus.sending,
      localImages: images,
      pollOptions: pollOptions,
      event: event,
      fileName: fileName,
      localFile: file,
    );
    _input.clear();
    _mentionPicks.clear();
    setState(() {
      _messages = <ChatMessage>[..._messages, optimistic];
      _images = const <Uint8List>[];
      _replyTo = null;
    });
    _startCooldown();
    _deliver(optimistic);
  }

  void _deliver(ChatMessage pending) {
    if (_scroll.hasClients) _scroll.jumpTo(0);
    unawaited(
      _chat
          .send(
            _room,
            text: pending.text,
            images: pending.localImages,
            replyToId: pending.replyToId,
            mentions: pending.mentions,
            pollOptions: pending.pollOptions,
            event: pending.event,
            fileName: pending.fileName,
            file: pending.localFile,
            nonce: pending.nonce,
          )
          .then(
            (sent) {
              _upsert(sent);
              _markLatestRead();
            },
            onError: (Object error) {
              _upsert(pending.copyWith(status: ChatMessageStatus.failed));
              if (error is ChatCooldownException || !mounted) return;
              showAppSnackBar(context, switch (error) {
                ChatException(:final message) => message,
                FormatException(:final message) => message,
                _ => 'Message could not be sent.',
              });
            },
          ),
    );
  }

  void _retry(ChatMessage message) {
    if (message.status != ChatMessageStatus.failed) return;
    final retried = message.copyWith(status: ChatMessageStatus.sending);
    setState(
      () => _messages = <ChatMessage>[
        ..._messages.where((m) => m.id != message.id),
        retried,
      ],
    );
    _deliver(retried);
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
                if (_canPin && message.text.isNotEmpty)
                  action(Icons.push_pin_outlined, 'Pin', () {
                    unawaited(_setPin(message.text));
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
    await showAppBottomSheet<void>(
      context,
      title: 'Report Message',
      draggable: false,
      isScrollControlled: true,
      builder: (sheetContext, textPrimary, textSecondary) => _ReportSheet(
        onSubmit: (reason) async {
          Navigator.of(sheetContext).pop();
          try {
            await _chat.report(message.id, reason);
            if (mounted) {
              showAppSnackBar(context, 'Reported to the moderators.');
            }
          } on ChatException catch (error) {
            if (mounted) showAppSnackBar(context, error.message);
          } catch (_) {
            if (mounted) showAppSnackBar(context, 'Report could not be sent.');
          }
        },
      ),
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
      title: _headerTitle,
      subtitle: _headerSubtitle(),
      icon: Icons.chat_bubble_outline_rounded,
      actions: [
        if (_room.kind != ChatRoomKind.lounge && _room.active)
          ValueListenableBuilder<Set<String>>(
            valueListenable: _chat.muted,
            builder: (context, muted, _) {
              final isMuted = muted.contains(_room.id);
              return HeaderActionButton(
                tooltip: isMuted ? 'Unmute' : 'Mute',
                icon: isMuted
                    ? Icons.notifications_off_outlined
                    : Icons.notifications_none_rounded,
                onTap: () => _toggleMute(!isMuted),
              );
            },
          ),
        HeaderActionButton(
          tooltip: 'Chat Rules',
          icon: Icons.info_outline_rounded,
          onTap: _showRules,
        ),
      ],
      body: Column(
        children: [
          ValueListenableBuilder<List<ChatRoom>>(
            valueListenable: _chat.rooms,
            builder: (context, rooms, _) {
              final pinned =
                  rooms
                      .where((room) => room.id == _room.id)
                      .firstOrNull
                      ?.pinned ??
                  _room.pinned;
              return pinned.isEmpty
                  ? const SizedBox.shrink()
                  : _PinnedNote(
                      text: pinned,
                      onUnpin: _canPin ? _confirmUnpin : null,
                    );
            },
          ),
          Expanded(child: _buildMessages()),
          if (_room.active) _buildComposer() else const _ReadOnlyNotice(),
        ],
      ),
    );
  }

  bool get _canPin => _room.kind == ChatRoomKind.section && _room.active;

  bool get _canShareEvents => _room.kind != ChatRoomKind.lounge && _room.active;

  Future<void> _setPin(String text) async {
    try {
      await _chat.pin(_room.id, text);
      if (mounted) {
        showAppSnackBar(context, text.isEmpty ? 'Unpinned.' : 'Pinned.');
      }
    } on ChatException catch (error) {
      if (mounted) showAppSnackBar(context, error.message);
    } catch (_) {
      if (mounted) showAppSnackBar(context, 'Could not update the pin.');
    }
  }

  Future<void> _confirmUnpin() {
    return showAppConfirmationWithActionDialog(
      context,
      icon: Icons.push_pin_outlined,
      title: 'Unpin Message',
      message: 'Remove the pinned message for everyone in this section?',
      confirmLabel: 'Unpin',
      confirmColor: AppPalette.danger,
      onConfirm: () => _setPin(''),
    );
  }

  Future<void> _showAttachMenu() {
    final photosFull = _images.length >= _chat.settings.value.maxPhotos;
    return showAppBottomSheet<void>(
      context,
      title: 'Share',
      draggable: false,
      isScrollControlled: false,
      builder: (sheetContext, textPrimary, textSecondary) {
        void pick(VoidCallback action) {
          Navigator.of(sheetContext).pop();
          action();
        }

        final options = <Widget>[
          _AttachOption(
            icon: Icons.photo_library_outlined,
            label: 'Photos',
            onTap: photosFull ? null : () => pick(_pickImages),
          ),
          _AttachOption(
            icon: Icons.picture_as_pdf_outlined,
            label: 'PDF',
            onTap: _images.isEmpty ? () => pick(_pickPdf) : null,
          ),
          _AttachOption(
            icon: Icons.poll_outlined,
            label: 'Poll',
            onTap: _images.isEmpty ? () => pick(_createPoll) : null,
          ),
          if (_canShareEvents)
            for (final kind in ChatEvent.kinds)
              _AttachOption(
                icon: _eventIcon(kind),
                label: personalSchedulesKindLabel(kind),
                onTap: _images.isEmpty
                    ? () => pick(() => _createEvent(kind))
                    : null,
              ),
        ];
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final option in options) Expanded(child: option),
              for (var i = options.length; i < 6; i++)
                const Expanded(child: SizedBox.shrink()),
            ],
          ),
        );
      },
    );
  }

  Future<void> _pickPdf() async {
    final picked = await openFile(
      acceptedTypeGroups: const <XTypeGroup>[
        XTypeGroup(
          label: 'PDF',
          extensions: <String>['pdf'],
          mimeTypes: <String>['application/pdf'],
          uniformTypeIdentifiers: <String>['com.adobe.pdf'],
        ),
      ],
    );
    if (picked == null || !mounted) return;
    final bytes = await picked.readAsBytes();
    if (!mounted) return;
    if (bytes.length > ChatService.maxFileBytes) {
      showAppSnackBar(context, 'PDFs can be up to 10 MB.');
      return;
    }
    final name = picked.name.toLowerCase().endsWith('.pdf')
        ? picked.name
        : '${picked.name}.pdf';
    _startCooldown();
    _post(
      _input.text.trim(),
      fileName: name.replaceAll(RegExp(r'[^A-Za-z0-9._ -]'), '_'),
      file: bytes,
    );
    _input.clear();
  }

  Future<void> _createEvent(String kind) {
    return showAppBottomSheet<void>(
      context,
      title: 'Share ${personalSchedulesKindLabel(kind)}',
      draggable: false,
      isScrollControlled: true,
      builder: (sheetContext, textPrimary, textSecondary) => _EventSheet(
        kind: kind,
        onShare: (event) {
          Navigator.of(sheetContext).pop();
          _startCooldown();
          _post(event.title, event: event);
        },
      ),
    );
  }

  Future<void> _createPoll() {
    return showAppBottomSheet<void>(
      context,
      title: 'New Poll',
      draggable: false,
      isScrollControlled: true,
      builder: (sheetContext, textPrimary, textSecondary) => _PollSheet(
        onCreate: (question, options) {
          Navigator.of(sheetContext).pop();
          _startCooldown();
          _post(question, pollOptions: options);
        },
      ),
    );
  }

  Future<void> _showRules() {
    return showAppBottomSheet<void>(
      context,
      title: 'Chat Rules',
      draggable: false,
      isScrollControlled: false,
      builder: (sheetContext, textPrimary, textSecondary) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: _RuleList(rules: _chat.settings.value.rules),
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
        final votesByMessage = <String, List<ChatVote>>{};
        for (final vote in _votes) {
          (votesByMessage[vote.messageId] ??= <ChatVote>[]).add(vote);
        }
        final reactionsByMessage = <String, List<ChatReaction>>{};
        for (final reaction in _reactions) {
          (reactionsByMessage[reaction.messageId] ??= <ChatReaction>[]).add(
            reaction,
          );
        }
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
              showFullTime: _timeShownFor == message.id,
              onTap: () => setState(
                () => _timeShownFor = _timeShownFor == message.id
                    ? null
                    : message.id,
              ),
              reactions:
                  reactionsByMessage[message.id] ?? const <ChatReaction>[],
              myId: me ?? '',
              votes: votesByMessage[message.id] ?? const <ChatVote>[],
              onVote: (option) => _vote(message, option),
              onLongPress: message.isPending
                  ? null
                  : () => _showActions(message),
              onReact: (emoji) => _toggleReaction(message, emoji),
              onRetry: () => _retry(message),
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
          if (_typing.isNotEmpty) _TypingLine(names: _typing.values.toList()),
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
                tooltip: 'Share',
                onPressed: _coolingDown ? null : _showAttachMenu,
                icon: const Icon(
                  Icons.add_circle_outline_rounded,
                  size: 26,
                  color: AppPalette.primary,
                ),
              ),
              Expanded(
                child: CallbackShortcuts(
                  bindings: <ShortcutActivator, VoidCallback>{
                    const SingleActivator(LogicalKeyboardKey.enter): _send,
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
                    icon: Icon(
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

class _RuleList extends StatelessWidget {
  const _RuleList({required this.rules});

  final List<String> rules;

  @override
  Widget build(BuildContext context) {
    final textSecondary = AppPalette.textSecondary(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final rule in rules) ...[
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

class _ReportSheet extends StatefulWidget {
  const _ReportSheet({required this.onSubmit});

  final Future<void> Function(String reason) onSubmit;

  @override
  State<_ReportSheet> createState() => _ReportSheetState();
}

class _ReportSheetState extends State<_ReportSheet> {
  final TextEditingController _reason = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final textSecondary = AppPalette.textSecondary(context);
    final minLength = ChatService.instance.settings.value.reportReasonMin;
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.viewInsetsOf(context).bottom + 12,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Text(
              'Tell the moderators what is wrong. Be specific — at least '
              '$minLength characters.',
              style: TextStyle(fontSize: 13, color: textSecondary),
            ),
          ),
          ValueListenableBuilder<TextEditingValue>(
            valueListenable: _reason,
            builder: (context, value, _) {
              final length = value.text.trim().length;
              final enough = length >= minLength;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextField(
                    controller: _reason,
                    minLines: 4,
                    maxLines: 8,
                    maxLength: 500,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: appInputDecoration(
                      context,
                      hintText: 'Reason',
                      counterText: '',
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(4, 4, 4, 12),
                    child: Text(
                      enough ? '$length characters' : '$length / $minLength',
                      style: TextStyle(
                        fontSize: 12,
                        color: enough ? textSecondary : AppPalette.danger,
                      ),
                    ),
                  ),
                  AppActionButton(
                    label: 'Report',
                    outlined: false,
                    backgroundColor: AppPalette.danger,
                    foregroundColor: Colors.white,
                    onPressed: (!enough || _busy)
                        ? null
                        : () async {
                            setState(() => _busy = true);
                            await widget.onSubmit(_reason.text.trim());
                          },
                  ),
                ],
              );
            },
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
    required this.urlKeys,
    required this.thumbKeys,
    required this.page,
  });

  final List<String> urls;
  final List<String> thumbs;
  final List<String> urlKeys;
  final List<String> thumbKeys;
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
                  cacheKey: widget.urlKeys[index],
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
                              cacheKey: widget.thumbKeys[index],
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
    required this.showFullTime,
    required this.onTap,
    required this.reactions,
    required this.votes,
    required this.onVote,
    required this.myId,
    required this.onLongPress,
    required this.onReact,
    required this.onRetry,
  });

  final ChatMessage message;
  final bool isMine;
  final bool showAuthor;
  final bool showTime;
  final bool showFullTime;
  final VoidCallback onTap;
  final List<ChatReaction> reactions;
  final List<ChatVote> votes;
  final ValueChanged<int> onVote;
  final String myId;
  final VoidCallback? onLongPress;
  final void Function(String emoji) onReact;
  final VoidCallback onRetry;

  static const double _avatarSize = 32;
  static const double _inset = 12;
  static const EdgeInsets _metaPadding = EdgeInsets.fromLTRB(
    _inset,
    4,
    _inset,
    2,
  );

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
    final hasReply =
        message.replyToId.isNotEmpty && message.replyText.isNotEmpty;
    final hasText = hasReply || message.text.isNotEmpty || message.hasFile;
    final bubble = GestureDetector(
      onTap: onTap,
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
              constraints: BoxConstraints(maxWidth: _bubbleMaxWidth(context)),
              padding: const EdgeInsets.symmetric(
                horizontal: _inset,
                vertical: 8,
              ),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(_ChatPhotos.radius),
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
                  if (message.hasFile) ...[
                    _FileCard(message: message),
                    if (message.text.isNotEmpty) const Gap(8),
                  ],
                  if (message.event != null)
                    _EventCard(
                      event: message.event!,
                      enabled: !message.isPending,
                    )
                  else if (message.isPoll)
                    _PollCard(
                      message: message,
                      votes: votes,
                      myId: myId,
                      onVote: message.isPending ? null : onVote,
                    )
                  else if (message.text.isNotEmpty)
                    _LinkText(
                      text: message.text,
                      style: TextStyle(
                        fontSize: 14,
                        height: 1.35,
                        color: textPrimary,
                      ),
                    ),
                  if (message.preview != null)
                    _LinkPreviewCard(preview: message.preview!),
                ],
              ),
            ),
        ],
      ),
    );
    return Padding(
      padding: EdgeInsets.only(top: showAuthor ? 12 : 3),
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
                    padding: const EdgeInsets.only(left: _inset, bottom: 4),
                    child: Text(
                      message.author.name,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: textSecondary,
                      ),
                    ),
                  ),
                bubble,
                if (isMine && message.status == ChatMessageStatus.sending)
                  Padding(
                    padding: _metaPadding,
                    child: Icon(
                      Icons.schedule_rounded,
                      size: 12,
                      color: textSecondary,
                    ),
                  ),
                if (isMine && message.status == ChatMessageStatus.failed)
                  Padding(
                    padding: _metaPadding,
                    child: InkWell(
                      onTap: onRetry,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.error_outline_rounded,
                            size: 12,
                            color: AppPalette.danger,
                          ),
                          const Gap(4),
                          Text(
                            'Not Sent · Tap to Retry',
                            style: const TextStyle(
                              fontSize: 11,
                              color: AppPalette.danger,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
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
                if (showTime || showFullTime)
                  Padding(
                    padding: _metaPadding,
                    child: Text(
                      showFullTime
                          ? '${AppTime.formatLongDate(message.created.toLocal())} · ${AppTime.formatDateTime(message.created)}'
                          : AppTime.formatDateTime(message.created),
                      style: TextStyle(fontSize: 10, color: textSecondary),
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

  static const double _gap = 4;
  static const double radius = 16;

  @override
  Widget build(BuildContext context) {
    final local = message.isPending && message.localImages.isNotEmpty;
    final count = local ? message.localImages.length : message.images.length;
    final width = _bubbleMaxWidth(context);
    final size = count == 1 ? width : (width - _gap) / 2;
    return SizedBox(
      width: width,
      child: Wrap(
        spacing: _gap,
        runSpacing: _gap,
        children: [
          if (local)
            for (final bytes in message.localImages)
              _LocalImage(bytes: bytes, size: size)
          else
            for (final name in message.images)
              _ChatImage(message: message, name: name, size: size),
        ],
      ),
    );
  }
}

class _LocalImage extends StatelessWidget {
  const _LocalImage({required this.bytes, required this.size});

  final Uint8List bytes;
  final double size;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(_ChatPhotos.radius),
      child: Opacity(
        opacity: 0.7,
        child: Image.memory(
          bytes,
          width: size,
          height: size,
          fit: BoxFit.cover,
          cacheWidth: (size * MediaQuery.devicePixelRatioOf(context)).round(),
        ),
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
  late final String _thumbKey = ChatService.instance.imageKey(
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
    final urlKeys = <String>[
      for (final name in message.images)
        chat.imageKey(message, name, thumb: false),
    ];
    final thumbKeys = <String>[
      for (final name in message.images) chat.imageKey(message, name),
    ];
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
              urlKeys[page.value],
              message.images[page.value],
            ),
          ),
        ),
      ],
      builder: (sheetContext, textPrimary, textSecondary) => _PhotoViewer(
        urls: urls,
        thumbs: thumbs,
        urlKeys: urlKeys,
        thumbKeys: thumbKeys,
        page: page,
      ),
    );
    page.dispose();
    title.dispose();
  }

  Future<void> _save(
    BuildContext buttonContext,
    String url,
    String cacheKey,
    String name,
  ) async {
    final box = buttonContext.findRenderObject() as RenderBox?;
    final origin = box == null
        ? null
        : box.localToGlobal(Offset.zero) & box.size;
    try {
      final file = await AppImageCache.instance.getSingleFile(
        url,
        key: cacheKey,
      );
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
              borderRadius: BorderRadius.circular(_ChatPhotos.radius),
              border: Border.all(
                color: AppPalette.textSecondary(context).withValues(alpha: 0.3),
              ),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(_ChatPhotos.radius),
              child: SizedBox(
                width: widget.size,
                height: widget.size,
                child: url == null
                    ? const Center(child: AppSpinner(size: 20))
                    : CachedImage(
                        url: url,
                        cacheKey: _thumbKey,
                        fit: BoxFit.cover,
                      ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _PinnedNote extends StatelessWidget {
  const _PinnedNote({required this.text, required this.onUnpin});

  final String text;
  final VoidCallback? onUnpin;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
      child: AppCard(
        padding: EdgeInsets.fromLTRB(14, 10, onUnpin == null ? 14 : 4, 10),
        child: Row(
          children: [
            Expanded(
              child: _LinkText(
                text: text,
                maxLines: 3,
                style: TextStyle(
                  fontSize: 13,
                  height: 1.35,
                  color: AppPalette.textPrimary(context),
                ),
              ),
            ),
            if (onUnpin != null)
              IconButton(
                tooltip: 'Unpin',
                visualDensity: VisualDensity.compact,
                onPressed: onUnpin,
                icon: Icon(
                  Icons.close_rounded,
                  size: 18,
                  color: AppPalette.textSecondary(context),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

IconData _eventIcon(String kind) => switch (kind) {
  'quiz' => Icons.quiz_outlined,
  'assignment' => Icons.assignment_outlined,
  _ => Icons.alarm_rounded,
};

class _AttachOption extends StatelessWidget {
  const _AttachOption({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    final color = enabled
        ? AppPalette.primary
        : AppPalette.textSecondary(context);
    return Center(
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Column(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: color.withValues(alpha: 0.14),
                ),
                child: Icon(icon, color: color, size: 24),
              ),
              const Gap(6),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  color: enabled
                      ? AppPalette.textPrimary(context)
                      : AppPalette.textSecondary(context),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EventSheet extends StatefulWidget {
  const _EventSheet({required this.kind, required this.onShare});

  final String kind;
  final ValueChanged<ChatEvent> onShare;

  @override
  State<_EventSheet> createState() => _EventSheetState();
}

class _EventSheetState extends State<_EventSheet> {
  final TextEditingController _title = TextEditingController();
  final TextEditingController _notes = TextEditingController();
  late DateTime _at = () {
    final tomorrow = DateTime.now().add(const Duration(days: 1));
    return DateTime(tomorrow.year, tomorrow.month, tomorrow.day, 9);
  }();

  @override
  void dispose() {
    _title.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showAppDatePicker(
      context,
      initialDate: _at,
      dayCount: 120,
    );
    if (picked == null || !mounted) return;
    setState(
      () => _at = DateTime(
        picked.year,
        picked.month,
        picked.day,
        _at.hour,
        _at.minute,
      ),
    );
  }

  Future<void> _pickTime() async {
    final picked = await showAppTimePicker(
      context,
      initialTime: TimeOfDay.fromDateTime(_at),
    );
    if (picked == null || !mounted) return;
    setState(
      () => _at = DateTime(
        _at.year,
        _at.month,
        _at.day,
        picked.hour,
        picked.minute,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final label = personalSchedulesKindLabel(widget.kind);
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.viewInsetsOf(context).bottom + 12,
      ),
      child: ValueListenableBuilder<TextEditingValue>(
        valueListenable: _title,
        builder: (context, value, _) => Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _title,
              maxLength: 120,
              textCapitalization: TextCapitalization.sentences,
              decoration: appInputDecoration(
                context,
                hintText: '$label title',
                counterText: '',
              ),
            ),
            const Gap(10),
            TextField(
              controller: _notes,
              minLines: 2,
              maxLines: 4,
              maxLength: 500,
              textCapitalization: TextCapitalization.sentences,
              decoration: appInputDecoration(
                context,
                hintText: 'Notes (optional)',
                counterText: '',
              ),
            ),
            const Gap(10),
            Row(
              children: [
                Expanded(
                  child: AppActionButton(
                    label: AppTime.formatDayMonth(_at),
                    icon: Icons.event_outlined,
                    onPressed: _pickDate,
                  ),
                ),
                const Gap(10),
                Expanded(
                  child: AppActionButton(
                    label: AppTime.formatDateTime(_at),
                    icon: Icons.schedule_rounded,
                    onPressed: _pickTime,
                  ),
                ),
              ],
            ),
            const Gap(16),
            AppActionButton(
              label: 'Share $label',
              outlined: false,
              backgroundColor: AppPalette.primary,
              foregroundColor: Colors.white,
              onPressed: value.text.trim().isEmpty
                  ? null
                  : () => widget.onShare(
                      ChatEvent(
                        kind: widget.kind,
                        title: value.text.trim(),
                        at: _at,
                        notes: _notes.text.trim(),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EventCard extends StatefulWidget {
  const _EventCard({required this.event, required this.enabled});

  final ChatEvent event;
  final bool enabled;

  @override
  State<_EventCard> createState() => _EventCardState();
}

class _EventCardState extends State<_EventCard> {
  final ChatService _chat = ChatService.instance;
  bool _added = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _chat.scheduledVersion.addListener(_refresh);
    _refresh();
  }

  @override
  void dispose() {
    _chat.scheduledVersion.removeListener(_refresh);
    super.dispose();
  }

  void _refresh() {
    unawaited(
      _chat.scheduledItem(widget.event).then((item) {
        if (mounted) setState(() => _added = item != null);
      }),
    );
  }

  Future<void> _toggle() async {
    setState(() => _saving = true);
    final label = personalSchedulesKindLabel(widget.event.kind);
    try {
      if (_added) {
        await _chat.removeFromSchedule(widget.event);
      } else {
        await _chat.addToSchedule(widget.event);
      }
      if (mounted) {
        showAppSnackBar(
          context,
          _added
              ? '$label removed from your schedule.'
              : '$label added to your schedule.',
        );
      }
    } catch (_) {
      if (mounted) showAppSnackBar(context, 'Could not update your schedule.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final event = widget.event;
    final textSecondary = AppPalette.textSecondary(context);
    final section = _chat.sectionFor(event);
    final course = <String>[
      event.courseCode,
      if (section.isNotEmpty) formatSectionBadge(section),
    ].where((part) => part.isNotEmpty).join(' · ');
    return SizedBox(
      width: _cardWidth(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(_eventIcon(event.kind), size: 14, color: AppPalette.primary),
              const Gap(6),
              Expanded(
                child: Text(
                  course.isEmpty
                      ? personalSchedulesKindLabel(event.kind)
                      : '${personalSchedulesKindLabel(event.kind)} · $course',
                  style: TextStyle(fontSize: 11, color: textSecondary),
                ),
              ),
            ],
          ),
          const Gap(4),
          Text(
            event.title,
            style: TextStyle(
              fontSize: 14,
              height: 1.35,
              fontWeight: FontWeight.w600,
              color: AppPalette.textPrimary(context),
            ),
          ),
          const Gap(2),
          Text(
            '${AppTime.formatDayMonth(event.at)} · ${AppTime.formatDateTime(event.at)}',
            style: TextStyle(fontSize: 12, color: textSecondary),
          ),
          if (event.notes.isNotEmpty) ...[
            const Gap(6),
            _LinkText(
              text: event.notes,
              style: TextStyle(
                fontSize: 13,
                height: 1.35,
                color: AppPalette.textPrimary(context),
              ),
            ),
          ],
          const Gap(10),
          SizedBox(
            width: double.infinity,
            child: AppActionButton(
              label: _added ? 'Remove from Schedule' : 'Add to Schedule',
              icon: _added
                  ? Icons.event_busy_outlined
                  : Icons.event_available_outlined,
              onPressed: !widget.enabled || _saving ? null : _toggle,
            ),
          ),
        ],
      ),
    );
  }
}

double _cardWidth(BuildContext context) =>
    _bubbleMaxWidth(context) - _MessageBubble._inset * 2;

double _bubbleMaxWidth(BuildContext context) =>
    math.min(MediaQuery.sizeOf(context).width * 0.78, 340);

class _FileCard extends StatefulWidget {
  const _FileCard({required this.message});

  final ChatMessage message;

  @override
  State<_FileCard> createState() => _FileCardState();
}

class _FileCardState extends State<_FileCard> {
  bool _opening = false;

  Future<void> _open() async {
    final message = widget.message;
    final chat = ChatService.instance;
    setState(() => _opening = true);
    try {
      final file = await AppImageCache.instance.getSingleFile(
        await chat.fileUrl(message),
        key: chat.fileKey(message),
      );
      if (kIsWeb) {
        await openPdfInBrowser(
          bytes: await file.readAsBytes(),
          fileName: message.fileName,
        );
      } else {
        final named = File(
          '${(await AppPaths.temporaryDirectory()).path}/'
          '${_displayName(message.fileName)}',
        );
        if (!await named.exists() ||
            await named.length() != await file.length()) {
          await file.copy(named.path);
        }
        if (!await NativeFile.open(named.path) && mounted) {
          showAppSnackBar(context, 'No app could open this PDF.');
        }
      }
    } catch (_) {
      if (mounted) showAppSnackBar(context, 'The PDF could not be opened.');
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final message = widget.message;
    final pending = message.isPending;
    final textSecondary = AppPalette.textSecondary(context);
    final size = message.localFile?.length;
    return InkWell(
      borderRadius: BorderRadius.circular(_ChatPhotos.radius - 4),
      onTap: pending || _opening ? null : _open,
      child: Container(
        width: _cardWidth(context),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(_ChatPhotos.radius - 4),
          border: Border.all(color: textSecondary.withValues(alpha: 0.25)),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: AppPalette.danger.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(
                Icons.picture_as_pdf_outlined,
                color: AppPalette.danger,
              ),
            ),
            const Gap(10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _displayName(message.fileName),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppPalette.textPrimary(context),
                    ),
                  ),
                  const Gap(2),
                  Text(
                    size == null
                        ? 'PDF · Tap to open'
                        : 'PDF · ${(size / 1048576).toStringAsFixed(1)} MB',
                    style: TextStyle(fontSize: 11, color: textSecondary),
                  ),
                ],
              ),
            ),
            if (_opening || pending)
              const Padding(
                padding: EdgeInsets.only(left: 8),
                child: AppSpinner(size: 18),
              ),
          ],
        ),
      ),
    );
  }
}

String _displayName(String stored) {
  final match = RegExp(r'^(.*)_[a-z0-9]{10}(\.pdf)$').firstMatch(stored);
  return match == null ? stored : '${match.group(1)}${match.group(2)}';
}

class _TypingLine extends StatelessWidget {
  const _TypingLine({required this.names});

  final List<String> names;

  @override
  Widget build(BuildContext context) {
    final first = names
        .map((name) => name.split(' ').where((p) => p.length > 1).firstOrNull)
        .whereType<String>()
        .toList();
    final label = switch (first.length) {
      0 => 'Someone is typing…',
      1 => '${first.first} is typing…',
      2 => '${first[0]} and ${first[1]} are typing…',
      _ => 'Several people are typing…',
    };
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontStyle: FontStyle.italic,
            color: AppPalette.textSecondary(context),
          ),
        ),
      ),
    );
  }
}

class _LinkText extends StatefulWidget {
  const _LinkText({required this.text, required this.style, this.maxLines});

  final String text;
  final TextStyle style;
  final int? maxLines;

  @override
  State<_LinkText> createState() => _LinkTextState();
}

class _LinkTextState extends State<_LinkText> {
  static final RegExp _link = RegExp(
    r'https?://[^\s<>"]+',
    caseSensitive: false,
  );
  final List<TapGestureRecognizer> _recognizers = <TapGestureRecognizer>[];

  void _clearRecognizers() {
    for (final recognizer in _recognizers) {
      recognizer.dispose();
    }
    _recognizers.clear();
  }

  @override
  void dispose() {
    _clearRecognizers();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _clearRecognizers();
    final spans = <TextSpan>[];
    var start = 0;
    for (final match in _link.allMatches(widget.text)) {
      final url = match.group(0)!.replaceAll(RegExp(r'[.,!?)]+$'), '');
      final end = match.start + url.length;
      if (match.start > start) {
        spans.add(TextSpan(text: widget.text.substring(start, match.start)));
      }
      final recognizer = TapGestureRecognizer()
        ..onTap = () => openExternalUrl(context, url);
      _recognizers.add(recognizer);
      spans.add(
        TextSpan(
          text: url,
          recognizer: recognizer,
          style: const TextStyle(
            color: AppPalette.primary,
            decoration: TextDecoration.underline,
            decorationColor: AppPalette.primary,
          ),
        ),
      );
      start = end;
    }
    if (start < widget.text.length) {
      spans.add(TextSpan(text: widget.text.substring(start)));
    }
    return Text.rich(
      TextSpan(style: widget.style, children: spans),
      maxLines: widget.maxLines,
      overflow: widget.maxLines == null ? null : TextOverflow.ellipsis,
    );
  }
}

class _LinkPreviewCard extends StatelessWidget {
  const _LinkPreviewCard({required this.preview});

  final ChatLinkPreview preview;

  @override
  Widget build(BuildContext context) {
    final textSecondary = AppPalette.textSecondary(context);
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: GestureDetector(
        onTap: () => openExternalUrl(context, preview.url),
        child: Container(
          width: _cardWidth(context),
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(_ChatPhotos.radius - 4),
            border: Border.all(color: textSecondary.withValues(alpha: 0.25)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (preview.image.isNotEmpty)
                CachedImage(
                  url: preview.image,
                  width: _cardWidth(context),
                  height: _cardWidth(context) * 0.52,
                  fit: BoxFit.cover,
                  placeholder: SizedBox(height: _cardWidth(context) * 0.52),
                  error: const SizedBox.shrink(),
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      preview.host,
                      style: TextStyle(fontSize: 11, color: textSecondary),
                    ),
                    const Gap(2),
                    Text(
                      preview.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppPalette.textPrimary(context),
                      ),
                    ),
                    if (preview.description.isNotEmpty) ...[
                      const Gap(2),
                      Text(
                        preview.description,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 12, color: textSecondary),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PollCard extends StatelessWidget {
  const _PollCard({
    required this.message,
    required this.votes,
    required this.myId,
    required this.onVote,
  });

  final ChatMessage message;
  final List<ChatVote> votes;
  final String myId;
  final ValueChanged<int>? onVote;

  @override
  Widget build(BuildContext context) {
    final textPrimary = AppPalette.textPrimary(context);
    final textSecondary = AppPalette.textSecondary(context);
    final counts = List<int>.filled(message.pollOptions.length, 0);
    for (final vote in votes) {
      if (vote.option >= 0 && vote.option < counts.length) {
        counts[vote.option]++;
      }
    }
    final mine = votes.where((v) => v.studentId == myId).firstOrNull?.option;
    final total = votes.length;
    return SizedBox(
      width: _cardWidth(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.poll_outlined,
                size: 14,
                color: AppPalette.primary,
              ),
              const Gap(6),
              Text(
                'Poll',
                style: TextStyle(fontSize: 11, color: textSecondary),
              ),
            ],
          ),
          const Gap(4),
          Text(
            message.text,
            style: TextStyle(
              fontSize: 14,
              height: 1.35,
              fontWeight: FontWeight.w600,
              color: textPrimary,
            ),
          ),
          const Gap(8),
          for (var index = 0; index < counts.length; index++)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: _PollOption(
                label: message.pollOptions[index],
                share: total == 0 ? 0 : counts[index] / total,
                selected: mine == index,
                onTap: onVote == null ? null : () => onVote!(index),
              ),
            ),
          Text(
            total == 1 ? '1 vote' : '${formatAmount(total)} votes',
            style: TextStyle(fontSize: 11, color: textSecondary),
          ),
        ],
      ),
    );
  }
}

class _PollOption extends StatelessWidget {
  const _PollOption({
    required this.label,
    required this.share,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final double share;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final textSecondary = AppPalette.textSecondary(context);
    final radius = BorderRadius.circular(10);
    return InkWell(
      borderRadius: radius,
      onTap: onTap,
      child: Container(
        height: 36,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          borderRadius: radius,
          border: Border.all(
            color: selected
                ? AppPalette.primary
                : textSecondary.withValues(alpha: 0.25),
          ),
        ),
        child: Stack(
          alignment: AlignmentDirectional.centerStart,
          children: [
            FractionallySizedBox(
              widthFactor: share,
              heightFactor: 1,
              child: ColoredBox(
                color: AppPalette.primary.withValues(alpha: 0.16),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Row(
                children: [
                  if (selected)
                    const Padding(
                      padding: EdgeInsets.only(right: 6),
                      child: Icon(
                        Icons.check_circle_rounded,
                        size: 14,
                        color: AppPalette.primary,
                      ),
                    ),
                  Expanded(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        color: AppPalette.textPrimary(context),
                      ),
                    ),
                  ),
                  Text(
                    '${(share * 100).round()}%',
                    style: TextStyle(fontSize: 12, color: textSecondary),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PollSheet extends StatefulWidget {
  const _PollSheet({required this.onCreate});

  final void Function(String question, List<String> options) onCreate;

  @override
  State<_PollSheet> createState() => _PollSheetState();
}

class _PollSheetState extends State<_PollSheet> {
  static const int _maxOptions = 6;
  final TextEditingController _question = TextEditingController();
  final List<TextEditingController> _options = <TextEditingController>[
    TextEditingController(),
    TextEditingController(),
  ];

  @override
  void dispose() {
    _question.dispose();
    for (final option in _options) {
      option.dispose();
    }
    super.dispose();
  }

  List<String> get _filled => _options
      .map((option) => option.text.trim())
      .where((text) => text.isNotEmpty)
      .toList();

  bool get _ready =>
      _question.text.trim().isNotEmpty &&
      _filled.length >= 2 &&
      _filled.toSet().length == _filled.length;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.viewInsetsOf(context).bottom + 12,
      ),
      child: ListenableBuilder(
        listenable: Listenable.merge([_question, ..._options]),
        builder: (context, _) => Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _question,
              maxLength: 200,
              textCapitalization: TextCapitalization.sentences,
              decoration: appInputDecoration(
                context,
                hintText: 'Question',
                counterText: '',
              ),
            ),
            const Gap(10),
            for (var index = 0; index < _options.length; index++) ...[
              TextField(
                controller: _options[index],
                maxLength: 80,
                textCapitalization: TextCapitalization.sentences,
                decoration: appInputDecoration(
                  context,
                  hintText: 'Option ${index + 1}',
                  counterText: '',
                ),
              ),
              const Gap(8),
            ],
            if (_options.length < _maxOptions)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  style: TextButton.styleFrom(
                    foregroundColor: AppPalette.primary,
                  ),
                  onPressed: () =>
                      setState(() => _options.add(TextEditingController())),
                  icon: const Icon(Icons.add_rounded, size: 18),
                  label: const Text('Add Option'),
                ),
              ),
            const Gap(8),
            AppActionButton(
              label: 'Create Poll',
              outlined: false,
              backgroundColor: AppPalette.primary,
              foregroundColor: Colors.white,
              onPressed: _ready
                  ? () => widget.onCreate(_question.text.trim(), _filled)
                  : null,
            ),
          ],
        ),
      ),
    );
  }
}
