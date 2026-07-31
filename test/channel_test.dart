import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:preconnect/tools/android_alarm.dart';
import 'package:preconnect/tools/calendar_event.dart';
import 'package:preconnect/tools/file_open.dart';
import 'package:preconnect/tools/platform_channels.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Android alarm sends the native channel contract', () async {
    const channel = MethodChannel(PlatformChannels.androidAlarm);
    MethodCall? captured;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          captured = call;
          return true;
        });

    final result = await AndroidAlarm.set(
      hour: 8,
      minute: 15,
      message: 'Class',
      days: const [2, 4],
    );

    expect(result, isTrue);
    expect(captured?.method, 'setAlarm');
    expect(captured?.arguments, {
      'hour': 8,
      'minute': 15,
      'message': 'Class',
      'days': [2, 4],
    });
  });

  test('platform channel names remain stable', () {
    expect(PlatformChannels.androidAlarm, 'preconnect/android_alarm');
    expect(PlatformChannels.androidNetworkAssist, 'preconnect/network_assist');
    expect(
      PlatformChannels.androidNetworkAssistEvents,
      'preconnect/network_assist_events',
    );
    expect(PlatformChannels.iosNetworkAssist, 'preconnect/ios_network_assist');
    expect(PlatformChannels.quietMode, 'preconnect/quiet_mode');
    expect(PlatformChannels.nativePrint, 'preconnect/native_print');
    expect(
      PlatformChannels.backgroundPermission,
      'preconnect/background_permission',
    );
    expect(PlatformChannels.calendar, 'preconnect/calendar');
    expect(PlatformChannels.file, 'preconnect/file');
    expect(PlatformChannels.store, 'preconnect/store');
    expect(PlatformChannels.appUpdate, 'preconnect/app_update');
    expect(PlatformChannels.appUpdateEvents, 'preconnect/app_update_events');
  });

  test('calendar reminders preserve their native payload', () async {
    const channel = MethodChannel(PlatformChannels.calendar);
    MethodCall? captured;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          captured = call;
          return true;
        });
    final start = DateTime(2026, 8, 1, 9);
    final result = await Add2Reminder.addReminder(
      Event(
        title: 'Class',
        description: 'Lecture',
        location: 'Campus',
        startDate: start,
        endDate: start.add(const Duration(hours: 1)),
        recurrence: const Recurrence(frequency: Frequency.weekly),
      ),
    );
    expect(result, isTrue);
    expect(captured?.method, 'add');
    expect(captured?.arguments, {
      'title': 'Class',
      'description': 'Lecture',
      'location': 'Campus',
      'start': start.millisecondsSinceEpoch,
      'end': start.add(const Duration(hours: 1)).millisecondsSinceEpoch,
      'frequency': Frequency.weekly.index,
      'interval': 1,
    });
  });

  test('native file open preserves its native payload', () async {
    const channel = MethodChannel(PlatformChannels.file);
    MethodCall? captured;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          captured = call;
          return true;
        });
    expect(await NativeFile.open('/tmp/report.pdf'), isTrue);
    expect(captured?.method, 'open');
    expect(captured?.arguments, {'path': '/tmp/report.pdf'});
  });
}
