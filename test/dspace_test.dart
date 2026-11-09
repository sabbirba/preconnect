import 'package:flutter_test/flutter_test.dart';
import 'package:preconnect/pages/dspace_browser.dart';

void main() {
  test('categories load from the public API whatever host the index names', () {
    final category = DSpaceCategory.fromJson({
      'category': 'Thesis',
      'url': 'http://api:3000/dspace/thesis.json',
      'count': 6462,
    });
    expect(category.url, 'https://api.preconnect.app/dspace/thesis.json');
  });

  test('embargoed and restricted items are locked, open items are not', () {
    bool locked(String? access) =>
        DSpaceItem.fromJson({'uuid': 'u', 'access': ?access}).locked;
    expect(locked('embargo'), isTrue);
    expect(locked('restricted'), isTrue);
    expect(locked('open.access'), isFalse);
    expect(locked(null), isFalse);
  });
}
