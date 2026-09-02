import 'package:flutter_test/flutter_test.dart';
import 'package:preconnect/api/api_client.dart';
import 'package:preconnect/api/api_config.dart';
import 'package:preconnect/tools/app_storage.dart';
import 'package:preconnect/tools/holiday.dart';
import 'package:preconnect/tools/http/http_headers.dart';
import 'package:preconnect/tools/ramadan.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('clearing transient caches invalidates every in-memory API cache', () {
    final client = ApiClient()..seedTransientCachesForTesting();
    expect(client.hasTransientCachesForTesting, isTrue);

    client.clearTransientCaches();

    expect(client.hasTransientCachesForTesting, isFalse);
  });

  test('dynamic public data uses the live API routes', () {
    expect(ApiConfig.holidayStatusUrl, endsWith('/holiday'));
    expect(ApiConfig.ramadanStatusUrl, endsWith('/ramadan'));
    expect(ApiConfig.coursePrerequisitesUrl, endsWith('/course-prerequisites'));
    expect(ApiConfig.bracuLeaksUrl, endsWith('/braculeaks'));
    expect(
      ApiConfig.bracuLeaksCollectionUrl('BRACU.CSE'),
      endsWith('/braculeaks/BRACU.CSE'),
    );
  });

  test('HTTP cache accepts only valid entity tags', () {
    expect(isValidHttpEtag('"abc123"'), isTrue);
    expect(isValidHttpEtag('W/"abc123"'), isTrue);
    expect(isValidHttpEtag('[{"title":"Announcement – Fall 2026"}]'), isFalse);
    expect(isValidHttpEtag('abc123'), isFalse);
  });

  test('live holiday and Ramadan response shapes remain parseable', () {
    final holiday = HolidayStatus.fromApi(<Map<String, dynamic>>[
      <String, dynamic>{
        'startDate': '2099-08-05',
        'endDate': '2099-08-05',
        'label': 'University Holiday',
      },
    ]);
    final ramadan = RamadanStatus.fromCache(<String, dynamic>{
      'isRamadan': true,
      'ramadanDay': 4,
      'sehriEndsAt': '04:30',
      'iftarAt': '18:30',
    });

    expect(holiday.nextHolidaysThisYear.single.label, 'University Holiday');
    expect(ramadan.isRamadan, isTrue);
    expect(ramadan.ramadanDay, 4);
  });

  test('large preference values round-trip through the file cache', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await AppStorage.initialize();
    const key = 'large_cache_test';
    final value = List.filled(300 * 1024, 'x').join();

    await AppStorage.instance.setString(key, value);

    expect(await AppStorage.instance.getString(key), value);
    await AppStorage.instance.remove(key);
    expect(await AppStorage.instance.getString(key), isNull);
  });
}
