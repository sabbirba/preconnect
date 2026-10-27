import 'package:flutter_test/flutter_test.dart';
import 'package:preconnect/tools/wifi_tile.dart';

void main() {
  group('isTrustedPortal', () {
    test('accepts campus hosts and private gateways', () {
      for (final url in [
        'https://wifi2.bracu.ac.bd:19008/portal',
        'http://bracu.ac.bd/',
        'http://172.16.0.1:8080/portal',
        'http://172.31.255.1/',
        'http://10.0.0.1/',
        'http://192.168.1.1/',
      ]) {
        expect(WifiTile.isTrustedPortal(Uri.parse(url)), isTrue, reason: url);
      }
    });

    test('rejects everything else', () {
      for (final url in [
        'http://evil.example.com/portal',
        'https://bracu.ac.bd.evil.com/',
        'http://8.8.8.8/',
        'http://172.32.0.1/',
        'http://[::1]/',
        'ftp://10.0.0.1/',
      ]) {
        expect(WifiTile.isTrustedPortal(Uri.parse(url)), isFalse, reason: url);
      }
      expect(WifiTile.isTrustedPortal(null), isFalse);
    });

    test('only the studentwifi scheme is handled by the tile', () {
      expect(WifiTile.handles(Uri.parse('studentwifi://login')), isTrue);
      expect(WifiTile.handles(Uri.parse('todaywidget://refresh')), isFalse);
      expect(WifiTile.handles(null), isFalse);
    });
  });
}
