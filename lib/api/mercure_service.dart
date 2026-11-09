import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:preconnect/api/api_client.dart';
import 'package:preconnect/api/api_config.dart';
import 'package:preconnect/features/schedule/application/session_resolver.dart';
import 'package:preconnect/tools/app_log.dart';
import 'package:preconnect/tools/app_logout.dart';
import 'package:preconnect/tools/http/http_utils.dart';
import 'package:preconnect/tools/sse_client.dart';
import 'package:preconnect/tools/refresh_bus.dart';

class MercureService {
  static final MercureService instance = MercureService._internal();
  factory MercureService() => instance;
  MercureService._internal();

  late final SseClient _sse = SseClient(
    name: 'Mercure',
    request: _hubRequest,
    onEvent: (_, data) => _handleData(data),
    minDelay: const Duration(seconds: 3),
  );

  void connect() => _sse.start();

  void disconnect() => _sse.stop();

  Future<http.BaseRequest?> _hubRequest() async {
    final token = await ApiClient().getAccessToken();
    if (token == null || token.isEmpty) return null;
    String? cookieHeader;
    try {
      final loginResponse = await HttpUtils.client.post(
        AppLogout.mercureLoginUri,
        headers: AppLogout.mercureLoginHeaders(accessToken: token),
        body: '{}',
      );
      cookieHeader = loginResponse.headers['set-cookie'];
    } catch (_) {}
    final jwt = cookieHeader == null
        ? null
        : RegExp(r'mercureAuthorization=([^;]+)').firstMatch(cookieHeader)?[1];
    return http.Request('GET', Uri.parse(ApiConfig.connectMercureHubUrl))
      ..headers.addAll(<String, String>{
        'authorization': 'Bearer ${jwt == null || jwt.isEmpty ? token : jwt}',
        'x-realm': 'bracu',
        'x-source': '3',
        if (cookieHeader != null && cookieHeader.isNotEmpty)
          'cookie': cookieHeader,
      });
  }

  void _handleData(String data) {
    if (data.isEmpty) return;
    try {
      _processMercureEvent(jsonDecode(data));
    } catch (_) {}
  }

  void _invalidateConnectData() {
    final connectApiBase = ApiConfig.connectApiBase;
    ApiClient().invalidateResponses((url) => url.startsWith(connectApiBase));
    resetCachedCurrentSessionSemesterId();
  }

  bool _isPrinterStatusEvent(dynamic data) {
    return data is Map<String, dynamic> &&
        (data.containsKey('status') ||
            data.containsKey('activePrinters') ||
            data.containsKey('queuedJobsCount') ||
            data.containsKey('claimedJobsCount'));
  }

  void _processMercureEvent(dynamic data) {
    if (_isPrinterStatusEvent(data)) {
      unawaited(
        AppLog.write('Mercure SSE: Received printer status update event'),
      );
      RefreshBus.instance.notify(reason: 'printer');
      return;
    }
    _invalidateConnectData();
    if (data is Map<String, dynamic>) {
      final type = (data['type'] ?? data['event'] ?? data['topic'] ?? '')
          .toString();
      if (type.isNotEmpty) {
        unawaited(AppLog.write('Mercure SSE: Received event type: $type'));
        RefreshBus.instance.notify(reason: type);
        RefreshBus.instance.notify(reason: 'mercure_event');
        return;
      }
    }
    unawaited(AppLog.write('Mercure SSE: Received generic event'));
    RefreshBus.instance.notify(reason: 'mercure_event');
  }
}
