import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:preconnect/api/chat.dart';
import 'package:preconnect/model/chat.dart';
import 'package:preconnect/model/section_info.dart';
import 'package:preconnect/tools/app_storage.dart';
import 'package:preconnect/tools/drafts.dart';
import 'package:preconnect/tools/image_compress.dart';
import 'package:preconnect/tools/storage_keys.dart';
import 'package:preconnect/tools/string_utils.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('saved chat push topics are cleared on sign-out', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    final directory = await Directory.systemTemp.createTemp('preconnect_chat_');
    addTearDown(() => directory.delete(recursive: true));
    SharedPreferences.setMockInitialValues({});
    await AppStorage.initialize(cacheDirectory: directory);
    await AppStorage.instance.setStringList(StorageKeys.chatPushTopics, [
      'chatr_abcdefghijklmnopqrstuvwx',
      'chatu_abcdefghijklmnopqrstuvwx',
    ]);

    expect(await ChatService.savedPushTopics(), {
      'chatr_abcdefghijklmnopqrstuvwx',
      'chatu_abcdefghijklmnopqrstuvwx',
    });
    await ChatService.instance.reset();
    expect(await ChatService.savedPushTopics(), isEmpty);
  });

  test('drafts survive a restart and clear when sent', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    final directory = await Directory.systemTemp.createTemp(
      'preconnect_draft_',
    );
    addTearDown(() => directory.delete(recursive: true));
    SharedPreferences.setMockInitialValues({});
    await AppStorage.initialize(cacheDirectory: directory);
    Drafts.instance.reset();
    final input = TextEditingController();
    addTearDown(input.dispose);
    Drafts.instance.bind(input, ChatService.draftKey('r1'));
    input.text = 'See you at the lab';
    await Future<void>.delayed(const Duration(milliseconds: 400));
    Drafts.instance.reset();
    expect(
      Drafts.instance.read(ChatService.draftKey('r1')),
      'See you at the lab',
    );
    final restored = TextEditingController();
    addTearDown(restored.dispose);
    Drafts.instance.bind(restored, ChatService.draftKey('r1'));
    expect(restored.text, 'See you at the lab');
    restored.clear();
    expect(Drafts.instance.read(ChatService.draftKey('r1')), isEmpty);
  });

  test('message keeps every photo name in order', () {
    final message = ChatMessage.fromJson({
      'id': 'm3',
      'room': 'r1',
      'author': 's1',
      'image': ['a.jpg', '', 'b.jpg'],
      'created': '2026-11-09 06:30:00.000Z',
    });
    expect(message.images, ['a.jpg', 'b.jpg']);
    expect(message.hasImage, isTrue);
  });

  test('message reads author, reply and photo from the expanded record', () {
    final message = ChatMessage.fromJson({
      'id': 'm2',
      'room': 'r1',
      'author': 's2',
      'text': ' Hi course ',
      'image': '',
      'replyTo': 'm1',
      'mentions': ['s1', ''],
      'created': '2026-11-09 06:30:00.000Z',
      'expand': {
        'author': {'id': 's2', 'name': 'Test Student B', 'photo': '/p/b.jpg'},
        'replyTo': {
          'id': 'm1',
          'text': '',
          'image': 'photo.jpg',
          'expand': {
            'author': {'id': 's1', 'name': 'Test Student A'},
          },
        },
      },
    });
    expect(message.author.name, 'Test Student B');
    expect(message.author.photo, '/p/b.jpg');
    expect(message.text, 'Hi course');
    expect(message.replyAuthorName, 'Test Student A');
    expect(message.replyText, 'Photo');
    expect(message.mentions, ['s1']);
    expect(message.created.toUtc(), DateTime.utc(2026, 11, 9, 6, 30));
    expect(message.hasImage, isFalse);
  });

  test('message reads its poll and link preview and saves them again', () {
    final message = ChatMessage.fromJson(<String, dynamic>{
      'id': 'm1',
      'room': 'r1',
      'author': 'a1',
      'text': 'Class at 8 or 9?',
      'created': '2026-11-10 10:00:00.000Z',
      'poll': <String, dynamic>{
        'options': <String>['8 AM', '9 AM'],
      },
      'preview': <String, dynamic>{
        'url': 'https://example.com/a',
        'host': 'example.com',
        'title': 'Example',
        'description': 'About',
        'image': '',
      },
    });
    expect(message.isPoll, isTrue);
    expect(message.pollOptions, <String>['8 AM', '9 AM']);
    expect(message.preview?.host, 'example.com');
    final restored = ChatMessage.fromJson(message.toJson());
    expect(restored.pollOptions, message.pollOptions);
    expect(restored.preview?.title, 'Example');
    expect(ChatVote.fromJson(<String, dynamic>{'option': 1}).option, 1);
  });

  test('event and settings read what the server sends', () {
    final message = ChatMessage.fromJson(<String, dynamic>{
      'id': 'm2',
      'text': 'Quiz 2',
      'event': <String, dynamic>{
        'kind': 'quiz',
        'title': 'Quiz 2',
        'at': '2026-11-20T03:00:00.000Z',
        'courseCode': 'CSE110',
        'sectionName': '05',
        'notes': 'Chapters 3 and 4',
      },
      'file': <String>['notes_ab12cd34ef.pdf', 'slides_ab12cd34ef.pdf'],
    });
    final event = message.event!;
    expect(event.kind, 'quiz');
    expect(event.at.toUtc(), DateTime.utc(2026, 11, 20, 3));
    final restored = ChatMessage.fromJson(message.toJson());
    expect(restored.event?.sectionName, '05');
    expect(restored.event?.notes, 'Chapters 3 and 4');
    expect(restored.hasFile, isTrue);
    expect(restored.fileNames, <String>[
      'notes_ab12cd34ef.pdf',
      'slides_ab12cd34ef.pdf',
    ]);
    final settings = ChatSettings.fromJson(<String, dynamic>{
      'rules': <String>['Be kind.'],
      'reportReasonMin': 50,
      'maxPhotos': 4,
    });
    expect(settings.rules, <String>['Be kind.']);
    expect(settings.maxPhotos, 4);
    expect(ChatSettings.fromJson(settings.toJson()).reportReasonMin, 50);
  });

  test('faculty reviews read ratings and hide below the minimum', () {
    final data = ChatFacultyReviews.fromJson(<String, dynamic>{
      'faculty': <String, dynamic>{
        'initial': 'ABC',
        'name': 'Dr. Abc',
        'reviewCount': 2,
        'minimum': 3,
        'teaching': 0,
      },
      'locked': true,
      'reviews': <Map<String, dynamic>>[],
      'mine': <String, dynamic>{
        'id': 'r1',
        'courseCode': 'CSE110',
        'comment': 'Clear',
        'teaching': 5,
        'grading': 4,
        'recommend': 3,
        'mine': true,
      },
    });
    expect(data.faculty?.visible, isFalse);
    expect(data.locked, isTrue);
    expect(data.mine?.ratings['grading'], 4);
    expect(data.mine?.ratings.overall, 4);
    final material = ChatMaterial.fromJson(<String, dynamic>{
      'id': 'm1',
      'courseCode': 'CSE110',
      'name': 'lecture 1.pdf',
      'file': 'lecture_1_ab12cd34ef.pdf',
      'size': 2048,
      'helpful': 3,
    });
    expect(material.helpful, 3);
    expect(
      chatFileTitle('contract_law_notes_ab12cd34ef.pdf'),
      'contract law notes.pdf',
    );
    final shared = ChatMessage.fromJson(<String, dynamic>{
      'id': 'f1',
      'file': <String>['a_ab12cd34ef.pdf', 'contract_law_ab12cd34ef.pdf'],
      'fileTitles': <String>['A.pdf', 'Contract Law.pdf'],
    });
    expect(shared.lastFileTitle, 'Contract Law.pdf');
    expect(facultyDisplayName('moz', 'MOZ'), 'MOZ');
    expect(facultyDisplayName('MOZ', ''), 'MOZ');
    expect(formatFileSize(2048), '2.0 KB');
    final switches = ChatSettings.fromJson(<String, dynamic>{
      'maxFiles': 3,
      'maxFileMB': 2,
      'maxTextLength': 10000,
      'pollsEnabled': false,
      'unsendEnabled': false,
    });
    expect(switches.maxFileBytes, 2 * 1024 * 1024);
    expect(switches.maxFiles, 3);
    expect(switches.maxTextLength, 10000);
    expect(switches.pollsEnabled, isFalse);
    expect(switches.unsendEnabled, isFalse);
    expect(switches.pdfsEnabled, isTrue);
    expect(
      ChatRoom.fromJson(<String, dynamic>{
        'id': 'r',
        'active': true,
        'closed': true,
      }).active,
      isFalse,
    );
    expect(formatFileSize(3 * 1048576), '3.0 MB');
    expect(facultyDisplayName('MOZ', 'Dr. Moz Rahman'), 'Dr. Moz Rahman (MOZ)');
    expect(
      const ChatSettings(
        rules: <String>[],
        reportReasonMin: 1,
        maxPhotos: 1,
      ).reviewMinimum,
      3,
    );
  });

  test('message without expand keeps the author id', () {
    final message = ChatMessage.fromJson({
      'id': 'm3',
      'room': 'r1',
      'author': 's9',
      'text': 'plain',
    });
    expect(message.author.id, 's9');
    expect(message.author.name, '');
    expect(message.replyText, '');
  });

  test('rooms read kind, state and push topic', () {
    final room = ChatRoom.fromJson({
      'id': 'r1',
      'kind': 'section',
      'title': 'ACT201-01',
      'active': false,
      'pushTopic': 'chatr_x',
      'lastMessageAt': 1794200000000,
      'semesterSessionId': 627,
    });
    expect(room.kind, ChatRoomKind.section);
    expect(room.active, isFalse);
    expect(room.pushTopic, 'chatr_x');
    expect(room.semesterSessionId, 627);
    expect(ChatRoom.fromJson({'kind': 'other'}).kind, ChatRoomKind.lounge);
  });

  test('rooms survive a snapshot round-trip', () {
    final room = ChatRoom.fromJson({
      'id': 'r1',
      'kind': 'course',
      'title': 'ACT201',
      'active': true,
      'pushTopic': 'chatr_x',
      'lastMessageAt': 1794200000000,
      'semesterSessionId': 627,
      'memberCount': 42,
      'slowSeconds': 0,
    });
    final restored = ChatRoom.fromJson(room.toJson());
    expect(restored.id, 'r1');
    expect(restored.kind, ChatRoomKind.course);
    expect(restored.title, 'ACT201');
    expect(restored.active, isTrue);
    expect(restored.lastMessageAt, 1794200000000);
    expect(restored.memberCount, 42);
  });

  test('cached room messages and reactions survive a disk round-trip', () {
    final original = ChatMessage.fromJson({
      'id': 'm2',
      'room': 'r1',
      'author': 's2',
      'text': 'when is the quiz?',
      'image': ['a.jpg', 'b.jpg'],
      'replyTo': 'm1',
      'mentions': ['s1'],
      'clientNonce': 's2-9',
      'created': '2026-11-10 06:30:00.000Z',
      'expand': {
        'author': {'id': 's2', 'name': 'Test Student B', 'photo': '/p/b.jpg'},
        'replyTo': {
          'text': '',
          'expand': {
            'author': {'name': 'Test Student A'},
          },
        },
      },
    });
    const reaction = ChatReaction(
      id: 'x1',
      messageId: 'm2',
      studentId: 's1',
      emoji: '👍',
    );
    final cached = ChatRecent(
      [original],
      const [reaction],
      lastMessageAt: 1794300000000,
    );
    final restored = ChatRecent.fromJson(
      jsonDecode(jsonEncode(cached.toJson())) as Map<String, dynamic>,
    );
    final message = restored.messages.single;
    expect(restored.lastMessageAt, 1794300000000);
    expect(message.id, 'm2');
    expect(message.author.name, 'Test Student B');
    expect(message.author.photo, '/p/b.jpg');
    expect(message.text, 'when is the quiz?');
    expect(message.images, ['a.jpg', 'b.jpg']);
    expect(message.replyToId, 'm1');
    expect(message.replyAuthorName, 'Test Student A');
    expect(message.replyText, 'Photo');
    expect(message.mentions, ['s1']);
    expect(message.nonce, 's2-9');
    expect(message.created.toUtc(), DateTime.utc(2026, 11, 10, 6, 30));
    expect(restored.reactions.single.emoji, '👍');
    expect(restored.reactions.single.messageId, 'm2');
  });

  test('messages default to sent and read the client nonce', () {
    final message = ChatMessage.fromJson({
      'id': 'm1',
      'room': 'r1',
      'author': 's1',
      'text': 'hi',
      'clientNonce': 's1-123',
    });
    expect(message.status, ChatMessageStatus.sent);
    expect(message.isPending, isFalse);
    expect(message.nonce, 's1-123');
  });

  test('a pending message carries local image bytes and can fail', () {
    final pending = ChatMessage(
      id: 's1-1',
      roomId: 'r1',
      author: const ChatAuthor(id: 's1', name: 'A', photo: ''),
      text: 'hi',
      images: const <String>[],
      created: DateTime.utc(2026, 11, 10),
      nonce: 's1-1',
      status: ChatMessageStatus.sending,
      localImages: <Uint8List>[
        Uint8List.fromList(<int>[1, 2, 3]),
      ],
    );
    expect(pending.isPending, isTrue);
    expect(pending.hasImage, isTrue);
    final failed = pending.copyWith(status: ChatMessageStatus.failed);
    expect(failed.status, ChatMessageStatus.failed);
    expect(failed.nonce, 's1-1');
    expect(failed.localImages, pending.localImages);
  });

  test('chat photos are resized, compressed and stripped of location', () {
    final source = img.Image(width: 3200, height: 1600);
    img.fill(source, color: img.ColorRgb8(30, 120, 220));
    source.exif.gpsIfd['GPSLatitude'] = img.IfdValueAscii('23.7');
    source.exif.imageIfd['Model'] = img.IfdValueAscii('Test Phone');
    final original = img.encodeJpg(source, quality: 100);
    expect(img.decodeJpg(original)!.exif.isEmpty, isFalse);

    final shrunk = shrinkChatImage(original);
    final decoded = img.decodeJpg(shrunk)!;
    expect(decoded.width, chatImageMaxSide);
    expect(decoded.height, chatImageMaxSide ~/ 2);
    expect(decoded.exif.isEmpty, isTrue);
    expect(shrunk.length, lessThanOrEqualTo(chatImageMaxBytes));
  });

  test('non-image files are refused', () {
    expect(
      () => shrinkChatImage(
        img.encodePng(img.Image(width: 1, height: 1)).sublist(0, 8),
      ),
      throwsFormatException,
    );
  });
}
