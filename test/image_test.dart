import 'dart:async';
import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:preconnect/tools/app_storage.dart';
import 'package:preconnect/tools/cached_image.dart';
import 'package:preconnect/tools/image_cache.dart';
import 'package:preconnect/tools/token_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('old image requests cannot apply authentication to a new URL', (
    tester,
  ) async {
    final directory = (await tester.runAsync(
      () => Directory.systemTemp.createTemp('preconnect_image_'),
    ))!;
    const paths = MethodChannel('plugins.flutter.io/path_provider');
    const secure = MethodChannel(
      'plugins.it_nomads.com/flutter_secure_storage',
    );
    final pending = Completer<String>();
    var delayed = false;
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(paths, (_) async => directory.path);
    messenger.setMockMethodCallHandler(secure, (call) async {
      if (call.method != 'read') return null;
      final key = (call.arguments as Map)['key'];
      if (key == 'access_token') {
        if (!delayed) {
          delayed = true;
          return pending.future;
        }
        return 'synthetic_access';
      }
      return null;
    });
    SharedPreferences.setMockInitialValues({});
    await tester.runAsync(
      () => AppStorage.initialize(cacheDirectory: directory),
    );
    Future<void> settleIo() async {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pump();
    }

    Widget image(String url) => MaterialApp(
      home: CachedImage(key: const ValueKey('image'), url: url),
    );
    await tester.pumpWidget(image('https://connect.bracu.ac.bd/old.png'));
    for (var i = 0; i < 20 && !delayed; i++) {
      await settleIo();
    }
    expect(delayed, isTrue);
    await tester.pumpWidget(image('https://example.test/public.png'));
    await settleIo();
    pending.complete('synthetic_access');
    for (var i = 0; i < 5; i++) {
      await settleIo();
    }
    final widget = tester.widget<CachedNetworkImage>(
      find.byType(CachedNetworkImage),
    );
    expect(widget.imageUrl, 'https://example.test/public.png');
    expect(widget.httpHeaders?.containsKey('Authorization'), isFalse);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 11));
    await settleIo();
    var cleaned = false;
    final cleanup = Future.wait([
      ProfileImageCache.instance.clear(),
      AppImageCache.instance.dispose(),
    ]).then((_) => cleaned = true);
    for (var i = 0; i < 20 && !cleaned; i++) {
      await settleIo();
    }
    expect(cleaned, isTrue);
    await cleanup;
    await tester.runAsync(() => directory.delete(recursive: true));
    messenger.setMockMethodCallHandler(paths, null);
    messenger.setMockMethodCallHandler(secure, null);
  });
}
