import 'package:flutter_test/flutter_test.dart';
import 'package:preconnect/api/dataset_sync.dart';

void main() {
  test('reads dataset versions from the manifest and ignores bad entries', () {
    final versions = DatasetSync.versionsFrom({
      'datasets': {
        'holiday': {'version': 'h1', 'updatedAt': '2026-11-09T00:00:00Z'},
        'news': {'version': ''},
        'map': 'not-a-map',
        'exammap': {'version': 'e1'},
      },
    });
    expect(versions, {'holiday': 'h1', 'exammap': 'e1'});
    expect(DatasetSync.versionsFrom({'datasets': null}), isEmpty);
  });

  test('picks only changed datasets the app uses', () {
    final changed = DatasetSync.changedDatasets(
      {'holiday': 'h2', 'news': 'n1', 'students': 's9', 'map': 'm1'},
      {'holiday': 'h1', 'news': 'n1'},
    );
    expect(changed, ['holiday', 'map']);
  });

  test('reads the same payload shape from the stream and the push', () {
    const payload =
        '{"datasets":{"materials":{"version":"v3","updatedAt":"x"}}}';
    expect(DatasetSync.decodeVersions(payload), {'materials': 'v3'});
    expect(DatasetSync.decodeVersions('not json'), isEmpty);
    expect(DatasetSync.decodeVersions(''), isEmpty);
  });

  test('runs downloads in parallel without passing the limit', () async {
    var running = 0;
    var peak = 0;
    final finished = <int>[];
    await DatasetSync.runInParallel(List<int>.generate(10, (i) => i), 4, (
      item,
    ) async {
      running++;
      peak = running > peak ? running : peak;
      await Future<void>.delayed(const Duration(milliseconds: 5));
      running--;
      finished.add(item);
    });
    expect(peak, 4);
    expect(finished..sort(), List<int>.generate(10, (i) => i));
  });

  test('counts a download as fresh only when its ETag matches', () {
    expect(DatasetSync.compactEtag('W/"abc123"'), 'abc123');
    expect(DatasetSync.isFreshResponse({'etag': 'W/"v2"'}, 'v2'), isTrue);
    expect(DatasetSync.isFreshResponse({'etag': 'W/"v1"'}, 'v2'), isFalse);
    expect(
      DatasetSync.isFreshResponse({'content-type': 'application/json'}, 'v2'),
      isFalse,
    );
  });
}
