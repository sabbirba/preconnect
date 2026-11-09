import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:pocketbase/pocketbase.dart';
import 'package:preconnect/api/api_client.dart';
import 'package:preconnect/api/api_config.dart';
import 'package:preconnect/api/auth.dart';
import 'package:preconnect/api/fcm.dart';
import 'package:preconnect/model/chat.dart';
import 'package:preconnect/tools/app_storage.dart';
import 'package:preconnect/tools/http/http_utils.dart';
import 'package:preconnect/tools/image_compress.dart';
import 'package:preconnect/tools/storage_keys.dart';

class ChatException implements Exception {
  const ChatException(this.message);

  final String message;

  @override
  String toString() => message;
}

class ChatWatch {
  ChatWatch(this._cancel);

  final Future<void> Function() _cancel;

  Future<void> cancel() => _cancel();
}

class ChatService {
  ChatService._();

  static final ChatService instance = ChatService._();

  static const List<String> reactionEmojis = <String>[
    '👍',
    '❤️',
    '😂',
    '😮',
    '😢',
    '🙏',
  ];
  static const int pageSize = 50;
  static const Duration _sessionLifetime = Duration(hours: 5);
  static const Duration _fileTokenLifetime = Duration(minutes: 2);
  static const String _messageExpand = 'author,replyTo,replyTo.author';

  final ValueNotifier<List<ChatRoom>> rooms = ValueNotifier<List<ChatRoom>>(
    const <ChatRoom>[],
  );
  final ValueNotifier<Map<String, int>> unread =
      ValueNotifier<Map<String, int>>(const <String, int>{});
  final ValueNotifier<Set<String>> blocked = ValueNotifier<Set<String>>(
    const <String>{},
  );
  final ValueNotifier<Set<String>> muted = ValueNotifier<Set<String>>(
    const <String>{},
  );

  PocketBase? _pb;
  ChatAuthor? _me;
  String _personalTopic = '';
  DateTime? _sessionAt;
  Future<void>? _starting;
  String? _fileToken;
  DateTime? _fileTokenAt;
  final Map<String, String> _memberIds = <String, String>{};
  final Map<String, DateTime> _lastRead = <String, DateTime>{};
  int _generation = 0;
  String? activeRoomId;

  ChatAuthor? get me => _me;

  bool isViewing(String roomId) => activeRoomId == roomId;

  Future<PocketBase> _client() async {
    final pb = _pb;
    final startedAt = _sessionAt;
    if (pb != null &&
        startedAt != null &&
        DateTime.now().difference(startedAt) < _sessionLifetime) {
      return pb;
    }
    await (_starting ??= _start().whenComplete(() => _starting = null));
    return _pb!;
  }

  Future<http.Response> _requestSession() async {
    final token = await ApiClient().getAccessToken();
    if (token == null || token.isEmpty) {
      throw const ChatException('Sign in to use chat.');
    }
    return HttpUtils.client
        .post(
          Uri.parse(ApiConfig.chatSessionUrl),
          headers: <String, String>{'Authorization': 'Bearer $token'},
        )
        .timeout(const Duration(seconds: 30));
  }

  Future<void> _start() async {
    final generation = _generation;
    await AuthService().ensureSignedIn();
    var response = await _requestSession();
    if (response.statusCode == 401 && await AuthService().refreshToken()) {
      response = await _requestSession();
    }
    if (response.statusCode == 401) {
      throw ChatException(_errorMessage(response.body));
    }
    if (response.statusCode != 200) {
      throw const ChatException('Chat is unavailable right now.');
    }
    if (generation != _generation) {
      throw const ChatException('Sign in to use chat.');
    }
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final student = (body['student'] as Map).cast<String, dynamic>();
    final pb = _pb ??= PocketBase(ApiConfig.pocketBaseUrl);
    pb.authStore.save('${body['token']}', RecordModel.fromJson(student));
    _me = ChatAuthor.fromJson(student);
    _personalTopic = '${body['pushTopic'] ?? ''}';
    _sessionAt = DateTime.now();
    _fileToken = null;
  }

  String _errorMessage(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map && decoded['message'] is String) {
        return decoded['message'] as String;
      }
    } catch (_) {}
    return 'Chat is unavailable right now.';
  }

  Future<List<ChatRoom>> loadRooms() async {
    final pb = await _client();
    final (roomRecords, memberRecords, blockRecords) = await (
      pb
          .collection('chat_rooms')
          .getFullList(sort: '-active,-lastMessageAt,title'),
      pb.collection('chat_members').getFullList(),
      pb.collection('chat_blocks').getFullList(),
    ).wait;
    final list = roomRecords.map((r) => ChatRoom.fromJson(r.toJson())).toList();
    _memberIds.clear();
    _lastRead.clear();
    for (final member in memberRecords) {
      _applyMember(member);
    }
    muted.value = memberRecords
        .where((member) => member.getBoolValue('muted'))
        .map((member) => member.getStringValue('room'))
        .toSet();
    blocked.value = blockRecords
        .map((record) => record.getStringValue('blocked'))
        .toSet();
    rooms.value = list;
    unawaited(_syncTopics(list));
    unawaited(refreshUnread());
    return list;
  }

  Future<void> refreshUnread() async {
    final ids = rooms.value.map((room) => room.id).toList();
    final counts = await Future.wait(ids.map(_countUnread));
    unread.value = <String, int>{
      for (var i = 0; i < ids.length; i++) ids[i]: counts[i],
    };
  }

  Future<int> _countUnread(String roomId) async {
    final read = _lastRead[roomId];
    if (read == null) return 0;
    final pb = await _client();
    final params = <String, dynamic>{
      'room': roomId,
      'me': _me?.id ?? '',
      'since': read.toUtc(),
    };
    final hidden = blocked.value.toList();
    for (var i = 0; i < hidden.length; i++) {
      params['b$i'] = hidden[i];
    }
    final filter = <String>[
      'room = {:room} && author != {:me} && created > {:since}',
      for (var i = 0; i < hidden.length; i++) 'author != {:b$i}',
    ].join(' && ');
    final result = await pb
        .collection('chat_messages')
        .getList(perPage: 1, filter: pb.filter(filter, params), fields: 'id');
    return result.totalItems;
  }

  Future<void> _refreshRoomUnread(String roomId) async {
    final count = await _countUnread(roomId);
    unread.value = <String, int>{...unread.value, roomId: count};
  }

  Future<ChatWatch> watchRooms() async {
    final pb = await _client();
    final stopMembers = await pb.collection('chat_members').subscribe('*', (
      event,
    ) {
      final record = event.record;
      if (event.action != 'update' || record == null) return;
      _applyMember(record);
      final roomId = record.getStringValue('room');
      final isMuted = record.getBoolValue('muted');
      if (muted.value.contains(roomId) != isMuted) {
        _setMutedLocally(roomId, isMuted);
      }
    });
    final stop = await pb.collection('chat_rooms').subscribe('*', (event) {
      final record = event.record;
      if (event.action != 'update' || record == null) return;
      final updated = ChatRoom.fromJson(record.toJson());
      final list = rooms.value;
      final index = list.indexWhere((room) => room.id == updated.id);
      if (index < 0) return;
      final previous = list[index];
      rooms.value = [...list]..[index] = updated;
      if (updated.lastMessageAt > previous.lastMessageAt &&
          !isViewing(updated.id)) {
        unawaited(_refreshRoomUnread(updated.id));
      }
    });
    return ChatWatch(() async {
      await stop();
      await stopMembers();
    });
  }

  void _applyMember(RecordModel member) {
    final roomId = member.getStringValue('room');
    _memberIds[roomId] = member.id;
    final read =
        chatDate(member.getStringValue('lastReadAt')) ??
        chatDate(member.getStringValue('created'));
    if (read != null) _lastRead[roomId] = read;
  }

  Future<void> setMuted(String roomId, bool value) async {
    final memberId = _memberIds[roomId];
    if (memberId == null) return;
    final pb = await _client();
    await pb
        .collection('chat_members')
        .update(memberId, body: <String, dynamic>{'muted': value});
    _setMutedLocally(roomId, value);
  }

  void _setMutedLocally(String roomId, bool value) {
    final next = <String>{...muted.value};
    value ? next.add(roomId) : next.remove(roomId);
    muted.value = next;
    unawaited(_syncTopics(rooms.value));
  }

  static Future<Set<String>> savedPushTopics() async =>
      (await AppStorage.instance.getStringList(StorageKeys.chatPushTopics) ??
              const <String>[])
          .toSet();

  Future<void> _syncTopics(List<ChatRoom> list) async {
    final wanted = <String>{
      if (_personalTopic.isNotEmpty) _personalTopic,
      for (final room in list)
        if (room.active &&
            room.kind != ChatRoomKind.lounge &&
            !muted.value.contains(room.id) &&
            room.pushTopic.isNotEmpty)
          room.pushTopic,
    };
    final saved = await savedPushTopics();
    await AppStorage.instance.setStringList(
      StorageKeys.chatPushTopics,
      wanted.toList(),
    );
    final fcm = FCMService.instance;
    await Future.wait(<Future<bool>>[
      for (final topic in wanted.difference(saved)) fcm.subscribeToTopic(topic),
      for (final topic in saved.difference(wanted))
        fcm.unsubscribeFromTopic(topic),
    ]);
  }

  Future<List<ChatMessage>> loadMessages(
    String roomId, {
    ChatMessage? before,
  }) async {
    final pb = await _client();
    final filter = before == null
        ? pb.filter('room = {:room}', {'room': roomId})
        : pb.filter(
            'room = {:room} && (created < {:at} || (created = {:at} && id < {:id}))',
            {'room': roomId, 'at': before.created.toUtc(), 'id': before.id},
          );
    final result = await pb
        .collection('chat_messages')
        .getList(
          perPage: pageSize,
          filter: filter,
          sort: '-created,-id',
          expand: _messageExpand,
          skipTotal: true,
        );
    return result.items
        .map((record) => ChatMessage.fromJson(record.toJson()))
        .toList()
        .reversed
        .toList();
  }

  Future<List<ChatReaction>> loadReactions(List<String> messageIds) async {
    if (messageIds.isEmpty) return const <ChatReaction>[];
    final pb = await _client();
    final params = <String, dynamic>{};
    final parts = <String>[];
    for (var i = 0; i < messageIds.length; i++) {
      params['m$i'] = messageIds[i];
      parts.add('message = {:m$i}');
    }
    final records = await pb
        .collection('chat_reactions')
        .getFullList(filter: pb.filter(parts.join(' || '), params));
    return records.map((r) => ChatReaction.fromJson(r.toJson())).toList();
  }

  Future<ChatMessage> send(
    ChatRoom room, {
    String text = '',
    Uint8List? image,
    ChatMessage? replyTo,
    List<String> mentions = const <String>[],
  }) async {
    final pb = await _client();
    final files = <http.MultipartFile>[];
    if (image != null) {
      final compressed = await compressChatImage(image);
      files.add(
        http.MultipartFile.fromBytes(
          'image',
          compressed,
          filename: 'photo.jpg',
        ),
      );
    }
    try {
      final record = await pb
          .collection('chat_messages')
          .create(
            body: <String, dynamic>{
              'room': room.id,
              'author': _me?.id ?? '',
              'text': text.trim(),
              if (replyTo != null) 'replyTo': replyTo.id,
              if (mentions.isNotEmpty) 'mentions': mentions,
            },
            files: files,
            expand: _messageExpand,
          );
      return ChatMessage.fromJson(record.toJson());
    } on ClientException catch (error) {
      throw ChatException(_sendError(room, error));
    }
  }

  String _sendError(ChatRoom room, ClientException error) {
    if (!room.active) return 'This room is read-only now.';
    if (error.statusCode == 400 && room.kind == ChatRoomKind.lounge) {
      return 'Please wait a few seconds before sending again.';
    }
    final message = error.response['message'];
    if (message is String && message.isNotEmpty && error.statusCode == 400) {
      return message == 'Failed to create record.'
          ? 'Message could not be sent.'
          : message;
    }
    return 'Message could not be sent. Check your connection.';
  }

  Future<void> toggleReaction(
    String messageId,
    String emoji,
    List<ChatReaction> current,
  ) async {
    final pb = await _client();
    final me = _me?.id ?? '';
    final mine = current.where(
      (r) => r.messageId == messageId && r.emoji == emoji && r.studentId == me,
    );
    if (mine.isNotEmpty) {
      await pb.collection('chat_reactions').delete(mine.first.id);
      return;
    }
    await pb
        .collection('chat_reactions')
        .create(
          body: <String, dynamic>{
            'message': messageId,
            'student': me,
            'emoji': emoji,
          },
        );
  }

  Future<void> report(String messageId) async {
    final pb = await _client();
    try {
      await pb
          .collection('chat_reports')
          .create(
            body: <String, dynamic>{
              'message': messageId,
              'reporter': _me?.id ?? '',
              'reason': 'Reported from the app',
            },
          );
    } on ClientException catch (error) {
      if (error.statusCode != 400) rethrow;
    }
  }

  Future<void> block(String studentId) async {
    final pb = await _client();
    if (blocked.value.contains(studentId)) return;
    await pb
        .collection('chat_blocks')
        .create(
          body: <String, dynamic>{
            'blocker': _me?.id ?? '',
            'blocked': studentId,
          },
        );
    blocked.value = <String>{...blocked.value, studentId};
  }

  Future<void> markRead(String roomId, DateTime latest) async {
    final memberId = _memberIds[roomId];
    final read = _lastRead[roomId];
    if (memberId == null || (read != null && !latest.isAfter(read))) return;
    final pb = await _client();
    await pb
        .collection('chat_members')
        .update(
          memberId,
          body: <String, dynamic>{
            'lastReadAt': latest.toUtc().toIso8601String(),
          },
        );
    _lastRead[roomId] = latest;
    unread.value = <String, int>{...unread.value, roomId: 0};
  }

  Future<String> imageUrl(ChatMessage message, {bool thumb = true}) async {
    final pb = await _client();
    final issued = _fileTokenAt;
    if (_fileToken == null ||
        issued == null ||
        DateTime.now().difference(issued) > _fileTokenLifetime) {
      _fileToken = await pb.files.getToken();
      _fileTokenAt = DateTime.now();
    }
    final query = <String>[
      if (thumb) 'thumb=320x0',
      'token=${Uri.encodeQueryComponent(_fileToken!)}',
    ].join('&');
    return '${ApiConfig.pocketBaseUrl}/api/files/chat_messages/'
        '${message.id}/${Uri.encodeComponent(message.image)}?$query';
  }

  Future<ChatWatch> watchRoom(
    String roomId, {
    required void Function(ChatMessage message) onMessage,
    required void Function(ChatReaction reaction, bool added) onReaction,
  }) async {
    final pb = await _client();
    final stopMessages = await pb
        .collection('chat_messages')
        .subscribe(
          '*',
          (event) {
            final record = event.record;
            if (event.action == 'create' && record != null) {
              onMessage(ChatMessage.fromJson(record.toJson()));
            }
          },
          filter: pb.filter('room = {:room}', {'room': roomId}),
          expand: _messageExpand,
        );
    final stopReactions = await pb.collection('chat_reactions').subscribe('*', (
      event,
    ) {
      final record = event.record;
      if (record == null || event.action == 'update') return;
      onReaction(
        ChatReaction.fromJson(record.toJson()),
        event.action == 'create',
      );
    }, filter: pb.filter('message.room = {:room}', {'room': roomId}));
    return ChatWatch(() async {
      await stopMessages();
      await stopReactions();
    });
  }

  Future<void> reset() async {
    _generation++;
    final pb = _pb;
    _pb = null;
    final saved = await savedPushTopics();
    await Future.wait(<Future<Object?>>[
      for (final topic in saved)
        FCMService.instance.unsubscribeFromTopic(topic),
      if (pb != null) pb.realtime.unsubscribe(),
    ]);
    await AppStorage.instance.remove(StorageKeys.chatPushTopics);
    pb?.authStore.clear();
    _me = null;
    _personalTopic = '';
    _sessionAt = null;
    _fileToken = null;
    _fileTokenAt = null;
    _memberIds.clear();
    _lastRead.clear();
    activeRoomId = null;
    rooms.value = const <ChatRoom>[];
    unread.value = const <String, int>{};
    blocked.value = const <String>{};
    muted.value = const <String>{};
  }
}
