import 'package:preconnect/api/api_config.dart';
import 'package:preconnect/tools/pkce.dart';
import 'package:preconnect/tools/preconnect_constants.dart';
import 'package:preconnect/tools/token_storage.dart';
import 'package:url_launcher/url_launcher.dart';

class BrowserLogin {
  BrowserLogin._();

  static Future<void> start({String? idp}) async {
    final verifier = generatePkceVerifier();
    final challenge = codeChallengeS256(verifier);
    await TokenStorage.instance.write(
      key: PreConnectStorageKeys.pkceVerifier,
      value: verifier,
    );

    final baseUri = Uri.parse(ApiConfig.authUrlWithPkce(challenge));
    final authUri = idp == null || idp.isEmpty
        ? baseUri
        : baseUri.replace(
            queryParameters: {...baseUri.queryParameters, 'kc_idp_hint': idp},
          );
    final opened = await launchUrl(
      authUri,
      mode: LaunchMode.inAppBrowserView,
      webOnlyWindowName: '_self',
    );
    if (!opened) {
      throw StateError('Unable to open BRACU sign in.');
    }
  }
}
