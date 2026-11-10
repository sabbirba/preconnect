import 'dart:typed_data';

enum ChatRoomKind { lounge, course, section }

enum ChatMessageStatus { sending, sent, failed }

ChatRoomKind _roomKind(String value) => switch (value) {
  'course' => ChatRoomKind.course,
  'section' => ChatRoomKind.section,
  _ => ChatRoomKind.lounge,
};

List<String> _strings(dynamic value) => value is List
    ? value.map(_string).where((item) => item.isNotEmpty).toList()
    : const <String>[];

String _string(Object? value) => value == null ? '' : '$value'.trim();

int _int(Object? value) =>
    value is num ? value.toInt() : int.tryParse(_string(value)) ?? 0;

DateTime? _date(Object? value) {
  final raw = _string(value);
  if (raw.isEmpty) return null;
  return DateTime.tryParse(raw.replaceFirst(' ', 'T'))?.toLocal();
}

Map<String, dynamic> _expanded(Map<String, dynamic> json, String field) {
  final expand = json['expand'];
  if (expand is! Map) return const <String, dynamic>{};
  final value = expand[field];
  if (value is Map) return value.cast<String, dynamic>();
  if (value is List && value.isNotEmpty && value.first is Map) {
    return (value.first as Map).cast<String, dynamic>();
  }
  return const <String, dynamic>{};
}

class ChatAuthor {
  const ChatAuthor({required this.id, required this.name, required this.photo});

  factory ChatAuthor.fromJson(Map<String, dynamic> json) => ChatAuthor(
    id: _string(json['id']),
    name: _string(json['name']),
    photo: _string(json['photo']),
  );

  final String id;
  final String name;
  final String photo;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'id': id,
    'name': name,
    'photo': photo,
  };
}

class ChatRoom {
  const ChatRoom({
    required this.id,
    required this.kind,
    required this.title,
    required this.active,
    required this.pushTopic,
    required this.lastMessageAt,
    required this.semesterSessionId,
    required this.memberCount,
    required this.slowSeconds,
    this.moderatedAt = 0,
    this.pinned = '',
  });

  factory ChatRoom.fromJson(Map<String, dynamic> json) => ChatRoom(
    id: _string(json['id']),
    kind: _roomKind(_string(json['kind'])),
    title: _string(json['title']),
    active: json['active'] == true,
    pushTopic: _string(json['pushTopic']),
    lastMessageAt: _int(json['lastMessageAt']),
    semesterSessionId: _int(json['semesterSessionId']),
    memberCount: _int(json['memberCount']),
    slowSeconds: _int(json['slowSeconds']),
    moderatedAt: _int(json['moderatedAt']),
    pinned: _string(json['pinned']),
  );

  final String id;
  final ChatRoomKind kind;
  final String title;
  final bool active;
  final String pushTopic;
  final int lastMessageAt;
  final int semesterSessionId;
  final int memberCount;
  final int slowSeconds;
  final int moderatedAt;
  final String pinned;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'id': id,
    'kind': kind.name,
    'title': title,
    'active': active,
    'pushTopic': pushTopic,
    'lastMessageAt': lastMessageAt,
    'semesterSessionId': semesterSessionId,
    'memberCount': memberCount,
    'slowSeconds': slowSeconds,
    'moderatedAt': moderatedAt,
    'pinned': pinned,
  };
}

class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.roomId,
    required this.author,
    required this.text,
    required this.images,
    required this.created,
    this.replyToId = '',
    this.replyAuthorName = '',
    this.replyText = '',
    this.mentions = const <String>[],
    this.nonce = '',
    this.status = ChatMessageStatus.sent,
    this.localImages = const <Uint8List>[],
    this.pollOptions = const <String>[],
    this.preview,
    this.event,
    this.fileNames = const <String>[],
    this.localFiles = const <Uint8List>[],
  });

  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    final reply = _expanded(json, 'replyTo');
    final replyAuthor = _expanded(reply, 'author');
    return ChatMessage(
      id: _string(json['id']),
      roomId: _string(json['room']),
      author: ChatAuthor.fromJson(<String, dynamic>{
        'id': _string(json['author']),
        ..._expanded(json, 'author'),
      }),
      text: _string(json['text']),
      images: _strings(json['image']),
      created: _date(json['created']) ?? DateTime.now(),
      replyToId: _string(json['replyTo']),
      replyAuthorName: _string(replyAuthor['name']),
      replyText: reply.isEmpty
          ? ''
          : (_string(reply['text']).isEmpty ? 'Photo' : _string(reply['text'])),
      mentions: _strings(json['mentions']),
      nonce: _string(json['clientNonce']),
      pollOptions: json['poll'] is Map
          ? _strings((json['poll'] as Map)['options'])
          : const <String>[],
      preview: json['preview'] is Map
          ? ChatLinkPreview.fromJson(
              (json['preview'] as Map).cast<String, dynamic>(),
            )
          : null,
      event: json['event'] is Map
          ? ChatEvent.fromJson((json['event'] as Map).cast<String, dynamic>())
          : null,
      fileNames: _strings(json['file']),
    );
  }

  final String id;
  final String roomId;
  final ChatAuthor author;
  final String text;
  final List<String> images;
  final DateTime created;
  final String replyToId;
  final String replyAuthorName;
  final String replyText;
  final List<String> mentions;
  final String nonce;
  final ChatMessageStatus status;
  final List<Uint8List> localImages;
  final List<String> pollOptions;
  final ChatLinkPreview? preview;
  final ChatEvent? event;
  final List<String> fileNames;
  final List<Uint8List> localFiles;

  bool get hasFile => fileNames.isNotEmpty;

  bool get isPoll => pollOptions.isNotEmpty;
  bool get hasImage => images.isNotEmpty || localImages.isNotEmpty;
  bool get isPending => status != ChatMessageStatus.sent;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'id': id,
    'room': roomId,
    'author': author.id,
    'text': text,
    'image': images,
    'created': created.toUtc().toIso8601String(),
    'replyTo': replyToId,
    'mentions': mentions,
    'clientNonce': nonce,
    if (isPoll) 'poll': <String, dynamic>{'options': pollOptions},
    if (preview != null) 'preview': preview!.toJson(),
    if (event != null) 'event': event!.toJson(),
    if (hasFile) 'file': fileNames,
    'expand': <String, dynamic>{
      'author': author.toJson(),
      if (replyToId.isNotEmpty)
        'replyTo': <String, dynamic>{
          'text': replyText == 'Photo' ? '' : replyText,
          'expand': <String, dynamic>{
            'author': <String, dynamic>{'name': replyAuthorName},
          },
        },
    },
  };

  ChatMessage copyWith({
    String? id,
    ChatMessageStatus? status,
    List<Uint8List>? localImages,
  }) => ChatMessage(
    id: id ?? this.id,
    roomId: roomId,
    author: author,
    text: text,
    images: images,
    created: created,
    replyToId: replyToId,
    replyAuthorName: replyAuthorName,
    replyText: replyText,
    mentions: mentions,
    nonce: nonce,
    status: status ?? this.status,
    localImages: localImages ?? this.localImages,
    pollOptions: pollOptions,
    preview: preview,
    event: event,
    fileNames: fileNames,
    localFiles: localFiles,
  );
}

class ChatEvent {
  const ChatEvent({
    required this.kind,
    required this.title,
    required this.at,
    this.courseCode = '',
    this.sectionName = '',
    this.notes = '',
  });

  factory ChatEvent.fromJson(Map<String, dynamic> json) => ChatEvent(
    kind: _string(json['kind']),
    title: _string(json['title']),
    at: (_date(json['at']) ?? DateTime.now()).toLocal(),
    courseCode: _string(json['courseCode']),
    sectionName: _string(json['sectionName']),
    notes: _string(json['notes']),
  );

  static const List<String> kinds = <String>['quiz', 'assignment', 'reminder'];

  final String kind;
  final String title;
  final DateTime at;
  final String courseCode;
  final String sectionName;
  final String notes;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'kind': kind,
    'title': title,
    'at': at.toUtc().toIso8601String(),
    'courseCode': courseCode,
    'sectionName': sectionName,
    'notes': notes,
  };
}

class ChatSettings {
  const ChatSettings({
    required this.rules,
    required this.reportReasonMin,
    required this.maxPhotos,
  });

  factory ChatSettings.fromJson(Map<String, dynamic> json) => ChatSettings(
    rules: _strings(json['rules']),
    reportReasonMin: _int(json['reportReasonMin']),
    maxPhotos: _int(json['maxPhotos']),
  );

  static const ChatSettings initial = ChatSettings(
    rules: <String>[],
    reportReasonMin: 100,
    maxPhotos: 10,
  );

  final List<String> rules;
  final int reportReasonMin;
  final int maxPhotos;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'rules': rules,
    'reportReasonMin': reportReasonMin,
    'maxPhotos': maxPhotos,
  };
}

class ChatLinkPreview {
  const ChatLinkPreview({
    required this.url,
    required this.host,
    required this.title,
    this.description = '',
    this.image = '',
  });

  factory ChatLinkPreview.fromJson(Map<String, dynamic> json) =>
      ChatLinkPreview(
        url: _string(json['url']),
        host: _string(json['host']),
        title: _string(json['title']),
        description: _string(json['description']),
        image: _string(json['image']),
      );

  final String url;
  final String host;
  final String title;
  final String description;
  final String image;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'url': url,
    'host': host,
    'title': title,
    'description': description,
    'image': image,
  };
}

class ChatVote {
  const ChatVote({
    required this.id,
    required this.messageId,
    required this.studentId,
    required this.option,
  });

  factory ChatVote.fromJson(Map<String, dynamic> json) => ChatVote(
    id: _string(json['id']),
    messageId: _string(json['message']),
    studentId: _string(json['student']),
    option: _int(json['option']),
  );

  final String id;
  final String messageId;
  final String studentId;
  final int option;
}

class ChatReaction {
  const ChatReaction({
    required this.id,
    required this.messageId,
    required this.studentId,
    required this.emoji,
  });

  factory ChatReaction.fromJson(Map<String, dynamic> json) => ChatReaction(
    id: _string(json['id']),
    messageId: _string(json['message']),
    studentId: _string(json['student']),
    emoji: _string(json['emoji']),
  );

  final String id;
  final String messageId;
  final String studentId;
  final String emoji;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'id': id,
    'message': messageId,
    'student': studentId,
    'emoji': emoji,
  };
}

DateTime? chatDate(Object? value) => _date(value);

List<Map<String, dynamic>> _maps(Object? value) => value is List
    ? value
          .whereType<Map>()
          .map((item) => item.cast<String, dynamic>())
          .toList()
    : const <Map<String, dynamic>>[];

class ChatRecent {
  const ChatRecent(this.messages, this.reactions, {this.lastMessageAt = 0});

  factory ChatRecent.fromJson(Map<String, dynamic> json) => ChatRecent(
    _maps(json['messages']).map(ChatMessage.fromJson).toList(),
    _maps(json['reactions']).map(ChatReaction.fromJson).toList(),
    lastMessageAt: _int(json['lastMessageAt']),
  );

  static const ChatRecent empty = ChatRecent(<ChatMessage>[], <ChatReaction>[]);

  final List<ChatMessage> messages;
  final List<ChatReaction> reactions;
  final int lastMessageAt;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'lastMessageAt': lastMessageAt,
    'messages': [for (final message in messages) message.toJson()],
    'reactions': [for (final reaction in reactions) reaction.toJson()],
  };
}
