import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:pocketbase/pocketbase.dart';
import 'package:preconnect/api/api_config.dart';
import 'package:preconnect/api/auth.dart';
import 'package:preconnect/api/fcm.dart';
import 'package:preconnect/api/schedule.dart';
import 'package:preconnect/model/chat.dart';
import 'package:preconnect/model/section_info.dart'
    show parseSectionsFromScheduleJson;
import 'package:preconnect/tools/app_storage.dart';
import 'package:preconnect/tools/http/http_utils.dart';
import 'package:preconnect/tools/image_compress.dart';
import 'package:preconnect/tools/preconnect_constants.dart';
import 'package:preconnect/tools/storage_keys.dart';
import 'package:preconnect/tools/token_storage.dart';

class ChatException implements Exception {
  const ChatException(this.message);

  final String message;

  @override
  String toString() => message;
}

class ChatCooldownException extends ChatException {
  const ChatCooldownException() : super('');
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
  static const int maxPhotos = 10;
  static const Duration _sessionLifetime = Duration(hours: 5);
  static const Duration _preloadInterval = Duration(minutes: 5);
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
  final ValueNotifier<int> recentVersion = ValueNotifier<int>(0);

  PocketBase? _pb;
  ChatAuthor? _me;
  String _personalTopic = '';
  DateTime? _sessionAt;
  Future<void>? _starting;
  String? _fileToken;
  DateTime? _fileTokenAt;
  final Map<String, String> _memberIds = <String, String>{};
  final Map<String, DateTime> _lastRead = <String, DateTime>{};
  final Map<String, ChatRecent> _recent = <String, ChatRecent>{};
  Future<List<ChatRoom>>? _roomsLoading;
  Future<ChatWatch>? _roomsWatch;
  DateTime? _preloadedAt;
  DateTime? _roomsLoadedAt;
  Timer? _persistTimer;
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
    final idToken = await TokenStorage.instance.read(
      key: PreConnectStorageKeys.idToken,
    );
    if (idToken == null || idToken.isEmpty) {
      throw const ChatException('Sign in to use chat.');
    }
    return HttpUtils.client
        .post(
          Uri.parse(ApiConfig.chatSessionUrl),
          headers: <String, String>{
            'Authorization': 'Bearer $idToken',
            'Content-Type': 'application/json',
          },
          body: jsonEncode(await _enrollment()),
        )
        .timeout(const Duration(seconds: 30));
  }

  Future<Map<String, Object?>> _enrollment() async {
    final schedules = ScheduleService();
    final sessions = await schedules.fetchSemesterSessions();
    final semesterId = sessions.isEmpty ? 0 : sessions.first.semesterSessionId;
    final sections = parseSectionsFromScheduleJson(
      semesterId > 0
          ? await schedules.fetchStudentScheduleForSemester(
              semesterSessionId: semesterId,
            )
          : null,
    );
    return <String, Object?>{
      'semesterId': semesterId,
      'sections': [
        for (final section in sections)
          if ((section.parentSectionId ?? 0) == 0)
            {
              'courseCode': section.courseCode,
              'sectionId': section.sectionId,
              'sectionName': section.sectionName,
            },
      ],
      'photo': AppStorage.instance.getStringSync(StorageKeys.photoFilePath),
    };
  }

  Future<void> _start() async {
    final generation = _generation;
    await AuthService().ensureSignedIn();
    var response = await _requestSession();
    if (response.statusCode == 401 && await AuthService().refreshToken()) {
      response = await _requestSession();
    }
    if (response.statusCode == 401) {
      throw ChatException(_serverMessage(_decodeMessage(response.body)));
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

  Object? _decodeMessage(String body) {
    try {
      final decoded = jsonDecode(body);
      return decoded is Map ? decoded['message'] : null;
    } catch (_) {
      return null;
    }
  }

  String _serverMessage(
    Object? message, [
    String fallback = 'Chat is unavailable right now.',
  ]) =>
      message is String &&
          message.isNotEmpty &&
          message != 'Failed to create record.'
      ? message
      : fallback;

  ChatRecent recent(String roomId) => _recent[roomId] ?? ChatRecent.empty;

  bool hasRecent(String roomId) => _recent.containsKey(roomId);

  ChatRoom? _room(String roomId) {
    for (final room in rooms.value) {
      if (room.id == roomId) return room;
    }
    return null;
  }

  bool isFresh(String roomId) {
    final cached = _recent[roomId];
    final room = _room(roomId);
    return cached != null &&
        room != null &&
        cached.lastMessageAt >= room.lastMessageAt;
  }

  void remember(
    String roomId,
    List<ChatMessage> messages,
    List<ChatReaction> reactions,
  ) {
    final kept = messages.length > pageSize
        ? messages.sublist(messages.length - pageSize)
        : messages;
    final ids = kept.map((message) => message.id).toSet();
    _recent[roomId] = ChatRecent(
      kept,
      reactions.where((r) => ids.contains(r.messageId)).toList(),
      lastMessageAt: _room(roomId)?.lastMessageAt ?? 0,
    );
    recentVersion.value++;
    _persistRecentSoon();
  }

  void restoreCache() {
    final store = AppStorage.instance;
    try {
      if (rooms.value.isEmpty) {
        final decoded = jsonDecode(
          store.getStringSync(StorageKeys.chatRoomsSnapshot) ?? '[]',
        );
        if (decoded is List) {
          rooms.value = decoded
              .whereType<Map>()
              .map((item) => ChatRoom.fromJson(item.cast<String, dynamic>()))
              .toList();
        }
      }
      if (_recent.isEmpty) {
        final decoded = jsonDecode(
          store.getStringSync(StorageKeys.chatRecent) ?? '{}',
        );
        if (decoded is Map) {
          for (final entry in decoded.entries) {
            if (entry.value is Map) {
              _recent['${entry.key}'] = ChatRecent.fromJson(
                (entry.value as Map).cast<String, dynamic>(),
              );
            }
          }
        }
      }
    } catch (_) {}
  }

  void _persistRooms(List<ChatRoom> list) {
    unawaited(
      AppStorage.instance.setString(
        StorageKeys.chatRoomsSnapshot,
        jsonEncode([for (final room in list) room.toJson()]),
      ),
    );
  }

  void _persistRecentSoon() {
    _persistTimer?.cancel();
    _persistTimer = Timer(const Duration(seconds: 1), () {
      final live = rooms.value.map((room) => room.id).toSet();
      unawaited(
        AppStorage.instance.setString(
          StorageKeys.chatRecent,
          jsonEncode(<String, dynamic>{
            for (final entry in _recent.entries)
              if (live.contains(entry.key)) entry.key: entry.value.toJson(),
          }),
        ),
      );
    });
  }

  Future<void> preload() async {
    restoreCache();
    final last = _preloadedAt;
    if (last != null && DateTime.now().difference(last) < _preloadInterval) {
      return;
    }
    _preloadedAt = DateTime.now();
    try {
      final list = await loadRooms(force: true);
      unawaited(keepRoomsLive());
      await Future.wait(
        list.where((room) => !isFresh(room.id)).map((r) => _sync(r.id)),
      );
    } catch (_) {
      _preloadedAt = null;
    }
  }

  Future<void> _sync(String roomId) async {
    final cached = recent(roomId);
    final fresh = await loadMessages(roomId, after: cached.messages.lastOrNull);
    if (isViewing(roomId)) return;
    final kept = fresh.length >= pageSize
        ? const <ChatMessage>[]
        : cached.messages;
    final known = {for (final message in kept) message.id};
    final added = fresh.where((m) => !known.contains(m.id)).toList();
    final reactions = await loadReactions(added.map((m) => m.id).toList());
    remember(roomId, [...kept, ...added], [...cached.reactions, ...reactions]);
  }

  Future<List<ChatRoom>> loadRooms({bool force = false}) async {
    final loaded = _roomsLoadedAt;
    if (!force &&
        loaded != null &&
        rooms.value.isNotEmpty &&
        DateTime.now().difference(loaded) < _preloadInterval) {
      return rooms.value;
    }
    return _roomsLoading ??= _loadRooms().whenComplete(
      () => _roomsLoading = null,
    );
  }

  Future<List<ChatRoom>> _loadRooms() async {
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
    _dropModerated(list);
    rooms.value = list;
    _roomsLoadedAt = DateTime.now();
    _persistRooms(list);
    unawaited(_syncTopics(list));
    unawaited(refreshUnread());
    return list;
  }

  bool _dropModerated(List<ChatRoom> next) {
    final before = {for (final room in rooms.value) room.id: room.moderatedAt};
    final dropped = next
        .where(
          (room) =>
              room.moderatedAt > (before[room.id] ?? 0) &&
              _recent.remove(room.id) != null,
        )
        .toList();
    if (dropped.isEmpty) return false;
    recentVersion.value++;
    _persistRecentSoon();
    return true;
  }

  Future<void> refreshUnread() async {
    final pb = await _client();
    final result = await pb.send('/api/chat/unread');
    final counts = result is Map ? result['counts'] : null;
    if (counts is! Map) return;
    unread.value = <String, int>{
      for (final entry in counts.entries)
        '${entry.key}': entry.value is num
            ? (entry.value as num).toInt()
            : int.tryParse('${entry.value}') ?? 0,
    };
  }

  Future<ChatWatch> keepRoomsLive() =>
      _roomsWatch ??= _watchRooms().catchError((Object error) {
        _roomsWatch = null;
        throw error;
      });

  Future<ChatWatch> _watchRooms() async {
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
      final moderated = _dropModerated([updated]);
      rooms.value = [...list]..[index] = updated;
      if ((moderated || updated.lastMessageAt > previous.lastMessageAt) &&
          !isViewing(updated.id)) {
        unawaited(refreshUnread().catchError((Object _) {}));
        unawaited(_sync(updated.id).catchError((Object _) {}));
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
    ChatMessage? after,
  }) async {
    final pb = await _client();
    final edge = before ?? after;
    final filter = edge == null
        ? pb.filter('room = {:room}', {'room': roomId})
        : pb.filter(
            before != null
                ? 'room = {:room} && (created < {:at} || (created = {:at} && id < {:id}))'
                : 'room = {:room} && (created > {:at} || (created = {:at} && id > {:id}))',
            {'room': roomId, 'at': edge.created.toUtc(), 'id': edge.id},
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
    List<Uint8List> images = const <Uint8List>[],
    String replyToId = '',
    List<String> mentions = const <String>[],
    String nonce = '',
  }) async {
    final pb = await _client();
    final compressed = await Future.wait(images.map(compressChatImage));
    final files = <http.MultipartFile>[
      for (final photo in compressed)
        http.MultipartFile.fromBytes('image', photo, filename: 'photo.jpg'),
    ];
    try {
      final record = await pb
          .collection('chat_messages')
          .create(
            body: <String, dynamic>{
              'room': room.id,
              'author': _me?.id ?? '',
              'text': text.trim(),
              if (replyToId.isNotEmpty) 'replyTo': replyToId,
              if (mentions.isNotEmpty) 'mentions': mentions,
              if (nonce.isNotEmpty) 'clientNonce': nonce,
            },
            files: files,
            expand: _messageExpand,
          );
      return ChatMessage.fromJson(record.toJson());
    } on ClientException catch (error) {
      if (error.statusCode == 400 && room.slowSeconds > 0) {
        throw const ChatCooldownException();
      }
      throw ChatException(
        !room.active
            ? 'This room is read-only now.'
            : error.statusCode == 400
            ? _serverMessage(
                error.response['message'],
                'Message could not be sent.',
              )
            : 'Message could not be sent. Check your connection.',
      );
    }
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

  static const int reportReasonMinLength = 100;

  Future<void> report(String messageId, String reason) async {
    final pb = await _client();
    try {
      await pb
          .collection('chat_reports')
          .create(
            body: <String, dynamic>{
              'message': messageId,
              'reporter': _me?.id ?? '',
              'reason': reason.trim(),
            },
          );
    } on ClientException catch (error) {
      throw ChatException(
        _serverMessage(
          error.response['message'],
          'You have already reported this message.',
        ),
      );
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

  Future<void> unblock(String studentId) async {
    final pb = await _client();
    final me = _me?.id ?? '';
    try {
      final record = await pb
          .collection('chat_blocks')
          .getFirstListItem(
            pb.filter('blocker = {:me} && blocked = {:blocked}', {
              'me': me,
              'blocked': studentId,
            }),
          );
      await pb.collection('chat_blocks').delete(record.id);
    } on ClientException catch (error) {
      if (error.statusCode != 404) rethrow;
    }
    blocked.value = <String>{...blocked.value}..remove(studentId);
  }

  Future<List<ChatAuthor>> loadBlockedStudents() async {
    final pb = await _client();
    final me = _me?.id ?? '';
    final records = await pb
        .collection('chat_blocks')
        .getFullList(
          filter: pb.filter('blocker = {:me}', {'me': me}),
          expand: 'blocked',
        );
    final students = records.map((record) {
      final json = record.toJson();
      final expand = json['expand'];
      final student = expand is Map && expand['blocked'] is Map
          ? (expand['blocked'] as Map).cast<String, dynamic>()
          : <String, dynamic>{'id': json['blocked']};
      return ChatAuthor.fromJson(student);
    }).toList();
    blocked.value = {for (final student in students) student.id};
    return students;
  }

  Future<void> markAllRead() async {
    final counts = unread.value;
    await Future.wait(<Future<void>>[
      for (final room in rooms.value)
        if ((counts[room.id] ?? 0) > 0)
          markRead(
            room.id,
            DateTime.fromMillisecondsSinceEpoch(room.lastMessageAt),
          ),
    ]);
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

  String imageKey(ChatMessage message, String name, {bool thumb = true}) {
    final base =
        '${ApiConfig.pocketBaseUrl}/api/files/chat_messages/'
        '${message.id}/${Uri.encodeComponent(name)}';
    return thumb ? '$base?thumb=320x0' : base;
  }

  Future<String> imageUrl(
    ChatMessage message,
    String name, {
    bool thumb = true,
  }) async {
    final pb = await _client();
    final issued = _fileTokenAt;
    if (_fileToken == null ||
        issued == null ||
        DateTime.now().difference(issued) > _fileTokenLifetime) {
      _fileToken = await pb.files.getToken();
      _fileTokenAt = DateTime.now();
    }
    final key = imageKey(message, name, thumb: thumb);
    final separator = key.contains('?') ? '&' : '?';
    return '$key${separator}token=${Uri.encodeQueryComponent(_fileToken!)}';
  }

  Future<ChatWatch> watchRoom(
    String roomId, {
    required void Function(ChatMessage message) onMessage,
    required void Function(ChatReaction reaction, bool added) onReaction,
  }) async {
    final pb = await _client();
    final (stopMessages, stopReactions) = await (
      pb
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
          ),
      pb.collection('chat_reactions').subscribe('*', (event) {
        final record = event.record;
        if (record == null || event.action == 'update') return;
        onReaction(
          ChatReaction.fromJson(record.toJson()),
          event.action == 'create',
        );
      }, filter: pb.filter('message.room = {:room}', {'room': roomId})),
    ).wait;
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
    _persistTimer?.cancel();
    await Future.wait(<Future<void>>[
      for (final key in <String>[
        StorageKeys.chatPushTopics,
        StorageKeys.chatRoomsSnapshot,
        StorageKeys.chatRecent,
      ])
        AppStorage.instance.remove(key),
    ]);
    pb?.authStore.clear();
    _me = null;
    _personalTopic = '';
    _sessionAt = null;
    _fileToken = null;
    _fileTokenAt = null;
    _memberIds.clear();
    _lastRead.clear();
    _recent.clear();
    _roomsWatch = null;
    _preloadedAt = null;
    _roomsLoadedAt = null;
    activeRoomId = null;
    rooms.value = const <ChatRoom>[];
    unread.value = const <String, int>{};
    blocked.value = const <String>{};
    muted.value = const <String>{};
  }
}
