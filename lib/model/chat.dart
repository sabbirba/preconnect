enum ChatRoomKind { lounge, course, section }

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
  );

  final String id;
  final ChatRoomKind kind;
  final String title;
  final bool active;
  final String pushTopic;
  final int lastMessageAt;
  final int semesterSessionId;
  final int memberCount;
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

  bool get hasImage => images.isNotEmpty;
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
}

DateTime? chatDate(Object? value) => _date(value);

class ChatRecent {
  const ChatRecent(this.messages, this.reactions);

  static const ChatRecent empty = ChatRecent(<ChatMessage>[], <ChatReaction>[]);

  final List<ChatMessage> messages;
  final List<ChatReaction> reactions;
}
