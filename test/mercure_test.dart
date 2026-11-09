import 'package:flutter_test/flutter_test.dart';
import 'package:preconnect/tools/app_logout.dart';

void main() {
  test('reads the hub cookie from the dedicated header first', () {
    expect(
      AppLogout.mercureCookie({
        'x-mercure-authorization': 'synthetic.jwt.value',
        'set-cookie': 'mercureAuthorization=other; Path=/',
      }),
      'mercureAuthorization=synthetic.jwt.value',
    );
    expect(
      AppLogout.mercureCookie({
        'x-mercure-authorization': 'mercureAuthorization=synthetic.jwt',
      }),
      'mercureAuthorization=synthetic.jwt',
    );
  });

  test('falls back to the cookie name and value only', () {
    expect(
      AppLogout.mercureCookie({
        'set-cookie':
            'mercureAuthorization=synthetic.jwt; Path=/.well-known/mercure; Secure; HttpOnly',
      }),
      'mercureAuthorization=synthetic.jwt',
    );
    expect(AppLogout.mercureCookie({'set-cookie': 'other=1'}), isNull);
    expect(AppLogout.mercureCookie(const {}), isNull);
  });
}
