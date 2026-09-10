import 'package:flutter_test/flutter_test.dart';
import 'package:preconnect/pages/shared_widgets/map_shared.dart';

void main() {
  group('CampusMapData', () {
    test('parses full json payload correctly', () {
      final json = {
        'campus_name': 'BRAC University Campus',
        'address': 'Kha 224 Pragati Sarani, Dhaka',
        'summary': 'A modern sustainable campus.',
        'google_maps_url': 'https://maps.google.com/test',
        'map_image_url': 'https://example.com/map.jpg',
        'images': ['https://example.com/1.jpg', 'https://example.com/2.jpg'],
        'source_url': 'https://example.com',
        'highlights': ['Feature 1', 'Feature 2'],
        'contact': {
          'telephone': '+8809638464646',
          'email': 'info@bracu.ac.bd',
          'emails': [
            'info@bracu.ac.bd',
            'support@bracu.ac.bd',
            'unassigned@bracu.ac.bd',
          ],
          'phones': ['+8809638464646'],
        },
        'general_contacts': [
          {
            'office': 'IT Systems',
            'emails': ['support@bracu.ac.bd'],
          },
        ],
        'emergency_contacts': [
          {
            'name': 'Medical Centre',
            'services': 'Emergency Care',
            'phones': ['+8801322821534'],
            'email': 'doctor@bracu.ac.bd',
            'hours': '24/7',
          },
        ],
      };

      final data = CampusMapData.fromJson(json);

      expect(data.campusName, 'BRAC University Campus');
      expect(data.address, 'Kha 224 Pragati Sarani, Dhaka');
      expect(data.summary, 'A modern sustainable campus.');
      expect(data.primaryEmail, 'info@bracu.ac.bd');
      expect(data.highlights.length, 2);

      expect(data.emergencyContacts.length, 1);
      expect(data.emergencyContacts.first.name, 'Medical Centre');
      expect(data.emergencyContacts.first.email, 'doctor@bracu.ac.bd');
      expect(data.emergencyContacts.first.hours, '24/7');

      expect(data.offices.length, 1);
      expect(data.offices.first.office, 'IT Systems');
      expect(data.offices.first.emails, ['support@bracu.ac.bd']);
    });

    test('normalizes campus phone value correctly', () {
      expect(
        normalizeCampusPhoneValue('+8809638464646 (press 2)'),
        '+8809638464646',
      );
      expect(
        normalizeCampusPhoneValue('+880 1313-049111 ext. 101'),
        '+8801313049111',
      );
    });
  });
}
