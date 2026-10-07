import 'package:flutter_test/flutter_test.dart';
import 'package:preconnect/api/fcm.dart';

void main() {
  group('FCMService notification cleaning', () {
    test('removes category prefixes from description', () {
      expect(
        FCMService.cleanNotificationDescription(
          '[Announcement] Fall 2026 Registration starts tomorrow',
        ),
        'Fall 2026 Registration starts tomorrow',
      );
      expect(
        FCMService.cleanNotificationDescription(
          'Announcement: Fall 2026 Registration starts tomorrow',
        ),
        'Fall 2026 Registration starts tomorrow',
      );
      expect(
        FCMService.cleanNotificationDescription(
          'Advising - Phase 1 begins tomorrow',
        ),
        'Phase 1 begins tomorrow',
      );
      expect(
        FCMService.cleanNotificationDescription(
          '[News] Vice Chancellor visits robotics lab',
        ),
        'Vice Chancellor visits robotics lab',
      );
      expect(
        FCMService.cleanNotificationDescription(
          'Exam • Room seating arrangement published',
        ),
        'Room seating arrangement published',
      );
    });

    test('drops standalone category strings', () {
      expect(FCMService.cleanNotificationDescription('Announcement'), isEmpty);
      expect(FCMService.cleanNotificationDescription('News'), isEmpty);
      expect(FCMService.cleanNotificationDescription('Notice'), isEmpty);
      expect(FCMService.cleanNotificationDescription('Advising'), isEmpty);
    });

    test('supports custom category and module parameter', () {
      expect(
        FCMService.cleanNotificationDescription(
          '[Scholarship] Deadline extended',
          category: 'Scholarship',
        ),
        'Deadline extended',
      );
      expect(
        FCMService.cleanNotificationDescription(
          'Internship: Submit your resume by Friday',
          module: 'Internship',
        ),
        'Submit your resume by Friday',
      );
      expect(
        FCMService.cleanNotificationDescription(
          'Scholarship',
          category: 'Scholarship',
        ),
        isEmpty,
      );
    });

    test('preserves normal description without category', () {
      expect(
        FCMService.cleanNotificationDescription(
          'Classes will start tomorrow morning at 8:00 AM.',
        ),
        'Classes will start tomorrow morning at 8:00 AM.',
      );
    });
  });
}
