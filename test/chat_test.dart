import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:preconnect/api/chat.dart';
import 'package:preconnect/model/chat.dart';
import 'package:preconnect/tools/app_storage.dart';
import 'package:preconnect/tools/image_compress.dart';
import 'package:preconnect/tools/storage_keys.dart';
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
