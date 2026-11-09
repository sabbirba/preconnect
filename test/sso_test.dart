import 'package:flutter_test/flutter_test.dart';
import 'package:preconnect/api/api_config.dart';

void main() {
  test('sign in endpoints stay on the BRACU realm', () {
    expect(
      ApiConfig.authEndpoint,
      'https://sso.bracu.ac.bd/realms/bracu/protocol/openid-connect/auth',
    );
    expect(
      ApiConfig.tokenEndpoint,
      'https://sso.bracu.ac.bd/realms/bracu/protocol/openid-connect/token',
    );
    expect(
      ApiConfig.logoutEndpoint,
      'https://sso.bracu.ac.bd/realms/bracu/protocol/openid-connect/logout',
    );
  });

  test('account security opens BRACU devices and sessions', () {
    expect(
      ApiConfig.accountSecurityUrl,
      'https://sso.bracu.ac.bd/realms/bracu/account/account-security/device-activity',
    );
  });
}
