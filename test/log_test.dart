import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:preconnect/tools/app_log.dart';

void main() {
  test('shortens long messages and keeps short ones', () {
    expect(AppLog.shorten('ok'), 'ok');
    final long = AppLog.shorten('x' * (AppLog.maxMessageLength + 50));
    expect(long.length, AppLog.maxMessageLength + 1);
    expect(long.endsWith('…'), isTrue);
  });

  test('trims an oversized log to its newest half', () async {
    final directory = await Directory.systemTemp.createTemp('preconnect_log_');
    final file = File('${directory.path}/debug_logs.txt');
    await file.writeAsString(
      '${'old\n' * (AppLog.maxBytes ~/ 4)}${'new\n' * (AppLog.maxBytes ~/ 8)}',
    );
    await AppLog.trim(file);
    final kept = await file.readAsString();
    expect(await file.length(), AppLog.maxBytes ~/ 2);
    expect(kept.endsWith('new\n'), isTrue);
    await AppLog.trim(file);
    expect(await file.length(), AppLog.maxBytes ~/ 2);
    await directory.delete(recursive: true);
  });
}
