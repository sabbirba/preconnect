import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:preconnect/api/api_client.dart';
import 'package:preconnect/api/api_config.dart';
import 'package:preconnect/features/schedule/application/session_resolver.dart';
import 'package:preconnect/tools/app_log.dart';
import 'package:preconnect/tools/bracu_logout.dart';
import 'package:preconnect/tools/http/http_utils.dart';
import 'package:preconnect/tools/refresh_bus.dart';

class MercureService {
  static final MercureService instance = MercureService._internal();
  factory MercureService() => instance;
  MercureService._internal();

  StreamSubscription<String>? _subscription;
  http.Client? _client;
  bool _isConnected = false;
  bool _isConnecting = false;
  Timer? _reconnectTimer;

  bool get isConnected => _isConnected;

  Future<void> connect() async {
    if (_isConnected || _isConnecting) return;
    _isConnecting = true;
    _reconnectTimer?.cancel();

    try {
      final token = await ApiClient().getAccessToken();
      if (token == null || token.isEmpty) {
        _isConnecting = false;
        return;
      }

      _client = HttpUtils.client;
      try {
        await _client!.post(
          BracuLogout.mercureLoginUri,
          headers: BracuLogout.mercureLoginHeaders(accessToken: token),
          body: '{}',
        );
      } catch (_) {}

      final url = Uri.parse(ApiConfig.connectMercureHubUrl);
      final request = http.Request('GET', url);
      request.headers['accept'] = 'text/event-stream';
      request.headers['authorization'] = 'Bearer $token';
      request.headers['x-realm'] = 'bracu';
      request.headers['x-source'] = '3';
      request.headers['cache-control'] = 'no-cache';

      final response = await _client!.send(request);

      if (response.statusCode == 200) {
        _isConnected = true;
        _isConnecting = false;
        unawaited(AppLog.write('Mercure SSE: Hub connected successfully'));

        _subscription = response.stream
            .transform(utf8.decoder)
            .transform(const LineSplitter())
            .listen(
              _handleSseLine,
              onError: (error) {
                unawaited(AppLog.write('Mercure SSE: Stream error ($error)'));
                _handleDisconnect();
              },
              onDone: () {
                unawaited(
                  AppLog.write('Mercure SSE: Stream closed by remote hub'),
                );
                _handleDisconnect();
              },
              cancelOnError: true,
            );
      } else {
        _isConnecting = false;
        unawaited(
          AppLog.write(
            'Mercure SSE: Hub returned status ${response.statusCode}',
          ),
        );
        _scheduleReconnect();
      }
    } catch (e) {
      _isConnecting = false;
      unawaited(AppLog.write('Mercure SSE Error: Failed to connect ($e)'));
      _scheduleReconnect();
    }
  }

  void _handleSseLine(String line) {
    if (line.startsWith('data: ')) {
      final dataStr = line.substring(6).trim();
      if (dataStr.isEmpty) return;
      try {
        final data = jsonDecode(dataStr);
        _processMercureEvent(data);
      } catch (_) {}
    }
  }

  void _processMercureEvent(dynamic data) {
    ApiClient().clearTransientCaches();
    resetCachedCurrentSessionSemesterId();

    if (data is Map<String, dynamic>) {
      if (data.containsKey('status') ||
          data.containsKey('activePrinters') ||
          data.containsKey('queuedJobsCount') ||
          data.containsKey('claimedJobsCount')) {
        unawaited(
          AppLog.write('Mercure SSE: Received printer status update event'),
        );
        RefreshBus.instance.notify(reason: 'printer');
        return;
      }
      final type = (data['type'] ?? data['event'] ?? data['topic'] ?? '')
          .toString();
      if (type.isNotEmpty) {
        unawaited(AppLog.write('Mercure SSE: Received event type: $type'));
        RefreshBus.instance.notify(reason: type);
        return;
      }
    }
    unawaited(AppLog.write('Mercure SSE: Received generic event'));
    RefreshBus.instance.notify(reason: 'mercure_event');
  }

  void _handleDisconnect() {
    _isConnected = false;
    _isConnecting = false;
    _subscription?.cancel();
    _subscription = null;
    _scheduleReconnect();
  }

  void _scheduleReconnect() {
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(const Duration(seconds: 10), () {
      connect();
    });
  }

  void disconnect() {
    _reconnectTimer?.cancel();
    _subscription?.cancel();
    _subscription = null;
    _client = null;
    _isConnected = false;
    _isConnecting = false;
  }
}
