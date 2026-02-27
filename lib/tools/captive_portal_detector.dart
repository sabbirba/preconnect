import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:preconnect/api/api_client.dart';

enum CaptivePortalState { offline, validated, captive, unknown }

class CaptivePortalStatus {
  const CaptivePortalStatus({
    required this.state,
    required this.httpStatusCode,
  });

  final CaptivePortalState state;
  final int? httpStatusCode;
}

class CaptivePortalDetector {
  CaptivePortalDetector._();

  static final Uri _probeUri = Uri.parse(
    'http://connectivitycheck.gstatic.com/generate_204',
  );
  static const Duration _timeout = Duration(seconds: 4);

  static Future<CaptivePortalStatus> detect() async {
    final hasNetwork = await ApiClient().hasConnection(forceRefresh: true);
    if (!hasNetwork) {
      return const CaptivePortalStatus(
        state: CaptivePortalState.offline,
        httpStatusCode: null,
      );
    }

    final client = http.Client();
    try {
      final request = http.Request('GET', _probeUri)..followRedirects = false;
      final response = await client.send(request).timeout(_timeout);
      final status = response.statusCode;
      if (status == 204) {
        return CaptivePortalStatus(
          state: CaptivePortalState.validated,
          httpStatusCode: status,
        );
      }
      if (status == 200 || (status >= 300 && status < 400)) {
        return CaptivePortalStatus(
          state: CaptivePortalState.captive,
          httpStatusCode: status,
        );
      }
      return CaptivePortalStatus(
        state: CaptivePortalState.unknown,
        httpStatusCode: status,
      );
    } on SocketException {
      return const CaptivePortalStatus(
        state: CaptivePortalState.offline,
        httpStatusCode: null,
      );
    } catch (_) {
      return const CaptivePortalStatus(
        state: CaptivePortalState.unknown,
        httpStatusCode: null,
      );
    } finally {
      client.close();
    }
  }
}
