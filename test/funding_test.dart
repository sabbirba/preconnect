import 'package:flutter_test/flutter_test.dart';
import 'package:preconnect/api/funding.dart';
import 'package:preconnect/pages/ui_kit.dart';

void main() {
  test('supporter list keeps named supporters only', () {
    expect(isNamedSupporter('Example Supporter'), isTrue);
    expect(isNamedSupporter('Anonymous'), isFalse);
    expect(isNamedSupporter(' anonymous '), isFalse);
    expect(isNamedSupporter('   '), isFalse);
  });

  test('supporter list grows and shrinks five at a time', () {
    expect(visibleSupporterCount(0, step: 5, total: 12), 5);
    expect(visibleSupporterCount(10, step: 5, total: 12), 10);
    expect(visibleSupporterCount(15, step: 5, total: 12), 12);
    expect(visibleSupporterCount(0, step: 5, total: 3), 3);
  });

  test('supporter count matches the web count', () {
    ContributionItem gift(String name) =>
        ContributionItem(name: name, amount: 100, ts: 0);
    final gifts = [
      gift('Example One'),
      gift('Example One'),
      gift('Example Two'),
      gift('Anonymous'),
      gift(''),
    ];
    expect(
      supporterCount(
        FundingStatus(
          totalRaised: 500,
          contributorsCount: 90,
          contributions: gifts,
        ),
      ),
      90,
    );
    expect(
      supporterCount(
        FundingStatus(
          totalRaised: 500,
          contributorsCount: 0,
          contributions: gifts,
        ),
      ),
      4,
    );
  });

  test('supporters rank highest first with anonymous gifts as one total', () {
    final list = groupedSupporters([
      ContributionItem(name: 'Big Giver', amount: 2000, ts: 1),
      ContributionItem(name: 'Anonymous', amount: 300, ts: 2),
      ContributionItem(name: '', amount: 200, ts: 3),
      ContributionItem(name: 'Small Giver', amount: 100, ts: 4),
      ContributionItem(name: 'Small Giver', amount: 50, ts: 5),
      ContributionItem(name: 'Refunded', amount: 0, ts: 6),
    ]);
    expect(list.map((item) => item.name), [
      'Big Giver',
      'Anonymous',
      'Small Giver',
    ]);
    expect(list.map((item) => item.amount), [2000, 500, 150]);
  });
}
