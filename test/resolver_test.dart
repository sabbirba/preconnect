import 'package:flutter_test/flutter_test.dart';
import 'package:preconnect/features/schedule/application/session_resolver.dart';
import 'package:preconnect/tools/app_storage.dart';
import 'package:preconnect/tools/http/doh_resolver.dart';
import 'package:preconnect/tools/storage_keys.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    resetCachedCurrentSessionSemesterId();
  });

  test(
    'resolves the persisted semester id without hitting the network',
    () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        StorageKeys.currentSessionSemesterId: '20263',
      });
      await AppStorage.initialize();

      expect(await resolveCurrentSessionSemesterId(), 20263);
    },
  );

  test(
    'resetCachedCurrentSessionSemesterId clears the in-memory shortcut so a '
    'newly persisted semester id is picked up instead of a stale one',
    () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        StorageKeys.currentSessionSemesterId: '20263',
      });
      await AppStorage.initialize();
      expect(await resolveCurrentSessionSemesterId(), 20263);

      await AppStorage.instance.setString(
        StorageKeys.currentSessionSemesterId,
        '20271',
      );
      expect(await resolveCurrentSessionSemesterId(), 20263);

      resetCachedCurrentSessionSemesterId();

      expect(await resolveCurrentSessionSemesterId(), 20271);
    },
  );

  test('DohResolver parses ipv4hint from HTTPS record', () {
    const record =
        '1 . alpn=h3,h2 ipv4hint=104.21.51.147,172.67.181.182 ech=AEX+DQBB7QAgACCtn7wBSYETMvQeKSKuhY1k0Mo9x6K1D94JlBVzUecvLAAEAAEAAQASY2xvdWRmbGFyZS1lY2guY29tAAA= ipv6hint=2606:4700:3030::6815:3393,2606:4700:3034::ac43:b5b6';
    final ip = DohResolver.parseIpv4Hint(record);
    expect(ip, '104.21.51.147');
  });

  test('DohResolver parses type A records for BRACU domains', () {
    const recordData = '34.160.199.249';
    final ip = DohResolver.parseTypeA(recordData);
    expect(ip, '34.160.199.249');
  });

  test('DohResolver detects ALPN h3 capability', () {
    const record = '1 . alpn=h3,h2 ipv4hint=104.21.51.147';
    expect(DohResolver.parseAlpnH3(record), isTrue);
    expect(DohResolver.parseAlpnH3('1 . alpn=h2'), isFalse);
  });

  test('DohResolver parses port hint from HTTPS record', () {
    const record = '1 . alpn=h3 port=443';
    expect(DohResolver.parsePortHint(record), 443);
    expect(DohResolver.parsePortHint('1 . alpn=h3'), isNull);
  });

  test('DohResolver parses type A records for GitHub domains', () {
    const recordData = '20.205.243.168';
    final ip = DohResolver.parseTypeA(recordData);
    expect(ip, '20.205.243.168');
  });
}
